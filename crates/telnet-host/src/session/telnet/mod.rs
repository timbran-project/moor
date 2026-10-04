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

//! Sans-IO telnet protocol layer: option negotiation (RFC 1143), negotiation policy, and the
//! out-of-band protocols the host implements (GMCP, MSDP, MSSP, NAWS, TTYPE/MTTS, CHARSET,
//! EOR, MCCP2, MXP start-up).
//!
//! Nothing here performs I/O. The codec turns bytes into [`TelnetEvent`]s; the
//! [`TelnetNegotiator`] turns events and local requests into [`Action`]s, which the session
//! applies.

pub mod charset;
pub mod consts;
pub mod event;
pub mod gmcp;
pub mod msdp;
pub mod mssp;
pub mod naws;
pub mod negotiator;
pub mod options;
pub mod ttype;

pub use charset::Charset;
pub use event::{TelnetEvent, Verb};
pub use negotiator::{Action, OutFrame, PromptMark, ProtocolPolicy, TelnetNegotiator};
pub use options::Side;
