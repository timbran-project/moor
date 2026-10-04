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

//! Codec for telnet connections: line or binary input, telnet protocol framing, explicit flush
//! control, charset transcoding, prompt marks, and MCCP2 output compression.
//!
//! Input in text mode goes through a byte-at-a-time telnet state machine, modelled after
//! ToastStunt's `process_telnet_byte` in network.cc. Protocol elements are emitted as
//! [`ConnectionItem::Telnet`]; text accumulates into lines decoded with the codec's
//! [`Charset`]. `IAC IAC` in text is a literal 0xFF byte.

use bytes::{Buf, BufMut, Bytes, BytesMut};
use flate2::{Compress, Compression, FlushCompress, Status};
use std::{fmt, io};
use tokio_util::codec::{Decoder, Encoder};
use tracing::warn;

use super::telnet::{
    Charset, PromptMark, TelnetEvent, Verb,
    consts::{EOR, GA, IAC, OPT_MCCP2, SB, SE},
    event::write_subneg,
    negotiator::DEFAULT_MAX_SUBNEG,
};

/// Connection mode determines how data is parsed and handled
#[derive(Copy, Debug, Clone, PartialEq, Eq)]
pub enum ConnectionMode {
    /// Text mode: parse input into lines, handle line endings
    Text,
    /// Binary mode: pass through raw bytes without processing
    Binary,
}

/// Telnet protocol parsing state, modeled after ToastStunt's TelnetState enum.
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
enum TelnetState {
    /// Processing normal text input
    Normal,
    /// Just saw IAC byte (0xFF)
    Iac,
    /// Reading option byte after WILL/WONT/DO/DONT
    Negotiate(Verb),
    /// Reading the option byte after IAC SB
    SubnegOption,
    /// Inside subnegotiation data
    Subneg,
    /// Saw IAC while inside subnegotiation
    SubnegIac,
}

/// Items emitted by the decoder based on connection mode
#[derive(Debug)]
pub enum ConnectionItem {
    /// A complete line (text mode only)
    Line(String),
    /// Raw bytes (binary mode)
    Bytes(Bytes),
    /// A telnet protocol element (text mode only)
    Telnet(TelnetEvent),
}

/// Frames that can be encoded and sent
#[derive(Debug)]
pub enum ConnectionFrame {
    /// Send a line with automatic newline appending
    Line(String),
    /// Send raw text without adding newline (for no_newline attribute)
    RawText(String),
    /// Send raw bytes without modification
    Bytes(Bytes),
    /// Explicit flush command
    Flush,
    /// Switch codec mode (text vs binary)
    SetMode(ConnectionMode),
    /// `IAC SB <option> <payload> IAC SE`; 0xFF in `payload` is escaped
    Subneg { option: u8, payload: Bytes },
    /// Telnet protocol bytes, written as they are
    Telnet(Bytes),
    /// The end of a prompt: written as the current [`PromptMark`]
    PromptEnd,
    /// Change what [`ConnectionFrame::PromptEnd`] writes
    SetPromptMark(PromptMark),
    /// Change the charset of text input and output
    SetCharset(Charset),
    /// Write `IAC SB MCCP2 IAC SE`, then compress all later output
    StartCompress,
    /// End the compressed stream; later output is uncompressed
    StopCompress,
}

/// Errors that can occur during codec operations
#[derive(Debug)]
pub enum ConnectionCodecError {
    /// Line exceeded maximum length in text mode
    MaxLineLengthExceeded,
    /// IO error occurred
    Io(io::Error),
}

impl fmt::Display for ConnectionCodecError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ConnectionCodecError::MaxLineLengthExceeded => {
                write!(f, "maximum line length exceeded")
            }
            ConnectionCodecError::Io(e) => write!(f, "IO error: {e}"),
        }
    }
}

impl std::error::Error for ConnectionCodecError {}

impl From<io::Error> for ConnectionCodecError {
    fn from(e: io::Error) -> Self {
        ConnectionCodecError::Io(e)
    }
}

/// Custom codec supporting both text and binary modes with telnet protocol
/// handling and explicit flush control, similar to LambdaMOO/ToastStunt.
pub struct ConnectionCodec {
    mode: ConnectionMode,
    /// Telnet protocol parsing state (text mode only)
    telnet_state: TelnetState,
    /// Accumulates text bytes for the current line being parsed
    line_buf: Vec<u8>,
    /// Option of the subnegotiation being read
    subneg_option: u8,
    /// Unescaped data of the subnegotiation being read
    subneg_buf: Vec<u8>,
    /// The current subnegotiation exceeded `max_subneg` and is being skipped
    subneg_overflow: bool,
    /// Largest subnegotiation accepted, in unescaped data bytes
    max_subneg: usize,
    /// Maximum allowed line length (None for unlimited)
    max_length: Option<usize>,
    /// Track CR state for proper CRLF handling like LambdaMOO
    last_input_was_cr: bool,
    /// Charset of text input and output
    charset: Charset,
    /// What a prompt end writes
    prompt_mark: PromptMark,
    /// MCCP2 compressor, once compression has started
    compressor: Option<Compress>,
}

impl ConnectionCodec {
    /// Create a new codec in text mode without line length limits
    pub fn new() -> Self {
        Self {
            mode: ConnectionMode::Text,
            telnet_state: TelnetState::Normal,
            line_buf: Vec::new(),
            subneg_option: 0,
            subneg_buf: Vec::new(),
            subneg_overflow: false,
            max_subneg: DEFAULT_MAX_SUBNEG,
            max_length: None,
            last_input_was_cr: false,
            charset: Charset::Utf8,
            prompt_mark: PromptMark::None,
            compressor: None,
        }
    }

    /// Create a new codec in text mode with maximum line length
    #[cfg(test)]
    pub fn new_with_max_length(max_length: usize) -> Self {
        Self {
            max_length: Some(max_length),
            ..Self::new()
        }
    }

    /// Create a new codec in binary mode
    #[cfg(test)]
    pub fn new_binary() -> Self {
        Self {
            mode: ConnectionMode::Binary,
            ..Self::new()
        }
    }

    /// Set connection mode
    pub fn set_mode(&mut self, mode: ConnectionMode) {
        self.mode = mode;
        if mode == ConnectionMode::Binary {
            self.telnet_state = TelnetState::Normal;
            self.subneg_buf.clear();
            self.subneg_overflow = false;
            // Preserve last_input_was_cr across mode switches to handle pending LF from CRLF
        }
    }

    /// Set the largest subnegotiation accepted.
    pub fn set_max_subneg(&mut self, max: usize) {
        self.max_subneg = max;
    }

    pub fn set_prompt_mark(&mut self, mark: PromptMark) {
        self.prompt_mark = mark;
    }

    /// Decode text mode input using a byte-by-byte telnet state machine.
    ///
    /// Each byte is routed through the state machine. Text bytes accumulate in `line_buf`;
    /// subnegotiation data accumulates in `subneg_buf`. The function returns as soon as a
    /// complete item (line or telnet event) is available.
    fn decode_text(
        &mut self,
        buf: &mut BytesMut,
    ) -> Result<Option<ConnectionItem>, ConnectionCodecError> {
        while !buf.is_empty() {
            let c = buf[0];
            buf.advance(1);

            if let Some(item) = self.process_text_byte(c)? {
                return Ok(Some(item));
            }
        }

        Ok(None)
    }

    fn process_text_byte(&mut self, c: u8) -> Result<Option<ConnectionItem>, ConnectionCodecError> {
        match self.telnet_state {
            TelnetState::Normal => self.process_normal_byte(c),
            TelnetState::Iac => self.process_iac_byte(c),
            TelnetState::Negotiate(verb) => {
                self.telnet_state = TelnetState::Normal;
                Ok(Some(ConnectionItem::Telnet(TelnetEvent::Negotiate {
                    verb,
                    option: c,
                })))
            }
            TelnetState::SubnegOption => {
                self.subneg_option = c;
                self.subneg_buf.clear();
                self.subneg_overflow = false;
                self.telnet_state = TelnetState::Subneg;
                Ok(None)
            }
            TelnetState::Subneg => {
                if c == IAC {
                    self.telnet_state = TelnetState::SubnegIac;
                } else {
                    self.push_subneg_byte(c);
                }
                Ok(None)
            }
            TelnetState::SubnegIac => self.process_subneg_iac_byte(c),
        }
    }

    fn process_normal_byte(
        &mut self,
        c: u8,
    ) -> Result<Option<ConnectionItem>, ConnectionCodecError> {
        if c == IAC {
            self.telnet_state = TelnetState::Iac;
            return Ok(None);
        }

        if c == b'\r' || (c == b'\n' && !self.last_input_was_cr) {
            self.last_input_was_cr = c == b'\r';
            return Ok(Some(self.emit_line()));
        }

        if c == b'\n' && self.last_input_was_cr {
            self.last_input_was_cr = false;
            return Ok(None);
        }

        self.last_input_was_cr = false;
        self.push_text_byte(c)?;
        Ok(None)
    }

    fn process_iac_byte(&mut self, c: u8) -> Result<Option<ConnectionItem>, ConnectionCodecError> {
        self.telnet_state = TelnetState::Normal;
        if c == IAC {
            // IAC IAC: a literal 0xFF data byte.
            self.last_input_was_cr = false;
            self.push_text_byte(c)?;
            return Ok(None);
        }
        if c == SB {
            self.telnet_state = TelnetState::SubnegOption;
            return Ok(None);
        }
        if let Some(verb) = Verb::from_byte(c) {
            self.telnet_state = TelnetState::Negotiate(verb);
            return Ok(None);
        }
        Ok(Some(ConnectionItem::Telnet(TelnetEvent::Command(c))))
    }

    fn process_subneg_iac_byte(
        &mut self,
        c: u8,
    ) -> Result<Option<ConnectionItem>, ConnectionCodecError> {
        if c == IAC {
            self.push_subneg_byte(IAC);
            self.telnet_state = TelnetState::Subneg;
            return Ok(None);
        }
        if c == SE {
            self.telnet_state = TelnetState::Normal;
            return Ok(self.finish_subneg());
        }
        // IAC <cmd> inside a subnegotiation: the peer is broken. Drop the subnegotiation and
        // read the command as if it stood alone, as libtelnet does.
        warn!(
            option = self.subneg_option,
            cmd = c,
            "telnet command inside subnegotiation; subnegotiation dropped"
        );
        self.subneg_buf.clear();
        self.subneg_overflow = false;
        self.process_iac_byte(c)
    }

    fn push_subneg_byte(&mut self, c: u8) {
        if self.subneg_overflow {
            return;
        }
        if self.subneg_buf.len() >= self.max_subneg {
            self.subneg_overflow = true;
            self.subneg_buf = Vec::new();
            return;
        }
        self.subneg_buf.push(c);
    }

    fn finish_subneg(&mut self) -> Option<ConnectionItem> {
        if self.subneg_overflow {
            self.subneg_overflow = false;
            warn!(
                option = self.subneg_option,
                max = self.max_subneg,
                "subnegotiation over the size limit discarded"
            );
            return None;
        }
        let data = Bytes::from(std::mem::take(&mut self.subneg_buf));
        Some(ConnectionItem::Telnet(TelnetEvent::Subneg {
            option: self.subneg_option,
            data,
        }))
    }

    fn push_text_byte(&mut self, c: u8) -> Result<(), ConnectionCodecError> {
        if c != 0x09 && (c < 0x20 || c == 0x7F) {
            return Ok(());
        }

        self.line_buf.push(c);
        if let Some(max) = self.max_length
            && self.line_buf.len() > max
        {
            self.line_buf.clear();
            return Err(ConnectionCodecError::MaxLineLengthExceeded);
        }
        Ok(())
    }

    fn emit_line(&mut self) -> ConnectionItem {
        let line = self.charset.decode(&self.line_buf);
        self.line_buf.clear();
        ConnectionItem::Line(line)
    }

    /// Write the bytes of one frame, before any compression.
    fn encode_plain(&mut self, frame: ConnectionFrame, buf: &mut BytesMut) {
        match frame {
            ConnectionFrame::Line(line) => {
                self.charset.encode_into(&line, buf);
                buf.extend_from_slice(b"\r\n"); // telnet protocol requires CRLF
            }
            ConnectionFrame::RawText(text) => self.charset.encode_into(&text, buf),
            ConnectionFrame::Bytes(bytes) | ConnectionFrame::Telnet(bytes) => {
                buf.extend_from_slice(&bytes)
            }
            ConnectionFrame::Subneg { option, payload } => write_subneg(option, &payload, buf),
            ConnectionFrame::PromptEnd => match self.prompt_mark {
                PromptMark::None => {}
                PromptMark::Ga => buf.put_slice(&[IAC, GA]),
                PromptMark::Eor => buf.put_slice(&[IAC, EOR]),
            },
            // The framing layer flushes; nothing is written.
            ConnectionFrame::Flush => {}
            ConnectionFrame::SetMode(mode) => self.set_mode(mode),
            ConnectionFrame::SetPromptMark(mark) => self.prompt_mark = mark,
            ConnectionFrame::SetCharset(charset) => self.charset = charset,
            ConnectionFrame::StartCompress | ConnectionFrame::StopCompress => {
                unreachable!("handled in encode")
            }
        }
    }
}

impl Default for ConnectionCodec {
    fn default() -> Self {
        Self::new()
    }
}

impl Decoder for ConnectionCodec {
    type Item = ConnectionItem;
    type Error = ConnectionCodecError;

    fn decode(&mut self, buf: &mut BytesMut) -> Result<Option<Self::Item>, Self::Error> {
        if buf.is_empty() {
            return Ok(None);
        }

        match self.mode {
            ConnectionMode::Text => self.decode_text(buf),
            ConnectionMode::Binary => {
                // In binary mode, pass through all available bytes
                let bytes = buf.split().freeze();
                Ok(Some(ConnectionItem::Bytes(bytes)))
            }
        }
    }
}

impl Encoder<ConnectionFrame> for ConnectionCodec {
    type Error = ConnectionCodecError;

    fn encode(&mut self, frame: ConnectionFrame, buf: &mut BytesMut) -> Result<(), Self::Error> {
        match frame {
            ConnectionFrame::StartCompress => {
                if self.compressor.is_some() {
                    return Ok(());
                }
                buf.put_slice(&[IAC, SB, OPT_MCCP2, IAC, SE]);
                self.compressor = Some(Compress::new(Compression::default(), true));
                return Ok(());
            }
            ConnectionFrame::StopCompress => {
                let Some(mut compressor) = self.compressor.take() else {
                    return Ok(());
                };
                deflate(&mut compressor, &[], FlushCompress::Finish, buf)?;
                return Ok(());
            }
            _ => {}
        }
        if self.compressor.is_none() {
            self.encode_plain(frame, buf);
            return Ok(());
        }
        let mut plain = BytesMut::new();
        self.encode_plain(frame, &mut plain);
        if plain.is_empty() {
            return Ok(());
        }
        let Some(compressor) = self.compressor.as_mut() else {
            return Ok(());
        };
        deflate(compressor, &plain, FlushCompress::Sync, buf)?;
        Ok(())
    }
}

/// Compress all of `input` into `out`, flushing with `flush`.
fn deflate(
    compressor: &mut Compress,
    input: &[u8],
    flush: FlushCompress,
    out: &mut BytesMut,
) -> io::Result<()> {
    let start = compressor.total_in();
    let mut chunk: Vec<u8> = Vec::with_capacity(input.len() / 2 + 64);
    loop {
        let consumed = (compressor.total_in() - start) as usize;
        chunk.clear();
        let status = compressor
            .compress_vec(&input[consumed..], &mut chunk, flush)
            .map_err(io::Error::other)?;
        out.put_slice(&chunk);
        let consumed = (compressor.total_in() - start) as usize;
        let output_full = chunk.len() == chunk.capacity();
        if status == Status::StreamEnd {
            return Ok(());
        }
        // zlib is done with a flush once all input is consumed and it left output space unused.
        if consumed == input.len() && !output_full && flush != FlushCompress::Finish {
            return Ok(());
        }
        if status == Status::BufError && !output_full && consumed == input.len() {
            return Err(io::Error::other("compressor made no progress"));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use bytes::BytesMut;

    /// Helper: collect all items from a single decode pass until None
    fn decode_all(codec: &mut ConnectionCodec, buf: &mut BytesMut) -> Vec<ConnectionItem> {
        let mut items = Vec::new();
        while let Some(item) = codec.decode(buf).unwrap() {
            items.push(item);
        }
        items
    }

    /// Helper: extract line text, panicking if not a Line item
    fn expect_line(item: ConnectionItem) -> String {
        match item {
            ConnectionItem::Line(line) => line,
            other => panic!("Expected Line, got {:?}", other),
        }
    }

    /// Helper: the wire form of a telnet event, panicking if not a Telnet item
    fn expect_telnet_cmd(item: ConnectionItem) -> Bytes {
        expect_telnet(item).to_raw()
    }

    fn expect_telnet(item: ConnectionItem) -> TelnetEvent {
        match item {
            ConnectionItem::Telnet(event) => event,
            other => panic!("Expected Telnet, got {:?}", other),
        }
    }

    #[test]
    fn test_text_mode_line_parsing_both() {
        let mut codec = ConnectionCodec::new();
        let mut buf = BytesMut::from("hello\nworld\r\n");

        // First line (LF ending)
        let item = codec.decode(&mut buf).unwrap().unwrap();
        assert_eq!(expect_line(item), "hello");

        // Second line (CRLF ending - CR triggers completion, LF ignored)
        let item = codec.decode(&mut buf).unwrap().unwrap();
        assert_eq!(expect_line(item), "world");

        // No more data
        assert!(codec.decode(&mut buf).unwrap().is_none());
    }

    #[test]
    fn test_lambdamoo_cr_lf_handling() {
        let mut codec = ConnectionCodec::new();

        // Test standalone CR
        let mut buf = BytesMut::from("line1\r");
        let item = codec.decode(&mut buf).unwrap().unwrap();
        assert_eq!(expect_line(item), "line1");

        // Test LF after CR should be ignored, then parse next line
        let mut buf = BytesMut::from("\nline2\n");
        let item = codec.decode(&mut buf).unwrap().unwrap();
        assert_eq!(expect_line(item), "line2");

        // Test standalone LF (not after CR)
        let mut buf = BytesMut::from("line3\n");
        let item = codec.decode(&mut buf).unwrap().unwrap();
        assert_eq!(expect_line(item), "line3");

        // Test CRLF sequence
        let mut buf = BytesMut::from("line4\r\nline5\n");

        // CR should trigger line completion
        let item = codec.decode(&mut buf).unwrap().unwrap();
        assert_eq!(expect_line(item), "line4");

        // LF after CR should be ignored, then next line should work normally
        let item = codec.decode(&mut buf).unwrap().unwrap();
        assert_eq!(expect_line(item), "line5");
    }

    #[test]
    fn test_binary_mode() {
        let mut codec = ConnectionCodec::new_binary();
        let test_data = b"hello\nworld\x00\xff";
        let mut buf = BytesMut::from(&test_data[..]);

        let item = codec.decode(&mut buf).unwrap().unwrap();
        match item {
            ConnectionItem::Bytes(bytes) => assert_eq!(bytes, &test_data[..]),
            _ => panic!("Expected bytes"),
        }
    }

    #[test]
    fn test_encoding_line() {
        let mut codec = ConnectionCodec::new();
        let mut buf = BytesMut::new();

        codec
            .encode(ConnectionFrame::Line("test".to_string()), &mut buf)
            .unwrap();
        assert_eq!(buf, "test\r\n");
    }

    #[test]
    fn test_encoding_raw_text() {
        let mut codec = ConnectionCodec::new();
        let mut buf = BytesMut::new();

        codec
            .encode(ConnectionFrame::RawText("no newline".to_string()), &mut buf)
            .unwrap();
        assert_eq!(buf, "no newline");
    }

    #[test]
    fn test_encoding_bytes() {
        let mut codec = ConnectionCodec::new();
        let mut buf = BytesMut::new();
        let test_bytes = Bytes::from_static(b"raw\x00data");

        codec
            .encode(ConnectionFrame::Bytes(test_bytes.clone()), &mut buf)
            .unwrap();
        assert_eq!(buf, test_bytes);
    }

    #[test]
    fn test_max_line_length() {
        let mut codec = ConnectionCodec::new_with_max_length(5);
        let mut buf = BytesMut::from("toolong\n");

        let result = codec.decode(&mut buf);
        assert!(matches!(
            result,
            Err(ConnectionCodecError::MaxLineLengthExceeded)
        ));
    }

    #[test]
    fn test_encoding_set_mode() {
        let mut codec = ConnectionCodec::new();
        let mut output = BytesMut::new();
        let mut input = BytesMut::from(&b"hello\n"[..]);
        assert_eq!(
            expect_line(codec.decode(&mut input).unwrap().unwrap()),
            "hello"
        );

        codec
            .encode(
                ConnectionFrame::SetMode(ConnectionMode::Binary),
                &mut output,
            )
            .unwrap();
        assert!(output.is_empty());
        let mut input = BytesMut::from(&b"hello\n"[..]);
        let ConnectionItem::Bytes(bytes) = codec.decode(&mut input).unwrap().unwrap() else {
            panic!("Expected binary bytes after mode switch");
        };
        assert_eq!(bytes.as_ref(), b"hello\n");
        assert!(input.is_empty());

        codec
            .encode(ConnectionFrame::SetMode(ConnectionMode::Text), &mut output)
            .unwrap();
        assert!(output.is_empty());
        let mut input = BytesMut::from(&b"hello\n"[..]);
        assert_eq!(
            expect_line(codec.decode(&mut input).unwrap().unwrap()),
            "hello"
        );
        assert!(input.is_empty());
    }

    #[test]
    fn test_non_utf8_handling() {
        let mut codec = ConnectionCodec::new();

        // Create buffer with valid ASCII, then invalid UTF-8, then more ASCII
        // 0xC0 followed by ASCII is invalid (incomplete sequence)
        let mut buf = BytesMut::from(&b"hello \xC0 world\n"[..]);

        let item = codec.decode(&mut buf).unwrap().unwrap();
        match item {
            ConnectionItem::Line(line) => {
                // Invalid byte should be replaced with U+FFFD (replacement character)
                assert!(line.contains('\u{FFFD}'));
                assert!(line.starts_with("hello"));
                assert!(line.ends_with("world"));
            }
            _ => panic!("Expected line"),
        }
    }

    #[test]
    fn test_completely_invalid_utf8() {
        let mut codec = ConnectionCodec::new();

        // Use incomplete multi-byte sequences that each produce a replacement char
        // \xC0 is an invalid UTF-8 start byte (overlong encoding)
        let mut buf = BytesMut::from(&b"\xC0a\xC0b\xC0c\n"[..]);

        let item = codec.decode(&mut buf).unwrap().unwrap();
        match item {
            ConnectionItem::Line(line) => {
                // Each \xC0 is an invalid start byte, producing replacement characters
                assert_eq!(line.chars().filter(|&c| c == '\u{FFFD}').count(), 3);
                assert!(line.contains('a') && line.contains('b') && line.contains('c'));
            }
            _ => panic!("Expected line"),
        }
    }

    #[test]
    fn test_utf8_cjk_characters() {
        let mut codec = ConnectionCodec::new();

        // Test CJK characters that have continuation bytes in 0x80-0x9F range
        // 写 = E5 86 99 (0x86 and 0x99 are in the 0x80-0x9F range)
        let test_str = "读写汉字 - 学中文";
        let mut buf = BytesMut::from(format!("{}\n", test_str).as_bytes());

        let item = codec.decode(&mut buf).unwrap().unwrap();
        assert_eq!(expect_line(item), test_str);
    }

    // --- Telnet protocol tests ---

    #[test]
    fn test_telnet_nop_emitted_as_command() {
        let mut codec = ConnectionCodec::new();

        // IAC NOP (0xFF 0xF1) should be emitted as a TelnetCommand
        let mut buf = BytesMut::from(&b"\xFF\xF1hello\n"[..]);

        let item = codec.decode(&mut buf).unwrap().unwrap();
        let cmd = expect_telnet_cmd(item);
        assert_eq!(cmd.as_ref(), &[0xFF, 0xF1]);

        // Text after the NOP should be a normal line
        let item = codec.decode(&mut buf).unwrap().unwrap();
        assert_eq!(expect_line(item), "hello");
    }

    #[test]
    fn test_telnet_nop_standalone() {
        let mut codec = ConnectionCodec::new();

        // IAC NOP with no text — should emit command, buffer empty after
        let mut buf = BytesMut::from(&b"\xFF\xF1"[..]);
        let item = codec.decode(&mut buf).unwrap().unwrap();
        let cmd = expect_telnet_cmd(item);
        assert_eq!(cmd.as_ref(), &[0xFF, 0xF1]);
        assert!(buf.is_empty());

        // Subsequent text should arrive clean
        let mut buf = BytesMut::from(&b"hello\n"[..]);
        let item = codec.decode(&mut buf).unwrap().unwrap();
        assert_eq!(expect_line(item), "hello");
    }

    #[test]
    fn test_telnet_nop_between_lines() {
        let mut codec = ConnectionCodec::new();

        // NOP arriving between two lines of text
        let mut buf = BytesMut::from(&b"line1\r\n\xFF\xF1line2\r\n"[..]);

        let items = decode_all(&mut codec, &mut buf);
        let mut items = items.into_iter();
        assert_eq!(expect_line(items.next().unwrap()), "line1");
        assert_eq!(
            expect_telnet_cmd(items.next().unwrap()).as_ref(),
            &[0xFF, 0xF1]
        );
        assert_eq!(expect_line(items.next().unwrap()), "line2");
        assert!(items.next().is_none());
        assert!(buf.is_empty());
    }

    #[test]
    fn test_telnet_nop_mid_line() {
        let mut codec = ConnectionCodec::new();

        // NOP in the middle of text — text on both sides should join into one line
        let mut buf = BytesMut::from(&b"hel\xFF\xF1lo\n"[..]);

        // First item: the NOP command (emitted when the state machine completes it)
        // But text before/after NOP accumulates in line_buf across the command
        let item = codec.decode(&mut buf).unwrap().unwrap();
        let cmd = expect_telnet_cmd(item);
        assert_eq!(cmd.as_ref(), &[0xFF, 0xF1]);

        // Second item: the complete line with text from both sides of NOP
        let item = codec.decode(&mut buf).unwrap().unwrap();
        assert_eq!(expect_line(item), "hello");
    }

    #[test]
    fn test_telnet_will_echo() {
        let mut codec = ConnectionCodec::new();

        // IAC WILL ECHO (3-byte sequence)
        let mut buf = BytesMut::from(&b"\xFF\xFB\x01hello\n"[..]);

        let item = codec.decode(&mut buf).unwrap().unwrap();
        let cmd = expect_telnet_cmd(item);
        assert_eq!(cmd.as_ref(), &[0xFF, 0xFB, 0x01]); // IAC WILL ECHO

        let item = codec.decode(&mut buf).unwrap().unwrap();
        assert_eq!(expect_line(item), "hello");
    }

    #[test]
    fn test_telnet_do_dont() {
        let mut codec = ConnectionCodec::new();

        // IAC DO NAWS (0xFF 0xFD 0x1F) followed by IAC DONT ECHO (0xFF 0xFE 0x01)
        let mut buf = BytesMut::from(&b"\xFF\xFD\x1F\xFF\xFE\x01ok\n"[..]);

        let item = codec.decode(&mut buf).unwrap().unwrap();
        assert_eq!(expect_telnet_cmd(item).as_ref(), &[0xFF, 0xFD, 0x1F]);

        let item = codec.decode(&mut buf).unwrap().unwrap();
        assert_eq!(expect_telnet_cmd(item).as_ref(), &[0xFF, 0xFE, 0x01]);

        let item = codec.decode(&mut buf).unwrap().unwrap();
        assert_eq!(expect_line(item), "ok");
    }

    #[test]
    fn test_telnet_subnegotiation() {
        let mut codec = ConnectionCodec::new();

        // IAC SB NAWS <width_hi> <width_lo> <height_hi> <height_lo> IAC SE
        let mut buf = BytesMut::from(&b"\xFF\xFA\x1F\x00\x50\x00\x18\xFF\xF0hello\n"[..]);

        let item = codec.decode(&mut buf).unwrap().unwrap();
        let cmd = expect_telnet_cmd(item);
        assert_eq!(
            cmd.as_ref(),
            &[0xFF, 0xFA, 0x1F, 0x00, 0x50, 0x00, 0x18, 0xFF, 0xF0]
        );

        let item = codec.decode(&mut buf).unwrap().unwrap();
        assert_eq!(expect_line(item), "hello");
    }

    #[test]
    fn test_telnet_iac_iac_escape() {
        let mut codec = ConnectionCodec::new();

        // IAC IAC = escaped literal 0xFF, decoded through the charset. In UTF-8 a lone 0xFF is
        // invalid and becomes U+FFFD.
        let mut buf = BytesMut::from(&b"hello\xFF\xFFworld\n"[..]);

        let item = codec.decode(&mut buf).unwrap().unwrap();
        // IAC IAC doesn't emit a command, text on both sides joins
        assert_eq!(expect_line(item), "hello\u{FFFD}world");
    }

    #[test]
    fn test_telnet_multiple_nops() {
        let mut codec = ConnectionCodec::new();

        // Multiple IAC NOP sequences then text
        let mut buf = BytesMut::from(&b"\xFF\xF1\xFF\xF1say hello\n"[..]);

        let items = decode_all(&mut codec, &mut buf);
        let mut items = items.into_iter();
        assert_eq!(
            expect_telnet_cmd(items.next().unwrap()).as_ref(),
            &[0xFF, 0xF1]
        );
        assert_eq!(
            expect_telnet_cmd(items.next().unwrap()).as_ref(),
            &[0xFF, 0xF1]
        );
        assert_eq!(expect_line(items.next().unwrap()), "say hello");
        assert!(items.next().is_none());
        assert!(buf.is_empty());
    }

    #[test]
    fn test_telnet_incomplete_iac_at_end() {
        let mut codec = ConnectionCodec::new();

        // Lone IAC at end of buffer — state preserved for next decode
        let mut buf = BytesMut::from(&b"hello\xFF"[..]);
        let result = codec.decode(&mut buf).unwrap();
        // No complete item yet (line_buf has "hello", telnet_state is Iac)
        assert!(result.is_none());

        // Complete the NOP in the next buffer
        let mut buf = BytesMut::from(&b"\xF1\n"[..]);
        let item = codec.decode(&mut buf).unwrap().unwrap();
        let cmd = expect_telnet_cmd(item);
        assert_eq!(cmd.as_ref(), &[0xFF, 0xF1]);

        // Then the line
        let item = codec.decode(&mut buf).unwrap().unwrap();
        assert_eq!(expect_line(item), "hello");
    }

    #[test]
    fn test_telnet_incomplete_will_at_end() {
        let mut codec = ConnectionCodec::new();

        // IAC WILL at end of buffer — need one more byte
        let mut buf = BytesMut::from(&b"\xFF\xFB"[..]);
        let result = codec.decode(&mut buf).unwrap();
        assert!(result.is_none());

        // Complete with the option byte
        let mut buf = BytesMut::from(&b"\x01ok\n"[..]);
        let item = codec.decode(&mut buf).unwrap().unwrap();
        assert_eq!(expect_telnet_cmd(item).as_ref(), &[0xFF, 0xFB, 0x01]);

        let item = codec.decode(&mut buf).unwrap().unwrap();
        assert_eq!(expect_line(item), "ok");
    }

    #[test]
    fn test_telnet_incomplete_subneg_at_end() {
        let mut codec = ConnectionCodec::new();

        // Incomplete subnegotiation — no IAC SE yet
        let mut buf = BytesMut::from(&b"\xFF\xFA\x1F\x00\x50"[..]);
        let result = codec.decode(&mut buf).unwrap();
        assert!(result.is_none());

        // Complete the subnegotiation
        let mut buf = BytesMut::from(&b"\x00\x18\xFF\xF0done\n"[..]);
        let item = codec.decode(&mut buf).unwrap().unwrap();
        let cmd = expect_telnet_cmd(item);
        assert_eq!(
            cmd.as_ref(),
            &[0xFF, 0xFA, 0x1F, 0x00, 0x50, 0x00, 0x18, 0xFF, 0xF0]
        );

        let item = codec.decode(&mut buf).unwrap().unwrap();
        assert_eq!(expect_line(item), "done");
    }

    #[test]
    fn test_telnet_preserves_utf8() {
        let mut codec = ConnectionCodec::new();

        // IAC NOP followed by UTF-8 CJK text — must not corrupt the multi-byte chars
        let mut buf = BytesMut::new();
        buf.extend_from_slice(b"\xFF\xF1");
        buf.extend_from_slice("读写汉字\n".as_bytes());

        let item = codec.decode(&mut buf).unwrap().unwrap();
        expect_telnet_cmd(item); // NOP

        let item = codec.decode(&mut buf).unwrap().unwrap();
        assert_eq!(expect_line(item), "读写汉字");
    }

    #[test]
    fn test_control_chars_filtered() {
        let mut codec = ConnectionCodec::new();

        // Control characters (except tab) should be filtered from text
        let mut buf = BytesMut::from(&b"he\x01ll\x7Fo\tworld\n"[..]);

        let item = codec.decode(&mut buf).unwrap().unwrap();
        assert_eq!(expect_line(item), "hello\tworld");
    }

    // --- TelnetEvent forms, escaping, limits, charsets, prompt marks, compression ---

    use super::super::telnet::consts::{NOP, OPT_GMCP, OPT_NAWS, WILL};
    use flate2::{Decompress, FlushDecompress};

    fn encode_frame(codec: &mut ConnectionCodec, frame: ConnectionFrame) -> BytesMut {
        let mut buf = BytesMut::new();
        codec.encode(frame, &mut buf).unwrap();
        buf
    }

    /// Feed `input` split at `at` and return every item produced.
    fn decode_split(input: &[u8], at: usize) -> Vec<ConnectionItem> {
        let mut codec = ConnectionCodec::new();
        let mut items = Vec::new();
        let mut first = BytesMut::from(&input[..at]);
        items.extend(decode_all(&mut codec, &mut first));
        let mut second = BytesMut::from(&input[at..]);
        items.extend(decode_all(&mut codec, &mut second));
        items
    }

    /// Feed `input` one byte per call.
    fn decode_bytewise(codec: &mut ConnectionCodec, input: &[u8]) -> Vec<ConnectionItem> {
        let mut items = Vec::new();
        for b in input {
            let mut buf = BytesMut::from(&[*b][..]);
            items.extend(decode_all(codec, &mut buf));
        }
        items
    }

    fn events_and_lines(items: Vec<ConnectionItem>) -> (Vec<TelnetEvent>, Vec<String>) {
        let mut events = Vec::new();
        let mut lines = Vec::new();
        for item in items {
            match item {
                ConnectionItem::Telnet(e) => events.push(e),
                ConnectionItem::Line(l) => lines.push(l),
                ConnectionItem::Bytes(b) => panic!("unexpected bytes {b:?}"),
            }
        }
        (events, lines)
    }

    #[test]
    fn decodes_every_event_form() {
        let mut codec = ConnectionCodec::new();
        let mut buf = BytesMut::from(
            &b"\xFF\xF1\xFF\xF9\xFF\xFB\x01\xFF\xFC\x03\xFF\xFD\x18\xFF\xFE\x1F\xFF\xFA\x1F\x00\x50\x00\x18\xFF\xF0\xFF\xFA\x18\xFF\xF0"[..],
        );
        let events: Vec<_> = decode_all(&mut codec, &mut buf)
            .into_iter()
            .map(expect_telnet)
            .collect();
        assert_eq!(
            events,
            vec![
                TelnetEvent::Command(NOP),
                TelnetEvent::Command(GA),
                TelnetEvent::Negotiate {
                    verb: Verb::Will,
                    option: 1
                },
                TelnetEvent::Negotiate {
                    verb: Verb::Wont,
                    option: 3
                },
                TelnetEvent::Negotiate {
                    verb: Verb::Do,
                    option: 24
                },
                TelnetEvent::Negotiate {
                    verb: Verb::Dont,
                    option: 31
                },
                TelnetEvent::Subneg {
                    option: OPT_NAWS,
                    data: Bytes::from_static(&[0, 0x50, 0, 0x18]),
                },
                TelnetEvent::Subneg {
                    option: 24,
                    data: Bytes::new()
                },
            ]
        );
        assert!(buf.is_empty());
    }

    #[test]
    fn to_raw_round_trips() {
        let events = [
            TelnetEvent::Command(NOP),
            TelnetEvent::Negotiate {
                verb: Verb::Do,
                option: OPT_GMCP,
            },
            TelnetEvent::Subneg {
                option: OPT_GMCP,
                data: Bytes::from_static(b"A.B \"\xFF\xFF\""),
            },
        ];
        for event in events {
            let raw = event.to_raw();
            let mut codec = ConnectionCodec::new();
            let mut buf = BytesMut::from(&raw[..]);
            assert_eq!(
                expect_telnet(codec.decode(&mut buf).unwrap().unwrap()),
                event
            );
            assert!(buf.is_empty());
        }
        let sub = TelnetEvent::Subneg {
            option: 1,
            data: Bytes::from_static(&[0xFF]),
        };
        assert_eq!(sub.to_raw().as_ref(), &[IAC, SB, 1, IAC, IAC, IAC, SE]);
    }

    #[test]
    fn split_at_every_boundary_will() {
        let input = b"ab\xFF\xFB\xC9cd\n";
        for at in 0..=input.len() {
            let (events, lines) = events_and_lines(decode_split(input, at));
            assert_eq!(
                events,
                vec![TelnetEvent::Negotiate {
                    verb: Verb::Will,
                    option: OPT_GMCP
                }],
                "split at {at}"
            );
            assert_eq!(lines, vec!["abcd".to_string()], "split at {at}");
        }
    }

    #[test]
    fn split_at_every_boundary_naws() {
        let input = b"\xFF\xFA\x1F\x00\xFF\xFF\x00\x18\xFF\xF0x\n";
        for at in 0..=input.len() {
            let (events, lines) = events_and_lines(decode_split(input, at));
            assert_eq!(
                events,
                vec![TelnetEvent::Subneg {
                    option: OPT_NAWS,
                    data: Bytes::from_static(&[0x00, 0xFF, 0x00, 0x18]),
                }],
                "split at {at}"
            );
            assert_eq!(lines, vec!["x".to_string()], "split at {at}");
        }
    }

    #[test]
    fn split_at_every_boundary_gmcp_with_escaped_ff() {
        let input = b"\xFF\xFA\xC9Char.Vitals {\"a\":\"\xFF\xFF\"}\xFF\xF0";
        for at in 0..=input.len() {
            let (events, lines) = events_and_lines(decode_split(input, at));
            assert_eq!(
                events,
                vec![TelnetEvent::Subneg {
                    option: OPT_GMCP,
                    data: Bytes::from_static(b"Char.Vitals {\"a\":\"\xFF\"}"),
                }],
                "split at {at}"
            );
            assert!(lines.is_empty());
        }
        let mut codec = ConnectionCodec::new();
        let (events, _) = events_and_lines(decode_bytewise(&mut codec, input));
        assert_eq!(events.len(), 1);
    }

    #[test]
    fn iac_iac_in_text_is_latin1_ydiaeresis() {
        let mut codec = ConnectionCodec::new();
        codec.charset = Charset::Latin1;
        let mut buf = BytesMut::from(&b"a\xFF\xFFb\xE9\n"[..]);
        assert_eq!(
            expect_line(codec.decode(&mut buf).unwrap().unwrap()),
            "aÿbé"
        );
    }

    #[test]
    fn iac_iac_in_text_counts_toward_line_length() {
        let mut codec = ConnectionCodec::new_with_max_length(2);
        let mut buf = BytesMut::from(&b"\xFF\xFF\xFF\xFF\xFF\xFF\n"[..]);
        assert!(matches!(
            codec.decode(&mut buf),
            Err(ConnectionCodecError::MaxLineLengthExceeded)
        ));
    }

    #[test]
    fn iac_iac_in_subneg_is_one_ff() {
        let mut codec = ConnectionCodec::new();
        let mut buf = BytesMut::from(&b"\xFF\xFA\x63\xFF\xFF\xFF\xFF\x01\xFF\xF0"[..]);
        assert_eq!(
            expect_telnet(codec.decode(&mut buf).unwrap().unwrap()),
            TelnetEvent::Subneg {
                option: 0x63,
                data: Bytes::from_static(&[0xFF, 0xFF, 0x01])
            }
        );
    }

    #[test]
    fn command_inside_subneg_drops_it_and_resyncs() {
        let mut codec = ConnectionCodec::new();
        // IAC SB 99 'a' IAC WILL 1 ...: broken peer; the WILL is still seen.
        let mut buf = BytesMut::from(&b"\xFF\xFA\x63a\xFF\xFB\x01ok\n"[..]);
        let (events, lines) = events_and_lines(decode_all(&mut codec, &mut buf));
        assert_eq!(
            events,
            vec![TelnetEvent::Negotiate {
                verb: Verb::Will,
                option: 1
            }]
        );
        assert_eq!(lines, vec!["ok".to_string()]);
    }

    #[test]
    fn subneg_at_cap_is_kept() {
        let mut codec = ConnectionCodec::new();
        codec.set_max_subneg(4);
        let mut buf = BytesMut::from(&b"\xFF\xFA\x63\x01\x02\xFF\xFF\x04\xFF\xF0"[..]);
        assert_eq!(
            expect_telnet(codec.decode(&mut buf).unwrap().unwrap()),
            TelnetEvent::Subneg {
                option: 0x63,
                data: Bytes::from_static(&[1, 2, 0xFF, 4])
            }
        );
    }

    #[test]
    fn subneg_over_cap_is_discarded_and_resyncs() {
        let mut input = b"\xFF\xFA\xC9".to_vec();
        input.extend(std::iter::repeat_n(b'x', 1000));
        // Escaped 0xFF inside the overflow must not end it early.
        input.extend_from_slice(b"\xFF\xFFmore\xFF\xF0line\n\xFF\xFA\x1F\x00\x50\x00\x18\xFF\xF0");
        for bytewise in [false, true] {
            let mut codec = ConnectionCodec::new();
            codec.set_max_subneg(4);
            let items = if bytewise {
                decode_bytewise(&mut codec, &input)
            } else {
                let mut buf = BytesMut::from(&input[..]);
                decode_all(&mut codec, &mut buf)
            };
            let (events, lines) = events_and_lines(items);
            assert_eq!(lines, vec!["line".to_string()]);
            assert_eq!(
                events,
                vec![TelnetEvent::Subneg {
                    option: OPT_NAWS,
                    data: Bytes::from_static(&[0, 0x50, 0, 0x18]),
                }]
            );
        }
    }

    #[test]
    fn default_subneg_cap_is_65536() {
        let mut codec = ConnectionCodec::new();
        let mut input = b"\xFF\xFA\x63".to_vec();
        input.extend(std::iter::repeat_n(b'z', 65536));
        input.extend_from_slice(b"\xFF\xF0");
        let mut buf = BytesMut::from(&input[..]);
        let ConnectionItem::Telnet(TelnetEvent::Subneg { data, .. }) =
            codec.decode(&mut buf).unwrap().unwrap()
        else {
            panic!("expected subneg");
        };
        assert_eq!(data.len(), 65536);

        input.insert(5, b'z');
        let mut buf = BytesMut::from(&input[..]);
        assert!(codec.decode(&mut buf).unwrap().is_none());
        assert!(buf.is_empty());
    }

    #[test]
    fn latin1_decode() {
        let mut codec = ConnectionCodec::new();
        codec.charset = Charset::Latin1;
        let mut buf = BytesMut::from(&b"caf\xE9 \xA3\n"[..]);
        assert_eq!(
            expect_line(codec.decode(&mut buf).unwrap().unwrap()),
            "café £"
        );
        // Control filtering is unchanged in Latin-1 (0x7F dropped, 0x80+ kept).
        let mut buf = BytesMut::from(&b"a\x01\x7Fb\x80\n"[..]);
        assert_eq!(
            expect_line(codec.decode(&mut buf).unwrap().unwrap()),
            "ab\u{80}"
        );
    }

    #[test]
    fn latin1_encode_round_trip_with_ff_escaping() {
        let mut codec = ConnectionCodec::new();
        codec.charset = Charset::Latin1;
        let text = "ÿcafé ÿ";
        let out = encode_frame(&mut codec, ConnectionFrame::Line(text.to_string()));
        assert_eq!(&out[..], b"\xFF\xFFcaf\xE9 \xFF\xFF\r\n");
        let mut back = BytesMut::from(&out[..]);
        assert_eq!(expect_line(codec.decode(&mut back).unwrap().unwrap()), text);

        let out = encode_frame(&mut codec, ConnectionFrame::RawText("ÿ".to_string()));
        assert_eq!(&out[..], &[0xFF, 0xFF]);
    }

    #[test]
    fn latin1_unmappable_becomes_question_mark() {
        let mut codec = ConnectionCodec::new();
        codec.charset = Charset::Latin1;
        let out = encode_frame(&mut codec, ConnectionFrame::RawText("€ 写 é".to_string()));
        assert_eq!(&out[..], b"? ? \xE9");
    }

    #[test]
    fn utf8_text_is_unchanged_and_bytes_stay_raw() {
        let mut codec = ConnectionCodec::new();
        let out = encode_frame(&mut codec, ConnectionFrame::Line("ÿ写".to_string()));
        assert_eq!(&out[..], "ÿ写\r\n".as_bytes());
        codec.charset = Charset::Latin1;
        let out = encode_frame(
            &mut codec,
            ConnectionFrame::Bytes(Bytes::from_static(&[0xFF, 0xC3])),
        );
        assert_eq!(&out[..], &[0xFF, 0xC3]);
    }

    #[test]
    fn set_charset_frame_switches_codec() {
        let mut codec = ConnectionCodec::new();
        assert!(encode_frame(&mut codec, ConnectionFrame::SetCharset(Charset::Latin1)).is_empty());
        assert_eq!(codec.charset, Charset::Latin1);
        let out = encode_frame(&mut codec, ConnectionFrame::RawText("é".to_string()));
        assert_eq!(&out[..], &[0xE9]);
    }

    #[test]
    fn subneg_frame_escapes_ff() {
        let mut codec = ConnectionCodec::new();
        let out = encode_frame(
            &mut codec,
            ConnectionFrame::Subneg {
                option: OPT_GMCP,
                payload: Bytes::from_static(b"A \xFF\xFFb"),
            },
        );
        assert_eq!(&out[..], b"\xFF\xFA\xC9A \xFF\xFF\xFF\xFFb\xFF\xF0");
        let out = encode_frame(
            &mut codec,
            ConnectionFrame::Subneg {
                option: 1,
                payload: Bytes::new(),
            },
        );
        assert_eq!(&out[..], &[IAC, SB, 1, IAC, SE]);
    }

    #[test]
    fn telnet_frame_is_raw() {
        let mut codec = ConnectionCodec::new();
        codec.charset = Charset::Latin1;
        let out = encode_frame(
            &mut codec,
            ConnectionFrame::Telnet(Bytes::from_static(&[IAC, WILL, 1])),
        );
        assert_eq!(&out[..], &[IAC, WILL, 1]);
    }

    #[test]
    fn prompt_end_per_mark() {
        let mut codec = ConnectionCodec::new();
        assert_eq!(codec.prompt_mark, PromptMark::None);
        assert!(encode_frame(&mut codec, ConnectionFrame::PromptEnd).is_empty());
        for (mark, expect) in [
            (PromptMark::Ga, vec![IAC, GA]),
            (PromptMark::Eor, vec![IAC, EOR]),
            (PromptMark::None, vec![]),
        ] {
            assert!(encode_frame(&mut codec, ConnectionFrame::SetPromptMark(mark)).is_empty());
            let out = encode_frame(&mut codec, ConnectionFrame::PromptEnd);
            assert_eq!(out.to_vec(), expect, "{mark:?}");
        }
    }

    fn inflate(data: &[u8]) -> Vec<u8> {
        let mut d = Decompress::new(true);
        let mut out = Vec::with_capacity(4096);
        while (d.total_in() as usize) < data.len() {
            if out.len() == out.capacity() {
                out.reserve(out.capacity());
            }
            let consumed = d.total_in() as usize;
            d.decompress_vec(&data[consumed..], &mut out, FlushDecompress::Sync)
                .unwrap();
        }
        assert_eq!(d.total_in() as usize, data.len());
        out
    }

    #[test]
    fn start_compress_marker_is_plain_and_rest_inflates() {
        let mut codec = ConnectionCodec::new();
        let mut wire = BytesMut::new();
        codec
            .encode(ConnectionFrame::Line("before".into()), &mut wire)
            .unwrap();
        codec
            .encode(ConnectionFrame::StartCompress, &mut wire)
            .unwrap();
        assert!(codec.compressor.is_some());
        let marker_end = wire.len();
        assert_eq!(&wire[..], b"before\r\n\xFF\xFA\x56\xFF\xF0");

        let mut expected = Vec::new();
        let frames: Vec<(ConnectionFrame, &[u8])> = vec![
            (ConnectionFrame::Line("hello".into()), b"hello\r\n"),
            (ConnectionFrame::Flush, b""),
            (
                ConnectionFrame::Subneg {
                    option: OPT_GMCP,
                    payload: Bytes::from_static(b"Core.Ping"),
                },
                b"\xFF\xFA\xC9Core.Ping\xFF\xF0",
            ),
            (ConnectionFrame::RawText("prompt> ".into()), b"prompt> "),
            (ConnectionFrame::SetPromptMark(PromptMark::Eor), b""),
            (ConnectionFrame::PromptEnd, b"\xFF\xEF"),
        ];
        for (frame, plain) in frames {
            let before = wire.len();
            codec.encode(frame, &mut wire).unwrap();
            expected.extend_from_slice(plain);
            // Each non-empty frame is sync-flushed, so everything so far inflates.
            if !plain.is_empty() {
                assert!(wire.len() > before);
                assert_eq!(&inflate(&wire[marker_end..]), &expected);
            } else {
                assert_eq!(wire.len(), before);
            }
        }
        let big: String = "abcdefgh".repeat(20_000);
        codec
            .encode(ConnectionFrame::Line(big.clone()), &mut wire)
            .unwrap();
        expected.extend_from_slice(big.as_bytes());
        expected.extend_from_slice(b"\r\n");
        assert_eq!(inflate(&wire[marker_end..]), expected);

        // A second StartCompress is ignored.
        let before = wire.len();
        codec
            .encode(ConnectionFrame::StartCompress, &mut wire)
            .unwrap();
        assert_eq!(wire.len(), before);
    }

    #[test]
    fn stop_compress_ends_stream() {
        let mut codec = ConnectionCodec::new();
        let mut wire = BytesMut::new();
        codec
            .encode(ConnectionFrame::StartCompress, &mut wire)
            .unwrap();
        codec
            .encode(ConnectionFrame::Line("x".into()), &mut wire)
            .unwrap();
        codec
            .encode(ConnectionFrame::StopCompress, &mut wire)
            .unwrap();
        assert!(!codec.compressor.is_some());
        let stream_end = wire.len();
        codec
            .encode(ConnectionFrame::Line("plain".into()), &mut wire)
            .unwrap();
        assert_eq!(&wire[stream_end..], b"plain\r\n");

        let mut d = Decompress::new(true);
        let mut out = Vec::with_capacity(64);
        let status = d
            .decompress_vec(&wire[5..stream_end], &mut out, FlushDecompress::Finish)
            .unwrap();
        assert_eq!(status, flate2::Status::StreamEnd);
        assert_eq!(out, b"x\r\n");
    }

    #[test]
    fn binary_mode_does_not_parse_iac() {
        let mut codec = ConnectionCodec::new_binary();
        let mut buf = BytesMut::from(&b"\xFF\xFB\x01\xFF\xFF"[..]);
        let ConnectionItem::Bytes(b) = codec.decode(&mut buf).unwrap().unwrap() else {
            panic!("expected bytes");
        };
        assert_eq!(b.as_ref(), b"\xFF\xFB\x01\xFF\xFF");
    }

    #[test]
    fn switching_to_binary_mid_subneg_resets_state() {
        let mut codec = ConnectionCodec::new();
        let mut buf = BytesMut::from(&b"\xFF\xFA\x63abc"[..]);
        assert!(codec.decode(&mut buf).unwrap().is_none());
        codec.set_mode(ConnectionMode::Binary);
        codec.set_mode(ConnectionMode::Text);
        let mut buf = BytesMut::from(&b"hi\n"[..]);
        assert_eq!(expect_line(codec.decode(&mut buf).unwrap().unwrap()), "hi");
    }
}
