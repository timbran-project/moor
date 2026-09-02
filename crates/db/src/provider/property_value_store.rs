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

//! Physical record codec and bounded reconstruction for incremental property values.

#![allow(
    dead_code,
    reason = "the record codec is activated by later incremental persistence phases"
)]

use crate::{
    ObjAndUUIDHolder, db_counters,
    tx::{OpType, Timestamp, WorkingSet},
};
use moor_common::model::{WorldStateCountOp, WorldStateTimerOp};
use moor_schema::convert::{encode_db_var, var_from_db_flatbuffer_ref};
use moor_var::{List, Var};
use planus::ReadAsRoot;
use zerocopy::{FromBytes, IntoBytes};

const RECORD_MAGIC: [u8; 4] = *b"MPRV";
const RECORD_FORMAT_VERSION: u8 = 1;
const RECORD_HEADER_BYTES: usize = 16;
const PROPERTY_KEY_BYTES: usize = std::mem::size_of::<ObjAndUUIDHolder>();
pub(crate) const PROPERTY_RECORD_KEY_BYTES: usize = PROPERTY_KEY_BYTES + size_of::<u64>();

const FULL_RECORD_KIND: u8 = 0;
const LIST_APPEND_RECORD_KIND: u8 = 1;
const LIST_APPEND_COMPARISON_BUDGET: usize = 128;

pub(crate) const PROPERTY_VALUE_CHAIN_LIMITS: PropertyValueChainLimits =
    PropertyValueChainLimits::new(64, 4 * 1024 * 1024);

#[derive(Clone, Debug, PartialEq)]
pub(crate) struct PreparedPropertyValueOp {
    pub property: ObjAndUUIDHolder,
    pub mutation: PreparedPropertyValueMutation,
}

#[derive(Clone, Debug, PartialEq)]
pub(crate) enum PreparedPropertyValueMutation {
    Replace { value: Var },
    AppendList { suffix: List, final_value: Var },
    Delete,
}

pub(crate) fn prepare_property_value_working_set(
    working_set: WorkingSet<ObjAndUUIDHolder, Var>,
) -> Vec<PreparedPropertyValueOp> {
    let operation_count = working_set.len();
    let (operations, base_index) = working_set.into_parts();
    let mut prepared = Vec::with_capacity(operation_count);

    for (property, operation) in operations {
        let base = base_index.index_lookup(&property).map(|entry| &entry.value);
        prepared.push(PreparedPropertyValueOp {
            property,
            mutation: prepare_property_value_mutation(base, operation.operation),
        });
    }
    prepared
}

fn prepare_property_value_mutation(
    base: Option<&Var>,
    operation: OpType<Var>,
) -> PreparedPropertyValueMutation {
    let value = match operation {
        OpType::Delete => return PreparedPropertyValueMutation::Delete,
        OpType::Insert(value) => {
            db_counters()
                .counters
                .inc(WorldStateCountOp::PropertyValueCompleteReplacement);
            return PreparedPropertyValueMutation::Replace { value };
        }
        OpType::Update(value) => value,
    };

    if value.op_hint() != moor_var::OP_HINT_LIST_APPEND {
        db_counters()
            .counters
            .inc(WorldStateCountOp::PropertyValueCompleteReplacement);
        return PreparedPropertyValueMutation::Replace { value };
    }

    let counters = &db_counters().counters;
    counters.inc(WorldStateCountOp::PropertyListAppendCandidate);
    let _classification_timer = db_counters()
        .timers_rare
        .start(WorldStateTimerOp::PropertyListAppendClassify);
    let Some(base) = base else {
        counters.inc(WorldStateCountOp::PropertyListAppendMissingBase);
        counters.inc(WorldStateCountOp::PropertyValueCompleteReplacement);
        return PreparedPropertyValueMutation::Replace { value };
    };
    let (Some(base), Some(final_value)) = (base.as_list(), value.as_list()) else {
        counters.inc(WorldStateCountOp::PropertyListAppendNonList);
        counters.inc(WorldStateCountOp::PropertyValueCompleteReplacement);
        return PreparedPropertyValueMutation::Replace { value };
    };

    let suffix = match base.append_suffix(final_value, LIST_APPEND_COMPARISON_BUDGET) {
        Ok(suffix) => suffix,
        Err(reason) => {
            let counter = match reason {
                moor_var::ListAppendError::NotLonger => {
                    WorldStateCountOp::PropertyListAppendNotLonger
                }
                moor_var::ListAppendError::PrefixMismatch => {
                    WorldStateCountOp::PropertyListAppendPrefixMismatch
                }
                moor_var::ListAppendError::ComparisonBudgetExceeded => {
                    WorldStateCountOp::PropertyListAppendComparisonBudget
                }
            };
            counters.inc(counter);
            counters.inc(WorldStateCountOp::PropertyValueCompleteReplacement);
            return PreparedPropertyValueMutation::Replace { value };
        }
    };

    let suffix_bytes = suffix
        .iter_ref()
        .map(moor_var::ByteSized::size_bytes)
        .sum::<usize>();
    counters.inc(WorldStateCountOp::PropertyListAppendAccepted);
    counters.add(
        WorldStateCountOp::PropertyListAppendSuffixElements,
        isize::try_from(suffix.len()).unwrap_or(isize::MAX),
    );
    counters.add(
        WorldStateCountOp::PropertyListAppendSuffixBytes,
        isize::try_from(suffix_bytes).unwrap_or(isize::MAX),
    );
    PreparedPropertyValueMutation::AppendList {
        suffix,
        final_value: value,
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum PropertyValueRecordKind {
    Full,
    ListAppend,
}

impl PropertyValueRecordKind {
    fn as_byte(self) -> u8 {
        match self {
            Self::Full => FULL_RECORD_KIND,
            Self::ListAppend => LIST_APPEND_RECORD_KIND,
        }
    }

    fn from_byte(value: u8) -> Result<Self, PropertyValueRecordError> {
        match value {
            FULL_RECORD_KIND => Ok(Self::Full),
            LIST_APPEND_RECORD_KIND => Ok(Self::ListAppend),
            _ => Err(PropertyValueRecordError::UnknownRecordKind(value)),
        }
    }
}

#[derive(Debug, Eq, PartialEq, thiserror::Error)]
pub(crate) enum PropertyValueRecordError {
    #[error("property-value record key has an invalid length")]
    InvalidKeyLength,
    #[error("property-value record has a truncated header")]
    TruncatedHeader,
    #[error("property-value record has an invalid magic value")]
    InvalidMagic,
    #[error("property-value record uses unsupported format version {0}")]
    UnsupportedFormatVersion(u8),
    #[error("property-value record uses unknown kind {0}")]
    UnknownRecordKind(u8),
    #[error("property-value record has nonzero reserved header bytes")]
    InvalidReservedBytes,
    #[error("property-value record contains an invalid Var payload")]
    InvalidVarPayload,
    #[error("property-value chain is empty")]
    EmptyChain,
    #[error("property-value chain does not start with a complete value")]
    MissingFullRecord,
    #[error("property-value chain contains a second complete value")]
    UnexpectedFullRecord,
    #[error("property-value records are not in publication order")]
    PublicationOrder,
    #[error("property-value list append has an empty suffix")]
    EmptyListAppend,
    #[error("property-value list append does not contain a list")]
    InvalidListAppend,
    #[error("property-value list append follows a non-list value")]
    AppendToNonList,
    #[error("property-value chain exceeds its append-record limit")]
    AppendRecordLimit,
    #[error("property-value chain exceeds its append-byte limit")]
    AppendByteLimit,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) struct PropertyValueChainLimits {
    pub max_append_records: usize,
    pub max_append_bytes: usize,
}

impl PropertyValueChainLimits {
    pub const fn new(max_append_records: usize, max_append_bytes: usize) -> Self {
        Self {
            max_append_records,
            max_append_bytes,
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct PropertyValueRecordKey {
    pub property: ObjAndUUIDHolder,
    pub publication_version: u64,
}

pub(crate) fn encode_property_value_record_key(
    property: &ObjAndUUIDHolder,
    publication_version: u64,
) -> [u8; PROPERTY_RECORD_KEY_BYTES] {
    let mut key = [0; PROPERTY_RECORD_KEY_BYTES];
    key[..PROPERTY_KEY_BYTES].copy_from_slice(property.as_bytes());
    key[PROPERTY_KEY_BYTES..].copy_from_slice(&publication_version.to_be_bytes());
    key
}

pub(crate) fn decode_property_value_record_key(
    key: &[u8],
) -> Result<PropertyValueRecordKey, PropertyValueRecordError> {
    if key.len() != PROPERTY_RECORD_KEY_BYTES {
        return Err(PropertyValueRecordError::InvalidKeyLength);
    }

    let property = ObjAndUUIDHolder::read_from_bytes(&key[..PROPERTY_KEY_BYTES])
        .map_err(|_| PropertyValueRecordError::InvalidKeyLength)?;
    let publication_version = u64::from_be_bytes(
        key[PROPERTY_KEY_BYTES..]
            .try_into()
            .map_err(|_| PropertyValueRecordError::InvalidKeyLength)?,
    );
    Ok(PropertyValueRecordKey {
        property,
        publication_version,
    })
}

pub(crate) fn property_value_record_bounds(
    property: &ObjAndUUIDHolder,
) -> (
    [u8; PROPERTY_RECORD_KEY_BYTES],
    [u8; PROPERTY_RECORD_KEY_BYTES],
) {
    (
        encode_property_value_record_key(property, 0),
        encode_property_value_record_key(property, u64::MAX),
    )
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) struct PropertyValueRecordRef<'a> {
    pub logical_timestamp: Timestamp,
    pub kind: PropertyValueRecordKind,
    pub payload: &'a [u8],
}

pub(crate) fn encode_full_record(
    builder: &mut planus::Builder,
    value: &Var,
    logical_timestamp: Timestamp,
) -> Result<Vec<u8>, PropertyValueRecordError> {
    let payload =
        encode_db_var(builder, value).map_err(|_| PropertyValueRecordError::InvalidVarPayload)?;
    Ok(frame_record(
        PropertyValueRecordKind::Full,
        logical_timestamp,
        payload,
    ))
}

pub(crate) fn encode_list_append_record(
    builder: &mut planus::Builder,
    suffix: &List,
    logical_timestamp: Timestamp,
) -> Result<Vec<u8>, PropertyValueRecordError> {
    if suffix.is_empty() {
        return Err(PropertyValueRecordError::EmptyListAppend);
    }
    let suffix = Var::from(suffix.clone());
    let payload =
        encode_db_var(builder, &suffix).map_err(|_| PropertyValueRecordError::InvalidVarPayload)?;
    Ok(frame_record(
        PropertyValueRecordKind::ListAppend,
        logical_timestamp,
        payload,
    ))
}

fn frame_record(
    kind: PropertyValueRecordKind,
    logical_timestamp: Timestamp,
    payload: &[u8],
) -> Vec<u8> {
    let mut record = Vec::with_capacity(RECORD_HEADER_BYTES + payload.len());
    record.extend_from_slice(&RECORD_MAGIC);
    record.push(RECORD_FORMAT_VERSION);
    record.push(kind.as_byte());
    record.extend_from_slice(&[0, 0]);
    record.extend_from_slice(&logical_timestamp.0.to_le_bytes());
    record.extend_from_slice(payload);
    record
}

pub(crate) fn decode_property_value_record(
    record: &[u8],
) -> Result<PropertyValueRecordRef<'_>, PropertyValueRecordError> {
    if record.len() < RECORD_HEADER_BYTES {
        return Err(PropertyValueRecordError::TruncatedHeader);
    }
    if record[..4] != RECORD_MAGIC {
        return Err(PropertyValueRecordError::InvalidMagic);
    }
    if record[4] != RECORD_FORMAT_VERSION {
        return Err(PropertyValueRecordError::UnsupportedFormatVersion(
            record[4],
        ));
    }
    let kind = PropertyValueRecordKind::from_byte(record[5])?;
    if record[6..8] != [0, 0] {
        return Err(PropertyValueRecordError::InvalidReservedBytes);
    }
    let logical_timestamp = Timestamp(u64::from_le_bytes(
        record[8..16]
            .try_into()
            .map_err(|_| PropertyValueRecordError::TruncatedHeader)?,
    ));
    Ok(PropertyValueRecordRef {
        logical_timestamp,
        kind,
        payload: &record[RECORD_HEADER_BYTES..],
    })
}

pub(crate) fn property_value_record_payload_bytes(
    record: &[u8],
) -> Result<usize, PropertyValueRecordError> {
    Ok(decode_property_value_record(record)?.payload.len())
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct PropertyValueChain {
    full_version: u64,
    append_versions: Vec<u64>,
    append_bytes: usize,
}

impl PropertyValueChain {
    pub fn full(publication_version: u64) -> Self {
        Self {
            full_version: publication_version,
            append_versions: Vec::new(),
            append_bytes: 0,
        }
    }

    pub fn full_version(&self) -> u64 {
        self.full_version
    }

    pub fn append_versions(&self) -> &[u64] {
        &self.append_versions
    }

    pub fn append_count(&self) -> usize {
        self.append_versions.len()
    }

    pub fn append_bytes(&self) -> usize {
        self.append_bytes
    }

    pub fn record_versions(&self) -> impl Iterator<Item = u64> + '_ {
        std::iter::once(self.full_version).chain(self.append_versions.iter().copied())
    }

    pub fn reaches_limit(&self, additional_bytes: usize, limits: PropertyValueChainLimits) -> bool {
        self.append_versions.len().saturating_add(1) >= limits.max_append_records
            || self.append_bytes.saturating_add(additional_bytes) >= limits.max_append_bytes
    }

    pub fn push_append(&mut self, publication_version: u64, append_bytes: usize) {
        self.append_versions.push(publication_version);
        self.append_bytes = self.append_bytes.saturating_add(append_bytes);
    }
}

#[derive(Clone, Debug, PartialEq)]
pub(crate) struct ReconstructedPropertyValue {
    pub logical_timestamp: Timestamp,
    pub value: Var,
    pub chain: PropertyValueChain,
}

pub(crate) struct PropertyValueReconstructor {
    limits: PropertyValueChainLimits,
    value: Option<Var>,
    logical_timestamp: Timestamp,
    full_version: u64,
    append_versions: Vec<u64>,
    append_bytes: usize,
    last_version: Option<u64>,
}

impl PropertyValueReconstructor {
    pub fn new(limits: PropertyValueChainLimits) -> Self {
        Self {
            limits,
            value: None,
            logical_timestamp: Timestamp(0),
            full_version: 0,
            append_versions: Vec::new(),
            append_bytes: 0,
            last_version: None,
        }
    }

    pub fn push(
        &mut self,
        publication_version: u64,
        record: &[u8],
    ) -> Result<(), PropertyValueRecordError> {
        if self
            .last_version
            .is_some_and(|last_version| publication_version <= last_version)
        {
            return Err(PropertyValueRecordError::PublicationOrder);
        }

        let record = decode_property_value_record(record)?;
        match (&self.value, record.kind) {
            (None, PropertyValueRecordKind::Full) => {
                self.value = Some(decode_var(record.payload)?);
                self.full_version = publication_version;
            }
            (None, PropertyValueRecordKind::ListAppend) => {
                return Err(PropertyValueRecordError::MissingFullRecord);
            }
            (Some(_), PropertyValueRecordKind::Full) => {
                return Err(PropertyValueRecordError::UnexpectedFullRecord);
            }
            (Some(value), PropertyValueRecordKind::ListAppend) => {
                if self.append_versions.len() >= self.limits.max_append_records {
                    return Err(PropertyValueRecordError::AppendRecordLimit);
                }
                let append_bytes = self
                    .append_bytes
                    .checked_add(record.payload.len())
                    .ok_or(PropertyValueRecordError::AppendByteLimit)?;
                if append_bytes > self.limits.max_append_bytes {
                    return Err(PropertyValueRecordError::AppendByteLimit);
                }

                let suffix = decode_var(record.payload)?;
                let Some(suffix) = suffix.as_list() else {
                    return Err(PropertyValueRecordError::InvalidListAppend);
                };
                if suffix.is_empty() {
                    return Err(PropertyValueRecordError::EmptyListAppend);
                }
                let Some(value) = value.as_list() else {
                    return Err(PropertyValueRecordError::AppendToNonList);
                };
                let appended = value
                    .clone()
                    .append_owned(&Var::from(suffix.clone()))
                    .map_err(|_| PropertyValueRecordError::InvalidListAppend)?
                    .with_cleared_hint();
                self.value = Some(appended);
                self.append_versions.push(publication_version);
                self.append_bytes = append_bytes;
            }
        }

        self.logical_timestamp = record.logical_timestamp;
        self.last_version = Some(publication_version);
        Ok(())
    }

    pub fn finish(self) -> Result<ReconstructedPropertyValue, PropertyValueRecordError> {
        let Some(value) = self.value else {
            return Err(PropertyValueRecordError::EmptyChain);
        };
        Ok(ReconstructedPropertyValue {
            logical_timestamp: self.logical_timestamp,
            value,
            chain: PropertyValueChain {
                full_version: self.full_version,
                append_versions: self.append_versions,
                append_bytes: self.append_bytes,
            },
        })
    }
}

fn decode_var(payload: &[u8]) -> Result<Var, PropertyValueRecordError> {
    let value = moor_schema::var::VarRef::read_as_root(payload)
        .map_err(|_| PropertyValueRecordError::InvalidVarPayload)?;
    var_from_db_flatbuffer_ref(value).map_err(|_| PropertyValueRecordError::InvalidVarPayload)
}

#[cfg(test)]
mod tests {
    use super::*;
    use moor_var::{Obj, v_int, v_list, v_str};
    use uuid::Uuid;

    const LIMITS: PropertyValueChainLimits = PropertyValueChainLimits::new(4, 4096);

    fn holder() -> ObjAndUUIDHolder {
        ObjAndUUIDHolder::new(&Obj::mk_id(42), Uuid::from_u128(0x1234))
    }

    #[test]
    fn prepares_a_shared_list_append() {
        let base = (0..4096).map(v_int).collect::<List>();
        let final_value = base.clone().push_owned(&v_int(4096));

        let prepared = prepare_property_value_mutation(
            Some(&Var::from(base)),
            OpType::Update(final_value.clone()),
        );

        let PreparedPropertyValueMutation::AppendList {
            suffix,
            final_value: prepared_value,
        } = prepared
        else {
            panic!("expected a prepared list append");
        };
        assert_eq!(suffix, List::mk_list(&[v_int(4096)]));
        assert_eq!(prepared_value, final_value);
    }

    #[test]
    fn prepares_replacements_and_deletes() {
        let replacement = prepare_property_value_mutation(None, OpType::Insert(v_int(7)));
        assert_eq!(
            replacement,
            PreparedPropertyValueMutation::Replace { value: v_int(7) }
        );

        let rebuilt_base = (0..4096).map(v_int).collect::<List>();
        let rebuilt_final = (0..4097).map(v_int).collect::<List>();
        let replacement = prepare_property_value_mutation(
            Some(&Var::from(rebuilt_base)),
            OpType::Update(Var::from_list_with_hint(
                rebuilt_final,
                moor_var::OP_HINT_LIST_APPEND,
            )),
        );
        assert!(matches!(
            replacement,
            PreparedPropertyValueMutation::Replace { .. }
        ));

        assert_eq!(
            prepare_property_value_mutation(None, OpType::Delete),
            PreparedPropertyValueMutation::Delete
        );
    }

    #[test]
    fn record_key_orders_publication_versions() {
        let property = holder();
        let first = encode_property_value_record_key(&property, 1);
        let second = encode_property_value_record_key(&property, 256);

        assert_eq!(&first[..PROPERTY_KEY_BYTES], property.as_bytes());
        assert!(first < second);
        assert_eq!(
            decode_property_value_record_key(&second).unwrap(),
            PropertyValueRecordKey {
                property,
                publication_version: 256,
            }
        );
    }

    #[test]
    fn record_bounds_cover_all_publication_versions() {
        let property = holder();
        let (lower, upper) = property_value_record_bounds(&property);

        assert_eq!(lower, encode_property_value_record_key(&property, 0));
        assert_eq!(upper, encode_property_value_record_key(&property, u64::MAX));
    }

    #[test]
    fn record_header_has_stable_bytes() {
        let mut builder = planus::Builder::new();
        let record = encode_full_record(&mut builder, &v_int(7), Timestamp(0x0102)).unwrap();

        assert_eq!(
            &record[..RECORD_HEADER_BYTES],
            b"MPRV\x01\x00\x00\x00\x02\x01\x00\x00\x00\x00\x00\x00"
        );
    }

    #[test]
    fn reconstructs_a_bounded_append_chain() {
        let mut builder = planus::Builder::new();
        let full = encode_full_record(
            &mut builder,
            &v_list(&[v_str("one"), v_str("two")]),
            Timestamp(10),
        )
        .unwrap();
        let suffix = List::mk_list(&[v_str("three"), v_str("four")]);
        let append = encode_list_append_record(&mut builder, &suffix, Timestamp(11)).unwrap();
        let mut reconstructor = PropertyValueReconstructor::new(LIMITS);

        reconstructor.push(100, &full).unwrap();
        reconstructor.push(101, &append).unwrap();
        let value = reconstructor.finish().unwrap();

        assert_eq!(
            value.value,
            v_list(&[v_str("one"), v_str("two"), v_str("three"), v_str("four")])
        );
        assert_eq!(value.logical_timestamp, Timestamp(11));
        assert_eq!(value.value.op_hint(), 0);
        assert_eq!(value.chain.full_version(), 100);
        assert_eq!(value.chain.append_versions(), &[101]);
        assert_eq!(value.chain.append_count(), 1);
        assert_eq!(
            value.chain.append_bytes(),
            append.len() - RECORD_HEADER_BYTES
        );
    }

    #[test]
    fn rejects_an_append_without_a_full_record() {
        let mut builder = planus::Builder::new();
        let suffix = List::mk_list(&[v_int(1)]);
        let append = encode_list_append_record(&mut builder, &suffix, Timestamp(1)).unwrap();
        let mut reconstructor = PropertyValueReconstructor::new(LIMITS);

        assert_eq!(
            reconstructor.push(1, &append),
            Err(PropertyValueRecordError::MissingFullRecord)
        );
    }

    #[test]
    fn rejects_out_of_order_records() {
        let mut builder = planus::Builder::new();
        let full = encode_full_record(&mut builder, &v_list(&[]), Timestamp(1)).unwrap();
        let suffix = List::mk_list(&[v_int(1)]);
        let append = encode_list_append_record(&mut builder, &suffix, Timestamp(2)).unwrap();
        let mut reconstructor = PropertyValueReconstructor::new(LIMITS);

        reconstructor.push(2, &full).unwrap();
        assert_eq!(
            reconstructor.push(1, &append),
            Err(PropertyValueRecordError::PublicationOrder)
        );
    }

    #[test]
    fn rejects_record_and_byte_limit_overflow() {
        let mut builder = planus::Builder::new();
        let full = encode_full_record(&mut builder, &v_list(&[]), Timestamp(1)).unwrap();
        let suffix = List::mk_list(&[v_str("suffix")]);
        let append = encode_list_append_record(&mut builder, &suffix, Timestamp(2)).unwrap();
        let mut count_limited =
            PropertyValueReconstructor::new(PropertyValueChainLimits::new(0, usize::MAX));
        count_limited.push(1, &full).unwrap();
        assert_eq!(
            count_limited.push(2, &append),
            Err(PropertyValueRecordError::AppendRecordLimit)
        );

        let mut byte_limited = PropertyValueReconstructor::new(PropertyValueChainLimits::new(1, 0));
        byte_limited.push(1, &full).unwrap();
        assert_eq!(
            byte_limited.push(2, &append),
            Err(PropertyValueRecordError::AppendByteLimit)
        );
    }

    #[test]
    fn rejects_corrupt_record_headers() {
        assert_eq!(
            decode_property_value_record(b"short"),
            Err(PropertyValueRecordError::TruncatedHeader)
        );

        let mut record = vec![0; RECORD_HEADER_BYTES];
        record[..4].copy_from_slice(&RECORD_MAGIC);
        record[4] = RECORD_FORMAT_VERSION;
        record[5] = 99;
        assert_eq!(
            decode_property_value_record(&record),
            Err(PropertyValueRecordError::UnknownRecordKind(99))
        );

        record[5] = FULL_RECORD_KIND;
        record[4] = RECORD_FORMAT_VERSION + 1;
        assert_eq!(
            decode_property_value_record(&record),
            Err(PropertyValueRecordError::UnsupportedFormatVersion(2))
        );

        record[4] = RECORD_FORMAT_VERSION;
        record[6] = 1;
        assert_eq!(
            decode_property_value_record(&record),
            Err(PropertyValueRecordError::InvalidReservedBytes)
        );
    }

    #[test]
    fn rejects_invalid_chain_shapes() {
        let mut builder = planus::Builder::new();
        let full = encode_full_record(&mut builder, &v_list(&[]), Timestamp(1)).unwrap();
        let second_full = encode_full_record(&mut builder, &v_list(&[]), Timestamp(2)).unwrap();
        let mut reconstructor = PropertyValueReconstructor::new(LIMITS);
        reconstructor.push(1, &full).unwrap();
        assert_eq!(
            reconstructor.push(2, &second_full),
            Err(PropertyValueRecordError::UnexpectedFullRecord)
        );

        let empty = PropertyValueReconstructor::new(LIMITS);
        assert_eq!(empty.finish(), Err(PropertyValueRecordError::EmptyChain));
    }

    #[test]
    fn rejects_invalid_append_payloads() {
        let mut builder = planus::Builder::new();
        assert_eq!(
            encode_list_append_record(&mut builder, &List::mk_list(&[]), Timestamp(1)),
            Err(PropertyValueRecordError::EmptyListAppend)
        );

        let full = encode_full_record(&mut builder, &v_int(1), Timestamp(1)).unwrap();
        let suffix = List::mk_list(&[v_int(2)]);
        let append = encode_list_append_record(&mut builder, &suffix, Timestamp(2)).unwrap();
        let mut reconstructor = PropertyValueReconstructor::new(LIMITS);
        reconstructor.push(1, &full).unwrap();
        assert_eq!(
            reconstructor.push(2, &append),
            Err(PropertyValueRecordError::AppendToNonList)
        );
    }
}
