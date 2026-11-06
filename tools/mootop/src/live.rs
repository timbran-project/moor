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

//! The live, full-screen view.

use std::{sync::mpsc::TryRecvError, time::Duration};

use ratatui::{
    DefaultTerminal, Frame,
    crossterm::event::{self, Event, KeyCode, KeyEventKind, KeyModifiers},
    layout::{Constraint, Layout},
    style::{Modifier, Style, Stylize},
    text::{Line, Span},
    widgets::{Block, Cell, Paragraph, Row as TableRow, Table, TableState, Tabs},
};

use crate::{
    record::Recorder,
    snapshot::{Names, Snapshot, Summary, View, rows, summary},
    trace::{Trace, TraceEvent},
};

struct App {
    pid: u32,
    hz: u32,
    view: usize,
    /// Show totals since start rather than the last interval.
    cumulative: bool,
    paused: bool,
    last: Snapshot,
    total: Snapshot,
    names: Names,
    table: TableState,
    warning: Option<String>,
}

pub fn run(trace: Trace, hz: u32, mut recorder: Option<Recorder>) -> Result<(), String> {
    let mut app = App {
        pid: trace.pid,
        hz,
        view: 0,
        cumulative: false,
        paused: false,
        last: Snapshot::default(),
        total: Snapshot::default(),
        names: Names::default(),
        table: TableState::default().with_selected(0),
        warning: None,
    };
    let mut terminal = ratatui::init();
    let result = event_loop(&mut terminal, &mut app, &trace, &mut recorder);
    ratatui::restore();
    result
}

fn event_loop(
    terminal: &mut DefaultTerminal,
    app: &mut App,
    trace: &Trace,
    recorder: &mut Option<Recorder>,
) -> Result<(), String> {
    loop {
        loop {
            match trace.events.try_recv() {
                Ok(TraceEvent::Snapshot(snapshot)) => {
                    if let Some(recorder) = recorder {
                        recorder.write(&snapshot)?;
                    }
                    app.names.learn(&snapshot);
                    app.total.merge(&snapshot);
                    // Names live in `app.names`; don't keep accumulating them.
                    app.total.names.clear();
                    if !app.paused {
                        app.last = snapshot;
                    }
                }
                Ok(TraceEvent::Warning(warning)) => app.warning = Some(warning),
                Ok(TraceEvent::Exited(stderr)) => {
                    return Err(format!("bpftrace exited.\n{stderr}"));
                }
                Err(TryRecvError::Empty) => break,
                Err(TryRecvError::Disconnected) => return Err("bpftrace exited.".to_string()),
            }
        }

        terminal
            .draw(|frame| draw(frame, app))
            .map_err(|e| format!("Couldn't draw: {e}"))?;

        if !event::poll(Duration::from_millis(200)).map_err(|e| e.to_string())? {
            continue;
        }
        let Event::Key(key) = event::read().map_err(|e| e.to_string())? else {
            continue;
        };
        if key.kind != KeyEventKind::Press {
            continue;
        }
        let views = View::ALL.len();
        match key.code {
            KeyCode::Char('q') | KeyCode::Esc => return Ok(()),
            KeyCode::Char('c') if key.modifiers.contains(KeyModifiers::CONTROL) => return Ok(()),
            KeyCode::Tab | KeyCode::Right => app.view = (app.view + 1) % views,
            KeyCode::BackTab | KeyCode::Left => app.view = (app.view + views - 1) % views,
            KeyCode::Char(c @ '1'..='3') => app.view = c as usize - '1' as usize,
            KeyCode::Char('a') => app.cumulative = !app.cumulative,
            KeyCode::Char('p') | KeyCode::Char(' ') => app.paused = !app.paused,
            KeyCode::Down | KeyCode::Char('j') => app.table.select_next(),
            KeyCode::Up | KeyCode::Char('k') => app.table.select_previous(),
            KeyCode::PageDown => app.table.scroll_down_by(20),
            KeyCode::PageUp => app.table.scroll_up_by(20),
            KeyCode::Home => app.table.select_first(),
            _ => {}
        }
    }
}

fn draw(frame: &mut Frame, app: &mut App) {
    let shown = if app.cumulative {
        &app.total
    } else {
        &app.last
    };
    let view = View::ALL[app.view];
    let s = summary(shown, app.hz);

    let [header, tabs, body, footer] = Layout::vertical([
        Constraint::Length(3),
        Constraint::Length(1),
        Constraint::Min(3),
        Constraint::Length(1),
    ])
    .areas(frame.area());

    frame.render_widget(Paragraph::new(header_lines(app, &s)), header);

    let titles = View::ALL
        .iter()
        .enumerate()
        .map(|(i, v)| format!("{} {}", i + 1, v.title()));
    frame.render_widget(
        Tabs::new(titles)
            .select(app.view)
            .highlight_style(Style::new().reversed()),
        tabs,
    );

    let rows = rows(shown, app.hz, &app.names, view);
    let name_header = match view {
        View::Verbs => "Verb",
        View::Builtins => "Builtin",
        View::Tasks => "Task",
    };
    let (third, widths) = match view {
        View::Tasks => (
            "Busiest frame",
            [
                Constraint::Length(7),
                Constraint::Length(14),
                Constraint::Fill(1),
            ],
        ),
        _ => (
            name_header,
            [
                Constraint::Length(7),
                Constraint::Length(10),
                Constraint::Fill(1),
            ],
        ),
    };
    let second = match view {
        View::Tasks => name_header,
        _ => "Calls/s",
    };
    let table_rows = rows.iter().map(|r| {
        let (second, third) = match view {
            View::Tasks => (r.label.clone(), r.detail.clone()),
            _ => (
                r.calls.map(|c| format!("{c:.0}")).unwrap_or_default(),
                r.label.clone(),
            ),
        };
        TableRow::new([
            Cell::from(format!("{:6.1}", r.cpu)),
            Cell::from(format!("{second:>9}")),
            Cell::from(third),
        ])
    });
    let table = Table::new(table_rows, widths)
        .header(
            TableRow::new([
                "  %CPU".to_string(),
                format!("{second:>9}"),
                third.to_string(),
            ])
            .style(Style::new().add_modifier(Modifier::BOLD)),
        )
        .row_highlight_style(Style::new().reversed())
        .block(Block::bordered());
    frame.render_stateful_widget(table, body, &mut app.table);

    let mode = if app.cumulative {
        format!("totals over {:.0}s", app.total.seconds)
    } else {
        "last second".to_string()
    };
    let paused = if app.paused { "  PAUSED" } else { "" };
    frame.render_widget(
        Line::from(format!(
            " {mode}{paused}   q quit  tab/1-3 view  a totals  p pause  ↑↓ scroll"
        ))
        .dim(),
        footer,
    );
}

fn header_lines(app: &App, s: &Summary) -> Vec<Line<'static>> {
    let commits: f64 = s.commits.iter().sum();
    let mut lines = vec![
        Line::from(vec![
            Span::from("mootop").bold(),
            Span::from(format!("  pid {}  sampling at {} Hz", app.pid, app.hz)),
        ]),
        Line::from(format!(
            "CPU  daemon {:5.1}%   tasks {:5.1}%   commits {:5.1}%   other threads {:5.1}%",
            s.daemon_cpu, s.task_cpu, s.commit_cpu, s.other_cpu,
        )),
        Line::from(format!(
            "Commits/s {:.0}  (read-only {:.0}, write {:.0} at {:.0}µs, conflict {:.0}, error {:.0})",
            commits, s.commits[0], s.commits[1], s.commit_us[1], s.commits[2], s.commits[3]
        )),
    ];
    if let Some(warning) = &app.warning {
        lines[0].push_span(Span::from(format!("   {warning}")).red());
    }
    lines
}
