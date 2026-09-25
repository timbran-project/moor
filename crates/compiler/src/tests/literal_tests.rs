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

use moor_var::v_binary;

use crate::{CompileOptions, parse_program_frontend, unparse::to_literal};

#[test]
fn parses_binary_literals_through_frontend() {
    let parsed =
        parse_program_frontend(r#"return b"SGVsbG8gV29ybGQ=";"#, CompileOptions::default())
            .unwrap();
    let stmt = &parsed.stmts[0].node;
    if let crate::ast::StmtNode::Expr(crate::ast::Expr::Return(Some(expr))) = stmt
        && let crate::ast::Expr::Value(val) = expr.as_ref()
        && let Some(binary) = val.as_binary()
    {
        assert_eq!(binary.as_bytes(), b"Hello World");
    } else {
        panic!("expected binary literal return, got {stmt:?}");
    }
}

#[test]
fn parses_empty_binary_literals_through_frontend() {
    let parsed = parse_program_frontend(r#"return b"";"#, CompileOptions::default()).unwrap();
    let stmt = &parsed.stmts[0].node;
    if let crate::ast::StmtNode::Expr(crate::ast::Expr::Return(Some(expr))) = stmt
        && let crate::ast::Expr::Value(val) = expr.as_ref()
        && let Some(binary) = val.as_binary()
    {
        assert_eq!(binary.as_bytes(), b"");
    } else {
        panic!("expected empty binary literal return, got {stmt:?}");
    }
}

#[test]
fn rejects_invalid_binary_literal_base64() {
    let result = parse_program_frontend(r#"return b"SGVsbG8gV29ybGQ";"#, CompileOptions::default());
    assert!(result.is_err());
    let error = result.unwrap_err().to_string();
    assert!(error.contains("invalid base64") || error.contains("binary literal"));
}

#[test]
fn binary_literal_roundtrips_through_literal_formatter() {
    let original_data = b"Hello, World! This is binary data.";
    let binary_var = v_binary(original_data.to_vec());
    let literal_str = to_literal(&binary_var);
    let program = format!("return {literal_str};");
    let parsed = parse_program_frontend(&program, CompileOptions::default()).unwrap();

    if let crate::ast::StmtNode::Expr(crate::ast::Expr::Return(Some(expr))) = &parsed.stmts[0].node
        && let crate::ast::Expr::Value(val) = expr.as_ref()
        && let Some(binary) = val.as_binary()
    {
        assert_eq!(binary.as_bytes(), original_data);
    } else {
        panic!("expected roundtripped binary literal");
    }
}
