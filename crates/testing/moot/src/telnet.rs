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

#[cfg(feature = "colors")]
use anstream::eprintln;
use eyre::{WrapErr, eyre};
use moor_var::Obj;
use std::{
    collections::HashMap,
    io::{self, BufRead, BufReader, BufWriter, Write},
    net::TcpStream,
    process::Child,
    thread,
    time::{Duration, Instant},
};

use crate::{MootRunner, stylesheet::MOOT_STYLESHEET};

pub struct ManagedChild {
    name: &'static str,
    child: Child,
}
impl ManagedChild {
    pub fn new(name: &'static str, mut child: Child) -> Self {
        // Rust tests capture output, and hide it if the test passes unless `--nocapture` is passed to `cargo test`.
        // This does *not* automatically apply to subprocesses, so: start threads to send subprocess output through
        // `print!` / `eprintln!` to get the same behavior.
        let stdout = child.stdout.take().expect("Failed to get stdout");
        let stderr = child.stderr.take().expect("Failed to get stderr");
        thread::spawn(|| {
            let name = name.to_string();
            let reader = BufReader::new(stdout);
            for line in reader.lines() {
                println!("[{name}]: {}", line.expect("Failed to read line"));
            }
        });
        thread::spawn(|| {
            let name = name.to_string();
            let reader = BufReader::new(stderr);
            for line in reader.lines() {
                eprintln!("[{name}]: {}", line.expect("Failed to read line"));
            }
        });
        Self { name, child }
    }

    pub fn try_wait(&mut self) -> eyre::Result<Option<std::process::ExitStatus>> {
        self.child
            .try_wait()
            .wrap_err(format!("failed to wait: {}", self.name))
    }

    pub fn assert_running(&mut self) -> eyre::Result<()> {
        let status = self.try_wait()?;
        if status.is_some() {
            Err(eyre!("Unexpected exit: {}: {status:?}", self.name))
        } else {
            Ok(())
        }
    }
}
impl Drop for ManagedChild {
    fn drop(&mut self) {
        eprintln!("Killing {} (pid={})", self.name, self.child.id());
        self.child.kill().expect("Failed to kill child process");
    }
}

pub struct MootClient {
    stream: BufReader<TcpStream>,
    partial_line: Vec<u8>,
}
impl MootClient {
    pub fn new(port: u16) -> eyre::Result<Self> {
        TcpStream::connect(format!("localhost:{port}"))
            .and_then(|stream| {
                stream.set_read_timeout(Some(Duration::from_secs(1)))?;
                stream.set_write_timeout(Some(Duration::from_secs(1)))?;
                Ok(Self {
                    stream: BufReader::new(stream),
                    partial_line: Vec::new(),
                })
            })
            .wrap_err_with(|| format!("MootClient::new({port})"))
    }

    fn port(&self) -> u16 {
        self.stream
            .get_ref()
            .local_addr()
            .map(|addr| addr.port())
            .unwrap_or_default()
    }

    pub fn write_line<S>(&mut self, s: S) -> eyre::Result<()>
    where
        S: AsRef<str>,
    {
        let port = self.port();
        let mut writer = BufWriter::new(self.stream.get_mut());
        let result = writer
            .write_all(s.as_ref().as_bytes())
            .and_then(|_| writer.write_all(b"\n"))
            .and_then(|_| writer.flush())
            .wrap_err_with(|| format!("writing port={port}"));
        let s = s.as_ref();
        eprintln!(
            "{}{port}{:#} {}>>{:#} {}{s}{:#}",
            MOOT_STYLESHEET.remote,
            MOOT_STYLESHEET.remote,
            MOOT_STYLESHEET.arrows,
            MOOT_STYLESHEET.arrows,
            MOOT_STYLESHEET.request,
            MOOT_STYLESHEET.request,
        );
        result
    }

    fn read_line(&mut self) -> eyre::Result<Option<String>> {
        match self.read_line_with_timeout(Duration::from_secs(1)) {
            Err(e)
                if matches!(
                    e.kind(),
                    io::ErrorKind::WouldBlock | io::ErrorKind::TimedOut
                ) =>
            {
                let port = self.port();
                eprintln!(
                    "{}{port}{:#} {}(no response){:#}",
                    MOOT_STYLESHEET.remote,
                    MOOT_STYLESHEET.remote,
                    MOOT_STYLESHEET.response,
                    MOOT_STYLESHEET.response
                );
                Ok(None)
            }
            result => {
                result.wrap_err_with(|| format!("MootClient::read_line port={}", self.port()))
            }
        }
    }

    /// Keep read-ahead and partial UTF-8 bytes across timeouts. Only EOF returns None.
    fn read_line_with_timeout(&mut self, timeout: Duration) -> io::Result<Option<String>> {
        let deadline = Instant::now() + timeout;
        loop {
            let remaining = deadline.saturating_duration_since(Instant::now());
            if remaining.is_zero() {
                return Err(io::Error::new(
                    io::ErrorKind::TimedOut,
                    "line read deadline expired",
                ));
            }
            self.stream.get_ref().set_read_timeout(Some(remaining))?;
            let bytes = match self.stream.fill_buf() {
                Err(error) if error.kind() == io::ErrorKind::Interrupted => continue,
                result => result?,
            };
            if bytes.is_empty() {
                if self.partial_line.is_empty() {
                    return Ok(None);
                }
                break;
            }
            let newline = bytes.iter().position(|&byte| byte == b'\n');
            let length = newline.map_or(bytes.len(), |index| index + 1);
            self.partial_line.extend_from_slice(&bytes[..length]);
            self.stream.consume(length);
            if newline.is_some() {
                break;
            }
        }
        let text = String::from_utf8(std::mem::take(&mut self.partial_line))
            .map_err(|error| io::Error::new(io::ErrorKind::InvalidData, error))?;
        let line = text.trim_end_matches(['\r', '\n']).to_string();
        let port = self.port();
        eprintln!(
            "{}{port}{:#} {}<<{:#} {}{line}{:#}",
            MOOT_STYLESHEET.remote,
            MOOT_STYLESHEET.remote,
            MOOT_STYLESHEET.arrows,
            MOOT_STYLESHEET.arrows,
            MOOT_STYLESHEET.response,
            MOOT_STYLESHEET.response,
        );
        Ok(Some(line))
    }
}

pub struct TelnetMootRunner {
    port: u16,
    clients: HashMap<Obj, MootClient>,
}
impl TelnetMootRunner {
    pub fn new(port: u16) -> Self {
        Self {
            port,
            clients: HashMap::new(),
        }
    }

    fn client(&mut self, player: &Obj) -> &mut MootClient {
        self.clients.entry(*player).or_insert_with(|| {
            let start = Instant::now();
            loop {
                if let Ok(mut client) = MootClient::new(self.port) {
                    client.write_line(std::format!("connect {player}")).unwrap();
                    let remaining = Duration::from_secs(5).saturating_sub(start.elapsed());
                    let banner = client.read_line_with_timeout(remaining)
                        .unwrap_or_else(|error| panic!("Failed to read login banner for {player} on port {} within the five-second connection deadline: {error}", self.port))
                        .unwrap_or_else(|| panic!("Server closed connection before the login banner for {player} on port {}", self.port));
                    assert_eq!(banner, "*** Connected ***", "Unexpected login response for {player} on port {}", self.port);
                    return client;
                } else if start.elapsed() > Duration::from_secs(5) {
                    panic!("Failed to connect to server @ {}", self.port);
                } else {
                    std::thread::sleep(Duration::from_millis(10));
                }
            }
        })
    }

    fn resolve_response(&mut self, player: &Obj, response: String) -> eyre::Result<String> {
        let client = self.client(player);
        // Resolve the response; for example, the test assertion may be `$object`; resolve it to the object's specific number.
        client.write_line(format!(
            "; return {response}; \"TelnetMootRunner::resolve_response\";"
        ))?;
        client
            .read_line()
            .wrap_err_with(|| format!("TelnetMoorRunner::resolve_response({player}, {response:?})"))
            .and_then(|maybe_line| maybe_line.ok_or(eyre!("received no response from server")))
    }
}
impl MootRunner for TelnetMootRunner {
    type Value = String;

    fn eval<S: Into<String>>(&mut self, player: &Obj, command: S) -> eyre::Result<()> {
        let command: String = command.into();
        self.client(player)
            .write_line(format!("; {command} \"TelnetMootRunner::eval\";"))
            .with_context(|| format!("TelnetMootRunner::eval({player}, {command:?})"))
    }

    fn command<S: AsRef<str>>(&mut self, player: &Obj, command: S) -> eyre::Result<()> {
        let command: &str = command.as_ref();
        self.client(player)
            .write_line(command)
            .with_context(|| format!("TelnetMootRunner::command({player}, {command:?}"))
    }

    fn none(&self) -> Self::Value {
        "0".to_string()
    }

    fn read_line(&mut self, player: &Obj) -> eyre::Result<Option<String>> {
        self.client(player)
            .read_line()
            .with_context(|| format!("TelnetMootRunner::read_line({player})"))
    }

    fn read_eval_result(&mut self, player: &Obj) -> eyre::Result<Option<Self::Value>> {
        let raw = self
            .client(player)
            .read_line()
            .with_context(|| format!("TelnetMootRunner::read_eval_result({player}) / read raw"))?;
        if let Some(raw) = raw {
            self.resolve_response(player, raw)
                .map(Some)
                .with_context(|| format!("TelnetMootRunner::read_eval_result({player}) / resolve"))
        } else {
            Ok(None)
        }
    }

    fn read_command_result(&mut self, player: &Obj) -> eyre::Result<Option<Self::Value>> {
        self.client(player)
            .read_line()
            .map(|maybe_line| maybe_line.map(|line| format!("{line:?}")))
            .with_context(|| format!("TelnetMootRunner::read_command_result({player}) / read raw"))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::{net::TcpListener, sync::mpsc};

    #[test]
    fn login_waits_for_delayed_banner() {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let port = listener.local_addr().unwrap().port();
        thread::scope(|scope| {
            scope.spawn(|| {
                let (mut socket, _) = listener.accept().unwrap();
                socket
                    .set_read_timeout(Some(Duration::from_secs(5)))
                    .unwrap();
                let mut login = String::new();
                BufReader::new(&socket).read_line(&mut login).unwrap();
                assert_eq!(login, "connect #3\n");
                thread::sleep(Duration::from_millis(1200));
                socket.write_all(b"*** Connected ***\r\nready\r\n").unwrap();
            });
            let mut runner = TelnetMootRunner::new(port);
            assert_eq!(
                runner.read_line(&Obj::mk_id(3)).unwrap().as_deref(),
                Some("ready")
            );
        });
    }

    #[test]
    fn read_line_preserves_coalesced_lines() {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let mut client = MootClient::new(listener.local_addr().unwrap().port()).unwrap();
        let (mut socket, _) = listener.accept().unwrap();
        socket.write_all(b"first\r\nsecond\r\n").unwrap();
        drop(socket);
        assert_eq!(client.read_line().unwrap().as_deref(), Some("first"));
        assert_eq!(client.read_line().unwrap().as_deref(), Some("second"));
        assert_eq!(client.read_line().unwrap(), None);
    }

    #[test]
    fn read_line_preserves_partial_utf8_across_timeout() {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let mut client = MootClient::new(listener.local_addr().unwrap().port()).unwrap();
        let (mut socket, _) = listener.accept().unwrap();
        let (resume, wait) = mpsc::channel();
        thread::scope(|scope| {
            scope.spawn(move || {
                socket.write_all(b"part \xc3").unwrap();
                wait.recv_timeout(Duration::from_secs(5)).unwrap();
                socket.write_all(b"\xa9\r\n").unwrap();
            });
            assert_eq!(client.read_line().unwrap(), None);
            resume.send(()).unwrap();
            assert_eq!(client.read_line().unwrap().as_deref(), Some("part é"));
        });
    }

    #[test]
    fn read_line_distinguishes_timeout_from_eof() {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let mut client = MootClient::new(listener.local_addr().unwrap().port()).unwrap();
        let (socket, _) = listener.accept().unwrap();
        let error = client
            .read_line_with_timeout(Duration::from_millis(20))
            .unwrap_err();
        assert!(matches!(
            error.kind(),
            io::ErrorKind::WouldBlock | io::ErrorKind::TimedOut
        ));
        drop(socket);
        assert_eq!(
            client
                .read_line_with_timeout(Duration::from_secs(1))
                .unwrap(),
            None
        );
    }
}
