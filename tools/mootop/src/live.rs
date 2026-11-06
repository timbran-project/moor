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

use std::{collections::VecDeque, sync::mpsc::TryRecvError, time::Duration};

use ratatui::{
    DefaultTerminal, Frame,
    crossterm::event::{self, Event, KeyCode, KeyEventKind, KeyModifiers},
    layout::{Constraint, Layout, Rect},
    style::{Color, Modifier, Style, Stylize},
    symbols::Marker,
    text::{Line, Span},
    widgets::{
        Axis, Block, Cell, Chart, Dataset, GraphType, LegendPosition, LineGauge, Paragraph,
        RenderDirection, Row as TableRow, Sparkline, Table, TableState, Tabs,
    },
};

use crate::{
    dash::{self, Figure},
    metrics::{History, KEPT, Query, Window, duration, short},
    record::Recorder,
    snapshot::{KIND_VERB, Names, Snapshot, Summary, View, rows, summary},
    trace::{Trace, TraceEvent},
};

/// How far back rates and percentiles in tables look, unless showing totals.
const RECENT: Window = Window::Recent(5.0);

struct App {
    pid: u32,
    hz: u32,
    /// Whether the daemon sends its metrics.
    has_metrics: bool,
    view: usize,
    /// Show totals since start rather than recent figures.
    cumulative: bool,
    paused: bool,
    last: Snapshot,
    total: Snapshot,
    names: Names,
    /// CPU and verb calls per interval, for charts.
    cpu: VecDeque<(Summary, f64)>,
    metrics: History,
    table: TableState,
    warning: Option<String>,
}

pub fn run(trace: Trace, hz: u32, mut recorder: Option<Recorder>) -> Result<(), String> {
    let mut app = App {
        pid: trace.pid,
        hz,
        has_metrics: trace.metrics,
        view: 0,
        cumulative: false,
        paused: false,
        last: Snapshot::default(),
        total: Snapshot::default(),
        names: Names::default(),
        cpu: VecDeque::new(),
        metrics: History::default(),
        table: TableState::default().with_selected(0),
        warning: None,
    };
    let mut terminal = ratatui::init();
    let result = event_loop(&mut terminal, &mut app, &trace, &mut recorder);
    ratatui::restore();
    result
}

impl App {
    fn take(&mut self, snapshot: Snapshot) {
        self.names.learn(&snapshot);
        self.total.merge(&snapshot);
        // Names live in `self.names`; don't keep accumulating them.
        self.total.names.clear();
        if self.paused {
            return;
        }
        if let Some(set) = &snapshot.metrics {
            self.metrics.push(set);
        }
        let verb_calls: u64 = snapshot
            .calls
            .iter()
            .filter(|(k, _)| k.kind == KIND_VERB)
            .map(|(_, n)| n)
            .sum();
        if self.cpu.len() == KEPT {
            self.cpu.pop_front();
        }
        self.cpu.push_back((
            summary(&snapshot, self.hz),
            verb_calls as f64 / snapshot.seconds.max(1e-9),
        ));
        self.last = snapshot;
    }

    fn shown(&self) -> &Snapshot {
        if self.cumulative {
            &self.total
        } else {
            &self.last
        }
    }

    fn window(&self) -> Window {
        if self.cumulative { Window::All } else { RECENT }
    }
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
                    app.take(snapshot);
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
        let before = app.view;
        match key.code {
            KeyCode::Char('q') | KeyCode::Esc => return Ok(()),
            KeyCode::Char('c') if key.modifiers.contains(KeyModifiers::CONTROL) => return Ok(()),
            KeyCode::Tab | KeyCode::Right => app.view = (app.view + 1) % views,
            KeyCode::BackTab | KeyCode::Left => app.view = (app.view + views - 1) % views,
            KeyCode::Char(c @ '1'..='6') => app.view = c as usize - '1' as usize,
            KeyCode::Char('a') => app.cumulative = !app.cumulative,
            KeyCode::Char('p') | KeyCode::Char(' ') => app.paused = !app.paused,
            KeyCode::Down | KeyCode::Char('j') => app.table.select_next(),
            KeyCode::Up | KeyCode::Char('k') => app.table.select_previous(),
            KeyCode::PageDown => app.table.scroll_down_by(20),
            KeyCode::PageUp => app.table.scroll_up_by(20),
            KeyCode::Home => app.table.select_first(),
            _ => {}
        }
        if app.view != before {
            app.table.select_first();
        }
    }
}

fn draw(frame: &mut Frame, app: &mut App) {
    // The tables scroll by this state; take it out so the rest of `app` can be borrowed freely.
    let mut table = std::mem::take(&mut app.table);
    render(frame, app, &mut table);
    app.table = table;
}

fn render(frame: &mut Frame, app: &App, table_state: &mut TableState) {
    let view = View::ALL[app.view];
    let [status, tabs, body, footer] = Layout::vertical([
        Constraint::Length(1),
        Constraint::Length(1),
        Constraint::Min(5),
        Constraint::Length(1),
    ])
    .areas(frame.area());

    frame.render_widget(status_line(app), status);
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

    let needs_metrics = matches!(view, View::Database | View::Rpc);
    let query = app.metrics.query(app.window());
    match (view, query) {
        (View::Overview, q) => overview(frame, body, app, q),
        (View::Verbs, _) => {
            let table = frames_table(app, View::Verbs);
            frame.render_stateful_widget(table, body, table_state);
        }
        (View::Builtins, q) => {
            let table = builtins_table(app, q);
            frame.render_stateful_widget(table, body, table_state);
        }
        (View::Tasks, q) => tasks(frame, body, app, q, table_state),
        (View::Database, Some(q)) => database(frame, body, app, &q),
        (View::Rpc, Some(q)) => rpc(frame, body, &q),
        (_, None) if needs_metrics => {
            frame.render_widget(no_metrics(app), body);
        }
        _ => {}
    }

    let mode = if app.cumulative {
        format!("totals over {:.0}s", app.total.seconds)
    } else {
        "recent".to_string()
    };
    let paused = if app.paused { "  PAUSED" } else { "" };
    frame.render_widget(
        Line::from(format!(
            " {mode}{paused}   q quit  tab/1-6 view  a totals  p pause  ↑↓ scroll"
        ))
        .dim(),
        footer,
    );
}

fn status_line(app: &App) -> Line<'static> {
    let s = summary(&app.last, app.hz);
    let mut spans = vec![
        Span::from("mootop").bold(),
        Span::from(format!(
            "  pid {}  {} Hz   CPU {:.0}%",
            app.pid, app.hz, s.daemon_cpu
        )),
    ];
    if let Some(q) = app.metrics.query(RECENT) {
        let h = dash::headline(&q);
        spans.push(Span::from(format!(
            "   players {:.0}   tasks {:.0} active, {:.0} suspended",
            h.players, h.tasks_active, h.tasks_suspended
        )));
        let warnings = dash::warnings(&q).len();
        if warnings > 0 {
            spans.push(Span::from(format!("   {warnings} warnings")).red().bold());
        }
    }
    if let Some(warning) = &app.warning {
        spans.push(Span::from(format!("   {warning}")).red());
    }
    Line::from(spans)
}

fn no_metrics(app: &App) -> Paragraph<'static> {
    let text = if app.has_metrics {
        "Waiting for the daemon's metrics…"
    } else {
        "This process doesn't send metrics. Only the daemon (moor-daemon, or the single-process \
         moor) does."
    };
    Paragraph::new(text).block(Block::bordered())
}

/// A bold header row. Columns of numbers, every one but those in `text`, are right-aligned.
fn bold_header<const N: usize>(cells: [&str; N], text: &[usize]) -> TableRow<'static> {
    let cells = cells.iter().enumerate().map(|(i, c)| {
        if text.contains(&i) {
            Cell::from(c.to_string())
        } else {
            right(c.to_string())
        }
    });
    TableRow::new(cells.collect::<Vec<_>>()).style(Style::new().add_modifier(Modifier::BOLD))
}

fn right(text: String) -> Cell<'static> {
    Cell::from(Line::from(text).right_aligned())
}

fn frames_table(app: &App, view: View) -> Table<'static> {
    let rows = rows(app.shown(), app.hz, &app.names, view);
    let (header, text_cols, widths) = match view {
        View::Tasks => (
            ["%CPU", "Task", "Busiest frame"],
            &[1, 2][..],
            [
                Constraint::Length(7),
                Constraint::Length(12),
                Constraint::Fill(1),
            ],
        ),
        _ => (
            ["%CPU", "Calls/s", "Verb"],
            &[2][..],
            [
                Constraint::Length(7),
                Constraint::Length(10),
                Constraint::Fill(1),
            ],
        ),
    };
    let table_rows: Vec<TableRow> = rows
        .into_iter()
        .map(|r| {
            let (second, third) = match view {
                View::Tasks => (Cell::from(r.label), r.detail),
                _ => (right(r.calls.map(short).unwrap_or_default()), r.label),
            };
            TableRow::new([right(format!("{:.1}", r.cpu)), second, Cell::from(third)])
        })
        .collect();
    Table::new(table_rows, widths)
        .header(bold_header(header, text_cols))
        .row_highlight_style(Style::new().reversed())
        .block(Block::bordered().title(match view {
            View::Tasks => " Tasks by CPU ",
            _ => " Verbs by CPU (self time) ",
        }))
}

/// Builtins: CPU from sampling, and, from the daemon's metrics, exact call rates and latencies.
fn builtins_table(app: &App, q: Option<Query>) -> Table<'static> {
    let timers = q.map(|q| dash::builtin_timers(&q)).unwrap_or_default();
    let mut table_rows: Vec<(f64, f64, TableRow)> = vec![];
    let sampled = rows(app.shown(), app.hz, &app.names, View::Builtins);
    let mut seen = std::collections::HashSet::new();
    for r in sampled {
        let name = r.label.trim_end_matches("()").to_string();
        let t = timers.iter().find(|t| t.name == name);
        seen.insert(name.clone());
        let calls = t.map(|t| t.rate).or(r.calls).unwrap_or(0.0);
        table_rows.push((r.cpu, calls, builtin_row(Some(r.cpu), calls, t, &name)));
    }
    // Builtins the daemon counted that no sample landed in.
    for t in timers.iter().filter(|t| !seen.contains(&t.name)) {
        table_rows.push((0.0, t.rate, builtin_row(None, t.rate, Some(t), &t.name)));
    }
    table_rows.sort_by(|a, b| b.0.total_cmp(&a.0).then(b.1.total_cmp(&a.1)));
    let widths = [
        Constraint::Length(7),
        Constraint::Length(10),
        Constraint::Length(10),
        Constraint::Length(10),
        Constraint::Length(8),
        Constraint::Fill(1),
    ];
    Table::new(table_rows.into_iter().map(|(_, _, r)| r), widths)
        .header(bold_header(
            ["%CPU", "Calls/s", "Mean", "p99 ≤", "Thread", "Builtin"],
            &[5],
        ))
        .row_highlight_style(Style::new().reversed())
        .block(
            Block::bordered().title(" Builtins: CPU sampled; calls and latency from the daemon "),
        )
}

fn builtin_row(
    cpu: Option<f64>,
    calls: f64,
    t: Option<&crate::metrics::Timer>,
    name: &str,
) -> TableRow<'static> {
    let opt = |v: Option<f64>, f: fn(f64) -> String| v.map(f).unwrap_or_default();
    TableRow::new([
        right(cpu.map(|c| format!("{c:.1}")).unwrap_or_default()),
        right(short(calls)),
        right(opt(t.and_then(|t| t.mean), duration)),
        right(opt(t.and_then(|t| t.p99), duration)),
        right(opt(t.and_then(|t| t.thread), |x| {
            format!("{:.0}%", x * 100.0)
        })),
        Cell::from(format!("{name}()")),
    ])
}

/// A small box with a label and value per line.
fn figures(title: &str, figs: &[Figure]) -> Table<'static> {
    let rows: Vec<TableRow> = figs
        .iter()
        .map(|f| TableRow::new([Cell::from(f.label), right(f.value.clone())]))
        .collect();
    Table::new(rows, [Constraint::Fill(1), Constraint::Length(10)])
        .block(Block::bordered().title(format!(" {title} ")))
}

/// Scale values for a sparkline, which takes integers.
fn spark(values: impl Iterator<Item = f64>) -> Vec<u64> {
    values.map(|v| (v.max(0.0) * 100.0) as u64).collect()
}

fn stat(frame: &mut Frame, area: Rect, title: &str, value: String, history: Vec<u64>, alarm: bool) {
    let block = Block::bordered().title(format!(" {title} "));
    let inner = block.inner(area);
    frame.render_widget(block, area);
    let [value_area, spark_area] =
        Layout::vertical([Constraint::Length(1), Constraint::Min(1)]).areas(inner);
    let style = if alarm {
        Style::new().red().bold()
    } else {
        Style::new().bold()
    };
    frame.render_widget(Line::from(value).style(style).centered(), value_area);
    // The newest value at the right edge, and as many before it as fit.
    let newest_first: Vec<u64> = history
        .iter()
        .rev()
        .take(spark_area.width as usize)
        .copied()
        .collect();
    frame.render_widget(
        Sparkline::default()
            .data(&newest_first)
            .direction(RenderDirection::RightToLeft)
            .style(Style::new().fg(if alarm { Color::Red } else { Color::Cyan })),
        spark_area,
    );
}

fn overview(frame: &mut Frame, area: Rect, app: &App, q: Option<Query>) {
    let [row1, row2, charts, warn] = Layout::vertical([
        Constraint::Length(5),
        Constraint::Length(5),
        Constraint::Min(8),
        Constraint::Length(7),
    ])
    .areas(area);

    let steps: Vec<Query> = app.metrics.steps().collect();
    let each = |f: &dyn Fn(&Query) -> f64| spark(steps.iter().map(f));
    let cpu_hist = spark(app.cpu.iter().map(|(s, _)| s.daemon_cpu));
    let calls_hist = spark(app.cpu.iter().map(|(_, c)| *c));
    let (last_cpu, last_calls) = app
        .cpu
        .back()
        .map(|(s, c)| (s.daemon_cpu, *c))
        .unwrap_or_default();

    let cells1 = Layout::horizontal([Constraint::Ratio(1, 5); 5]).split(row1);
    let cells2 = Layout::horizontal([Constraint::Ratio(1, 5); 5]).split(row2);
    stat(
        frame,
        cells1[0],
        "Daemon CPU",
        format!("{last_cpu:.0}%"),
        cpu_hist,
        false,
    );
    stat(
        frame,
        cells1[1],
        "Verb calls/s",
        short(last_calls),
        calls_hist,
        false,
    );

    let Some(q) = q else {
        for (i, title) in ["Players", "Tasks active", "Tasks suspended"]
            .iter()
            .enumerate()
        {
            stat(frame, cells1[i + 2], title, "–".to_string(), vec![], false);
        }
        for (i, title) in [
            "Tasks started/s",
            "Commits/s",
            "Conflicts/s",
            "RPC queued",
            "RPC wait p99",
        ]
        .iter()
        .enumerate()
        {
            stat(frame, cells2[i], title, "–".to_string(), vec![], false);
        }
        frame.render_widget(no_metrics(app), charts);
        return;
    };
    let h = dash::headline(&q);
    let opt_rate = |v: Option<f64>| v.map(short).unwrap_or_else(|| "–".to_string());
    stat(
        frame,
        cells1[2],
        "Players",
        short(h.players),
        each(&|s| dash::headline(s).players),
        false,
    );
    stat(
        frame,
        cells1[3],
        "Tasks active",
        short(h.tasks_active),
        each(&|s| dash::headline(s).tasks_active),
        false,
    );
    stat(
        frame,
        cells1[4],
        "Tasks suspended",
        short(h.tasks_suspended),
        each(&|s| dash::headline(s).tasks_suspended),
        false,
    );
    stat(
        frame,
        cells2[0],
        "Tasks started/s",
        opt_rate(h.tasks_started),
        each(&|s| dash::headline(s).tasks_started.unwrap_or(0.0)),
        false,
    );
    stat(
        frame,
        cells2[1],
        "Commits/s",
        opt_rate(h.commits),
        each(&|s| dash::headline(s).commits.unwrap_or(0.0)),
        false,
    );
    stat(
        frame,
        cells2[2],
        "Conflicts/s",
        opt_rate(h.conflicts),
        each(&|s| dash::headline(s).conflicts.unwrap_or(0.0)),
        h.conflicts.is_some_and(|c| c >= 1.0),
    );
    stat(
        frame,
        cells2[3],
        "RPC queued",
        short(h.rpc_queued),
        each(&|s| dash::headline(s).rpc_queued),
        h.rpc_queued >= 10.0,
    );
    stat(
        frame,
        cells2[4],
        "RPC wait p99",
        h.rpc_wait_p99
            .map(duration)
            .unwrap_or_else(|| "–".to_string()),
        each(&|s| dash::headline(s).rpc_wait_p99.unwrap_or(0.0) / 1e3),
        h.rpc_wait_p99.is_some_and(|p| p > 1e9),
    );

    let [left, right_area] =
        Layout::horizontal([Constraint::Ratio(1, 2), Constraint::Ratio(1, 2)]).areas(charts);
    let now = app.cpu.len() as f64;
    let cpu_series = |f: fn(&Summary) -> f64| -> Vec<(f64, f64)> {
        app.cpu
            .iter()
            .enumerate()
            .map(|(i, (s, _))| (i as f64 - now + 1.0, f(s)))
            .collect()
    };
    line_chart(
        frame,
        left,
        " CPU, % of one core ",
        &[
            ("daemon", Color::White, cpu_series(|s| s.daemon_cpu)),
            ("tasks", Color::Cyan, cpu_series(|s| s.task_cpu)),
            ("commits", Color::Yellow, cpu_series(|s| s.commit_cpu)),
            ("other", Color::Magenta, cpu_series(|s| s.other_cpu)),
        ],
        |v| format!("{v:.0}%"),
    );
    commits_chart(frame, right_area, &steps);

    let warnings = dash::warnings(&app.metrics.query(Window::All).unwrap_or(q));
    let lines: Vec<Line> = if warnings.is_empty() {
        vec![Line::from("Nothing to report.").green()]
    } else {
        warnings
            .into_iter()
            .map(|w| Line::from(format!("• {w}")).red())
            .collect()
    };
    frame.render_widget(
        Paragraph::new(lines).block(Block::bordered().title(" Warnings since mootop started ")),
        warn,
    );
}

fn commits_chart(frame: &mut Frame, area: Rect, steps: &[Query]) {
    let now = steps.len() as f64;
    let series = |i: usize| -> Vec<(f64, f64)> {
        steps
            .iter()
            .enumerate()
            .map(|(x, q)| {
                (
                    x as f64 - now + 1.0,
                    dash::commit_rates(q)[i].unwrap_or(0.0),
                )
            })
            .collect()
    };
    line_chart(
        frame,
        area,
        " Commits per second ",
        &[
            ("read-only", Color::Cyan, series(0)),
            ("write", Color::Green, series(1)),
            ("conflict", Color::Red, series(2)),
        ],
        short,
    );
}

/// One line of a chart: its name, colour, and (x, y) points.
type ChartLine<'a> = (&'a str, Color, Vec<(f64, f64)>);

/// A line chart over the last two minutes, with x in seconds before now.
fn line_chart(
    frame: &mut Frame,
    area: Rect,
    title: &str,
    lines: &[ChartLine],
    label: fn(f64) -> String,
) {
    let max = lines
        .iter()
        .flat_map(|(_, _, d)| d.iter().map(|(_, y)| *y))
        .fold(0.0_f64, f64::max)
        .max(1.0)
        * 1.1;
    let datasets: Vec<Dataset> = lines
        .iter()
        .map(|(name, color, data)| {
            Dataset::default()
                .name(name.to_string())
                .marker(Marker::Braille)
                .graph_type(GraphType::Line)
                .style(Style::new().fg(*color))
                .data(data)
        })
        .collect();
    let span = KEPT as f64;
    let chart = Chart::new(datasets)
        .block(Block::bordered().title(title.to_string()))
        .legend_position(Some(LegendPosition::TopLeft))
        .x_axis(
            Axis::default()
                .bounds([-span + 1.0, 0.0])
                .labels(["-2m", "-1m", "now"])
                .style(Style::new().dim()),
        )
        .y_axis(
            Axis::default()
                .bounds([0.0, max])
                .labels(["0".to_string(), label(max / 2.0), label(max)])
                .style(Style::new().dim()),
        );
    frame.render_widget(chart, area);
}

fn tasks(frame: &mut Frame, area: Rect, app: &App, q: Option<Query>, table_state: &mut TableState) {
    let [left, side] =
        Layout::horizontal([Constraint::Percentage(55), Constraint::Percentage(45)]).areas(area);
    let table = frames_table(app, View::Tasks);
    frame.render_stateful_widget(table, left, table_state);
    let Some(q) = q else {
        frame.render_widget(no_metrics(app), side);
        return;
    };
    let suspended = dash::suspended(&q);
    let [activity, trouble, latency, waiting, schedules] = Layout::vertical([
        Constraint::Length(6),
        Constraint::Length(7),
        Constraint::Length(7),
        Constraint::Length(suspended.len().max(1) as u16 + 2),
        Constraint::Min(9),
    ])
    .areas(side);
    frame.render_widget(
        figures("Tasks per second", &dash::task_activity(&q)),
        activity,
    );
    frame.render_widget(
        figures("Trouble per second", &dash::task_trouble(&q)),
        trouble,
    );
    frame.render_widget(
        figures("Scheduling delay, p99", &dash::task_latency(&q)),
        latency,
    );
    let waiting_figs: Vec<Figure> = suspended
        .iter()
        .map(|(w, n)| Figure {
            label: waiting_label(w),
            value: short(*n),
        })
        .collect();
    frame.render_widget(figures("Suspended, waiting for", &waiting_figs), waiting);
    frame.render_widget(figures("Schedules", &dash::schedules(&q)), schedules);
}

fn waiting_label(w: &str) -> &'static str {
    match w {
        "time" => "a time",
        "input" => "input",
        "task" => "another task",
        "immediate" => "the next turn",
        "worker" => "a worker",
        "gc_complete" => "GC",
        "retry" => "a retry",
        "task_message" => "a message",
        "never" => "nothing (forever)",
        _ => "other",
    }
}

fn database(frame: &mut Frame, area: Rect, app: &App, q: &Query) {
    let [top, ops, bottom] = Layout::vertical([
        Constraint::Length(11),
        Constraint::Min(6),
        Constraint::Length(10),
    ])
    .areas(area);
    let [chart, latency] =
        Layout::horizontal([Constraint::Percentage(62), Constraint::Percentage(38)]).areas(top);
    let steps: Vec<Query> = app.metrics.steps().collect();
    commits_chart(frame, chart, &steps);
    frame.render_widget(figures("Commit latency", &dash::commit_latency(q)), latency);

    let timers = dash::db_operations(q);
    let top_share = timers
        .iter()
        .filter_map(|t| t.thread)
        .fold(0.0_f64, f64::max)
        .max(1e-9);
    let rows: Vec<TableRow> = timers
        .iter()
        .take(ops.height.saturating_sub(3) as usize)
        .map(|t| {
            let share = t.thread.unwrap_or(0.0);
            let bar = "█".repeat(((share / top_share) * 16.0).round() as usize);
            TableRow::new([
                Cell::from(t.name.clone()),
                right(format!("{:.1}%", share * 100.0)),
                Cell::from(bar).cyan(),
                right(short(t.rate)),
                right(t.mean.map(duration).unwrap_or_default()),
                right(t.p99.map(duration).unwrap_or_default()),
            ])
        })
        .collect();
    frame.render_widget(
        Table::new(
            rows,
            [
                Constraint::Fill(1),
                Constraint::Length(8),
                Constraint::Length(17),
                Constraint::Length(9),
                Constraint::Length(9),
                Constraint::Length(9),
            ],
        )
        .header(bold_header(["Operation", "Thread", "", "Calls/s", "Mean", "p99 ≤"], &[0, 2]))
        .block(Block::bordered().title(
            " Operations by thread time (sampled mean × calls; 100% is one thread busy; commits above) ",
        )),
        ops,
    );

    let [caches, writes, maint] = Layout::horizontal([
        Constraint::Percentage(45),
        Constraint::Percentage(30),
        Constraint::Percentage(25),
    ])
    .areas(bottom);
    cache_panel(frame, caches, q);
    frame.render_widget(figures("Writes per second", &dash::write_path(q)), writes);
    frame.render_widget(figures("Maintenance, mean", &dash::maintenance(q)), maint);
}

fn cache_panel(frame: &mut Frame, area: Rect, q: &Query) {
    let block = Block::bordered().title(" Caches: hit ratio, entries, flushes/s ");
    let inner = block.inner(area);
    frame.render_widget(block, area);
    let caches = dash::caches(q);
    let lines = Layout::vertical(vec![Constraint::Length(1); caches.len()]).split(inner);
    for (cache, line) in caches.iter().zip(lines.iter()) {
        let [gauge, rest] =
            Layout::horizontal([Constraint::Fill(1), Constraint::Length(18)]).areas(*line);
        let ratio = cache.hit_ratio.unwrap_or(0.0).clamp(0.0, 1.0);
        let label = match cache.hit_ratio {
            Some(r) => format!("{:<9}{:>4.0}%", cache.name, r * 100.0),
            None => format!("{:<9}    –", cache.name),
        };
        frame.render_widget(
            LineGauge::default()
                .ratio(ratio)
                .label(label)
                .filled_style(Style::new().fg(if ratio < 0.5 {
                    Color::Yellow
                } else {
                    Color::Green
                })),
            gauge,
        );
        frame.render_widget(
            Line::from(format!(
                "{:>8} {:>8}",
                short(cache.entries),
                cache.flushes.map(short).unwrap_or_default()
            )),
            rest,
        );
    }
}

fn rpc(frame: &mut Frame, area: Rect, q: &Query) {
    let queues = dash::rpc_queues(q);
    let pools = dash::pools(q);
    let worker_list = dash::workers(q);
    let [queue_area, pool_area, bottom, _] = Layout::vertical([
        Constraint::Length(queues.len() as u16 + 3),
        Constraint::Length(pools.len() as u16 + 2),
        Constraint::Length(worker_list.len().max(3) as u16 + 3),
        Constraint::Fill(1),
    ])
    .areas(area);

    let rows: Vec<TableRow> = queues
        .iter()
        .map(|r| {
            let opt = |v: Option<f64>, f: fn(f64) -> String| v.map(f).unwrap_or_default();
            let dropped = r.dropped.unwrap_or(0.0);
            TableRow::new([
                Cell::from(r.name.clone()),
                right(short(r.queued)),
                right(opt(r.taken, short)),
                right(opt(r.p50, duration)),
                right(opt(r.p99, duration)),
                right(short(dropped)).style(if dropped > 0.0 {
                    Style::new().red()
                } else {
                    Style::new()
                }),
            ])
        })
        .collect();
    frame.render_widget(
        Table::new(
            rows,
            [
                Constraint::Fill(1),
                Constraint::Length(9),
                Constraint::Length(9),
                Constraint::Length(10),
                Constraint::Length(10),
                Constraint::Length(10),
            ],
        )
        .header(bold_header(
            [
                "Queue",
                "Waiting",
                "Taken/s",
                "Wait p50",
                "Wait p99",
                "Dropped/s",
            ],
            &[0],
        ))
        .block(Block::bordered().title(" RPC queues: requests waiting for a daemon thread ")),
        queue_area,
    );

    let block = Block::bordered().title(" Deferred call pools: places in use ");
    let inner = block.inner(pool_area);
    frame.render_widget(block, pool_area);
    let lines = Layout::vertical(vec![Constraint::Length(1); pools.len()]).split(inner);
    for (pool, line) in pools.iter().zip(lines.iter()) {
        let ratio = if pool.limit > 0.0 {
            (pool.in_use / pool.limit).clamp(0.0, 1.0)
        } else {
            0.0
        };
        let refused = if pool.refused > 0.0 {
            format!("  {} refused", short(pool.refused))
        } else {
            String::new()
        };
        let color = if pool.refused > 0.0 || ratio > 0.9 {
            Color::Red
        } else if ratio > 0.5 {
            Color::Yellow
        } else {
            Color::Green
        };
        frame.render_widget(
            LineGauge::default()
                .ratio(ratio)
                .label(format!(
                    "{:<14}{:>5}/{:<5}{refused}",
                    pool.name,
                    short(pool.in_use),
                    short(pool.limit)
                ))
                .filled_style(Style::new().fg(color)),
            *line,
        );
    }

    let [sessions, workers] =
        Layout::horizontal([Constraint::Percentage(30), Constraint::Percentage(70)]).areas(bottom);
    frame.render_widget(figures("Sessions", &dash::sessions(q)), sessions);
    let rows: Vec<TableRow> = worker_list
        .into_iter()
        .map(|w| {
            let results = w
                .results
                .iter()
                .map(|(r, n)| format!("{r} {}/s", short(*n)))
                .collect::<Vec<_>>()
                .join(", ");
            TableRow::new([
                Cell::from(w.name),
                right(short(w.attached)).style(if w.attached == 0.0 {
                    Style::new().red()
                } else {
                    Style::new()
                }),
                right(short(w.pending)),
                Cell::from(results),
            ])
        })
        .collect();
    frame.render_widget(
        Table::new(
            rows,
            [
                Constraint::Length(10),
                Constraint::Length(9),
                Constraint::Length(9),
                Constraint::Fill(1),
            ],
        )
        .header(bold_header(
            ["Worker", "Attached", "Pending", "Requests by result"],
            &[0, 3],
        ))
        .block(Block::bordered().title(" Workers ")),
        workers,
    );
}
