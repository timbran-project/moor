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

//! Core-local scenario directives layered on the existing mooT runner interface.

use eyre::{Result, WrapErr, eyre};
use moor_moot::MootRunner;
use moor_var::Obj;
use std::path::Path;

pub trait SessionRunner: MootRunner {
    fn provide_input(&mut self, player: &Obj, text: &str) -> Result<()>;
    fn system_hook(&mut self, player: &Obj, verb: &str, object: Option<&Obj>) -> Result<()>;
}

pub struct Actors {
    pub wizard: Obj,
    pub programmer: Obj,
    pub nonprogrammer: Obj,
}

#[derive(Debug, PartialEq)]
enum Expectation<'a> {
    Exact(&'a str),
    Contains(&'a str),
    Value(&'a str),
}

#[derive(Debug, PartialEq)]
enum Action<'a> {
    Player(&'a str),
    Input(&'a str),
    Hook(&'a str, Option<Obj>),
    Test {
        kind: char,
        program: String,
        expected: Vec<(usize, Expectation<'a>)>,
    },
}

fn directive(line: &str) -> bool {
    line.starts_with(['@', ';', '%', '&']) || line.starts_with(">>")
}

/// Parse complete lines; input directives take precedence over program continuations.
fn parse(source: &str) -> Result<Vec<(usize, Action<'_>)>> {
    let lines: Vec<_> = source.lines().collect();
    let mut cursor = 0;
    let mut actions = Vec::new();
    while cursor < lines.len() {
        let line = lines[cursor];
        let number = cursor + 1;
        cursor += 1;
        if line.trim().is_empty() || line.starts_with("//") {
            continue;
        }
        let action = if let Some(input) = line.strip_prefix(">>") {
            Action::Input(input.strip_prefix(' ').unwrap_or(input))
        } else if let Some(hook) = line.strip_prefix("@@") {
            let words: Vec<_> = hook.split_whitespace().collect();
            if words.is_empty() || words.len() > 2 {
                return Err(eyre!("line {number}: expected @@ verb [object]"));
            }
            Action::Hook(
                words[0],
                words
                    .get(1)
                    .map(|word| Obj::try_from(*word))
                    .transpose()
                    .wrap_err_with(|| format!("line {number}: invalid hook object"))?,
            )
        } else if let Some(player) = line.strip_prefix('@') {
            Action::Player(player)
        } else if line.starts_with([';', '%', '&']) {
            let kind = line.chars().next().unwrap();
            let mut program = line[1..].trim_start().to_string();
            while cursor < lines.len()
                && lines[cursor].starts_with('>')
                && !lines[cursor].starts_with(">>")
            {
                program.push('\n');
                program.push_str(&lines[cursor][1..]);
                cursor += 1;
            }
            let mut expected = Vec::new();
            while cursor < lines.len() && !directive(lines[cursor]) {
                let line = lines[cursor];
                let number = cursor + 1;
                cursor += 1;
                if line.trim().is_empty() || line.starts_with("//") {
                    continue;
                }
                if kind == '&' {
                    return Err(eyre!(
                        "line {number}: ignored eval cannot have expectations"
                    ));
                }
                let expectation = if let Some(text) = line.strip_prefix('=') {
                    Expectation::Exact(text)
                } else if let Some(text) = line.strip_prefix("~~") {
                    Expectation::Contains(text)
                } else {
                    Expectation::Value(line.strip_prefix('<').unwrap_or(line).trim_start())
                };
                expected.push((number, expectation));
            }
            Action::Test {
                kind,
                program,
                expected,
            }
        } else {
            return Err(eyre!(
                "line {number}: expected a command, eval, player, input, or hook"
            ));
        };
        actions.push((number, action));
    }
    Ok(actions)
}

fn result<R: MootRunner>(runner: &mut R, player: &Obj, kind: char) -> Result<R::Value> {
    let result = if kind == '%' {
        runner.read_command_result(player)?
    } else {
        runner.read_eval_result(player)?
    };
    result.ok_or_else(|| eyre!("missing task result"))
}

fn execute<R: SessionRunner>(runner: &mut R, actors: &Actors, source: &str) -> Result<()> {
    let mut player = actors.wizard;
    for (line, action) in parse(source)? {
        let step = || -> Result<()> {
            match action {
                Action::Player(name) => {
                    player = match name {
                        "wizard" => actors.wizard,
                        "programmer" => actors.programmer,
                        "nonprogrammer" => actors.nonprogrammer,
                        _ => return Err(eyre!("unknown player: {name}")),
                    }
                }
                Action::Input(text) => runner.provide_input(&player, text)?,
                Action::Hook(verb, target) => runner.system_hook(&player, verb, target.as_ref())?,
                Action::Test {
                    kind,
                    program,
                    expected,
                } => {
                    if kind == '%' {
                        runner.command(&player, program)?;
                    } else {
                        runner.eval(&player, format!("{program} \"moot-line:{line}\";"))?;
                    }
                    if kind == '&' {
                        result(runner, &player, kind)?;
                    } else if expected.is_empty() && kind == ';' {
                        let actual = result(runner, &player, kind)?;
                        if actual != runner.none() {
                            return Err(eyre!("expected empty result, got {actual:?}"));
                        }
                    }
                    for (number, expectation) in expected {
                        match expectation {
                            Expectation::Exact(text) | Expectation::Contains(text) => {
                                let actual = runner.read_line(&player)?;
                                let matched = match expectation {
                                    Expectation::Exact(_) => actual.as_deref() == Some(text),
                                    _ => actual.as_ref().is_some_and(|line| line.contains(text)),
                                };
                                if !matched {
                                    return Err(eyre!(
                                        "line {number}: expected {expectation:?}, got {actual:?}"
                                    ));
                                }
                            }
                            Expectation::Value(text) => {
                                let actual = result(runner, &player, kind)?;
                                runner.eval(&player, format!("return {text};"))?;
                                let expected = result(runner, &player, ';')?;
                                if actual != expected {
                                    return Err(eyre!(
                                        "line {number}: expected {expected:?}, got {actual:?}"
                                    ));
                                }
                            }
                        }
                    }
                }
            }
            Ok(())
        };
        step().wrap_err_with(|| format!("scenario line {line}"))?;
    }
    Ok(())
}

pub fn run<R: SessionRunner>(runner: &mut R, actors: &Actors, path: &Path) -> Result<()> {
    eprintln!("Test definition: {}", path.display());
    let source = std::fs::read_to_string(path).wrap_err_with(|| path.display().to_string())?;
    execute(runner, actors, &source).wrap_err_with(|| path.display().to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::VecDeque;

    #[derive(Default)]
    struct Runner {
        calls: Vec<(Obj, String)>,
        output: VecDeque<String>,
        value: Option<String>,
    }
    impl MootRunner for Runner {
        type Value = String;
        fn eval<S: Into<String>>(&mut self, player: &Obj, code: S) -> Result<()> {
            let code = code.into();
            if code.starts_with("bad") {
                return Err(eyre!("underlying eval error"));
            }
            self.calls.push((*player, code.clone()));
            self.value = Some(
                code.strip_prefix("return ")
                    .unwrap_or("")
                    .split(';')
                    .next()
                    .unwrap()
                    .to_string(),
            );
            Ok(())
        }
        fn command<S: AsRef<str>>(&mut self, player: &Obj, command: S) -> Result<()> {
            if command.as_ref() == "bad" {
                return Err(eyre!("underlying command error"));
            }
            self.calls.push((*player, command.as_ref().into()));
            self.value = Some("42".into());
            Ok(())
        }
        fn read_line(&mut self, _: &Obj) -> Result<Option<String>> {
            Ok(self.output.pop_front())
        }
        fn read_eval_result(&mut self, _: &Obj) -> Result<Option<String>> {
            Ok(self.value.take())
        }
        fn read_command_result(&mut self, _: &Obj) -> Result<Option<String>> {
            Ok(self.value.take())
        }
        fn none(&self) -> String {
            String::new()
        }
    }
    impl SessionRunner for Runner {
        fn provide_input(&mut self, player: &Obj, text: &str) -> Result<()> {
            self.calls.push((*player, format!("input:{text}")));
            Ok(())
        }
        fn system_hook(&mut self, player: &Obj, verb: &str, target: Option<&Obj>) -> Result<()> {
            if verb == "bad" {
                return Err(eyre!("underlying hook error"));
            }
            self.calls
                .push((*target.unwrap_or(player), format!("hook:{verb}")));
            Ok(())
        }
    }
    fn actors() -> Actors {
        Actors {
            wizard: Obj::mk_id(1),
            programmer: Obj::mk_id(2),
            nonprogrammer: Obj::mk_id(3),
        }
    }
    #[test]
    fn input_is_not_a_program_continuation() {
        let actions =
            parse("% command\n>> answer\n; first\n> second\n>>\n@@ user_connected").unwrap();
        assert_eq!(actions.len(), 5);
        assert!(matches!(&actions[0].1, Action::Test { program, .. } if program == "command"));
        assert_eq!(actions[1].1, Action::Input("answer"));
        assert!(
            matches!(&actions[2].1, Action::Test { program, .. } if program == "first\n second")
        );
        assert_eq!(actions[3].1, Action::Input(""));
        assert_eq!(actions[4].1, Action::Hook("user_connected", None));
        assert_eq!(
            parse("@@ connected #7").unwrap()[0].1,
            Action::Hook("connected", Some(Obj::mk_id(7)))
        );
    }
    #[test]
    fn actor_input_and_hook_targets_survive_eof_and_adjacent_directives() {
        let mut runner = Runner::default();
        execute(
            &mut runner,
            &actors(),
            "@programmer\n>>  two spaces\n@@ connected\n@@ disconnected #9\n% command\n42",
        )
        .unwrap();
        assert_eq!(runner.calls[0], (Obj::mk_id(2), "input: two spaces".into()));
        assert_eq!(runner.calls[1], (Obj::mk_id(2), "hook:connected".into()));
        assert_eq!(runner.calls[2], (Obj::mk_id(9), "hook:disconnected".into()));
        assert_eq!(runner.calls[3], (Obj::mk_id(2), "command".into()));
    }
    #[test]
    fn raw_expectations_consume_exactly_the_next_line() {
        let mut runner = Runner {
            output: VecDeque::from(["".into(), "a needle b".into()]),
            ..Default::default()
        };
        execute(&mut runner, &actors(), "% output\n=\n~~needle").unwrap();
        assert!(runner.output.is_empty());
        for output in [
            VecDeque::new(),
            VecDeque::from(["wrong".into(), "needle".into()]),
        ] {
            let mut runner = Runner {
                output,
                ..Default::default()
            };
            let error = execute(&mut runner, &actors(), "% output\n~~needle").unwrap_err();
            assert!(format!("{error:?}").contains("line 2"));
        }
        let mut runner = Runner {
            output: VecDeque::from(["not exact".into()]),
            ..Default::default()
        };
        assert!(execute(&mut runner, &actors(), "% output\n=exact").is_err());
    }
    #[test]
    fn malformed_input_and_execution_errors_are_visible() {
        for source in [
            "@@",
            "@@ hook bad-object",
            "@@ hook #1 extra",
            "& ignored\n1",
            "orphan",
        ] {
            assert!(parse(source).is_err(), "{source}");
        }
        for source in ["% bad", "; bad", "@@ bad", "@unknown"] {
            let error = execute(&mut Runner::default(), &actors(), source).unwrap_err();
            let message = format!("{error:?}");
            assert!(message.contains("scenario line 1"));
            assert!(message.contains("underlying") || message.contains("unknown player"));
        }
        execute(
            &mut Runner::default(),
            &actors(),
            "; return 42;\n42\n& return 9;",
        )
        .unwrap();
        assert!(execute(&mut Runner::default(), &actors(), "; return 42;").is_err());
    }
}
