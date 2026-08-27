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
use std::{any::Any, marker::PhantomData};

/// Fjall backing provider used for startup reads and encoding transaction writes.
#[derive(Clone)]
pub(crate) struct FjallProvider<Domain, Codomain>
where
    Domain: RelationDomain,
    Codomain: RelationCodomain,
{
    relation_name: &'static str,
    fjall_keyspace: fjall::Keyspace,
    marker: PhantomData<fn() -> (Domain, Codomain)>,
}

const TIMESTAMP_BYTES: usize = std::mem::size_of::<u64>();

fn frame_value(payload: &[u8], timestamp: Timestamp) -> Slice {
    let mut framed = Vec::with_capacity(payload.len() + TIMESTAMP_BYTES);
    framed.extend_from_slice(payload);
    framed.extend_from_slice(&timestamp.0.to_le_bytes());
    framed.into()
}

pub(crate) fn decode_fjall_value<Codomain>(
    user_value: Slice,
) -> Result<(Timestamp, Codomain), Error>
where
    FjallCodec: EncodeFor<Codomain, Stored = ByteView>,
{
    let stored = ByteView::from(user_value);
    let Some(payload_len) = stored.len().checked_sub(TIMESTAMP_BYTES) else {
        return Err(Error::EncodingFailure);
    };
    let timestamp = Timestamp(u64::from_le_bytes(
        stored[payload_len..]
            .try_into()
            .map_err(|_| Error::EncodingFailure)?,
    ));
    let payload = stored.slice(..payload_len);
    let codomain = FjallCodec.decode(payload)?;
    Ok((timestamp, codomain))
}

pub(crate) trait EncodeFjallValue<T>: EncodeFor<T, Stored = ByteView> {
    fn encode_fjall_value(&self, value: &T, timestamp: Timestamp) -> Result<Slice, Error>;
}

fn encode_flatbuffer<T>(root: impl WriteAsOffset<T>) -> ByteView {
    let mut builder = planus::Builder::new();
    let bytes = builder.finish(root, None);
    ByteView::from(bytes)
}

fn frame_flatbuffer<T>(root: impl WriteAsOffset<T>, timestamp: Timestamp) -> Slice {
    let mut builder = planus::Builder::new();
    let bytes = builder.finish(root, None);
    frame_value(bytes, timestamp)
}

struct FjallBatchValue<Codomain>
where
    Codomain: RelationCodomain,
{
    codomain: Codomain,
}

impl<Codomain> BatchValue for FjallBatchValue<Codomain>
where
    Codomain: RelationCodomain,
    FjallCodec: EncodeFjallValue<Codomain>,
{
    fn encode(self: Box<Self>, timestamp: Timestamp) -> Result<Slice, Error> {
        FjallCodec.encode_fjall_value(&self.codomain, timestamp)
    }
}

impl<Domain, Codomain> FjallProvider<Domain, Codomain>
where
    Domain: RelationDomain,
    Codomain: RelationCodomain,
{
    pub fn new(relation_name: &'static str, fjall_keyspace: fjall::Keyspace) -> Self {
        Self {
            relation_name,
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
    FjallCodec: EncodeFjallValue<Codomain>,
{
    /// Consume a published working set into operations for the BatchWriter.
    pub fn encode_working_set(
        &self,
        working_set: crate::tx::WorkingSet<Domain, Codomain>,
    ) -> Result<Vec<super::batch_writer::BatchOp>, Error> {
        use super::batch_writer::{BatchOp, BatchOpType};
        use crate::tx::OpType;

        let mut batch_ops = Vec::with_capacity(working_set.len());
        for (domain, op) in working_set.tuples() {
            match op.operation {
                OpType::Insert(codomain) | OpType::Update(codomain) => {
                    let key_bytes = <Self as EncodeFor<Domain>>::encode(self, &domain)?;
                    let source = self.batch_op_source(&domain);
                    let batch_value: Box<dyn super::batch_writer::BatchValue> =
                        Box::new(FjallBatchValue { codomain });
                    batch_ops.push(BatchOp {
                        partition: self.fjall_keyspace.clone(),
                        op_type: BatchOpType::Insert {
                            key: key_bytes.into(),
                            value: batch_value,
                        },
                        source,
                    });
                }
                OpType::Delete => {
                    let key_bytes = <Self as EncodeFor<Domain>>::encode(self, &domain)?;
                    batch_ops.push(BatchOp {
                        partition: self.fjall_keyspace.clone(),
                        op_type: BatchOpType::Delete {
                            key: key_bytes.into(),
                        },
                        source: self.batch_op_source(&domain),
                    });
                }
            }
        }
        Ok(batch_ops)
    }

    fn batch_op_source(&self, domain: &Domain) -> super::batch_writer::BatchOpSource {
        use super::batch_writer::BatchOpSource;

        if matches!(self.relation_name, "object_propvalues" | "object_propflags")
            && let Some(holder) =
                (domain as &dyn Any).downcast_ref::<crate::model::ObjAndUUIDHolder>()
        {
            return BatchOpSource::Property {
                relation: self.relation_name,
                object: holder.obj(),
                uuid: holder.uuid(),
            };
        }

        BatchOpSource::Relation(self.relation_name)
    }
}

impl<Domain, Codomain> Provider<Domain, Codomain> for FjallProvider<Domain, Codomain>
where
    Domain: RelationDomain,
    Codomain: RelationCodomain,
    Self: EncodeFor<Domain, Stored = ByteView> + EncodeFor<Codomain, Stored = ByteView>,
    FjallCodec: EncodeFjallValue<Codomain>,
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
        Ok(Some(decode_fjall_value(result)?))
    }

    fn put(&self, timestamp: Timestamp, domain: &Domain, codomain: &Codomain) -> Result<(), Error> {
        let key_bytes = <Self as EncodeFor<Domain>>::encode(self, domain)?;
        let value = FjallCodec.encode_fjall_value(codomain, timestamp)?;
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

            let (timestamp, codomain) = decode_fjall_value(value)?;
            if predicate(&domain, &codomain) {
                result.push((timestamp, domain, codomain));
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
use moor_schema::convert::{stored_to_program, var_from_db_flatbuffer_ref, var_to_db_flatbuffer};
use moor_schema::convert_program::encode_program_to_fb;
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

        Ok(encode_flatbuffer(fb_var))
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
        Ok(encode_flatbuffer(fb_verbdefs))
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
        Ok(encode_flatbuffer(fb_propdefs))
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
                let stored = encode_program_to_fb(prog)
                    .map_err(|e| Error::StorageFailure(format!("Failed to encode program: {e}")))?;
                Ok(encode_flatbuffer(stored))
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

macro_rules! impl_fjall_value_from_bytes {
    ($type:ty) => {
        impl EncodeFjallValue<$type> for FjallCodec {
            fn encode_fjall_value(
                &self,
                value: &$type,
                timestamp: Timestamp,
            ) -> Result<Slice, Error> {
                use zerocopy::IntoBytes;
                Ok(frame_value(IntoBytes::as_bytes(value), timestamp))
            }
        }
    };
}

macro_rules! impl_fjall_value_from_byteview {
    ($type:ty) => {
        impl EncodeFjallValue<$type> for FjallCodec {
            fn encode_fjall_value(
                &self,
                value: &$type,
                timestamp: Timestamp,
            ) -> Result<Slice, Error> {
                Ok(frame_value(AsRef::<ByteView>::as_ref(value), timestamp))
            }
        }
    };
}

impl_fjall_value_from_bytes!(Obj);
impl_fjall_value_from_bytes!(BitEnum<ObjFlag>);
impl_fjall_value_from_bytes!(AnonymousObjectMetadata);
impl_fjall_value_from_byteview!(ObjSet);
impl_fjall_value_from_byteview!(PropPerms);

impl EncodeFjallValue<StringHolder> for FjallCodec {
    fn encode_fjall_value(
        &self,
        value: &StringHolder,
        timestamp: Timestamp,
    ) -> Result<Slice, Error> {
        Ok(frame_value(value.0.as_bytes(), timestamp))
    }
}

impl EncodeFjallValue<Var> for FjallCodec {
    fn encode_fjall_value(&self, value: &Var, timestamp: Timestamp) -> Result<Slice, Error> {
        let fb_var = var_to_db_flatbuffer(value).map_err(|_| Error::EncodingFailure)?;
        Ok(frame_flatbuffer(fb_var, timestamp))
    }
}

impl EncodeFjallValue<VerbDefs> for FjallCodec {
    fn encode_fjall_value(&self, value: &VerbDefs, timestamp: Timestamp) -> Result<Slice, Error> {
        let fb_verbdefs = moor_schema::convert::verbdefs_to_flatbuffer(value)
            .map_err(|_| Error::EncodingFailure)?;
        Ok(frame_flatbuffer(fb_verbdefs, timestamp))
    }
}

impl EncodeFjallValue<PropDefs> for FjallCodec {
    fn encode_fjall_value(&self, value: &PropDefs, timestamp: Timestamp) -> Result<Slice, Error> {
        let fb_propdefs = moor_schema::convert::propdefs_to_flatbuffer(value)
            .map_err(|_| Error::EncodingFailure)?;
        Ok(frame_flatbuffer(fb_propdefs, timestamp))
    }
}

impl EncodeFjallValue<ProgramType> for FjallCodec {
    fn encode_fjall_value(
        &self,
        program: &ProgramType,
        timestamp: Timestamp,
    ) -> Result<Slice, Error> {
        match program {
            ProgramType::MooR(program) => {
                let stored = encode_program_to_fb(program).map_err(|error| {
                    Error::StorageFailure(format!("Failed to encode program: {error}"))
                })?;
                Ok(frame_flatbuffer(stored, timestamp))
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
    use moor_var::v_str;

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

        provider.put(Timestamp(17), &key, &value).unwrap();

        assert_eq!(provider.get(&key).unwrap(), Some((Timestamp(17), value)));
    }

    #[test]
    fn stored_values_suffix_the_timestamp_outside_the_codec_payload() {
        let tempdir = tempfile::tempdir().unwrap();
        let database = fjall::Database::builder(tempdir.path()).open().unwrap();
        let partition = database
            .keyspace("values", KeyspaceCreateOptions::default)
            .unwrap();
        let provider = FjallProvider::<Obj, Obj>::new("values", partition.clone());
        let key = Obj::mk_id(7);
        let value = Obj::mk_id(8);

        provider.put(Timestamp(123), &key, &value).unwrap();

        let encoded_key = FjallCodec.encode(&key).unwrap();
        let encoded_value = FjallCodec.encode(&value).unwrap();
        let stored = partition.get(encoded_key).unwrap().unwrap();
        let payload_len = stored.len() - TIMESTAMP_BYTES;
        assert_eq!(&stored[..payload_len], &*encoded_value);
        assert_eq!(&stored[payload_len..], &123_u64.to_le_bytes());
        assert_eq!(provider.get(&key).unwrap(), Some((Timestamp(123), value)));
    }

    #[test]
    fn flatbuffer_payload_remains_valid_inside_timestamp_frame() {
        let tempdir = tempfile::tempdir().unwrap();
        let database = fjall::Database::builder(tempdir.path()).open().unwrap();
        let partition = database
            .keyspace("values", KeyspaceCreateOptions::default)
            .unwrap();
        let provider = FjallProvider::<Obj, Var>::new("values", partition.clone());
        let key = Obj::mk_id(7);
        let value = v_str(&"context".repeat(1_024));

        provider.put(Timestamp(456), &key, &value).unwrap();

        let encoded_key = FjallCodec.encode(&key).unwrap();
        let encoded_value = FjallCodec.encode(&value).unwrap();
        let stored = partition.get(encoded_key).unwrap().unwrap();
        let payload_len = stored.len() - TIMESTAMP_BYTES;
        assert_eq!(&stored[..payload_len], &*encoded_value);
        assert_eq!(&stored[payload_len..], &456_u64.to_le_bytes());
        assert_eq!(provider.get(&key).unwrap(), Some((Timestamp(456), value)));
    }
}
