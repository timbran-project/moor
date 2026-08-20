// Copyright (C) 2026 Ryan Daum <ryan.daum@gmail.com> This program is free
// software: you can redistribute it and/or modify it under the terms of the GNU
// Affero General Public License as published by the Free Software Foundation,
// version 3.
//
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
// FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
// details.
//
// You should have received a copy of the GNU Affero General Public License along
// with this program. If not, see <https://www.gnu.org/licenses/>.

//! Fjall-backed persistence provider with per-type encoding strategies.
//!
//! This module implements a `Provider` using Fjall (an embedded LSM-tree database) as the backing
//! store. The key architectural feature is **per-type encoding**: each data type can use its own
//! optimal serialization strategy via the `EncodeFor` trait.
//!
//! ## Encoding Strategies
//!
//! Different types use different encoding approaches for performance and efficiency:
//!
//! - **Zerocopy types** (`Obj`, `BitEnum`, etc.): Direct byte representation using the `zerocopy`
//!   crate's `IntoBytes`/`FromBytes` traits. No serialization overhead.
//!
//! - **ByteView wrappers** (`ObjSet`, `PropPerms`): Zero-copy passthrough - these types already
//!   hold a `ByteView` internally, so encoding just extracts the view via `AsRef<ByteView>` and
//!   decoding uses `From<ByteView>`.
//!
//! - **FlatBuffer types** (`ProgramType`, `Var`, `VerbDefs`, `PropDefs`): Uses FlatBuffers via
//!   the `planus` crate for efficient schema-based serialization with forward/backward
//!   compatibility. `Var` uses `var_to_db_flatbuffer` which allows lambdas and anonymous object
//!   references for DB storage.
//!
//! - **UTF-8 types** (`StringHolder`): Direct UTF-8 byte encoding without additional framing.
//!
//! ## Transaction persistence
//!
//! The database commit pipeline collects operations from every relation into one
//! transaction batch. A single background writer commits those batches to Fjall
//! atomically and in publication order.

use crate::{
    db_counters,
    provider::batch_writer::BatchValue,
    tx::{EncodeFor, Error, RelationCodomain, RelationDomain, Timestamp},
};
use byteview::ByteView;
use fjall::Slice;
use moor_common::model::WorldStateTimerOp;
use planus::{ReadAsRoot, WriteAsOffset};
use std::{marker::PhantomData, sync::Arc};

/// Fjall backing provider used for startup reads and encoding transaction writes.
#[derive(Clone)]
pub(crate) struct FjallProvider<Domain, Codomain>
where
    Domain: RelationDomain,
    Codomain: RelationCodomain,
{
    fjall_keyspace: fjall::Keyspace,
    marker: PhantomData<fn() -> (Domain, Codomain)>,
}

fn decode_codomain_with_ts<P, Codomain>(
    provider: &P,
    user_value: Slice,
) -> Result<(Timestamp, Codomain), Error>
where
    P: EncodeFor<Codomain, Stored = ByteView>,
{
    let result = ByteView::from(user_value);
    let ts = Timestamp(u64::from_le_bytes(result[0..8].try_into().unwrap()));
    let codomain_bytes = result.slice(8..);
    let codomain = provider.decode(codomain_bytes)?;
    Ok((ts, codomain))
}

fn encode_codomain_with_ts<P, Codomain>(
    provider: &P,
    ts: Timestamp,
    codomain: &Codomain,
) -> Result<Vec<u8>, Error>
where
    P: EncodeFor<Codomain, Stored = ByteView>,
{
    let codomain_stored = provider.encode(codomain)?;
    let mut result = Vec::with_capacity(8 + codomain_stored.len());
    result.extend_from_slice(&ts.0.to_le_bytes());
    result.extend_from_slice(&codomain_stored);
    Ok(result)
}

#[derive(Clone)]
struct FjallBatchValue<Domain, Codomain>
where
    Domain: RelationDomain,
    Codomain: RelationCodomain,
{
    provider: FjallProvider<Domain, Codomain>,
    timestamp: Timestamp,
    codomain: Codomain,
}

impl<Domain, Codomain> BatchValue for FjallBatchValue<Domain, Codomain>
where
    Domain: RelationDomain,
    Codomain: RelationCodomain,
    FjallProvider<Domain, Codomain>: EncodeFor<Codomain, Stored = ByteView>,
{
    fn encode(&self) -> Result<Vec<u8>, Error> {
        encode_codomain_with_ts(&self.provider, self.timestamp, &self.codomain)
    }
}

impl<Domain, Codomain> FjallProvider<Domain, Codomain>
where
    Domain: RelationDomain,
    Codomain: RelationCodomain,
{
    pub fn new(_relation_name: &str, fjall_keyspace: fjall::Keyspace) -> Self {
        Self {
            fjall_keyspace,
            marker: PhantomData,
        }
    }

    pub fn partition(&self) -> &fjall::Keyspace {
        &self.fjall_keyspace
    }
}

impl<Domain, Codomain> FjallProvider<Domain, Codomain>
where
    Domain: RelationDomain,
    Codomain: RelationCodomain,
    Self: EncodeFor<Domain, Stored = ByteView> + EncodeFor<Codomain, Stored = ByteView>,
{
    /// Encode deferred persistence operations into batch ops for the BatchWriter.
    pub fn encode_persist_ops(
        &self,
        ops: &[crate::tx::PersistOp<Domain, Codomain>],
    ) -> Result<Vec<super::batch_writer::BatchOp>, Error> {
        use super::batch_writer::{BatchOp, BatchOpType};
        use crate::tx::PersistOp;

        let mut batch_ops = Vec::with_capacity(ops.len());
        for op in ops {
            match op {
                PersistOp::Put {
                    ts,
                    domain,
                    codomain,
                } => {
                    let key_bytes = <Self as EncodeFor<Domain>>::encode(self, domain)?;
                    let batch_value: Arc<dyn super::batch_writer::BatchValue> =
                        Arc::new(FjallBatchValue {
                            provider: self.clone(),
                            timestamp: *ts,
                            codomain: codomain.clone(),
                        });
                    batch_ops.push(BatchOp {
                        partition: self.fjall_keyspace.clone(),
                        op_type: BatchOpType::Insert {
                            key: key_bytes.to_vec(),
                            value: batch_value,
                        },
                    });
                }
                PersistOp::Del { ts: _, domain } => {
                    let key_bytes = <Self as EncodeFor<Domain>>::encode(self, domain)?;
                    batch_ops.push(BatchOp {
                        partition: self.fjall_keyspace.clone(),
                        op_type: BatchOpType::Delete {
                            key: key_bytes.to_vec(),
                        },
                    });
                }
            }
        }
        Ok(batch_ops)
    }
}

impl<Domain, Codomain> Provider<Domain, Codomain> for FjallProvider<Domain, Codomain>
where
    Domain: RelationDomain,
    Codomain: RelationCodomain,
    Self: EncodeFor<Domain, Stored = ByteView> + EncodeFor<Codomain, Stored = ByteView>,
{
    fn get(&self, domain: &Domain) -> Result<Option<(Timestamp, Codomain)>, Error> {
        let _t = db_counters()
            .timers_hot
            .start(WorldStateTimerOp::ProviderTupleCheck);

        // Hit backing store
        let _t = db_counters()
            .timers_hot
            .start(WorldStateTimerOp::ProviderTupleLoad);
        let key_stored = <Self as EncodeFor<Domain>>::encode(self, domain)?;
        let Some(result) = self
            .fjall_keyspace
            .get(key_stored)
            .map_err(|e| Error::RetrievalFailure(e.to_string()))?
        else {
            return Ok(None);
        };
        let (ts, codomain) = decode_codomain_with_ts::<Self, Codomain>(self, result)?;
        Ok(Some((ts, codomain)))
    }

    fn put(&self, timestamp: Timestamp, domain: &Domain, codomain: &Codomain) -> Result<(), Error> {
        let key_bytes = <Self as EncodeFor<Domain>>::encode(self, domain)?;
        let value = encode_codomain_with_ts(self, timestamp, codomain)?;
        self.fjall_keyspace
            .insert(key_bytes, value)
            .map_err(|error| Error::StorageFailure(error.to_string()))
    }

    fn del(&self, _timestamp: Timestamp, domain: &Domain) -> Result<(), Error> {
        let key_bytes = <Self as EncodeFor<Domain>>::encode(self, domain)?;
        self.fjall_keyspace
            .remove(key_bytes)
            .map_err(|error| Error::StorageFailure(error.to_string()))
    }

    fn scan<F>(&self, predicate: &F) -> Result<Vec<(Timestamp, Domain, Codomain)>, Error>
    where
        F: Fn(&Domain, &Codomain) -> bool,
    {
        let mut result = Vec::new();

        // Scan backing store
        for entry in self.fjall_keyspace.iter() {
            let (key, value) = entry
                .into_inner()
                .map_err(|e| Error::RetrievalFailure(e.to_string()))?;
            let domain = <Self as EncodeFor<Domain>>::decode(self, ByteView::from(key))?;

            let (ts, codomain) = decode_codomain_with_ts::<Self, Codomain>(self, value)?;
            if predicate(&domain, &codomain) {
                result.push((ts, domain, codomain));
            }
        }

        Ok(result)
    }

    fn stop(&self) -> Result<(), Error> {
        // No-op: providers no longer have their own background threads.
        // The BatchWriter is stopped at the MoorDB level.
        Ok(())
    }
}

// ============================================================================
// Fjall Codec - Shared encoding logic for FjallProvider and SnapshotLoader
// ============================================================================

/// Zero-sized type that provides encoding/decoding for all Fjall-stored types.
/// This allows both FjallProvider and SnapshotLoader to share the same encoding logic.
#[derive(Clone, Copy)]
pub(crate) struct FjallCodec;

// ============================================================================
// Per-Type Encoding Implementations for FjallCodec
// ============================================================================
// Each type gets its own EncodeFor impl, allowing custom encoding logic

use crate::{
    AnonymousObjectMetadata, EntityMetadataKey, ObjAndUUIDHolder, StringHolder, provider::Provider,
};
use moor_common::{
    model::{ObjFlag, ObjSet, PropDefs, PropPerms, VerbDefs},
    util::BitEnum,
};
use moor_schema::convert::{
    program_to_stored, stored_to_program, var_from_db_flatbuffer_ref, var_to_db_flatbuffer,
};
use moor_var::{Obj, Var, program::ProgramType};
// Per-type encoding implementations
// Each type can be encoded regardless of whether it's used as Domain or Codomain
// We use a blanket impl for all FjallProvider<Domain, Codomain> combinations

/// Encoding for zerocopy types (IntoBytes + FromBytes) - zero-copy serialization
macro_rules! impl_zerocopy_encode {
    ($type:ty) => {
        impl EncodeFor<$type> for FjallCodec {
            type Stored = ByteView;

            fn encode(&self, value: &$type) -> Result<Self::Stored, Error> {
                use zerocopy::IntoBytes;
                Ok(ByteView::from(IntoBytes::as_bytes(value)))
            }

            fn decode(&self, stored: Self::Stored) -> Result<$type, Error> {
                use zerocopy::FromBytes;
                let bytes = stored.as_ref();
                if bytes.len() != std::mem::size_of::<$type>() {
                    return Err(Error::EncodingFailure);
                }

                // Handle potentially unaligned data safely
                let mut aligned_buffer = vec![0u8; std::mem::size_of::<$type>()];
                aligned_buffer.copy_from_slice(bytes);

                <$type>::read_from_bytes(&aligned_buffer).map_err(|_| Error::EncodingFailure)
            }
        }
    };
}

/// Encoding for types that wrap ByteView - zero-copy passthrough
macro_rules! impl_byteview_wrapper_encode {
    ($type:ty) => {
        impl EncodeFor<$type> for FjallCodec {
            type Stored = ByteView;

            fn encode(&self, value: &$type) -> Result<Self::Stored, Error> {
                Ok(AsRef::<ByteView>::as_ref(value).clone())
            }

            fn decode(&self, stored: Self::Stored) -> Result<$type, Error> {
                Ok(<$type>::from(stored))
            }
        }
    };
}

// Zerocopy types - direct byte access, no serialization overhead
impl_zerocopy_encode!(Obj);
impl_zerocopy_encode!(ObjAndUUIDHolder);
impl_zerocopy_encode!(EntityMetadataKey);
impl_zerocopy_encode!(AnonymousObjectMetadata);
impl_zerocopy_encode!(BitEnum<ObjFlag>);

// ByteView wrappers - zero-copy passthrough
impl_byteview_wrapper_encode!(ObjSet);
impl_byteview_wrapper_encode!(PropPerms);

// Var - FlatBuffer encoding for DB storage (allows lambdas and anonymous objects)
impl EncodeFor<Var> for FjallCodec {
    type Stored = ByteView;

    fn encode(&self, value: &Var) -> Result<Self::Stored, Error> {
        // Convert to FlatBuffer struct
        let fb_var = var_to_db_flatbuffer(value).map_err(|_| Error::EncodingFailure)?;

        // Serialize to bytes
        let mut builder = planus::Builder::new();
        let offset = fb_var.prepare(&mut builder);
        let bytes = builder.finish(offset, None);

        Ok(ByteView::from(bytes))
    }

    fn decode(&self, stored: Self::Stored) -> Result<Var, Error> {
        // Parse FlatBuffer and convert directly from ref (avoids intermediate owned struct copy)
        let fb_ref =
            moor_schema::var::VarRef::read_as_root(&stored).map_err(|_| Error::EncodingFailure)?;
        var_from_db_flatbuffer_ref(fb_ref).map_err(|_| Error::EncodingFailure)
    }
}

// FlatBuffer types - VerbDefs and PropDefs
impl EncodeFor<VerbDefs> for FjallCodec {
    type Stored = ByteView;

    fn encode(&self, value: &VerbDefs) -> Result<Self::Stored, Error> {
        let fb_verbdefs = moor_schema::convert::verbdefs_to_flatbuffer(value)
            .map_err(|_| Error::EncodingFailure)?;
        let mut builder = planus::Builder::new();
        let offset = fb_verbdefs.prepare(&mut builder);
        let bytes = builder.finish(offset, None);
        Ok(ByteView::from(bytes))
    }

    fn decode(&self, stored: Self::Stored) -> Result<VerbDefs, Error> {
        let fb_ref = moor_schema::common::VerbDefsRef::read_as_root(&stored)
            .map_err(|_| Error::EncodingFailure)?;
        let fb_verbdefs: moor_schema::common::VerbDefs =
            fb_ref.try_into().map_err(|_| Error::EncodingFailure)?;
        moor_schema::convert::verbdefs_from_flatbuffer(&fb_verbdefs)
            .map_err(|_| Error::EncodingFailure)
    }
}

impl EncodeFor<PropDefs> for FjallCodec {
    type Stored = ByteView;

    fn encode(&self, value: &PropDefs) -> Result<Self::Stored, Error> {
        let fb_propdefs = moor_schema::convert::propdefs_to_flatbuffer(value)
            .map_err(|_| Error::EncodingFailure)?;
        let mut builder = planus::Builder::new();
        let offset = fb_propdefs.prepare(&mut builder);
        let bytes = builder.finish(offset, None);
        Ok(ByteView::from(bytes))
    }

    fn decode(&self, stored: Self::Stored) -> Result<PropDefs, Error> {
        let fb_ref = moor_schema::common::PropDefsRef::read_as_root(&stored)
            .map_err(|_| Error::EncodingFailure)?;
        let fb_propdefs: moor_schema::common::PropDefs =
            fb_ref.try_into().map_err(|_| Error::EncodingFailure)?;
        moor_schema::convert::propdefs_from_flatbuffer(&fb_propdefs)
            .map_err(|_| Error::EncodingFailure)
    }
}

// StringHolder - direct UTF-8 encoding
impl EncodeFor<StringHolder> for FjallCodec {
    type Stored = ByteView;

    fn encode(&self, value: &StringHolder) -> Result<Self::Stored, Error> {
        Ok(ByteView::from(value.0.as_bytes()))
    }

    fn decode(&self, stored: Self::Stored) -> Result<StringHolder, Error> {
        let s = String::from_utf8(stored.to_vec()).map_err(|_| Error::EncodingFailure)?;
        Ok(StringHolder(s))
    }
}

// ProgramType uses flatbuffer encoding - see below

// ============================================================================
// ProgramType - uses FlatBuffer encoding via program_convert
// ============================================================================

impl EncodeFor<ProgramType> for FjallCodec {
    type Stored = ByteView;

    fn encode(&self, program: &ProgramType) -> Result<Self::Stored, Error> {
        match program {
            ProgramType::MooR(prog) => {
                let stored = program_to_stored(prog)
                    .map_err(|e| Error::StorageFailure(format!("Failed to encode program: {e}")))?;
                // StoredProgram is a ByteView wrapper - extract the inner ByteView
                Ok(AsRef::<ByteView>::as_ref(&stored).clone())
            }
        }
    }

    fn decode(&self, stored: Self::Stored) -> Result<ProgramType, Error> {
        use moor_var::program::stored_program::StoredProgram;

        let stored_program = StoredProgram::from(stored);

        // Read the FlatBuffer and extract the language union
        use moor_schema::program as fb;
        use planus::ReadAsRoot;

        let fb_program = fb::StoredProgramRef::read_as_root(stored_program.as_bytes())
            .map_err(|e| Error::StorageFailure(format!("Failed to read program: {e}")))?;

        let language = fb_program
            .language()
            .map_err(|e| Error::StorageFailure(format!("Failed to read language union: {e}")))?;

        // Match on language variant and construct appropriate ProgramType
        match language {
            fb::StoredProgramLanguageRef::StoredMooRProgram(_moor_ref) => {
                // Decode the full program using the existing function
                let program = stored_to_program(&stored_program).map_err(|e| {
                    Error::StorageFailure(format!("Failed to decode MooR program: {e}"))
                })?;
                Ok(ProgramType::MooR(program))
            }
        }
    }
}

// ============================================================================
// Blanket impl: FjallProvider delegates to FjallCodec for all types
// ============================================================================

impl<Domain, Codomain, T> EncodeFor<T> for FjallProvider<Domain, Codomain>
where
    Domain: RelationDomain,
    Codomain: RelationCodomain,
    FjallCodec: EncodeFor<T, Stored = ByteView>,
{
    type Stored = ByteView;

    fn encode(&self, value: &T) -> Result<Self::Stored, Error> {
        FjallCodec.encode(value)
    }

    fn decode(&self, stored: Self::Stored) -> Result<T, Error> {
        FjallCodec.decode(stored)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::provider::Provider;
    use fjall::KeyspaceCreateOptions;

    #[test]
    fn a_previous_miss_does_not_mask_a_later_value() {
        let tempdir = tempfile::tempdir().unwrap();
        let database = fjall::Database::builder(tempdir.path()).open().unwrap();
        let partition = database
            .keyspace("values", KeyspaceCreateOptions::default)
            .unwrap();
        let provider = FjallProvider::<Obj, Obj>::new("values", partition.clone());
        let key = Obj::mk_id(7);
        let value = Obj::mk_id(8);

        assert_eq!(provider.get(&key).unwrap(), None);

        let encoded_key =
            <FjallProvider<Obj, Obj> as EncodeFor<Obj>>::encode(&provider, &key).unwrap();
        let encoded_value = encode_codomain_with_ts(&provider, Timestamp(1), &value).unwrap();
        partition.insert(encoded_key, encoded_value).unwrap();

        assert_eq!(provider.get(&key).unwrap(), Some((Timestamp(1), value)));
    }
}
