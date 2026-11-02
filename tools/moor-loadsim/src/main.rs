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

//! Runs a simulated load against a throwaway daemon and telnet host, and reports what players
//! would see: which sessions were dropped, and how long commands took.
//!
//! This always starts its own servers on a temporary database and never attaches to an existing
//! server, because scenarios overwrite verbs such as `do_login_command`.

use clap::Parser;
use clap_derive::{Args, Parser, Subcommand, ValueEnum};
use eyre::{WrapErr, bail, eyre};
use std::{
    fs,
    io::{ErrorKind, Read, Write},
    net::{Shutdown, TcpListener, TcpStream},
    path::{Path, PathBuf},
    process::{Child, Command, Stdio},
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, Ordering},
        mpsc::{self, Receiver, RecvTimeoutError, Sender},
    },
    thread,
    time::{Duration, Instant},
};

/// Test-only keypair, the same one the telnet host's wire tests use.
const SIGNING_KEY: &str = "-----BEGIN PRIVATE KEY-----
MC4CAQAwBQYDK2VwBCIEILrkKmddHFUDZqRCnbQsPoW/Wsp0fLqhnv5KNYbcQXtk
-----END PRIVATE KEY-----
";
const VERIFYING_KEY: &str = "-----BEGIN PUBLIC KEY-----
MCowBQYDK2VwAyEAZQUxGvw8u9CcUHUGLttWFZJaoroXAmQgUGINgbBlVYw=
-----END PUBLIC KEY-----
";

const LOGIN_LINE: &str = "connect #3\r\n";
const CONNECTED_BANNER: &str = "*** Connected ***";
const SERVER_START_TIMEOUT: Duration = Duration::from_secs(60);
const SESSION_LOGIN_TIMEOUT: Duration = Duration::from_secs(15);
const EVAL_TIMEOUT: Duration = Duration::from_secs(30);
const PROBE_TIMEOUT: Duration = Duration::from_secs(30);
/// Schedules created per eval, so large counts stay inside one task's tick limit.
const SETUP_CHUNK: usize = 200;

/// Log lines worth counting. The `DIAG:` lines only appear in builds with the logging patch.
const LOG_PATTERNS: &[&str] = &[
    "Unable to send pong",
    "Unable to send login request",
    "Removing connection due to ping timeout",
    "has not responded in time",
    "Task exception:",
    "DIAG: pong failed",
    "DIAG: pong was slow",
    "DIAG: long gap between pings",
    "DIAG: pong reached an RPC worker late",
    "DIAG: RPC worker is held now",
    "DIAG: RPC request held a worker",
    "DIAG: slow scheduler step",
    "DIAG: scheduler step is stuck now",
    "DIAG: lifecycle lock unavailable",
    "DIAG: task pool has a backlog",
    "DIAG: task waited for a pool thread",
    "DIAG: scheduler client request backlog",
    "DIAG: ping round",
];

#[derive(Parser)]
#[command(about, version)]
struct Cli {
    #[command(subcommand)]
    scenario: Scenario,
}

#[derive(Subcommand)]
enum Scenario {
    /// Run many tasks through schedule_every() or schedule_at() while players sit idle.
    ScheduledTasks(ScheduledTasks),
    /// Hold RPC workers with logins that suspend. This is known to drop sessions, so it also
    /// serves as a control for the tool itself.
    HeldWorkers(HeldWorkers),
    /// Run web API evals that wait on a slow task, as a bot calling out to a slow service does.
    CapturedCalls(CapturedCalls),
}

#[derive(Args)]
struct Common {
    /// Idle logged-in telnet sessions to watch.
    #[arg(long, default_value_t = 20)]
    sessions: usize,
    /// Time between probe commands.
    #[arg(long, default_value_t = 1000)]
    probe_interval_ms: u64,
    /// Time to measure before starting the load.
    #[arg(long, default_value_t = 10)]
    baseline_secs: u64,
    /// Daemon binary. Defaults to moor-daemon next to this tool.
    #[arg(long)]
    daemon_bin: Option<PathBuf>,
    /// Telnet host binary. Defaults to moor-telnet-host next to this tool.
    #[arg(long)]
    telnet_bin: Option<PathBuf>,
    /// Textdump to import. Defaults to the workspace's Test.db.
    #[arg(long)]
    core: Option<PathBuf>,
    /// Extra daemon argument, such as --daemon-arg=--num-io-threads=16. Can be repeated.
    #[arg(long = "daemon-arg", allow_hyphen_values = true)]
    daemon_args: Vec<String>,
    /// Directory for the database and logs. It must not already exist.
    #[arg(long)]
    run_dir: Option<PathBuf>,
}

#[derive(Args)]
struct ScheduledTasks {
    #[command(flatten)]
    common: Common,
    /// Number of schedules to create.
    #[arg(long, default_value_t = 500)]
    schedules: usize,
    /// Time between firings of each schedule.
    #[arg(long, default_value_t = 200)]
    interval_ms: u64,
    /// Loop iterations each firing runs.
    #[arg(long, default_value_t = 1000)]
    work_iterations: u64,
    /// `every` uses schedule_every(). `at` has each firing call schedule_at() again.
    #[arg(long, value_enum, default_value_t = ScheduleMode::Every)]
    mode: ScheduleMode,
    /// Random delay added to each firing. Zero makes schedules fire together. `every` mode only.
    #[arg(long, default_value_t = 0)]
    jitter_ms: u64,
    /// Have every firing write the same property, which causes transaction conflicts.
    #[arg(long)]
    shared_property: bool,
    /// How long to run the load.
    #[arg(long, default_value_t = 120)]
    duration_secs: u64,
}

#[derive(Clone, Copy, PartialEq, ValueEnum)]
enum ScheduleMode {
    Every,
    At,
}

#[derive(Args)]
struct HeldWorkers {
    #[command(flatten)]
    common: Common,
    /// Connections whose login holds an RPC worker.
    #[arg(long, default_value_t = 2)]
    holders: usize,
    /// How long each login holds its worker.
    #[arg(long, default_value_t = 35)]
    hold_secs: u64,
    /// How long to keep watching after the holds end.
    #[arg(long, default_value_t = 12)]
    cooldown_secs: u64,
}

#[derive(Args)]
struct CapturedCalls {
    #[command(flatten)]
    common: Common,
    /// Web API calls running at once. Each one sends another when it finishes.
    #[arg(long, default_value_t = 14)]
    calls: usize,
    /// How long each call's task suspends.
    #[arg(long, default_value_t = 5)]
    call_secs: u64,
    /// How long to run the load.
    #[arg(long, default_value_t = 60)]
    duration_secs: u64,
    /// Web host binary. Defaults to moor-web-host next to this tool.
    #[arg(long)]
    web_bin: Option<PathBuf>,
}

/// A server process, killed when the run ends for any reason.
struct ManagedChild(Child);

impl Drop for ManagedChild {
    fn drop(&mut self) {
        let _ = self.0.kill();
        let _ = self.0.wait();
    }
}

struct Servers {
    run_dir: PathBuf,
    port: u16,
    daemon: ManagedChild,
    telnet: ManagedChild,
}

impl Servers {
    fn start(common: &Common) -> eyre::Result<Self> {
        let run_dir = match &common.run_dir {
            Some(dir) => dir.clone(),
            None => std::env::temp_dir().join(format!("moor-loadsim-{}", std::process::id())),
        };
        fs::create_dir_all(run_dir.parent().unwrap_or(Path::new("/")))?;
        fs::create_dir(&run_dir)
            .wrap_err_with(|| format!("Could not create run directory {}", run_dir.display()))?;
        let run_dir = run_dir.canonicalize()?;
        let config_dir = run_dir.join("config");
        fs::create_dir(&config_dir)?;
        let signing_key = run_dir.join("moor-signing-key.pem");
        let verifying_key = run_dir.join("moor-verifying-key.pem");
        fs::write(&signing_key, SIGNING_KEY)?;
        fs::write(&verifying_key, VERIFYING_KEY)?;

        let core = match &common.core {
            Some(core) => core.canonicalize()?,
            None => Path::new(env!("CARGO_MANIFEST_DIR"))
                .join("../../crates/testing/moot/Test.db")
                .canonicalize()
                .wrap_err("Could not find Test.db; pass --core")?,
        };
        let daemon_bin = server_binary(&common.daemon_bin, "moor-daemon")?;
        let telnet_bin = server_binary(&common.telnet_bin, "moor-telnet-host")?;

        // IPC paths are relative to the run directory, because socket paths have a short limit.
        let daemon = Command::new(daemon_bin)
            .arg("--import")
            .arg(core)
            .args(["--import-format", "textdump"])
            .arg("--private-key")
            .arg(signing_key)
            .arg("--public-key")
            .arg(verifying_key)
            .args(["--enrollment-listen", "ipc://enrollment.sock"])
            .args(["--workers-request-listen", "ipc://workers-request.sock"])
            .args(["--workers-response-listen", "ipc://workers-response.sock"])
            .args(["--events-listen", "ipc://events.sock"])
            .args(["--rpc-listen", "ipc://rpc.sock"])
            .args(&common.daemon_args)
            .arg("test.db")
            .env("XDG_CONFIG_HOME", &config_dir)
            .current_dir(&run_dir)
            .stdin(Stdio::null())
            .stdout(fs::File::create(run_dir.join("daemon.log"))?)
            .stderr(fs::File::create(run_dir.join("daemon.err.log"))?)
            .spawn()
            .wrap_err("Could not start the daemon")?;
        let daemon = ManagedChild(daemon);

        let port = TcpListener::bind("127.0.0.1:0")?.local_addr()?.port();
        let telnet = Command::new(telnet_bin)
            .args(["--events-address", "ipc://events.sock"])
            .args(["--rpc-address", "ipc://rpc.sock"])
            .args(["--telnet-address", "127.0.0.1"])
            .args(["--telnet-port", &port.to_string()])
            .args(["--health-check-port", "0"])
            .env("XDG_CONFIG_HOME", &config_dir)
            .current_dir(&run_dir)
            .stdin(Stdio::null())
            .stdout(fs::File::create(run_dir.join("telnet.log"))?)
            .stderr(fs::File::create(run_dir.join("telnet.err.log"))?)
            .spawn()
            .wrap_err("Could not start the telnet host")?;
        let telnet = ManagedChild(telnet);

        Ok(Self {
            run_dir,
            port,
            daemon,
            telnet,
        })
    }

    /// Log in, retrying while the servers start.
    fn first_login(&mut self) -> eyre::Result<TcpStream> {
        let deadline = Instant::now() + SERVER_START_TIMEOUT;
        loop {
            for (name, child) in [
                ("daemon", &mut self.daemon),
                ("telnet host", &mut self.telnet),
            ] {
                if let Some(status) = child.0.try_wait()? {
                    bail!(
                        "The {name} exited during startup ({status}). See the logs in {}",
                        self.run_dir.display()
                    );
                }
            }
            match login(self.port, SESSION_LOGIN_TIMEOUT) {
                Ok(stream) => return Ok(stream),
                Err(error) if Instant::now() >= deadline => {
                    return Err(error.wrap_err(format!(
                        "Servers did not accept a login. See the logs in {}",
                        self.run_dir.display()
                    )));
                }
                Err(_) => thread::sleep(Duration::from_millis(500)),
            }
        }
    }
}

fn server_binary(configured: &Option<PathBuf>, name: &str) -> eyre::Result<PathBuf> {
    if let Some(path) = configured {
        return Ok(path.clone());
    }
    let path = std::env::current_exe()?
        .parent()
        .ok_or_else(|| eyre!("This tool's binary has no parent directory"))?
        .join(name);
    if !path.exists() {
        bail!(
            "{} does not exist. Run `cargo build -p moor-daemon -p moor-telnet-host`, or pass the binary path.",
            path.display()
        );
    }
    Ok(path)
}

fn login(port: u16, timeout: Duration) -> eyre::Result<TcpStream> {
    let mut stream = TcpStream::connect(("127.0.0.1", port))?;
    stream.set_read_timeout(Some(Duration::from_millis(100)))?;
    stream.write_all(LOGIN_LINE.as_bytes())?;
    wait_for_text(&mut stream, CONNECTED_BANNER, timeout)?;
    Ok(stream)
}

/// Read until `text` appears, and return everything read.
fn wait_for_text(stream: &mut TcpStream, text: &str, timeout: Duration) -> eyre::Result<String> {
    let deadline = Instant::now() + timeout;
    let mut received = Vec::new();
    let mut buffer = [0u8; 4096];
    loop {
        let so_far = String::from_utf8_lossy(&received);
        if so_far.contains(text) {
            return Ok(so_far.into_owned());
        }
        if Instant::now() >= deadline {
            bail!("Timed out waiting for {text:?}. Received: {so_far}");
        }
        match stream.read(&mut buffer) {
            Ok(0) => bail!("Connection closed while waiting for {text:?}. Received: {so_far}"),
            Ok(read) => received.extend_from_slice(&buffer[..read]),
            Err(error) if matches!(error.kind(), ErrorKind::WouldBlock | ErrorKind::TimedOut) => {}
            Err(error) => return Err(error.into()),
        }
    }
}

/// Run MOO statements, and return the output up to and including a marker the eval returns.
fn eval(stream: &mut TcpStream, code: &str, marker: &str) -> eyre::Result<String> {
    stream.write_all(format!("; {code} return \"{marker}\";\r\n").as_bytes())?;
    wait_for_text(stream, marker, EVAL_TIMEOUT).wrap_err_with(|| format!("Eval failed: {code}"))
}

/// Shared record of sessions dropped while the load ran.
#[derive(Clone)]
struct Watch {
    started: Instant,
    stopping: Arc<AtomicBool>,
    drops: Arc<Mutex<Vec<(f64, String)>>>,
}

impl Watch {
    /// Read a session until it ends, recording the end unless the run is finishing.
    fn watch(&self, label: String, mut stream: TcpStream, output: Option<Sender<Vec<u8>>>) {
        let watch = self.clone();
        thread::spawn(move || {
            let _ = stream.set_read_timeout(None);
            let mut buffer = [0u8; 4096];
            loop {
                match stream.read(&mut buffer) {
                    Ok(read) if read > 0 => {
                        if let Some(output) = &output {
                            let _ = output.send(buffer[..read].to_vec());
                        }
                    }
                    _ => break,
                }
            }
            if !watch.stopping.load(Ordering::SeqCst) {
                let at = watch.started.elapsed().as_secs_f64();
                watch.drops.lock().unwrap().push((at, label));
            }
        });
    }
}

/// Latencies of probe commands in one phase of the run.
#[derive(Default)]
struct ProbeResults {
    baseline: Vec<Duration>,
    load: Vec<Duration>,
    timeouts: usize,
    gave_up: bool,
}

/// Send a command, wait for its reply, and repeat, until told to stop or the session ends.
fn run_probes(
    mut stream: TcpStream,
    output: Receiver<Vec<u8>>,
    interval: Duration,
    load_running: Arc<AtomicBool>,
    stop: Arc<AtomicBool>,
) -> ProbeResults {
    let mut results = ProbeResults::default();
    let mut sequence = 0u64;
    let mut pending = String::new();
    while !stop.load(Ordering::SeqCst) {
        sequence += 1;
        let token = format!("probe-{sequence}-reply");
        let in_load = load_running.load(Ordering::SeqCst);
        let sent = Instant::now();
        if stream
            .write_all(format!("; return \"{token}\";\r\n").as_bytes())
            .is_err()
        {
            results.gave_up = true;
            return results;
        }
        loop {
            if pending.contains(&token) {
                pending.clear();
                if in_load {
                    results.load.push(sent.elapsed());
                } else {
                    results.baseline.push(sent.elapsed());
                }
                break;
            }
            if sent.elapsed() >= PROBE_TIMEOUT {
                results.timeouts += 1;
                break;
            }
            match output.recv_timeout(Duration::from_millis(100)) {
                Ok(bytes) => pending.push_str(&String::from_utf8_lossy(&bytes)),
                Err(RecvTimeoutError::Timeout) => {
                    if stop.load(Ordering::SeqCst) {
                        return results;
                    }
                }
                Err(RecvTimeoutError::Disconnected) => {
                    results.gave_up = true;
                    return results;
                }
            }
        }
        thread::sleep(interval);
    }
    results
}

fn percentile(sorted: &[Duration], fraction: f64) -> Duration {
    let index = ((sorted.len() - 1) as f64 * fraction).round() as usize;
    sorted[index]
}

fn print_latency(label: &str, latencies: &[Duration]) {
    if latencies.is_empty() {
        println!("  {label}: no completed probes");
        return;
    }
    let mut sorted = latencies.to_vec();
    sorted.sort();
    println!(
        "  {label}: {} completed, p50 {:?}, p95 {:?}, max {:?}",
        sorted.len(),
        percentile(&sorted, 0.50),
        percentile(&sorted, 0.95),
        sorted[sorted.len() - 1],
    );
}

fn print_log_counts(run_dir: &Path) {
    println!("Log lines:");
    let logs: Vec<String> = [
        "daemon.log",
        "daemon.err.log",
        "telnet.log",
        "telnet.err.log",
        "web.log",
        "web.err.log",
    ]
    .iter()
    .filter_map(|name| fs::read(run_dir.join(name)).ok())
    .map(|bytes| String::from_utf8_lossy(&bytes).into_owned())
    .collect();
    let mut any = false;
    for pattern in LOG_PATTERNS {
        let count: usize = logs.iter().map(|log| log.matches(pattern).count()).sum();
        if count > 0 {
            any = true;
            println!("  {count:6}  {pattern}");
        }
    }
    if !any {
        println!("  none of the tracked lines appeared");
    }
}

/// Sleep for `duration`, returning early if the user interrupts the run.
fn wait(duration: Duration, interrupted: &AtomicBool) {
    let deadline = Instant::now() + duration;
    while Instant::now() < deadline && !interrupted.load(Ordering::SeqCst) {
        thread::sleep(Duration::from_millis(100));
    }
}

/// Create the schedules, and return the MOO code that reads back how many firings ran.
fn start_scheduled_tasks(stream: &mut TcpStream, args: &ScheduledTasks) -> eyre::Result<String> {
    let interval_secs = args.interval_ms as f64 / 1000.0;
    let mut verb_code = vec![
        "{name, work} = args;".to_string(),
        "for i in [1..work]".to_string(),
        "x = i;".to_string(),
        "endfor".to_string(),
        "#0.(name) = #0.(name) + 1;".to_string(),
    ];
    if args.mode == ScheduleMode::At {
        verb_code.push(format!(
            "schedule_at(this, verb, ftime() + {interval_secs}, args, [\"pass_elapsed\" -> 0]);"
        ));
    }
    let verb_list = verb_code
        .iter()
        .map(|line| format!("\"{}\"", line.replace('"', "\\\"")))
        .collect::<Vec<_>>()
        .join(", ");
    eval(
        stream,
        &format!(
            "add_property(#0, \"loadsim_shared\", 0, {{#3, \"rw\"}}); \
             add_verb(#0, {{#3, \"rxd\", \"loadsim_tick\"}}, {{\"this\", \"none\", \"this\"}}); \
             set_verb_code(#0, \"loadsim_tick\", {{{verb_list}}});"
        ),
        "loadsim-verb-ready",
    )?;

    // Without pass_elapsed off, firings get an extra argument the verb does not expect.
    let options = if args.jitter_ms > 0 && args.mode == ScheduleMode::Every {
        format!(
            "[\"pass_elapsed\" -> 0, \"jitter\" -> {}]",
            args.jitter_ms as f64 / 1000.0
        )
    } else {
        "[\"pass_elapsed\" -> 0]".to_string()
    };
    let mut first = 1;
    while first <= args.schedules {
        let last = (first + SETUP_CHUNK - 1).min(args.schedules);
        let property = if args.shared_property {
            "\"loadsim_shared\"".to_string()
        } else {
            "name".to_string()
        };
        let create = match args.mode {
            ScheduleMode::Every => format!(
                "schedule_every(#0, \"loadsim_tick\", {interval_secs}, {{{property}, {}}}, {options});",
                args.work_iterations
            ),
            // The random start spreads firings across the interval.
            ScheduleMode::At => format!(
                "schedule_at(#0, \"loadsim_tick\", ftime() + {interval_secs} * (tofloat(random(1000)) / 1000.0), {{{property}, {}}}, {options});",
                args.work_iterations
            ),
        };
        eval(
            stream,
            &format!(
                "for i in [{first}..{last}] name = \"loadsim_\" + tostr(i); \
                 add_property(#0, name, 0, {{#3, \"rw\"}}); {create} endfor"
            ),
            &format!("loadsim-created-{last}"),
        )?;
        first = last + 1;
    }

    Ok(format!(
        "total = #0.loadsim_shared; for i in [1..{}] total = total + #0.(\"loadsim_\" + tostr(i)); endfor notify(player, \"loadsim-firings=\" + tostr(total));",
        args.schedules
    ))
}

/// Send one HTTP request and return the status and response headers.
fn http_post(
    port: u16,
    path: &str,
    headers: &[(&str, &str)],
    body: &str,
    timeout: Duration,
) -> eyre::Result<(u16, String)> {
    let mut stream = TcpStream::connect(("127.0.0.1", port))?;
    stream.set_read_timeout(Some(timeout))?;
    let mut request = format!("POST {path} HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n");
    for (name, value) in headers {
        request.push_str(&format!("{name}: {value}\r\n"));
    }
    request.push_str(&format!("Content-Length: {}\r\n\r\n{body}", body.len()));
    stream.write_all(request.as_bytes())?;
    let mut response = Vec::new();
    stream.read_to_end(&mut response)?;
    let response = String::from_utf8_lossy(&response);
    let head = response.split("\r\n\r\n").next().unwrap_or_default();
    let status = head
        .split_whitespace()
        .nth(1)
        .and_then(|status| status.parse().ok())
        .ok_or_else(|| eyre!("No HTTP status in the response: {head}"))?;
    Ok((status, head.to_string()))
}

/// Start a web host on the running daemon, and log in through it.
fn start_web_host(
    servers: &Servers,
    args: &CapturedCalls,
) -> eyre::Result<(ManagedChild, u16, String)> {
    let web_bin = server_binary(&args.web_bin, "moor-web-host")?;
    let port = TcpListener::bind("127.0.0.1:0")?.local_addr()?.port();
    let web = Command::new(web_bin)
        .args(["--events-address", "ipc://events.sock"])
        .args(["--rpc-address", "ipc://rpc.sock"])
        .args(["--listen-address", &format!("127.0.0.1:{port}")])
        .env("XDG_CONFIG_HOME", servers.run_dir.join("config"))
        .current_dir(&servers.run_dir)
        .stdin(Stdio::null())
        .stdout(fs::File::create(servers.run_dir.join("web.log"))?)
        .stderr(fs::File::create(servers.run_dir.join("web.err.log"))?)
        .spawn()
        .wrap_err("Could not start the web host")?;
    let web = ManagedChild(web);

    let deadline = Instant::now() + SERVER_START_TIMEOUT;
    let mut last_problem = eyre!("the web host never answered");
    while Instant::now() < deadline {
        match http_post(
            port,
            "/auth/connect",
            &[("Content-Type", "application/x-www-form-urlencoded")],
            "player=%233&password=unused",
            SESSION_LOGIN_TIMEOUT,
        ) {
            Ok((200, head)) => {
                let token = head
                    .lines()
                    .find_map(|line| {
                        let (name, value) = line.split_once(':')?;
                        name.eq_ignore_ascii_case("x-moor-auth-token")
                            .then(|| value.trim().to_string())
                    })
                    .ok_or_else(|| eyre!("The login reply had no auth token"))?;
                return Ok((web, port, token));
            }
            Ok((status, _)) => last_problem = eyre!("the login returned HTTP {status}"),
            Err(error) => last_problem = error,
        }
        thread::sleep(Duration::from_millis(500));
    }
    Err(last_problem.wrap_err(format!(
        "The web host did not accept a login. See the logs in {}",
        servers.run_dir.display()
    )))
}

/// Run web API calls until told to stop, and return each one's time and outcome.
fn run_captured_calls(
    args: &CapturedCalls,
    port: u16,
    token: &str,
    interrupted: &AtomicBool,
) -> Vec<(Duration, Result<u16, String>)> {
    let stop = Arc::new(AtomicBool::new(false));
    let results = Arc::new(Mutex::new(Vec::new()));
    let call_timeout = Duration::from_secs(args.call_secs + 30);
    let path = format!("/v1/eval?timeout_ms={}", (args.call_secs + 10) * 1000);
    let code = format!("suspend({}); return 1;", args.call_secs);
    let threads: Vec<_> = (0..args.calls)
        .map(|_| {
            let (stop, results) = (stop.clone(), results.clone());
            let (path, code, token) = (path.clone(), code.clone(), token.to_string());
            thread::spawn(move || {
                while !stop.load(Ordering::SeqCst) {
                    let started = Instant::now();
                    let outcome = http_post(
                        port,
                        &path,
                        &[
                            ("Content-Type", "text/plain"),
                            ("X-Moor-Auth-Token", token.as_str()),
                        ],
                        &code,
                        call_timeout,
                    )
                    .map(|(status, _)| status)
                    .map_err(|error| format!("{error:#}"));
                    results.lock().unwrap().push((started.elapsed(), outcome));
                }
            })
        })
        .collect();
    wait(Duration::from_secs(args.duration_secs), interrupted);
    stop.store(true, Ordering::SeqCst);
    for thread in threads {
        let _ = thread.join();
    }
    std::mem::take(&mut *results.lock().unwrap())
}

fn print_call_results(results: &[(Duration, Result<u16, String>)]) {
    let succeeded: Vec<Duration> = results
        .iter()
        .filter(|(_, outcome)| matches!(outcome, Ok(200)))
        .map(|(elapsed, _)| *elapsed)
        .collect();
    println!("Web API calls:");
    print_latency("succeeded", &succeeded);
    let failures: Vec<_> = results
        .iter()
        .filter(|(_, outcome)| !matches!(outcome, Ok(200)))
        .collect();
    println!("  failed: {}", failures.len());
    if let Some((_, outcome)) = failures.first() {
        println!("  first failure: {outcome:?}");
    }
}

fn read_firings(port: u16, code: &str) -> eyre::Result<u64> {
    let mut stream = login(port, SESSION_LOGIN_TIMEOUT)?;
    let output = eval(&mut stream, code, "loadsim-firings-read")?;
    let (_, after) = output
        .split_once("loadsim-firings=")
        .ok_or_else(|| eyre!("No firing count in the output: {output}"))?;
    let digits: String = after.chars().take_while(char::is_ascii_digit).collect();
    Ok(digits.parse()?)
}

fn run(common: &Common, scenario: &Scenario) -> eyre::Result<()> {
    let interrupted = Arc::new(AtomicBool::new(false));
    signal_hook::flag::register(signal_hook::consts::SIGINT, interrupted.clone())?;
    signal_hook::flag::register(signal_hook::consts::SIGTERM, interrupted.clone())?;

    let mut servers = Servers::start(common)?;
    println!("Run directory: {}", servers.run_dir.display());
    let mut admin = servers.first_login()?;

    let watch = Watch {
        started: Instant::now(),
        stopping: Arc::new(AtomicBool::new(false)),
        drops: Arc::new(Mutex::new(Vec::new())),
    };
    for index in 0..common.sessions {
        let stream = login(servers.port, SESSION_LOGIN_TIMEOUT)
            .wrap_err_with(|| format!("Could not log in session {index}"))?;
        watch.watch(format!("session-{index}"), stream, None);
    }

    let probe_stream = login(servers.port, SESSION_LOGIN_TIMEOUT)?;
    let (output_send, output_receive) = mpsc::channel();
    watch.watch(
        "probe".to_string(),
        probe_stream.try_clone()?,
        Some(output_send),
    );
    let load_running = Arc::new(AtomicBool::new(false));
    let stop_probes = Arc::new(AtomicBool::new(false));
    let probes = {
        let interval = Duration::from_millis(common.probe_interval_ms);
        let load_running = load_running.clone();
        let stop_probes = stop_probes.clone();
        thread::spawn(move || {
            run_probes(
                probe_stream,
                output_receive,
                interval,
                load_running,
                stop_probes,
            )
        })
    };

    println!(
        "Watching {} idle sessions and one probe session. Measuring a {}s baseline.",
        common.sessions, common.baseline_secs
    );
    wait(Duration::from_secs(common.baseline_secs), &interrupted);

    let load_started = watch.started.elapsed().as_secs_f64();
    load_running.store(true, Ordering::SeqCst);
    let mut firings = None;
    let mut call_results = None;
    match scenario {
        Scenario::ScheduledTasks(args) => {
            let read_code = start_scheduled_tasks(&mut admin, args)?;
            println!(
                "Created {} schedules firing every {} ms. Running for {}s.",
                args.schedules, args.interval_ms, args.duration_secs
            );
            wait(Duration::from_secs(args.duration_secs), &interrupted);
            firings = Some((
                read_firings(servers.port, &read_code),
                args.duration_secs * 1000 * args.schedules as u64 / args.interval_ms.max(1),
            ));
        }
        Scenario::CapturedCalls(args) => {
            let (web, port, token) = start_web_host(&servers, args)?;
            println!(
                "Running {} web API calls of {}s each for {}s.",
                args.calls, args.call_secs, args.duration_secs
            );
            call_results = Some(run_captured_calls(args, port, &token, &interrupted));
            drop(web);
        }
        Scenario::HeldWorkers(args) => {
            eval(
                &mut admin,
                &format!(
                    "set_verb_code(#0, \"do_login_command\", {{\"suspend({});\", \"return 0;\"}});",
                    args.hold_secs
                ),
                "loadsim-login-replaced",
            )?;
            // Connecting is enough: the host sends a login request for the welcome message.
            let mut holders = Vec::with_capacity(args.holders);
            for _ in 0..args.holders {
                holders.push(TcpStream::connect(("127.0.0.1", servers.port))?);
            }
            println!(
                "{} logins are holding RPC workers for {}s.",
                args.holders, args.hold_secs
            );
            wait(
                Duration::from_secs(args.hold_secs + args.cooldown_secs),
                &interrupted,
            );
            drop(holders);
        }
    }

    watch.stopping.store(true, Ordering::SeqCst);
    stop_probes.store(true, Ordering::SeqCst);
    let _ = admin.shutdown(Shutdown::Both);
    let probe_results = probes
        .join()
        .map_err(|_| eyre!("The probe thread panicked"))?;

    println!();
    println!("Load started at {load_started:.1}s.");
    let drops = watch.drops.lock().unwrap().clone();
    println!(
        "Sessions dropped: {} of {}",
        drops.len(),
        common.sessions + 1
    );
    for (at, label) in &drops {
        println!("  {at:7.1}s  {label}");
    }
    println!("Probe commands:");
    print_latency("baseline", &probe_results.baseline);
    print_latency("under load", &probe_results.load);
    println!(
        "  timed out after {PROBE_TIMEOUT:?}: {}",
        probe_results.timeouts
    );
    if probe_results.gave_up {
        println!("  stopped early because the probe session ended");
    }
    if let Some(results) = &call_results {
        print_call_results(results);
    }
    if let Some((measured, expected)) = firings {
        match measured {
            Ok(count) => println!("Schedule firings: {count} of about {expected} requested"),
            Err(error) => println!("Schedule firings: could not read the count: {error:#}"),
        }
    }
    print_log_counts(&servers.run_dir);
    println!("Logs: {}", servers.run_dir.display());
    Ok(())
}

fn main() -> eyre::Result<()> {
    color_eyre::install()?;
    let cli = Cli::parse();
    let common = match &cli.scenario {
        Scenario::ScheduledTasks(args) => &args.common,
        Scenario::HeldWorkers(args) => &args.common,
        Scenario::CapturedCalls(args) => &args.common,
    };
    run(common, &cli.scenario)
}
