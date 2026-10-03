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

//! Per-client telnet session state machine, daemon RPC flow, and terminal output.

pub mod codec;
mod djot_formatter;
mod moo_highlighter;
mod protocol;
pub mod telnet;

use std::{
    collections::{HashMap, VecDeque},
    net::SocketAddr,
    os::fd::RawFd,
    sync::{Arc, atomic::AtomicBool},
    time::{Duration, Instant, SystemTime},
};

use self::{
    codec::{ConnectionCodec, ConnectionFrame, ConnectionItem},
    protocol::{PlanContext, data_frame, plan_actions},
    telnet::{Action, Side, TelnetEvent, TelnetNegotiator, consts::*},
};
use eyre::{Context, bail};
use futures_util::{
    SinkExt, StreamExt,
    stream::{SplitSink, SplitStream},
};
use moor_common::{
    model::{CompileError, ObjectRef},
    tasks::{AbortLimitReason, CommandError, Event, SchedulerError, VerbProgramError},
    util::parse_into_words,
};
use moor_runtime_api::{
    AuthToken, ClientToken,
    api::{
        BroadcastEvent, ClientBroadcastSubscription, ClientEvent, ClientEventSubscription,
        ClientReply, ClientRequest, ConnectType as ApiConnectType, InvocationMode,
    },
};
use moor_var::{List, Obj, Symbol, Var, Variant, v_str, v_string};
pub(crate) use protocol::ClientDataLimiter;
use socket2::{SockRef, TcpKeepalive};
use std::pin::Pin;
use tokio::{
    io::{AsyncRead, AsyncWrite},
    select,
};
use tokio_util::codec::Framed;
use tracing::{debug, error, info, trace, warn};
use uuid::Uuid;

/// Combined trait for async read/write streams (needed for trait objects).
pub(crate) trait AsyncStream: AsyncRead + AsyncWrite + Unpin + Send {}
impl<T: AsyncRead + AsyncWrite + Unpin + Send> AsyncStream for T {}

/// Type alias for a boxed async stream that can be either TcpStream or TlsStream.
pub(crate) type BoxedAsyncIo = Pin<Box<dyn AsyncStream>>;

use self::djot_formatter::{Markup, RenderOptions, djot_to_terminal_with_options};

/// Out of band messages are prefixed with this string, e.g. for MCP clients.
const OUT_OF_BAND_PREFIX: &str = "#$#";

/// Default flush command
pub(crate) const DEFAULT_FLUSH_COMMAND: &str = ".flush";

const CONTENT_TYPE_MARKDOWN: &str = "text_markdown";
const CONTENT_TYPE_DJOT: &str = "text_djot";
const CONTENT_TYPE_DJOT_SLASH: &str = "text/djot";
const CONTENT_TYPE_MARKDOWN_SLASH: &str = "text/markdown";

/// Output formatting result - indicates how the content should be sent
enum FormattedOutput {
    /// Plain text - needs newline added via send_line
    Plain(String),
    /// Rich formatted (markdown/djot) - preserve embedded line breaks for telnet output
    Rich(String),
}

fn normalize_telnet_line_endings(text: &str) -> String {
    let mut normalized = String::with_capacity(text.len());
    let mut chars = text.chars().peekable();

    while let Some(ch) = chars.next() {
        match ch {
            '\r' => {
                if chars.peek() == Some(&'\n') {
                    chars.next();
                }
                normalized.push_str("\r\n");
            }
            '\n' => normalized.push_str("\r\n"),
            _ => normalized.push(ch),
        }
    }

    normalized
}

pub(crate) struct TelnetConnection {
    pub(crate) peer_addr: SocketAddr,
    /// The "handler" object, who is responsible for this connection, defaults to SYSTEM_OBJECT,
    /// but custom listeners can be set up to handle connections differently.
    pub(crate) handler_object: Obj,
    /// The MOO connection connection ID
    pub(crate) connection_object: Obj,
    /// The player we're authenticated to, if any.
    pub(crate) player_object: Option<Obj>,
    pub(crate) client_id: Uuid,
    /// Current PASETO token.
    pub(crate) client_token: ClientToken,
    pub(crate) write: SplitSink<Framed<BoxedAsyncIo, ConnectionCodec>, ConnectionFrame>,
    pub(crate) read: SplitStream<Framed<BoxedAsyncIo, ConnectionCodec>>,
    pub(crate) kill_switch: Arc<AtomicBool>,

    pub(crate) broadcast_sub: Box<dyn ClientBroadcastSubscription>,
    pub(crate) narrative_sub: Box<dyn ClientEventSubscription>,
    pub(crate) auth_token: Option<AuthToken>,
    pub(crate) daemon_client: Arc<dyn moor_runtime_api::api::RuntimeClient>,
    pub(crate) pending_task: Option<PendingTask>,

    /// Output prefix for command-output delimiters
    pub(crate) output_prefix: Option<String>,
    /// Output suffix for command-output delimiters
    pub(crate) output_suffix: Option<String>,
    /// Flush command for this connection
    pub(crate) flush_command: String,
    /// Connection attributes (terminal size, type, etc.)
    pub(crate) connection_attributes: HashMap<Symbol, Var>,

    /// Connection option states
    pub(crate) is_binary_mode: bool,
    /// When Some, input is held in the buffer for read() calls; when None, input is processed as commands
    pub(crate) hold_input: Option<Vec<String>>,
    pub(crate) disable_oob: bool,
    /// Pending line mode to switch to (for text_area input)
    pub(crate) pending_line_mode: Option<LineMode>,
    /// Currently collecting input (allows input even when pending_task is set)
    pub(crate) collecting_input: bool,
    /// Raw file descriptor for the socket (used for setting socket options like keep-alive)
    pub(crate) socket_fd: RawFd,
    /// Whether the client supports UTF-8 (for fancy characters in output)
    pub(crate) supports_utf8: bool,
    /// Whether output should avoid decorative formatting for screen readers / TTS.
    pub(crate) screen_reader_mode: bool,
    /// Telnet option state and protocol handlers.
    pub(crate) negotiator: TelnetNegotiator,
    /// Rate limit on inbound `ClientData`.
    pub(crate) client_data_limiter: ClientDataLimiter,
    /// When the host started, Unix seconds (MSSP `UPTIME`).
    pub(crate) host_started_at: u64,
}

/// The input modes the telnet session can be in.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) enum LineMode {
    /// Receiving input
    Input,
    /// Spooling up .program input.
    SpoolingProgram(String, String),
    /// Collecting multiline text_area input
    CollectingTextArea(Uuid),
}

/// Metadata for input requests, matching the web client's InputMetadata
#[derive(Debug, Clone)]
struct InputMetadata {
    input_type: Option<String>,
    prompt: Option<String>,
    choices: Option<Vec<String>>,
    min: Option<i64>,
    max: Option<i64>,
    default: Option<Var>,
    placeholder: Option<String>,
    rows: Option<i64>,
    alternative_label: Option<String>,
    alternative_placeholder: Option<String>,
}

impl InputMetadata {
    /// Parse metadata from RequestInputEvent
    fn from_metadata_pairs(metadata: &[(Symbol, Var)]) -> Self {
        let mut result = Self {
            input_type: None,
            prompt: None,
            choices: None,
            min: None,
            max: None,
            default: None,
            placeholder: None,
            rows: None,
            alternative_label: None,
            alternative_placeholder: None,
        };

        for (key, value) in metadata {
            match key.as_arc_str().as_str() {
                "input_type" => {
                    result.input_type = value.as_string().map(|s| s.to_string());
                }
                "prompt" => {
                    result.prompt = value.as_string().map(|s| s.to_string());
                }
                "choices" => {
                    if let Variant::List(list) = value.variant() {
                        let choices: Vec<String> = list
                            .iter()
                            .filter_map(|v| v.as_string().map(|s| s.to_string()))
                            .collect();
                        if !choices.is_empty() {
                            result.choices = Some(choices);
                        }
                    }
                }
                "min" => {
                    result.min = value.as_integer();
                }
                "max" => {
                    result.max = value.as_integer();
                }
                "default" => {
                    result.default = Some(value.clone());
                }
                "placeholder" => {
                    result.placeholder = value.as_string().map(|s| s.to_string());
                }
                "rows" => {
                    result.rows = value.as_integer();
                }
                "alternative_label" => {
                    result.alternative_label = value.as_string().map(|s| s.to_string());
                }
                "alternative_placeholder" => {
                    result.alternative_placeholder = value.as_string().map(|s| s.to_string());
                }
                _ => {}
            }
        }

        result
    }
}

fn describe_compile_error(compile_error: CompileError) -> String {
    match compile_error {
        CompileError::StringLexError(_, le) => {
            format!("String format error: {le}")
        }
        CompileError::ParseError {
            error_position,
            context: _,
            end_line_col,
            message,
            details: _,
        } => {
            let mut err = format!(
                "Parse error at line {} column {}: {}",
                error_position.line_col.0, error_position.line_col.1, message
            );
            if let Some(end_line_col) = end_line_col {
                err.push_str(&format!(
                    " (to line {} column {})",
                    end_line_col.0, end_line_col.1
                ));
            }
            err.push_str(format!(": {message}").as_str());
            err
        }
        CompileError::UnknownBuiltinFunction(_, bf) => {
            format!("Unknown builtin function: {bf}")
        }
        CompileError::UnknownLoopLabel(_, ll) => {
            format!("Unknown break/loop label: {ll}")
        }
        CompileError::DuplicateVariable(_, dv) => {
            format!("Duplicate variable: {dv}")
        }
        CompileError::AssignToConst(_, ac) => {
            format!("Assignment to constant: {ac}")
        }
        CompileError::DisabledFeature(_, df) => {
            format!("Disabled feature: {df}")
        }
        CompileError::BadSlotName(_, bs) => {
            format!("Bad slot name in flyweight: {bs}")
        }
        CompileError::InvalidAssignmentTarget(_) => "Invalid l-value for assignment".to_string(),
        CompileError::UnknownTypeConstant(_, t) => {
            format!("Unknown type constant: {t}")
        }
        CompileError::InvalidTypeLiteralAssignment(t, _) => {
            format!("Illegal type literal `{t}` as assignment target")
        }
        CompileError::AssignmentToCapturedVariable(_, var) => {
            format!("Cannot assign to captured variable `{var}`; lambdas capture by value")
        }
    }
}

#[derive(Debug, PartialEq, Eq)]
pub struct PendingTask {
    task_id: usize,
    start_time: Instant,
}

pub enum ReadEvent {
    Command(String),
    InputReply(Var),
    Telnet(TelnetEvent),
    ConnectionClose,
    PendingEvent,
}

const TASK_TIMEOUT: Duration = Duration::from_secs(10);

impl InputMetadata {
    /// Display the input prompt to the user based on the input type
    async fn display_prompt(&self, conn: &mut TelnetConnection) -> Result<(), eyre::Error> {
        // Render the prompt using markdown if present
        if let Some(prompt) = &self.prompt {
            let formatted = djot_to_terminal_with_options(prompt, conn.render_options());
            conn.send_line(&formatted).await?;
        }

        let input_type = self.input_type.as_deref().unwrap_or("text");

        match input_type {
            "yes_no" => {
                conn.send_line("Enter 'yes' or 'no'").await?;
            }
            "yes_no_alternative" => {
                conn.send_line("Enter 'yes', 'no', or describe an alternative")
                    .await?;
            }
            "choice" => {
                if let Some(choices) = &self.choices {
                    conn.send_line("Choose one of:").await?;
                    for (i, choice) in choices.iter().enumerate() {
                        conn.send_line(&format!("  {}. {}", i + 1, choice)).await?;
                    }
                    conn.send_line("Enter the number or text of your choice")
                        .await?;
                }
            }
            "number" => {
                let mut msg = "Enter a number".to_string();
                if let Some(min) = self.min {
                    if let Some(max) = self.max {
                        msg.push_str(&format!(" (between {} and {})", min, max));
                    } else {
                        msg.push_str(&format!(" (minimum {})", min));
                    }
                } else if let Some(max) = self.max {
                    msg.push_str(&format!(" (maximum {})", max));
                }
                conn.send_line(&msg).await?;
            }
            "text_area" => {
                conn.send_line("Enter your text. Use '.' on a line by itself to finish")
                    .await?;
            }
            "confirmation" => {
                conn.send_line("Press Enter to continue").await?;
            }
            "text" => {
                if let Some(placeholder) = &self.placeholder {
                    conn.send_line(&format!("({})", placeholder)).await?;
                }
            }
            _ => {
                // Unknown input type, treat as text
                if let Some(placeholder) = &self.placeholder {
                    conn.send_line(&format!("({})", placeholder)).await?;
                }
            }
        }

        conn.prompt_end().await?;
        Ok(())
    }

    /// Validate and convert user input based on the input type
    fn validate_input(&self, input: &str) -> Result<Var, String> {
        let input_type = self.input_type.as_deref().unwrap_or("text");

        match input_type {
            "yes_no" => {
                let normalized = input.trim().to_lowercase();
                match normalized.as_str() {
                    "yes" | "y" => Ok(v_str("yes")),
                    "no" | "n" => Ok(v_str("no")),
                    _ => Err("Please enter 'yes' or 'no'".to_string()),
                }
            }
            "yes_no_alternative" => {
                let normalized = input.trim().to_lowercase();
                match normalized.as_str() {
                    "yes" | "y" => Ok(v_str("yes")),
                    "no" | "n" => Ok(v_str("no")),
                    _ => {
                        // Treat anything else as alternative text
                        if !normalized.is_empty() {
                            Ok(v_str(&format!("alternative: {}", input.trim())))
                        } else {
                            Err("Please enter 'yes', 'no', or describe an alternative".to_string())
                        }
                    }
                }
            }
            "choice" => {
                if let Some(choices) = &self.choices {
                    // Try to parse as a number first
                    if let Ok(num) = input.trim().parse::<usize>()
                        && num > 0
                        && num <= choices.len()
                    {
                        return Ok(v_str(&choices[num - 1]));
                    }
                    // Try to match the text
                    let normalized = input.trim().to_lowercase();
                    for choice in choices {
                        if choice.to_lowercase() == normalized {
                            return Ok(v_str(choice));
                        }
                    }
                    Err(format!(
                        "Please enter a number 1-{} or one of the listed choices",
                        choices.len()
                    ))
                } else {
                    Ok(v_str(input))
                }
            }
            "number" => {
                match input.trim().parse::<i64>() {
                    Ok(num) => {
                        // Validate min/max
                        if let Some(min) = self.min
                            && num < min
                        {
                            return Err(format!("Number must be at least {}", min));
                        }
                        if let Some(max) = self.max
                            && num > max
                        {
                            return Err(format!("Number must be at most {}", max));
                        }
                        Ok(Var::mk_integer(num))
                    }
                    Err(_) => Err("Please enter a valid number".to_string()),
                }
            }
            "confirmation" => Ok(v_str("ok")),
            "text" | "text_area" => Ok(v_str(input)),
            _ => Ok(v_str(input)), // Unknown input type, treat as text
        }
    }
}

impl TelnetConnection {
    async fn handle_client_rpc_error(
        &mut self,
        error: moor_runtime_api::RpcError,
        fallback_message: &str,
    ) -> Result<(), eyre::Error> {
        match error {
            moor_runtime_api::RpcError::Daemon(moor_runtime_api::RpcMessageError::TaskError(
                error,
            )) => self.handle_task_error(error).await,
            moor_runtime_api::RpcError::Daemon(
                moor_runtime_api::RpcMessageError::PermissionDenied,
            ) => self.send_line("Permission denied.").await,
            moor_runtime_api::RpcError::Daemon(
                moor_runtime_api::RpcMessageError::InvalidRequest(_),
            ) => self.send_line("Invalid request.").await,
            moor_runtime_api::RpcError::Daemon(
                moor_runtime_api::RpcMessageError::InternalError(_),
            ) => self.send_line("Internal server error.").await,
            moor_runtime_api::RpcError::Daemon(error) => {
                error!("Unhandled daemon RPC error: {error:?}");
                self.send_line(fallback_message).await
            }
            error => Err(error.into()),
        }
    }

    /// Send a line with automatic newline appending (like LambdaMOO's network_send_line)
    pub async fn send_line(&mut self, line: &str) -> Result<(), eyre::Error> {
        self.write
            .send(ConnectionFrame::Line(line.to_string()))
            .await
            .with_context(|| "Unable to send line to client")
    }

    /// Explicitly flush the output (like LambdaMOO's flush control)
    pub async fn flush(&mut self) -> Result<(), eyre::Error> {
        self.write
            .send(ConnectionFrame::Flush)
            .await
            .with_context(|| "Unable to flush output to client")
    }

    /// Write one frame. Every write goes through here or the helpers above, on the one sink, so
    /// frames reach the wire in the order they are written.
    async fn send_frame(&mut self, frame: ConnectionFrame) -> Result<(), eyre::Error> {
        self.write
            .send(frame)
            .await
            .with_context(|| "Unable to write to client")
    }

    /// Mark the end of a prompt (`IAC EOR`, `IAC GA`, or nothing) and flush.
    pub async fn prompt_end(&mut self) -> Result<(), eyre::Error> {
        self.send_frame(ConnectionFrame::PromptEnd).await
    }

    fn render_options(&self) -> RenderOptions {
        RenderOptions {
            utf8: self.supports_utf8,
            screen_reader_mode: self.screen_reader_mode,
            markup: self.markup(),
        }
    }

    fn markup(&self) -> Markup {
        if self.negotiator.is_enabled(OPT_MXP) {
            Markup::Mxp
        } else {
            Markup::Ansi
        }
    }

    fn terminal_width(&self) -> Option<usize> {
        self.connection_attributes
            .get(&Symbol::mk("columns"))
            .and_then(|v| v.as_integer())
            .and_then(|w| if w > 0 { Some(w as usize) } else { None })
    }

    /// Apply negotiator actions: write frames, record attributes, and send requests.
    async fn apply_actions(&mut self, actions: Vec<Action>) -> Result<(), eyre::Error> {
        if actions.is_empty() {
            return Ok(());
        }
        let ctx = PlanContext {
            client_token: &self.client_token,
            auth_token: self.auth_token.as_ref(),
            handler_object: self.handler_object,
            passive: self.negotiator.is_passive(),
            disable_oob: self.disable_oob,
            // The host has no request for the connected player count.
            players: 0,
            uptime: self.host_started_at,
            now: Instant::now(),
        };
        let plan = plan_actions(
            actions,
            &self.negotiator,
            &ctx,
            &mut self.connection_attributes,
            &mut self.client_data_limiter,
        );
        for (key, value) in &plan.changed {
            let on = value.as_ref().is_some_and(|v| v.is_true());
            match key.as_arc_str().as_str() {
                "utf8" => self.supports_utf8 = on,
                "screen-reader" => self.screen_reader_mode = on,
                _ => {}
            }
        }
        for frame in plan.frames {
            self.send_frame(frame).await?;
        }
        for request in plan.requests {
            // Fire and forget: attribute updates and ClientData tasks report nothing back.
            if let Err(e) = self
                .daemon_client
                .client_call(self.client_id, request)
                .await
            {
                warn!("telnet protocol request to daemon failed: {e}");
            }
        }
        Ok(())
    }

    /// Handle one telnet protocol element from the client, before or after login.
    async fn handle_telnet_event(&mut self, event: TelnetEvent) -> Result<(), eyre::Error> {
        if self.negotiator.is_passive() {
            // As before the protocol layer: raw bytes to `do_out_of_band_command`, after login.
            let raw = Var::mk_binary(event.to_raw().to_vec());
            return self.process_telnet_command(raw).await;
        }
        let actions = self.negotiator.on_event(event);
        self.apply_actions(actions).await
    }

    /// Ask the negotiator to enable or disable a telnet option from `set_connection_option`.
    async fn request_option(&mut self, option: u8, enable: bool) -> Result<(), eyre::Error> {
        let side = TelnetNegotiator::primary_side(option);
        let actions = self.negotiator.request(option, side, enable);
        self.apply_actions(actions).await
    }

    /// Handle connection option changes
    async fn handle_connection_option(
        &mut self,
        option_name: Symbol,
        value: Option<Var>,
    ) -> Result<(), eyre::Error> {
        let option_str = option_name.as_arc_str();

        match option_str.as_str() {
            "binary" => {
                let binary_mode = value.as_ref().map(|v| v.is_true()).unwrap_or(false);
                debug!("Setting binary mode to {}", binary_mode);
                self.is_binary_mode = binary_mode;

                // Switch the codec mode by sending a SetMode frame
                use self::codec::ConnectionMode;
                let new_mode = if binary_mode {
                    ConnectionMode::Binary
                } else {
                    ConnectionMode::Text
                };

                self.write
                    .send(ConnectionFrame::SetMode(new_mode))
                    .await
                    .with_context(|| "Unable to set codec mode")?;
            }
            "hold-input" => {
                let hold = value.as_ref().map(|v| v.is_true()).unwrap_or(false);
                debug!("Setting hold-input to {}", hold);
                self.hold_input = if hold { Some(Vec::new()) } else { None };
            }
            "disable-oob" => {
                let disable = value.as_ref().map(|v| v.is_true()).unwrap_or(false);
                debug!("Setting disable-oob to {}", disable);
                self.disable_oob = disable;
            }
            "client-echo" => {
                let echo_on = value.as_ref().map(|v| v.is_true()).unwrap_or(true);
                debug!("Setting client-echo to {}", echo_on);
                self.send_telnet_echo_command(echo_on).await?;
            }
            "echo" => {
                // Server echo: the inverse of `client-echo`.
                let server_echo = value.as_ref().is_some_and(|v| v.is_true());
                self.send_telnet_echo_command(!server_echo).await?;
            }
            "gmcp" | "msdp" | "mxp" | "eor" | "mccp2" | "naws" | "ttype" | "charset" => {
                let enable = value.as_ref().is_some_and(|v| v.is_true());
                let option = match option_str.as_str() {
                    "gmcp" => OPT_GMCP,
                    "msdp" => OPT_MSDP,
                    "mxp" => OPT_MXP,
                    "eor" => OPT_EOR,
                    "mccp2" => OPT_MCCP2,
                    "naws" => OPT_NAWS,
                    "ttype" => OPT_TTYPE,
                    _ => OPT_CHARSET,
                };
                debug!("Requesting telnet option {option_str} {enable}");
                self.request_option(option, enable).await?;
            }
            "flush-command" => {
                let flush_cmd = value
                    .as_ref()
                    .and_then(|v| v.as_string())
                    .unwrap_or(DEFAULT_FLUSH_COMMAND);
                debug!("Setting flush-command to '{}'", flush_cmd);
                self.flush_command = flush_cmd.to_string();
            }
            "keep-alive" => {
                self.set_tcp_keepalive(value)?;
            }
            "utf8" => {
                let utf8 = value.as_ref().map(|v| v.is_true()).unwrap_or(false);
                debug!("Setting UTF-8 support to {}", utf8);
                self.supports_utf8 = utf8;
            }
            "screen-reader" => {
                let screen_reader_mode = value.as_ref().map(|v| v.is_true()).unwrap_or(false);
                debug!("Setting screen-reader mode to {}", screen_reader_mode);
                self.screen_reader_mode = screen_reader_mode;
            }
            _ => {
                warn!("Unsupported connection option: {}", option_str);
            }
        }

        Ok(())
    }

    /// Ask the client to echo (`WONT ECHO`) or not (`WILL ECHO`, the server echoes).
    ///
    /// With protocols configured the negotiator tracks ECHO and sends a verb only when the
    /// state needs one. Passive connections write the verb on every call, as they always have.
    async fn send_telnet_echo_command(&mut self, client_echo: bool) -> Result<(), eyre::Error> {
        if !self.negotiator.is_passive() {
            let actions = self.negotiator.request(OPT_ECHO, Side::Us, !client_echo);
            return self.apply_actions(actions).await;
        }
        let verb = if client_echo { WONT } else { WILL };
        self.send_frame(ConnectionFrame::Telnet(bytes::Bytes::copy_from_slice(&[
            IAC, verb, OPT_ECHO,
        ])))
        .await
    }

    /// Set TCP keepalive options on the socket.
    /// Value can be:
    /// - An integer (1 to enable with defaults, 0 to disable)
    /// - A map with keys: "idle", "interval", "count"
    fn set_tcp_keepalive(&self, value: Option<Var>) -> Result<(), eyre::Error> {
        use std::os::fd::BorrowedFd;

        // Default values matching ToastStunt
        const DEFAULT_IDLE: u64 = 300; // 5 minutes
        const DEFAULT_INTERVAL: u64 = 120; // 2 minutes
        const DEFAULT_COUNT: u32 = 5;

        // SAFETY: We know the fd is valid because the connection is still active
        let borrowed_fd = unsafe { BorrowedFd::borrow_raw(self.socket_fd) };
        let sock_ref = SockRef::from(&borrowed_fd);

        let Some(value) = value else {
            // No value means disable
            if let Err(e) = sock_ref.set_tcp_keepalive(&TcpKeepalive::new()) {
                warn!("Failed to disable TCP keepalive: {}", e);
            } else {
                debug!("TCP keepalive disabled");
            }
            return Ok(());
        };

        // Check if it's a simple integer (0 = disable, non-zero = enable with defaults)
        if let Some(int_val) = value.as_integer() {
            if int_val == 0 {
                if let Err(e) = sock_ref.set_tcp_keepalive(&TcpKeepalive::new()) {
                    warn!("Failed to disable TCP keepalive: {}", e);
                } else {
                    debug!("TCP keepalive disabled");
                }
            } else {
                let keepalive = TcpKeepalive::new()
                    .with_time(Duration::from_secs(DEFAULT_IDLE))
                    .with_interval(Duration::from_secs(DEFAULT_INTERVAL))
                    .with_retries(DEFAULT_COUNT);
                if let Err(e) = sock_ref.set_tcp_keepalive(&keepalive) {
                    warn!("Failed to set TCP keepalive: {}", e);
                } else {
                    debug!(
                        "TCP keepalive enabled: idle={}s, interval={}s, count={}",
                        DEFAULT_IDLE, DEFAULT_INTERVAL, DEFAULT_COUNT
                    );
                }
            }
            return Ok(());
        }

        // Check if it's a map with specific values
        if let Some(m) = value.as_map() {
            let idle = m
                .iter()
                .find(|(k, _)| {
                    k.as_symbol()
                        .map(|s| s.as_string() == "idle")
                        .unwrap_or(false)
                })
                .and_then(|(_, v)| v.as_integer())
                .map(|v| v as u64)
                .unwrap_or(DEFAULT_IDLE);

            let interval = m
                .iter()
                .find(|(k, _)| {
                    k.as_symbol()
                        .map(|s| s.as_string() == "interval")
                        .unwrap_or(false)
                })
                .and_then(|(_, v)| v.as_integer())
                .map(|v| v as u64)
                .unwrap_or(DEFAULT_INTERVAL);

            let count = m
                .iter()
                .find(|(k, _)| {
                    k.as_symbol()
                        .map(|s| s.as_string() == "count")
                        .unwrap_or(false)
                })
                .and_then(|(_, v)| v.as_integer())
                .map(|v| v as u32)
                .unwrap_or(DEFAULT_COUNT);

            let keepalive = TcpKeepalive::new()
                .with_time(Duration::from_secs(idle))
                .with_interval(Duration::from_secs(interval))
                .with_retries(count);

            if let Err(e) = sock_ref.set_tcp_keepalive(&keepalive) {
                warn!("Failed to set TCP keepalive: {}", e);
            } else {
                debug!(
                    "TCP keepalive enabled: idle={}s, interval={}s, count={}",
                    idle, interval, count
                );
            }
            return Ok(());
        }

        // Boolean true enables with defaults
        if value.is_true() {
            let keepalive = TcpKeepalive::new()
                .with_time(Duration::from_secs(DEFAULT_IDLE))
                .with_interval(Duration::from_secs(DEFAULT_INTERVAL))
                .with_retries(DEFAULT_COUNT);
            if let Err(e) = sock_ref.set_tcp_keepalive(&keepalive) {
                warn!("Failed to set TCP keepalive: {}", e);
            } else {
                debug!(
                    "TCP keepalive enabled: idle={}s, interval={}s, count={}",
                    DEFAULT_IDLE, DEFAULT_INTERVAL, DEFAULT_COUNT
                );
            }
        } else if let Err(e) = sock_ref.set_tcp_keepalive(&TcpKeepalive::new()) {
            warn!("Failed to disable TCP keepalive: {}", e);
        } else {
            debug!("TCP keepalive disabled");
        }

        Ok(())
    }

    async fn update_connection_attribute(&mut self, key: Symbol, value: Option<Var>) {
        let _ = self
            .daemon_client
            .client_call(
                self.client_id,
                ClientRequest::SetClientAttribute {
                    client_token: self.client_token.clone(),
                    auth_token: self.auth_token.clone(),
                    key,
                    value,
                },
            )
            .await;
    }
    /// Run the connection to its end, then detach it from the daemon.
    pub(crate) async fn run(&mut self) -> Result<(), eyre::Error> {
        let result = self.run_session().await;
        if let Err(e) = &result {
            info!("Connection closed: {e}");
        }

        // Let the server know this client is gone.
        let _ = self
            .daemon_client
            .client_call(
                self.client_id,
                ClientRequest::Detach {
                    client_token: self.client_token.clone(),
                    disconnected: true,
                },
            )
            .await;

        Ok(())
    }

    async fn run_session(&mut self) -> Result<(), eyre::Error> {
        if !self.negotiator.is_passive() {
            let offers = self.negotiator.initial_offers();
            self.apply_actions(offers).await?;
        }

        // Provoke welcome message, which is a login command with no arguments, and we
        // don't care about the reply at this point.
        self.daemon_client
            .client_call(
                self.client_id,
                ClientRequest::LoginCommand {
                    client_token: self.client_token.clone(),
                    handler_object: self.handler_object,
                    connect_args: vec![],
                    do_attach: false,
                    registration_data: None,
                },
            )
            .await
            .with_context(|| "Unable to send login request to RPC server")?;

        let (auth_token, player, connect_type) = self
            .authorization_phase()
            .await
            .with_context(|| "Unable to authorize connection")?;
        debug!("Authorized player: {:?}", player);

        self.auth_token = Some(auth_token);

        let connect_message = match connect_type {
            ApiConnectType::Connected => "*** Connected ***",
            ApiConnectType::Reconnected => "*** Reconnected ***",
            ApiConnectType::Created => "*** Created ***",
            ApiConnectType::NoConnect => bail!("Login returned NoConnect"),
        };
        self.send_line(connect_message).await?;
        self.flush().await?;

        // Now that we're authenticated, send all current connection attributes to daemon
        for (key, value) in self.connection_attributes.clone() {
            self.update_connection_attribute(key, Some(value)).await;
        }

        self.command_loop().await
    }

    /// Write one narrative event, before or after login.
    async fn output(&mut self, event: Event) -> Result<(), eyre::Error> {
        let view = OutputView {
            negotiator: &self.negotiator,
            width: self.terminal_width(),
            options: self.render_options(),
            binary_mode: self.is_binary_mode,
        };
        for frame in event_frames(&view, event) {
            self.send_frame(frame).await?;
        }
        Ok(())
    }

    async fn authorization_phase(
        &mut self,
    ) -> Result<(AuthToken, Obj, ApiConnectType), eyre::Error> {
        loop {
            select! {
                Ok(event_msg) = self.broadcast_sub.recv_client_broadcast() => {
                    trace!("broadcast_event");

                    match event_msg.event {
                        BroadcastEvent::PingPong => {
                            let timestamp = SystemTime::now()
                                .duration_since(std::time::UNIX_EPOCH)
                                .map(|d| d.as_nanos() as u64)
                                .unwrap_or_default();
                            let _ = self.daemon_client.client_call(
                                self.client_id,
                                ClientRequest::ClientPong {
                                    client_token: self.client_token.clone(),
                                    client_sys_time: timestamp,
                                    player: self.connection_object,
                                    host_type: moor_runtime_api::HostType::TCP,
                                    socket_addr: self.peer_addr.to_string(),
                                },
                            ).await?;
                        }
                    }
                }
                Ok(event_msg) = self.narrative_sub.recv_client_event() => {
                    match event_msg.event {
                        ClientEvent::SystemMessage { message, .. } => {
                            self.send_line(&message).await.with_context(|| "Unable to send message to client")?;
                        }
                        ClientEvent::Narrative { event, .. } => {
                            self.output(event.event).await?;
                        }
                        ClientEvent::RequestInput { .. } => {
                            bail!("RequestInput before login");
                        }
                        ClientEvent::Disconnect => {
                            self.write.close().await?;
                            bail!("Disconnect before login");
                        }
                        ClientEvent::TaskError { error, .. } => {
                            self.handle_task_error(error).await?;
                        }
                        ClientEvent::TaskSuccess { .. } |
                        ClientEvent::TaskSuspended { .. } => {
                            trace!("TaskSuccess")
                            // We don't need to do anything with successes.
                        }
                        ClientEvent::PlayerSwitched { new_player, new_auth_token, .. } => {
                            info!("Switching player from {:?} to {} during authorization for client {}", self.player_object, new_player, self.client_id);
                            self.player_object = Some(new_player);
                            self.auth_token = Some(new_auth_token);
                            info!("Player switched successfully to {} during authorization for client {}", new_player, self.client_id);
                        }
                        ClientEvent::SetConnectionOption { connection_obj, option_name, value } => {
                            // Only handle if this event is for our connection
                            if connection_obj == self.connection_object {
                                self.handle_connection_option(option_name, Some(value)).await?;
                            }
                        }
                        ClientEvent::EventsAvailable => bail!("Connection delivery ownership changed"),
            ClientEvent::CredentialsUpdated { .. } => {
                            // Not relevant for telnet - only used by web clients
                        }
                    }
                }
                // Auto loop
                item = self.read.next() => {
                    let Some(item) = item else {
                        bail!("Connection closed before login");
                    };
                    let item = match item {
                        Ok(i) => i,
                        Err(e) => {
                            warn!("Failure to decode: {:?}", e);
                            continue;
                        }
                    };
                    let line = match item {
                        ConnectionItem::Line(line) => line,
                        ConnectionItem::Telnet(event) => {
                            self.handle_telnet_event(event).await?;
                            continue;
                        }
                        ConnectionItem::Bytes(_) => continue,
                    };
                    let words = parse_into_words(&line);
                    let reply = self.daemon_client.client_call(
                        self.client_id,
                        ClientRequest::LoginCommand {
                            client_token: self.client_token.clone(),
                            handler_object: self.handler_object,
                            connect_args: words,
                            do_attach: true,
                            registration_data: None,
                        },
                    ).await?;

                    if let ClientReply::LoginResult { success: true, auth_token: Some(auth_token), connect_type, player: Some(player), .. } = reply {
                        info!(?player, client_id = ?self.client_id, "Login successful");
                        self.player_object = Some(player);
                        return Ok((auth_token, player, connect_type))
                    }
                }
            }
        }
    }

    async fn command_loop(&mut self) -> Result<(), eyre::Error> {
        if self.kill_switch.load(std::sync::atomic::Ordering::Relaxed) {
            return Ok(());
        }

        let mut line_mode = LineMode::Input;
        let mut expecting_input: VecDeque<(Uuid, InputMetadata)> = VecDeque::new();
        let mut program_input = Vec::new();
        let mut textarea_input = Vec::new();
        loop {
            // We should not send the next line until we've received a narrative event for the
            // previous.
            let input_future = async {
                if let Some(pt) = &self.pending_task
                    && expecting_input.is_empty()
                    && !self.collecting_input
                    && pt.start_time.elapsed() > TASK_TIMEOUT
                {
                    error!(
                        "Task {} stuck without response for more than {TASK_TIMEOUT:?}",
                        pt.task_id
                    );
                    self.pending_task = None;
                } else if let Some(pt) = &self.pending_task
                    && expecting_input.is_empty()
                    && !self.collecting_input
                {
                    // Yield this branch so event reception and the I/O driver can progress.
                    let remaining = TASK_TIMEOUT.saturating_sub(pt.start_time.elapsed());
                    tokio::time::sleep(remaining).await;
                    return ReadEvent::PendingEvent;
                }

                let Some(Ok(item)) = self.read.next().await else {
                    return ReadEvent::ConnectionClose;
                };

                match item {
                    ConnectionItem::Line(line) => {
                        if !expecting_input.is_empty() {
                            ReadEvent::InputReply(v_str(&line))
                        } else {
                            ReadEvent::Command(line)
                        }
                    }
                    ConnectionItem::Bytes(bytes) => {
                        if !self.is_binary_mode {
                            ReadEvent::PendingEvent
                        } else if !expecting_input.is_empty() {
                            // Convert binary data to Var::Binary for input reply
                            ReadEvent::InputReply(Var::mk_binary(bytes.to_vec()))
                        } else {
                            // Binary data as unprompted command not yet supported
                            ReadEvent::PendingEvent
                        }
                    }
                    ConnectionItem::Telnet(event) => ReadEvent::Telnet(event),
                }
            };

            select! {
                line = input_future => {
                    match line {
                        ReadEvent::Command(line) => {
                            if let Some(ref mut buffer) = self.hold_input {
                                // When hold-input is active, store input in buffer for read() calls
                                debug!("Holding input due to hold-input option: {}", line);
                                buffer.push(line);
                            } else {
                                line_mode = self.handle_command(&mut program_input, &mut textarea_input, &mut expecting_input, line_mode, line).await?;
                                // Update collecting_input flag after command processing
                                self.collecting_input = !expecting_input.is_empty() || matches!(line_mode, LineMode::CollectingTextArea(_));
                            }
                        }
                        ReadEvent::InputReply(input_data) =>{
                            self.process_requested_input_line(input_data, &mut expecting_input).await?;
                            // Update collecting_input flag after processing input
                            self.collecting_input = !expecting_input.is_empty() || matches!(line_mode, LineMode::CollectingTextArea(_));
                        }
                        ReadEvent::Telnet(event) => {
                            self.handle_telnet_event(event).await?;
                        }
                        ReadEvent::ConnectionClose => {
                            info!("Connection closed");
                            return Ok(());
                        }
                        ReadEvent::PendingEvent => {
                            continue
                        }
                    }
                }
                Ok(event_msg) = self.broadcast_sub.recv_client_broadcast() => {
                    match event_msg.event {
                        BroadcastEvent::PingPong => {
                            let timestamp = SystemTime::now()
                                .duration_since(std::time::UNIX_EPOCH)
                                .map(|d| d.as_nanos() as u64)
                                .unwrap_or_default();
                            let _ = self.daemon_client.client_call(
                                self.client_id,
                                ClientRequest::ClientPong {
                                    client_token: self.client_token.clone(),
                                    client_sys_time: timestamp,
                                    player: self.handler_object,
                                    host_type: moor_runtime_api::HostType::TCP,
                                    socket_addr: self.peer_addr.to_string(),
                                },
                            ).await.with_context(|| "Unable to send pong to RPC server")?;

                        }
                    }
                }
                Ok(event_msg) = self.narrative_sub.recv_client_event() => {
                    if let Some(input_request) = self.handle_narrative_event(event_msg.event).await? {
                        expecting_input.push_back(input_request);
                    }
                    // Check if we need to switch line mode (for text_area)
                    if let Some(new_mode) = self.pending_line_mode.take() {
                        line_mode = new_mode;
                    }
                    // Update collecting_input flag based on state
                    self.collecting_input = !expecting_input.is_empty() || matches!(line_mode, LineMode::CollectingTextArea(_));
                }
            }
        }
    }

    async fn handle_command(
        &mut self,
        program_input: &mut Vec<String>,
        textarea_input: &mut Vec<String>,
        expecting_input: &mut VecDeque<(Uuid, InputMetadata)>,
        line_mode: LineMode,
        line: String,
    ) -> Result<LineMode, eyre::Error> {
        // Handle flush command first - it should be processed immediately.
        if line.trim() == self.flush_command {
            self.flush().await?;
            return Ok(line_mode);
        }

        if let LineMode::SpoolingProgram(target, verb) = &line_mode {
            // If the line is "." that means we're done, and we can send the program off and switch modes back.
            if line == "." {
                // Clear the program input, and send it off.
                let Some(auth_token) = self.auth_token.clone() else {
                    bail!("Received program command before auth token was set");
                };
                let code = std::mem::take(program_input);
                let target = ObjectRef::Match(target.clone());
                let verb = Symbol::mk(verb);
                let reply = match self
                    .daemon_client
                    .client_call(
                        self.client_id,
                        ClientRequest::Program {
                            auth_token: auth_token.clone(),
                            object: target,
                            verb,
                            code,
                        },
                    )
                    .await
                {
                    Ok(reply) => reply,
                    Err(error) => {
                        self.handle_client_rpc_error(error, "An error occurred.")
                            .await?;
                        return Ok(LineMode::Input);
                    }
                };

                match reply {
                    ClientReply::VerbProgramResponseReply { response } => match response {
                        moor_runtime_api::api::VerbProgramResponse::Success { obj, verb_name } => {
                            self.send_line(&format!(
                                "0 error(s).\nVerb {verb_name} programmed on object {obj}"
                            ))
                            .await?;
                        }
                        moor_runtime_api::api::VerbProgramResponse::Failure { error } => {
                            match error {
                                moor_common::tasks::SchedulerError::VerbProgramFailed(
                                    moor_common::tasks::VerbProgramError::CompilationError(ce),
                                ) => {
                                    let error_str = describe_compile_error(ce);
                                    self.send_line(&format!("Compilation error: {error_str}"))
                                        .await?;
                                }
                                moor_common::tasks::SchedulerError::VerbProgramFailed(
                                    moor_common::tasks::VerbProgramError::NoVerbToProgram,
                                ) => {
                                    self.send_line("That object does not have that verb.")
                                        .await?;
                                }
                                _ => {
                                    error!("Unhandled verb program error: {error:?}");
                                }
                            }
                        }
                    },
                    _ => {
                        bail!("Unexpected RPC reply type");
                    }
                }
                return Ok(LineMode::Input);
            } else {
                // Otherwise, we're still spooling up the program, so just keep spooling.
                program_input.push(line);
            }
            return Ok(line_mode);
        }

        // Handle text_area collection mode
        if let LineMode::CollectingTextArea(request_id) = &line_mode {
            if line == "." || line.trim() == "@abort" {
                // Done collecting, send the input
                let Some(auth_token) = self.auth_token.clone() else {
                    bail!("Received input before auth token was set");
                };

                // If @abort, send just "@abort", otherwise join collected lines
                let input_var = if line.trim() == "@abort" {
                    v_str("@abort")
                } else {
                    let text = std::mem::take(textarea_input).join("\n");
                    v_str(&text)
                };

                let reply = match self
                    .daemon_client
                    .client_call(
                        self.client_id,
                        ClientRequest::RequestedInput {
                            client_token: self.client_token.clone(),
                            auth_token: auth_token.clone(),
                            request_id: *request_id,
                            input: input_var,
                        },
                    )
                    .await
                {
                    Ok(reply) => reply,
                    Err(error) => {
                        self.handle_client_rpc_error(
                            error,
                            "An error occurred processing your input.",
                        )
                        .await?;
                        return Ok(LineMode::Input);
                    }
                };

                match reply {
                    ClientReply::TaskSubmitted { task_id } => {
                        self.pending_task = Some(PendingTask {
                            task_id: task_id as usize,
                            start_time: Instant::now(),
                        });
                    }
                    ClientReply::InputThanks => {
                        // Input was accepted
                    }
                    _ => {
                        bail!("Unexpected RPC reply for text_area input");
                    }
                }

                // Remove from expecting_input queue
                expecting_input.retain(|(id, _)| id != request_id);

                return Ok(LineMode::Input);
            } else {
                // Keep collecting lines
                textarea_input.push(line);
                return Ok(line_mode);
            }
        }

        // Handle special built-in commands before regular command processing
        if self.handle_builtin_command(&line).await? {
            return Ok(line_mode);
        }

        if line.starts_with(".program") {
            let words = parse_into_words(&line);
            let usage_msg = "Usage: .program <target>:<verb>";
            if words.len() != 2 {
                self.send_line(usage_msg).await?;
                return Ok(line_mode);
            }
            let verb_spec = words[1].split(':').collect::<Vec<_>>();
            if verb_spec.len() != 2 {
                self.send_line(usage_msg).await?;
                return Ok(line_mode);
            }
            let target = verb_spec[0].to_string();
            let verb = verb_spec[1].to_string();

            // verb must be a valid identifier
            if !verb
                .chars()
                .all(|c| c.is_alphanumeric() || c == '_' || c == '-')
            {
                self.send_line("You must specify a verb; use the format object:verb.")
                    .await?;
                return Ok(line_mode);
            }

            // target should be a valid object #number, $objref, ident, or
            //  a string inside quotes
            if !target.starts_with('$')
                && !target.starts_with('#')
                && !target.starts_with('"')
                && !target.chars().all(|c| c.is_alphanumeric() || c == '_')
            {
                self.send_line("You must specify a target; use the format object:verb.")
                    .await?;
                return Ok(line_mode);
            }

            self.send_line(&format!("Now programming {}. Use \".\" to end.", words[1]))
                .await?;
            self.prompt_end().await?;

            return Ok(LineMode::SpoolingProgram(target, verb));
        }

        self.process_command_line(line).await?;
        Ok(line_mode)
    }

    /// Handle built-in commands that are processed by the telnet host itself.
    /// Returns true if the command was handled, false if it should be passed through to normal processing.
    async fn handle_builtin_command(&mut self, line: &str) -> Result<bool, eyre::Error> {
        let words = parse_into_words(line);
        if words.is_empty() {
            return Ok(false);
        }

        let command = words[0].to_uppercase();
        match command.as_str() {
            "PREFIX" | "OUTPUTPREFIX" => {
                // Set output prefix
                if words.len() == 1 {
                    // Clear prefix
                    self.output_prefix = None;
                } else {
                    // Set prefix to everything after the command
                    let prefix = line[words[0].len()..].trim_start();
                    self.output_prefix = if prefix.is_empty() {
                        None
                    } else {
                        Some(prefix.to_string())
                    };
                }

                // Notify daemon of prefix change
                if let Some(auth_token) = &self.auth_token {
                    let prefix_value = self.output_prefix.as_ref().map(|s| v_str(s));
                    let key = Symbol::mk("line-output-prefix");
                    let _ = self
                        .daemon_client
                        .client_call(
                            self.client_id,
                            ClientRequest::SetClientAttribute {
                                client_token: self.client_token.clone(),
                                auth_token: Some(auth_token.clone()),
                                key,
                                value: prefix_value,
                            },
                        )
                        .await;
                }
                Ok(true)
            }
            "SUFFIX" | "OUTPUTSUFFIX" => {
                // Set output suffix
                if words.len() == 1 {
                    // Clear suffix
                    self.output_suffix = None;
                } else {
                    // Set suffix to everything after the command
                    let suffix = line[words[0].len()..].trim_start();
                    self.output_suffix = if suffix.is_empty() {
                        None
                    } else {
                        Some(suffix.to_string())
                    };
                }

                // Notify daemon of suffix change
                if let Some(auth_token) = &self.auth_token {
                    let suffix_value = self.output_suffix.as_ref().map(|s| v_str(s));
                    let key = Symbol::mk("line-output-suffix");
                    let _ = self
                        .daemon_client
                        .client_call(
                            self.client_id,
                            ClientRequest::SetClientAttribute {
                                client_token: self.client_token.clone(),
                                auth_token: Some(auth_token.clone()),
                                key,
                                value: suffix_value,
                            },
                        )
                        .await;
                }
                Ok(true)
            }
            ".UTF8" => {
                // Toggle UTF-8 support for rich output
                self.supports_utf8 = !self.supports_utf8;
                let status = if self.supports_utf8 { "on" } else { "off" };
                self.send_line(&format!("UTF-8 support is now {}", status))
                    .await?;
                Ok(true)
            }
            ".SCREENREADER" | ".A11Y" => {
                self.screen_reader_mode = !self.screen_reader_mode;
                self.update_connection_attribute(
                    Symbol::mk("screen-reader"),
                    Some(Var::mk_bool(self.screen_reader_mode)),
                )
                .await;
                let status = if self.screen_reader_mode { "on" } else { "off" };
                self.send_line(&format!("Screen reader mode is now {}", status))
                    .await?;
                Ok(true)
            }
            _ => Ok(false),
        }
    }

    async fn handle_narrative_event(
        &mut self,
        event: ClientEvent,
    ) -> Result<Option<(Uuid, InputMetadata)>, eyre::Error> {
        match event {
            ClientEvent::EventsAvailable => bail!("Connection delivery ownership changed"),
            ClientEvent::SystemMessage { message, .. } => {
                self.send_line(&message).await?;
                Ok(None)
            }
            ClientEvent::Narrative {
                event: narrative_event,
                ..
            } => {
                self.output(narrative_event.event).await?;
                Ok(None)
            }
            ClientEvent::RequestInput {
                request_id,
                metadata,
            } => {
                let metadata = InputMetadata::from_metadata_pairs(&metadata);
                // If hold_input is active and has buffered input, return it immediately
                if let Some(ref mut buffer) = self.hold_input
                    && let Some(input_line) = buffer.drain(..1).next()
                {
                    // Send the buffered input as an input reply
                    let Some(auth_token) = self.auth_token.clone() else {
                        bail!("Received input request before auth token was set");
                    };

                    let input_var = v_str(&input_line);
                    let _ = self
                        .daemon_client
                        .client_call(
                            self.client_id,
                            ClientRequest::RequestedInput {
                                client_token: self.client_token.clone(),
                                auth_token,
                                request_id,
                                input: input_var,
                            },
                        )
                        .await;

                    return Ok(None);
                }

                // Display the prompt based on input type
                metadata.display_prompt(self).await?;

                // For text_area, switch to collection mode instead of adding to expecting_input
                if metadata.input_type.as_deref() == Some("text_area") {
                    self.pending_line_mode = Some(LineMode::CollectingTextArea(request_id));
                    Ok(None)
                } else {
                    // Store the request with metadata for later processing
                    Ok(Some((request_id, metadata)))
                }
            }
            ClientEvent::Disconnect => {
                self.pending_task = None;
                self.send_line("** Disconnected **").await?;
                self.flush().await?;
                self.write
                    .close()
                    .await
                    .with_context(|| "Unable to close connection")?;
                Ok(None)
            }
            ClientEvent::TaskError { task_id, error } => {
                let ti = task_id as usize;
                if let Some(pending_event) = self.pending_task.take()
                    && pending_event.task_id != ti
                {
                    error!(
                        "Inbound task response {ti} does not belong to the event we submitted and are expecting {pending_event:?}"
                    );
                }
                self.handle_task_error(error).await?;
                // Send suffix after task error
                self.send_output_suffix().await?;
                Ok(None)
            }
            ClientEvent::TaskSuccess { task_id, .. } => {
                let ti = task_id as usize;
                if let Some(pending_event) = self.pending_task.take()
                    && pending_event.task_id != ti
                {
                    error!(
                        "Inbound task response {ti} does not belong to the event we submitted and are expecting {pending_event:?}"
                    );
                }
                // Send suffix after task success
                self.send_output_suffix().await?;
                Ok(None)
            }
            ClientEvent::TaskSuspended { task_id } => {
                let ti = task_id as usize;
                if let Some(pending_event) = self.pending_task.take()
                    && pending_event.task_id != ti
                {
                    error!(
                        "Inbound task response {ti} does not belong to the event we submitted and are expecting {pending_event:?}"
                    );
                }
                Ok(None)
            }
            ClientEvent::PlayerSwitched {
                new_player,
                new_auth_token,
                ..
            } => {
                info!(
                    "Switching player from {} to {} for client {}",
                    self.connection_object, new_player, self.client_id
                );
                self.connection_object = new_player;
                self.auth_token = Some(new_auth_token);
                info!(
                    "Player switched successfully to {} for client {}",
                    new_player, self.client_id
                );
                Ok(None)
            }
            ClientEvent::SetConnectionOption {
                connection_obj,
                option_name,
                value,
            } => {
                // Only handle if this event is for our connection
                if connection_obj == self.connection_object {
                    self.handle_connection_option(option_name, Some(value))
                        .await?;
                }
                Ok(None)
            }
            ClientEvent::CredentialsUpdated { .. } => {
                // Not relevant for telnet - only used by web clients
                Ok(None)
            }
        }
    }

    /// Send a raw telnet sequence to `do_out_of_band_command` as binary, after login only
    /// (passive mode).
    async fn process_telnet_command(&mut self, cmd: Var) -> Result<(), eyre::Error> {
        let Some(auth_token) = self.auth_token.clone() else {
            // No auth yet — silently ignore telnet commands during login
            return Ok(());
        };

        let args = Var::from(List::from_iter(std::iter::once(cmd.clone())));
        // Fire and forget — we don't wait for OOB task results
        let _ = self
            .daemon_client
            .client_call(
                self.client_id,
                ClientRequest::OutOfBand {
                    client_token: self.client_token.clone(),
                    auth_token,
                    handler_object: self.handler_object,
                    args,
                    argstr: cmd,
                },
            )
            .await;
        Ok(())
    }

    async fn process_command_line(&mut self, line: String) -> Result<(), eyre::Error> {
        let Some(auth_token) = self.auth_token.clone() else {
            bail!("Received command before auth token was set");
        };

        // Send output prefix before executing command
        self.send_output_prefix().await?;

        let reply = if line.starts_with(OUT_OF_BAND_PREFIX) && !self.disable_oob {
            let argstr = v_str(&line);
            let words = parse_into_words(&line);
            let args = Var::from(List::from_iter(words.into_iter().map(v_string)));
            self.daemon_client
                .client_call(
                    self.client_id,
                    ClientRequest::OutOfBand {
                        client_token: self.client_token.clone(),
                        auth_token: auth_token.clone(),
                        handler_object: self.handler_object,
                        args,
                        argstr,
                    },
                )
                .await
        } else {
            let line = line.trim().to_string();

            // Silently ignore empty commands, like LambdaMOO does at parse_command level
            if line.is_empty() {
                return Ok(());
            }

            self.daemon_client
                .client_call(
                    self.client_id,
                    ClientRequest::Command {
                        auth_token: auth_token.clone(),
                        handler_object: self.handler_object,
                        command: line,
                        mode: InvocationMode::Connected {
                            client_token: self.client_token.clone(),
                        },
                    },
                )
                .await
        };

        let reply = match reply {
            Ok(reply) => reply,
            Err(error) => {
                self.handle_client_rpc_error(error, "An error occurred processing your request.")
                    .await?;
                self.send_output_suffix().await?;
                return Ok(());
            }
        };

        match reply {
            ClientReply::TaskSubmitted { task_id } => {
                self.pending_task = Some(PendingTask {
                    task_id: task_id as usize,
                    start_time: Instant::now(),
                });
            }
            ClientReply::InputThanks => {
                bail!("Received input thanks unprovoked, out of order")
            }
            _ => {
                bail!("Unexpected RPC reply type");
            }
        }
        Ok(())
    }

    async fn process_requested_input_line(
        &mut self,
        input_data: Var,
        expecting_input: &mut VecDeque<(Uuid, InputMetadata)>,
    ) -> Result<(), eyre::Error> {
        let Some((input_request_id, metadata)) = expecting_input.front() else {
            bail!("Attempt to send reply to input request without an input request");
        };

        // Validate the input based on metadata
        let Some(input_str) = input_data.as_string() else {
            // Binary input, pass through as-is
            return self
                .send_validated_input(*input_request_id, input_data, expecting_input)
                .await;
        };

        // Special case: @abort always passes through without validation
        if input_str.trim() == "@abort" {
            return self
                .send_validated_input(*input_request_id, v_str("@abort"), expecting_input)
                .await;
        }

        match metadata.validate_input(input_str) {
            Ok(validated_input) => {
                self.send_validated_input(*input_request_id, validated_input, expecting_input)
                    .await
            }
            Err(err_msg) => {
                // Validation failed, show error and keep the request in queue
                self.send_line(&err_msg).await?;
                self.send_line("Please try again:").await?;
                self.prompt_end().await?;
                Ok(())
            }
        }
    }

    async fn send_validated_input(
        &mut self,
        input_request_id: Uuid,
        input_data: Var,
        expecting_input: &mut VecDeque<(Uuid, InputMetadata)>,
    ) -> Result<(), eyre::Error> {
        let Some(auth_token) = self.auth_token.clone() else {
            bail!("Received input reply before auth token was set");
        };

        let reply = match self
            .daemon_client
            .client_call(
                self.client_id,
                ClientRequest::RequestedInput {
                    client_token: self.client_token.clone(),
                    auth_token,
                    request_id: input_request_id,
                    input: input_data,
                },
            )
            .await
        {
            Ok(reply) => reply,
            Err(error) => {
                self.handle_client_rpc_error(error, "An error occurred processing your input.")
                    .await?;
                return Ok(());
            }
        };

        match reply {
            ClientReply::InputThanks => {
                expecting_input.pop_front();
            }
            ClientReply::TaskSubmitted { task_id } => {
                self.pending_task = Some(PendingTask {
                    task_id: task_id as usize,
                    start_time: Instant::now(),
                });
                bail!("Got TaskSubmitted when expecting input-thanks")
            }
            _ => {
                bail!("Unexpected RPC reply type");
            }
        }
        Ok(())
    }

    async fn handle_task_error(&mut self, task_error: SchedulerError) -> Result<(), eyre::Error> {
        match task_error {
            SchedulerError::CommandExecutionError(CommandError::CouldNotParseCommand) => {
                self.send_line("I couldn't understand that.").await?;
                self.flush().await?;
            }
            SchedulerError::CommandExecutionError(CommandError::NoObjectMatch) => {
                self.send_line("I don't see that here.").await?;
                self.flush().await?;
            }
            SchedulerError::CommandExecutionError(CommandError::NoCommandMatch) => {
                self.send_line("I couldn't understand that.").await?;
                self.flush().await?;
            }
            SchedulerError::CommandExecutionError(CommandError::PermissionDenied) => {
                self.send_line("You can't do that.").await?;
                self.flush().await?;
            }
            SchedulerError::VerbProgramFailed(VerbProgramError::CompilationError(
                compile_error,
            )) => {
                let ce = describe_compile_error(compile_error);
                self.send_line(&ce).await?;
                self.send_line("Verb not programmed.").await?;
                self.flush().await?;
            }
            SchedulerError::VerbProgramFailed(VerbProgramError::NoVerbToProgram) => {
                self.send_line("That object does not have that verb definition.")
                    .await?;
            }
            SchedulerError::TaskAbortedLimit(AbortLimitReason::Ticks(_)) => {
                self.send_line("Task ran out of ticks").await?;
            }
            SchedulerError::TaskAbortedLimit(AbortLimitReason::Time(_)) => {
                self.send_line("Task ran out of seconds").await?;
            }
            SchedulerError::TaskAbortedLimit(AbortLimitReason::OutputEvents(_)) => {
                self.send_line("Task produced too many captured output events")
                    .await?;
            }
            SchedulerError::TaskAbortedLimit(AbortLimitReason::OutputBytes(_)) => {
                self.send_line("Task produced too much captured output")
                    .await?;
            }
            SchedulerError::TaskAbortedError => {
                self.send_line("Task aborted").await?;
            }
            SchedulerError::TaskAbortedException(e) => {
                // This should not really be happening here... but?
                self.send_line(&format!("Task exception: {e}")).await?;
            }
            SchedulerError::TaskAbortedCancelled => {
                self.send_line("Task cancelled").await?;
            }
            _ => {
                warn!(?task_error, "Unhandled unexpected task error");
            }
        }
        Ok(())
    }

    /// Send output prefix if defined
    async fn send_output_prefix(&mut self) -> Result<(), eyre::Error> {
        if let Some(prefix) = self.output_prefix.clone() {
            self.send_line(&prefix).await?;
        }
        Ok(())
    }

    /// Send output suffix if defined
    async fn send_output_suffix(&mut self) -> Result<(), eyre::Error> {
        if let Some(suffix) = self.output_suffix.clone() {
            self.send_line(&suffix).await?;
        }
        Ok(())
    }
}

/// The connection state that output rendering depends on.
struct OutputView<'a> {
    negotiator: &'a TelnetNegotiator,
    width: Option<usize>,
    options: RenderOptions,
    binary_mode: bool,
}

/// The frames for one narrative event, in write order.
///
/// A Notify with `["prompt" -> true]` metadata is followed by [`ConnectionFrame::PromptEnd`].
/// `no_newline` is honoured; `no_flush` has no effect, since frames are flushed as written.
fn event_frames(view: &OutputView<'_>, event: Event) -> Vec<ConnectionFrame> {
    match event {
        Event::Notify {
            value,
            content_type,
            no_newline,
            metadata,
            ..
        } => {
            let mut frames = Vec::with_capacity(2);
            if let Some(frame) = notify_frame(view, &value, content_type, no_newline) {
                frames.push(frame);
            }
            if is_prompt(metadata.as_deref()) {
                frames.push(ConnectionFrame::PromptEnd);
            }
            frames
        }
        Event::Traceback(e) => e
            .backtrace
            .iter()
            .filter_map(|frame| frame.as_string())
            .map(|s| ConnectionFrame::Line(s.to_string()))
            .collect(),
        Event::Data {
            namespace,
            kind,
            payload,
        } => data_frame(
            view.negotiator,
            &namespace.as_arc_str(),
            &kind.as_arc_str(),
            &payload,
        )
        .into_iter()
        .collect(),
        Event::Present(_) | Event::Unpresent(_) | Event::SetConnectionOption { .. } => {
            // Web UI elements, and options delivered as ClientEvent::SetConnectionOption.
            trace!("Ignoring event in telnet client");
            vec![]
        }
    }
}

/// The frame for a Notify value. Binary values are written as raw bytes.
fn notify_frame(
    view: &OutputView<'_>,
    value: &Var,
    content_type: Option<Symbol>,
    no_newline: bool,
) -> Option<ConnectionFrame> {
    if let Variant::Binary(b) = value.variant() {
        return Some(ConnectionFrame::Bytes(bytes::Bytes::copy_from_slice(
            b.as_bytes(),
        )));
    }
    let Ok(formatted) = output_format(value, content_type, view.width, view.options) else {
        warn!("Failed to format message: {:?}", value);
        return None;
    };
    Some(match formatted {
        FormattedOutput::Plain(text) if no_newline || view.binary_mode => {
            ConnectionFrame::RawText(text)
        }
        FormattedOutput::Plain(text) => ConnectionFrame::Line(text),
        FormattedOutput::Rich(text) => {
            ConnectionFrame::RawText(normalize_telnet_line_endings(&text))
        }
    })
}

/// True when Notify metadata marks the output as a prompt (`["prompt" -> true]`).
fn is_prompt(metadata: Option<&[(Symbol, Var)]>) -> bool {
    metadata
        .into_iter()
        .flatten()
        .any(|(key, value)| key.as_arc_str().as_str() == "prompt" && value.is_true())
}

/// Produce the right kind of "telnet" compatible output for the given content.
fn output_format(
    content: &Var,
    content_type: Option<Symbol>,
    width: Option<usize>,
    options: RenderOptions,
) -> Result<FormattedOutput, eyre::Error> {
    match content.variant() {
        Variant::Str(s) => output_str_format(s.as_str(), content_type, width, options),
        Variant::Sym(s) => output_str_format(&s.as_arc_str(), content_type, width, options),
        Variant::List(l) => {
            // If the content is a list, it must be a list of strings.
            let mut output = String::new();
            for item in l.iter() {
                let Some(item_str) = item.as_string() else {
                    bail!("Expected list item to be a string, got: {:?}", item);
                };
                if !output.is_empty() {
                    output.push('\n');
                }
                output.push_str(item_str);
            }
            output_str_format(&output, content_type, width, options)
        }
        _ => bail!("Unsupported content type: {:?}", content.variant()),
    }
}

fn output_str_format(
    content: &str,
    content_type: Option<Symbol>,
    _width: Option<usize>,
    options: RenderOptions,
) -> Result<FormattedOutput, eyre::Error> {
    let Some(content_type) = content_type else {
        debug!("output_str_format: no content_type, using plain");
        return Ok(FormattedOutput::Plain(content.to_string()));
    };
    let content_type_str = content_type.as_arc_str();
    debug!("output_str_format: content_type={}", content_type_str);
    Ok(match content_type_str.as_str() {
        // The djot renderer handles most markdown syntax too.
        CONTENT_TYPE_MARKDOWN
        | CONTENT_TYPE_MARKDOWN_SLASH
        | CONTENT_TYPE_DJOT
        | CONTENT_TYPE_DJOT_SLASH => {
            FormattedOutput::Rich(djot_to_terminal_with_options(content, options))
        }
        // text/plain, None, or unknown
        _ => FormattedOutput::Plain(content.to_string()),
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::session::telnet::{ProtocolPolicy, Verb};
    use bytes::BytesMut;
    use moor_var::{v_int, v_map};
    use tokio_util::codec::Encoder;

    fn notify(text: &str, no_newline: bool, metadata: Option<Vec<(Symbol, Var)>>) -> Event {
        Event::Notify {
            value: v_str(text),
            content_type: None,
            no_flush: true,
            no_newline,
            metadata,
        }
    }

    fn prompt_meta() -> Option<Vec<(Symbol, Var)>> {
        Some(vec![(Symbol::mk("prompt"), v_int(1))])
    }

    fn gmcp_on(mark: bool) -> TelnetNegotiator {
        let mut n = TelnetNegotiator::new(ProtocolPolicy {
            gmcp: true,
            eor: mark,
            ..ProtocolPolicy::default()
        });
        n.on_event(TelnetEvent::Negotiate {
            verb: Verb::Do,
            option: OPT_GMCP,
        });
        if mark {
            n.on_event(TelnetEvent::Negotiate {
                verb: Verb::Do,
                option: OPT_EOR,
            });
        }
        n
    }

    /// Encode the frames of each event in order, as the session's single writer does.
    fn wire(n: &TelnetNegotiator, events: Vec<Event>) -> Vec<u8> {
        let view = OutputView {
            negotiator: n,
            width: None,
            options: RenderOptions::default(),
            binary_mode: false,
        };
        let mut codec = ConnectionCodec::new();
        codec.set_prompt_mark(n.prompt_mark());
        let mut buf = BytesMut::new();
        for event in events {
            for frame in event_frames(&view, event) {
                codec.encode(frame, &mut buf).unwrap();
            }
        }
        buf.to_vec()
    }

    fn data(kind: &str) -> Event {
        Event::Data {
            namespace: Symbol::mk("gmcp"),
            kind: Symbol::mk(kind),
            payload: v_map(&[]),
        }
    }

    #[test]
    fn normalize_telnet_line_endings_coalesces_mixed_newlines() {
        let input = "alpha\nbeta\r\ngamma\rdelta";
        let expected = "alpha\r\nbeta\r\ngamma\r\ndelta";
        assert_eq!(normalize_telnet_line_endings(input), expected);
    }

    #[test]
    fn prompt_notify_is_text_then_prompt_end() {
        let n = gmcp_on(true);
        let view = OutputView {
            negotiator: &n,
            width: None,
            options: RenderOptions::default(),
            binary_mode: false,
        };
        let frames = event_frames(&view, notify("HP:20> ", true, prompt_meta()));
        assert!(
            matches!(&frames[..], [ConnectionFrame::RawText(t), ConnectionFrame::PromptEnd] if t == "HP:20> ")
        );
        // Without the metadata there is no mark; a false value is not a prompt.
        let frames = event_frames(&view, notify("x", true, None));
        assert!(matches!(&frames[..], [ConnectionFrame::RawText(_)]));
        let frames = event_frames(
            &view,
            notify("x", false, Some(vec![(Symbol::mk("prompt"), v_int(0))])),
        );
        assert!(matches!(&frames[..], [ConnectionFrame::Line(_)]));
    }

    #[test]
    fn prompt_mark_ordering_with_gmcp() {
        let n = gmcp_on(true);
        let bytes = wire(
            &n,
            vec![
                data("Char.Vitals"),
                notify("> ", true, prompt_meta()),
                data("Core.Ping"),
            ],
        );
        let mut expected = Vec::new();
        expected.extend_from_slice(&[IAC, SB, OPT_GMCP]);
        expected.extend_from_slice(b"Char.Vitals");
        expected.extend_from_slice(&[IAC, SE]);
        expected.extend_from_slice(b"> ");
        expected.extend_from_slice(&[IAC, EOR]);
        expected.extend_from_slice(&[IAC, SB, OPT_GMCP]);
        expected.extend_from_slice(b"Core.Ping");
        expected.extend_from_slice(&[IAC, SE]);
        assert_eq!(bytes, expected);
    }

    #[test]
    fn prompt_mark_is_ga_without_eor() {
        let n = gmcp_on(false);
        assert_eq!(
            wire(&n, vec![notify("> ", true, prompt_meta())]),
            [b"> ".as_slice(), &[IAC, GA]].concat()
        );
    }

    #[test]
    fn passive_prompt_writes_no_mark() {
        let n = TelnetNegotiator::new(ProtocolPolicy::default());
        assert_eq!(
            wire(
                &n,
                vec![notify("> ", true, prompt_meta()), data("Core.Ping")]
            ),
            b"> ".to_vec()
        );
    }

    #[test]
    fn binary_notify_is_raw_bytes() {
        let n = TelnetNegotiator::new(ProtocolPolicy::default());
        let event = Event::Notify {
            value: Var::mk_binary(vec![IAC, WILL, 77]),
            content_type: None,
            no_flush: false,
            no_newline: false,
            metadata: None,
        };
        assert_eq!(wire(&n, vec![event]), vec![IAC, WILL, 77]);
    }

    #[test]
    fn no_newline_is_honoured() {
        let n = TelnetNegotiator::new(ProtocolPolicy::default());
        assert_eq!(
            wire(&n, vec![notify("a", true, None), notify("b", false, None)]),
            b"ab\r\n".to_vec()
        );
    }
}
