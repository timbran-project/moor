// Copyright (C) 2026 Ryan Daum <ryan.daum@gmail.com>
// This program is free software: you can redistribute it and/or modify it under
// the terms of the GNU General Public License as published by the Free Software
// Foundation, version 3.
//
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
// FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License along with
// this program. If not, see <https://www.gnu.org/licenses/>.

//! Report source-level style debt using the objdef compiler and MOO concrete syntax tree.

use moor_compiler::{
    CompileOptions, SyntaxKind, lex, parse_program_frontend, parse_to_syntax_node,
};
use moor_objdef::{ObjDefSet, ObjDefSource};
use std::{collections::BTreeMap, error::Error, fs, path::PathBuf};

fn run() -> Result<bool, Box<dyn Error>> {
    let mut args = std::env::args().skip(1);
    let directory = PathBuf::from(args.next().ok_or("usage: style-audit SRC_DIR [--strict]")?);
    let strict = args.any(|arg| arg == "--strict");
    let mut files = fs::read_dir(&directory)?
        .map(|entry| entry.map(|entry| entry.path()))
        .collect::<Result<Vec<_>, _>>()?;
    files.retain(|path| path.extension().is_some_and(|ext| ext == "moo"));
    files.sort();
    if let Some(index) = files
        .iter()
        .position(|path| path.file_name().is_some_and(|name| name == "constants.moo"))
    {
        let constants = files.remove(index);
        files.insert(0, constants);
    }
    let mut sources = Vec::new();
    for path in &files {
        sources.push(ObjDefSource {
            label: path
                .file_name()
                .ok_or("missing file name")?
                .to_string_lossy()
                .into_owned(),
            contents: fs::read_to_string(path)?,
            path: Some(path.clone()),
        });
    }
    let options = CompileOptions {
        call_unsupported_builtins: true,
        ..Default::default()
    };
    let definitions = ObjDefSet::parse_sources(&options, Some(&directory), None, sources)
        .map_err(|error| format!("objdef compile failed: {error}"))?;
    let expected_verbs: usize = definitions
        .graph()
        .object_definitions()
        .values()
        .map(|(_, object)| object.verbs.len())
        .sum();
    let mut verbs = 0;
    let mut findings = BTreeMap::new();
    let mut declarations = 0;
    println!("file\tline\tverb\tkind\tdetail");
    for path in files {
        let source = fs::read_to_string(&path)?;
        let mut body = None;
        // The lexer locates declaration boundaries; both the full objdef and each body
        // are checked by the compiler. Core declarations use the guide's two-space indent.
        for token in lex(&source) {
            if token.kind != SyntaxKind::Ident {
                continue;
            }
            let word = &source[token.span.clone()];
            let line = source[..token.span.start]
                .rfind('\n')
                .map_or(0, |offset| offset + 1);
            if &source[line..token.span.start] != "  " {
                continue;
            }
            if matches!(word, "verb" | "method") {
                if body.is_some() {
                    return Err(format!("nested declaration in {}", path.display()).into());
                }
                let start = source[token.span.end..]
                    .find('\n')
                    .ok_or("unterminated declaration")?
                    + token.span.end
                    + 1;
                let header = source[token.span.end..start].trim().to_owned();
                body = Some((
                    start,
                    header,
                    if word == "verb" {
                        "endverb"
                    } else {
                        "endmethod"
                    },
                ));
                continue;
            }
            let Some((start, header, endword)) = body.as_ref() else {
                continue;
            };
            if word != *endword {
                continue;
            }
            let (start, header) = (*start, header.clone());
            let code = &source[start..line];
            let (root, errors) = parse_to_syntax_node(code);
            if !errors.is_empty() {
                return Err(format!("{}: {errors:?}", path.display()).into());
            }
            verbs += 1;
            let mut report = |offset: usize, kind: &str, detail: String| {
                let line_number = source[..start + offset]
                    .bytes()
                    .filter(|byte| *byte == b'\n')
                    .count()
                    + 1;
                *findings.entry(kind.to_owned()).or_insert(0_usize) += 1;
                println!(
                    "{}\t{line_number}\t{header}\t{kind}\t{}",
                    path.display(),
                    detail.replace(['\n', '\t'], " ")
                );
            };
            let statements = root
                .children()
                .find(|node| node.kind() == SyntaxKind::StmtList);
            if let Some(first) = statements.and_then(|node| node.children().next()) {
                let first_token = first
                    .descendants_with_tokens()
                    .filter_map(|element| element.into_token())
                    .find(|token| {
                        !matches!(token.kind(), SyntaxKind::Whitespace | SyntaxKind::Newline)
                    });
                if !first_token.is_some_and(|token| token.kind() == SyntaxKind::StringLit) {
                    report(
                        0,
                        "missing-docstring",
                        "Describe the contract before executable statements.".to_owned(),
                    );
                }
            }
            let explicit_scatter_names: std::collections::BTreeSet<String> = root
                .descendants()
                .filter(|node| node.kind() == SyntaxKind::ScatterItem)
                .filter(|node| {
                    node.ancestors().any(|ancestor| {
                        matches!(
                            ancestor.kind(),
                            SyntaxKind::LetStmt
                                | SyntaxKind::ConstStmt
                                | SyntaxKind::LambdaExpr
                                | SyntaxKind::FnStmt
                        )
                    })
                })
                .filter_map(|node| {
                    node.children_with_tokens()
                        .filter_map(|element| element.into_token())
                        .find(|token| token.kind() == SyntaxKind::Ident)
                })
                .map(|token| token.text().to_string())
                .collect();
            let parsed = parse_program_frontend(code, options.clone())
                .map_err(|error| format!("{}: {error:?}", path.display()))?;
            for declaration in &parsed.variables.variables {
                if matches!(
                    declaration.decl_type,
                    moor_var::program::DeclType::Assign | moor_var::program::DeclType::Unknown
                ) && let moor_var::program::names::VarName::Named(name) =
                    declaration.identifier.nr
                    && !explicit_scatter_names.contains(&name.to_string())
                {
                    report(0, "implicit-local", name.to_string());
                }
            }
            for node in root.descendants() {
                if matches!(node.kind(), SyntaxKind::ConstStmt | SyntaxKind::LetStmt) {
                    declarations += 1;
                }
                if node.kind() != SyntaxKind::AssignExpr {
                    continue;
                }
                for ancestor in node.ancestors().skip(1) {
                    if ancestor.kind() == SyntaxKind::StmtList {
                        break;
                    }
                    if matches!(
                        ancestor.kind(),
                        SyntaxKind::IfStmt | SyntaxKind::ElseIfClause | SyntaxKind::WhileStmt
                    ) {
                        report(
                            u32::from(node.text_range().start()) as usize,
                            "conditional-assignment",
                            node.text().to_string(),
                        );
                        break;
                    }
                }
            }
            body = None;
        }
        if body.is_some() {
            return Err(format!("unterminated verb in {}", path.display()).into());
        }
    }
    if verbs != expected_verbs {
        return Err(
            format!("body coverage mismatch: {verbs} examined, {expected_verbs} compiled").into(),
        );
    }
    eprintln!("{verbs} verb bodies; {declarations} explicit declarations; findings: {findings:?}");
    Ok(!strict || findings.is_empty())
}

fn main() -> std::process::ExitCode {
    match run() {
        Ok(true) => std::process::ExitCode::SUCCESS,
        Ok(false) => std::process::ExitCode::FAILURE,
        Err(error) => {
            eprintln!("{error}");
            std::process::ExitCode::FAILURE
        }
    }
}
