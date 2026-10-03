# Telnet out-of-band protocols: design contract

Status: being implemented on branch `feat/telnet-oob-protocols`. This document is the contract
that the implementation and its tests follow. Where the code and this document disagree, fix one
of them in the same change.

## Goals

- Telnet option negotiation, escaping, framing, and compression live in `telnet-host`. The daemon
  routes values. It does not interpret any telnet protocol.
- MOO code sends and receives structured values. MOO code never builds or parses IAC bytes, except
  through the existing raw `notify(conn, <binary>)` path.
- Every protocol is off by default. With the default configuration, the bytes on the wire do not
  change.
- No data migrations. The schemas change only by appending.

## Non-goals

- The protocol choice is visible to application code. A namespace named `gmcp` shares transport
  plumbing with other hosts. It does not make MOO code protocol-independent. Package names and
  value shapes are a contract between the world and its clients.
- The host does not decode the semantics of an option that it does not implement.

## Layers

| Layer | Owns |
|---|---|
| `telnet-host::session::telnet` (sans-IO) | Option state (RFC 1143 Q method), negotiation policy, protocol encode/decode (GMCP, MSDP, MSSP, NAWS, TTYPE/MTTS, CHARSET, EOR), producing `Action`s |
| `telnet-host::session::codec` | Byte framing: IAC parse into `TelnetEvent`, IAC escaping on output, subnegotiation size cap, prompt marks, MCCP2 compression switch |
| `telnet-host::session` | Applies `Action`s: writes frames, records attributes, sends `ClientData` to the daemon |
| `moor_var::json` | The single MOO value <-> JSON mapping used by the kernel builtins and by hosts |
| `runtime-api` / `schema` | `ClientData` request, `SetClientAttribute` with optional auth |
| `daemon` | Delivers `ClientData` to `do_client_data`; stores attributes |

## Outbound: `emit_data` is the envelope, the adapter is the contract

MOO code calls the existing builtin:

```
emit_data(conn_or_player, 'gmcp, 'Char.Vitals, ["hp" -> 12, "maxhp" -> 20]);
```

`Event::Data { namespace, kind, payload }` is the envelope only. The telnet adapter defines the
rest:

### Delivery rules

- Target. A negative connection object reaches that connection only. A player object reaches each
  connection of the player. Each telnet connection applies the rules below independently.
- Negotiation gate. A `gmcp` event is written only if GMCP is enabled on that connection
  (`him`/`us` state Yes). Otherwise it is dropped and counted at `trace` level. The same rule
  applies to `msdp`.
- Package gate. If the client sent `Core.Supports.Set`/`Add`, a `gmcp` event is written only when
  the package or one of its parents (`Char` for `Char.Vitals`) is in the supported set. If the
  client never sent `Core.Supports`, every package is written.
- Other namespaces are ignored by the telnet host, as before.

### Package mapping (`gmcp`)

- `kind` is the GMCP package and message name, unchanged (`Char.Vitals`). It must match
  `[A-Za-z0-9_.-]{1,128}`. An invalid name is dropped with a `warn`.
- Wire form: `IAC SB 201 <kind> SP <json> IAC SE`.
- No body. A payload equal to the empty map `[]` is sent as `IAC SB 201 <kind> IAC SE`, with no
  space and no body (`Core.Ping`). Inbound, a message with no body is delivered with payload `[]`.
  An explicit `{}` body is also delivered as `[]`; GMCP clients treat the two the same.
- 0xFF bytes in the encoded message are escaped as `IAC IAC`.

### Value conversion (`moor_var::json`)

| MOO | JSON |
|---|---|
| INT | number |
| FLOAT (finite) | number |
| STR | string |
| SYM | string |
| BOOL | true/false |
| OBJ `#-1` | null |
| OBJ other | string `"#N"` (UUID objects in their literal form) |
| LIST | array |
| MAP (keys STR, SYM, INT, FLOAT, OBJ) | object (keys rendered as strings) |
| ERR, BINARY, FLYWEIGHT, LAMBDA, non-finite FLOAT, other map key types | not convertible: the event is dropped with a `warn`; it does not disconnect |

Inbound JSON maps back as in `parse_json`: `null` -> `#-1`, objects -> maps with string keys,
booleans by the daemon's `use_boolean_returns` (the host gets it from `GetServerFeatures`). A body
that is not valid JSON is delivered as a STR holding the raw body text.

`generate_json`/`parse_json` keep their current behaviour except that SYM now converts to a string
instead of raising `E_TYPE`.

### MSDP

`emit_data(conn, 'msdp, 'VARNAME, value)` writes `MSDP_VAR VARNAME MSDP_VAL <value>`; a MAP becomes
`MSDP_TABLE_OPEN ... MSDP_TABLE_CLOSE`, a LIST becomes `MSDP_ARRAY_OPEN ... MSDP_ARRAY_CLOSE`, a
scalar becomes its string form. Inbound MSDP commands (`LIST`, `REPORT`, `SEND`, ...) are delivered
to MOO as `ClientData('msdp, <VAR>, <value>)`.

## Inbound: `ClientData` and `do_client_data`

### Request

Appended last to `HostClientToDaemonMessageUnion`:

```
table ClientData {
  client_token:   ClientToken (required);
  auth_token:     AuthToken;          // absent before login
  handler_object: Obj (required);     // the listener's handler object
  data_namespace: Symbol (required);  // `namespace` is reserved in the IDL
  kind:           Symbol (required);
  payload:        Var (required);
}
```

The daemon replies `ClientReply::TaskSubmitted { task_id }` or an error. Hosts do not wait for the
task result and do not register it with the task monitor, so task completion and task errors are
not published to the client for this task.

### The hook

```
handler_object:do_client_data(obj connection, sym namespace, sym kind, any payload)
```

| Question | Before login | After login |
|---|---|---|
| Which object | the listener's `handler_object` (`#0` for the default listener) | same |
| `connection` arg | the connection object (negative) | the connection object (negative) |
| `player` | the connection object | the logged-in player |
| Task permissions / authority | `#0`, as for `do_login_command` | the logged-in player, as for `do_out_of_band_command` |
| Where `notify`/`emit_data` to `player` go | that connection | each connection of the player; use `connection` to target this one |
| Auth | client token only | client token and auth token, checked as `verify_tokens` |

If the hook verb does not exist, the task ends with no output to the client.

`do_out_of_band_command` is unchanged. It still receives `#$#` lines and, as a fallback, unknown
telnet options (below).

### Unknown options

The host forwards every subnegotiation or negotiation for an option it does not implement, when
OOB is not disabled, as:

```
ClientData('telnet, 'subneg, ["option" -> <int>, "data" -> <binary>])        // IAC SB opt ... IAC SE, data unescaped
ClientData('telnet, 'negotiate, ["option" -> <int>, "verb" -> 'will|'wont|'do|'dont])
```

The host refuses the option (`DONT`/`WONT`) per RFC 1143 unless policy says otherwise. The world
can reply with `notify(conn, <binary>)` for an option the host does not implement.

### Capability changes

Negotiation results are connection attributes. When a negotiation step changes one or more
attributes, the host:

1. updates its local attribute map;
2. sends `SetClientAttribute` for each changed key (allowed before login, see below);
3. sends one `ClientData('client, 'attributes, <map of changed keys -> new values>)`.

MOO code reads the current state with `connection_options(conn)`. It does not poll.

### `SetClientAttribute` before login

`SetClientAttribute.auth_token` becomes optional (removing `(required)` is acceptable here because
there are no deployments to migrate). The daemon:

- always validates the client token;
- if an auth token is present, verifies it as today;
- if absent, accepts the request only while the client has no logged-in player.

## Attributes owned by the telnet host

| Key | Type | Source |
|---|---|---|
| `host_type` | STR | fixed `"telnet"` |
| `tls` | BOOL | listener; sent in `ConnectionEstablish` |
| `columns`, `rows` | INT | NAWS |
| `terminal_type` | STR | TTYPE first reply |
| `client_name` | STR | TTYPE first reply, or GMCP `Core.Hello.client` |
| `client_version` | STR | GMCP `Core.Hello.version` |
| `mtts` | INT | TTYPE `MTTS n` |
| `utf8` | BOOL | MTTS bit 4, or CHARSET `UTF-8` accepted, or `set_connection_option(conn, 'utf8, 1)` |
| `charset` | STR | CHARSET result (`"UTF-8"`, `"ISO-8859-1"`, ...) |
| `screen-reader` | BOOL | MTTS bit 64, `.SCREENREADER`, or option |
| `gmcp`, `msdp`, `mxp`, `eor`, `mccp2` | BOOL | option state |
| `gmcp_supports` | MAP STR -> INT | `Core.Supports.*` |

## Option toggling from MOO

`set_connection_option(conn, <name>, <value>)` for `gmcp`, `msdp`, `mxp`, `eor`, `mccp2`, `naws`,
`ttype`, `charset`, `echo` asks the negotiator to enable or disable the option. The negotiator
sends `WILL`/`WONT`/`DO`/`DONT` only if the state requires it, so repeated calls do not cause loops.
`client-echo` is routed through the negotiator. Disabling an option clears its attribute.

## UTF-8 and charsets

- Default: input is decoded as UTF-8 with replacement (as today). Output is UTF-8.
- If the host offers CHARSET (RFC 2066) and the client accepts `UTF-8`, `utf8` becomes true.
- If the client selects `ISO-8859-1` (or another 8-bit charset supported by the codec), input
  bytes are transcoded to UTF-8, and output is transcoded to that charset. Characters that do not
  exist in the charset become `?`.
- In text, `IAC IAC` is a literal 0xFF byte and goes through charset decoding. On output, a 0xFF
  byte produced by charset encoding is written as `IAC IAC`.
- The MTTS UTF-8 bit sets `utf8` but does not change the codec charset; a client that reports it
  already speaks UTF-8.

## Prompts, GA and EOR

A prompt mark is sent only for output that is explicitly a prompt. "No newline" and "flush now" do
not mean "end of prompt".

A Notify is a prompt when its metadata contains `prompt` with a true value:

```
notify(conn, "HP:20> ", 0, 1, 'text_plain, ["prompt" -> 1]);
```

The host also marks its own prompts: the `RequestInput` prompt (`display_prompt`), the `.program`
prompt, and validation re-prompts.

Rule: after the prompt text is written, the host writes `IAC EOR` if EOR is enabled, otherwise
`IAC GA` unless SUPPRESS-GO-AHEAD is enabled, otherwise nothing.

Ordering: the mark goes immediately after the prompt text and before any later frame, text or
subnegotiation, from the same or a later event. A GMCP subnegotiation emitted by the same task
before the prompt Notify is written before the prompt text.

`no_newline` is honoured after login as it is before login.

## MXP

- MXP is offered only when configured. When it is enabled, the host sends `ESC [7z` (locked mode
  as the default) so that `<` in user text is never parsed.
- `text_djot` / `text_markdown` output is rendered with an MXP target: links become `<SEND>` or
  `<A>`, `& < >` are escaped, and each line is opened in secure mode (`ESC [1z`).
- Plain text is never in secure mode.

## MSSP

If MSSP is enabled, the host answers `DO MSSP` from the configured static values, plus `PLAYERS`
and `UPTIME` that the host computes. The world is not called. Plain-text `MSSP-REQUEST` is not
implemented.

## MCCP2

If configured and the client sends `DO MCCP2`, the host writes `IAC SB 86 IAC SE` uncompressed. It
then compresses every later byte of the connection with zlib, using a sync flush per frame. If
compression fails, the host closes the connection.

## Limits

- A subnegotiation over `max_subneg` bytes (default 65536) is discarded. The decoder resynchronises
  at the next `IAC SE`, and the stream is not closed.
- Inbound `ClientData` per connection is rate limited (default 50 per second, burst 100). Excess
  messages are dropped with a `warn`.
- Telnet protocol code must not panic. Errors are logged, and the connection either continues or
  closes cleanly, sending `Detach`.

## Configuration

`TelnetProtocolConfig`, in `TelnetHostConfig` and in the single-process `services.telnet` section:

```yaml
protocols:
  offer_on_connect: false   # send WILL/DO offers at connect
  gmcp: false
  msdp: false
  mssp: false
  mxp: false
  naws: false
  ttype: false
  eor: false
  charset: false
  mccp2: false
  max_subneg: 65536
  client_data_rate: 50
  mssp_values: { NAME: "...", CODEBASE: "mooR" }
```

## Out of scope for this change

- Event routing for players with several connections. `set_connection_option()` already requires
  a connection object, and `client_ids_for()` resolves a connection record before player-wide
  records, so `client_ids.first()` in `publish_narrative_events` is that connection's client. No
  routing change without a reproducer.
- Event-log policy for `Event::Data`. Data events stay logged as today.
- Browser-side GMCP input (a web-host `ClientData` path).
- Plain-text `MSSP-REQUEST`.

## Tests

The existing tests stay green with the defaults. New tests:

- codec unit tests: every TelnetEvent form, split buffers, IAC IAC in text and subneg, the
  subneg cap and resync, escaping, PromptEnd, compression (inflate and compare), charset round
  trips;
- negotiator unit tests: the RFC 1143 state table (including loop prevention and the opposite
  queue), each option's subnegotiation, TTYPE cycling and MTTS bits, CHARSET accept and reject,
  `Core.Supports` handling, package gating;
- `moor_var::json` unit tests for every row of the conversion table;
- a raw-socket integration test suite (`crates/telnet-host/tests/telnet_protocols.rs`) against a
  daemon and telnet host with protocols enabled: negotiation at connect, NAWS and TTYPE becoming
  attributes before and after login, UTF-8 negotiation and Latin-1 transcoding, option toggling
  from MOO with no loops, GMCP both ways including before login, the unknown-option fallback,
  prompt marks and their ordering with GMCP, MSSP, MCCP2, and the subneg cap.
