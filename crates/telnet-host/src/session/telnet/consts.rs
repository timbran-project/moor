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

//! Telnet command bytes (RFC 854, RFC 885) and the option numbers the host knows about.

/// Interpret As Command.
pub const IAC: u8 = 255;
pub const DONT: u8 = 254;
pub const DO: u8 = 253;
pub const WONT: u8 = 252;
pub const WILL: u8 = 251;
/// Subnegotiation begin.
pub const SB: u8 = 250;
/// Go ahead.
pub const GA: u8 = 249;
/// Subnegotiation end.
pub const SE: u8 = 240;
pub const NOP: u8 = 241;
/// End of record (RFC 885), used as a prompt mark.
pub const EOR: u8 = 239;

pub const OPT_ECHO: u8 = 1;
pub const OPT_SGA: u8 = 3;
pub const OPT_TTYPE: u8 = 24;
pub const OPT_EOR: u8 = 25;
pub const OPT_NAWS: u8 = 31;
pub const OPT_CHARSET: u8 = 42;
pub const OPT_MSDP: u8 = 69;
pub const OPT_MSSP: u8 = 70;
pub const OPT_MCCP2: u8 = 86;
pub const OPT_MXP: u8 = 91;
pub const OPT_GMCP: u8 = 201;
