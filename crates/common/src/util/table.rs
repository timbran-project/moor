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

//! A fixed-width text table for tool output.
//!
//! Columns are as wide as their widest cell. Characters that occupy two
//! terminal cells, such as East Asian characters, are counted as two, so the
//! borders line up in a terminal.

use std::fmt::Write;

/// Border style. Both styles only draw ASCII and box-drawing characters.
#[derive(Debug, Clone, Copy, Eq, PartialEq)]
pub enum TableStyle {
    /// Rounded corners, for small lists.
    Rounded,
    /// Sharp corners, for reports.
    Sharp,
}

impl TableStyle {
    fn corners(self) -> (&'static str, &'static str, &'static str, &'static str) {
        match self {
            TableStyle::Rounded => ("╭", "╮", "╰", "╯"),
            TableStyle::Sharp => ("┌", "┐", "└", "┘"),
        }
    }
}

/// Renders `header` and `rows` as a table.
///
/// `rows` may be shorter or longer than `header`; cells beyond a row's length
/// are blank. Nothing is inserted before the first column, so the result suits
/// `println!` and `eprintln!`.
#[must_use]
pub fn render_table(header: &[String], rows: &[Vec<String>]) -> String {
    render_styled_table(header, rows, TableStyle::Rounded)
}

/// Renders a table with the chosen border style.
#[must_use]
pub fn render_styled_table(header: &[String], rows: &[Vec<String>], style: TableStyle) -> String {
    let mut widths: Vec<usize> = header.iter().map(|h| display_width(h)).collect();
    for row in rows {
        for (index, cell) in row.iter().enumerate() {
            if index >= widths.len() {
                widths.push(0);
            }
            widths[index] = widths[index].max(display_width(cell));
        }
    }

    let (left, right, bottom_left, bottom_right) = style.corners();
    let mut out = String::new();

    write_border(&mut out, left, "┬", right, &widths, "─");
    write_row(&mut out, header, &widths);
    write_border(&mut out, "├", "┼", "┤", &widths, "─");
    for row in rows {
        write_row(&mut out, row, &widths);
    }
    write_border(&mut out, bottom_left, "┴", bottom_right, &widths, "─");

    out
}

/// Writes a table directly to `out`.
pub fn write_table(
    out: &mut impl Write,
    header: &[String],
    rows: &[Vec<String>],
) -> std::fmt::Result {
    out.write_str(&render_table(header, rows))
}

fn write_border(
    out: &mut String,
    left: &str,
    middle: &str,
    right: &str,
    widths: &[usize],
    horizontal: &str,
) {
    if widths.is_empty() {
        return;
    }
    let _ = write!(out, "{left}");
    for (index, width) in widths.iter().enumerate() {
        if index > 0 {
            let _ = write!(out, "{middle}");
        }
        for _ in 0..width + 2 {
            out.push_str(horizontal);
        }
    }
    let _ = writeln!(out, "{right}");
}

fn write_row(out: &mut String, cells: &[String], widths: &[usize]) {
    if widths.is_empty() {
        return;
    }
    for (index, width) in widths.iter().enumerate() {
        let cell = cells.get(index).map_or("", String::as_str);
        out.push_str(if index == 0 { "│ " } else { " │ " });
        out.push_str(cell);
        for _ in display_width(cell)..*width {
            out.push(' ');
        }
    }
    out.push_str(" │\n");
}

/// Width of `text` in terminal cells.
fn display_width(text: &str) -> usize {
    text.chars().map(char_width).sum()
}

/// Width of one character in terminal cells: zero for combining marks and
/// formatting characters, two for the East Asian wide and fullwidth blocks,
/// one otherwise.
fn char_width(c: char) -> usize {
    let code = u32::from(c);
    match code {
        // Combining marks and control characters take no cell of their own.
        0..=0x1F | 0x7F..=0x9F => 0,
        0x300..=0x36F | 0x200B..=0x200F | 0xFE00..=0xFE0F | 0xFE20..=0xFE2F => 0,
        // East Asian Wide and Fullwidth, the ranges terminals render as two
        // cells. This is the commonly used subset of EastAsianWidth.txt.
        0x1100..=0x115F
        | 0x2E80..=0x303E
        | 0x3041..=0x33FF
        | 0x3400..=0x4DBF
        | 0x4E00..=0x9FFF
        | 0xA000..=0xA4CF
        | 0xAC00..=0xD7A3
        | 0xF900..=0xFAFF
        | 0xFE30..=0xFE6F
        | 0xFF00..=0xFF60
        | 0xFFE0..=0xFFE6
        | 0x1F300..=0x1F64F
        | 0x1F900..=0x1F9FF
        | 0x20000..=0x3FFFD => 2,
        _ => 1,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn row(cells: &[&str]) -> Vec<String> {
        cells.iter().map(|c| (*c).to_string()).collect()
    }

    #[test]
    fn columns_take_the_width_of_their_widest_cell() {
        let table = render_table(&row(&["a", "bb"]), &[row(&["ccc", "d"])]);
        let width = display_width(table.lines().next().unwrap());
        for line in table.lines() {
            assert_eq!(
                display_width(line),
                width,
                "every line must be as wide: {table}"
            );
        }
        assert!(table.contains("│ ccc │ d  │"), "{table}");
        assert!(table.contains("│ a   │ bb │"), "{table}");
    }

    #[test]
    fn short_rows_are_padded() {
        let table = render_table(&row(&["x", "y"]), &[row(&["1"])]);
        assert!(table.contains("│ 1 │   │"), "{table}");
    }

    #[test]
    fn wide_characters_take_two_cells() {
        assert_eq!(display_width("日本"), 4);
        assert_eq!(display_width("a日b"), 4);
        let table = render_table(&row(&["日本"]), &[row(&["abcd"])]);
        let widths: Vec<usize> = table.lines().map(display_width).collect();
        assert!(widths.windows(2).all(|w| w[0] == w[1]), "{table}");
    }

    #[test]
    fn styles_differ_only_in_the_corners() {
        let header = row(&["h"]);
        let rows = [row(&["1"])];
        let rounded = render_styled_table(&header, &rows, TableStyle::Rounded);
        let sharp = render_styled_table(&header, &rows, TableStyle::Sharp);
        assert_eq!(rounded.lines().count(), sharp.lines().count());
        assert!(rounded.starts_with('╭'));
        assert!(sharp.starts_with('┌'));
    }
}
