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

//! Packages: source directories that declare themselves in a `package.moo`.
//!
//! A package's `package.moo` opens with `package "name" [...]` and holds the package's constants.
//! Its constants are qualified by its name (`minecraft::WORLD`), and its objects carry `package`
//! metadata so export can write each one back to its package. A directory without `package.moo`
//! is read exactly as before: its `constants.moo` defines global constants.

use crate::ObjdefLoaderError;
use moor_compiler::{PackageDeclaration, is_package_name, parse_package_declaration};
use moor_var::{Symbol, Var, v_list, v_map, v_str};
use std::{
    collections::HashMap,
    path::{Path, PathBuf},
    sync::OnceLock,
};

pub const PACKAGE_FILE: &str = "package.moo";
pub const CONSTANTS_FILE: &str = "constants.moo";

/// The newest `objdef_version` this reader understands. Version 1 is the format of directories
/// without `package.moo`; version 2 adds packages.
pub const OBJDEF_VERSION: i64 = 2;

static PACKAGE_KEY: OnceLock<Symbol> = OnceLock::new();
static PACKAGES_KEY: OnceLock<Symbol> = OnceLock::new();
static UNPACKAGED_DIRECTORY_KEY: OnceLock<Symbol> = OnceLock::new();

/// Object metadata naming the package that defines an object. Prefixed, like `objdef_packages`,
/// so it cannot be mistaken for a world's own metadata.
pub fn package_key() -> Symbol {
    *PACKAGE_KEY.get_or_init(|| Symbol::mk("objdef_package"))
}

/// `#0` metadata holding the declarations of the packages a world was imported from, as a map
/// from package name to its declared attributes, a list of `{key, value}` pairs in source order,
/// so export can write them back as they were written.
pub fn packages_key() -> Symbol {
    *PACKAGES_KEY.get_or_init(|| Symbol::mk("objdef_packages"))
}

/// The member directories of a world directory, or None if `directory` is not one.
///
/// A world directory holds packages side by side, as export writes them: it has no `package.moo`
/// or `constants.moo` of its own, and at least one of its subdirectories has a `package.moo`. Its
/// members are those subdirectories, plus any with a `constants.moo`, such as the `unpackaged`
/// directory export writes for objects from no package.
pub(crate) fn world_members(directory: &Path) -> Result<Option<Vec<PathBuf>>, ObjdefLoaderError> {
    // A missing directory is not a world; reading it as one reports that it is missing.
    if !directory.is_dir()
        || directory.join(PACKAGE_FILE).is_file()
        || directory.join(CONSTANTS_FILE).is_file()
    {
        return Ok(None);
    }
    let mut members = Vec::new();
    let mut packages = 0;
    let entries = std::fs::read_dir(directory)
        .map_err(|e| ObjdefLoaderError::ObjectFileReadError(directory.to_path_buf(), e))?;
    for entry in entries {
        let path = entry
            .map_err(|e| ObjdefLoaderError::ObjectFileReadError(directory.to_path_buf(), e))?
            .path();
        if !path.is_dir() {
            continue;
        }
        if path.join(PACKAGE_FILE).is_file() {
            packages += 1;
            members.push(path);
        } else if path.join(CONSTANTS_FILE).is_file() {
            members.push(path);
        }
    }
    if packages == 0 {
        return Ok(None);
    }
    members.sort();
    Ok(Some(members))
}

/// `#0` metadata naming the plain directory a world of packages was imported with, such as Cowbell's
/// source beside its test fixtures, so export writes objects from no package back under that name.
pub fn unpackaged_directory_key() -> Symbol {
    *UNPACKAGED_DIRECTORY_KEY.get_or_init(|| Symbol::mk("objdef_unpackaged_directory"))
}

/// A source directory, with its declaration when it is a package.
pub(crate) struct SourceDirectory {
    pub path: PathBuf,
    pub declaration: Option<PackageDeclaration>,
}

fn invalid(path: &Path, message: impl std::fmt::Display) -> ObjdefLoaderError {
    ObjdefLoaderError::InvalidPackage(format!("{}: {message}", path.display()))
}

/// Read a directory's package declaration, or None for a directory without `package.moo`.
pub(crate) fn read_declaration(
    directory: &Path,
) -> Result<Option<PackageDeclaration>, ObjdefLoaderError> {
    let package_file = directory.join(PACKAGE_FILE);
    if !package_file.is_file() {
        return Ok(None);
    }
    if directory.join(CONSTANTS_FILE).is_file() {
        return Err(invalid(
            directory,
            "has both package.moo and constants.moo; a package's constants belong in package.moo",
        ));
    }
    let text = std::fs::read_to_string(&package_file)
        .map_err(|e| ObjdefLoaderError::ObjectFileReadError(package_file.clone(), e))?;
    let declaration = parse_package_declaration(&text)
        .map_err(|e| {
            ObjdefLoaderError::ObjectDefParseError(package_file.display().to_string(), Box::new(e))
        })?
        .ok_or_else(|| invalid(&package_file, "must begin with a package declaration"))?;
    validate(&package_file, &declaration)?;
    Ok(Some(declaration))
}

fn validate(path: &Path, declaration: &PackageDeclaration) -> Result<(), ObjdefLoaderError> {
    match declaration
        .attribute("objdef_version")
        .and_then(Var::as_integer)
    {
        Some(version) if (1..=OBJDEF_VERSION).contains(&version) => {}
        Some(version) => {
            return Err(invalid(
                path,
                format!(
                    "is objdef_version {version}; this reader understands versions up to {OBJDEF_VERSION}"
                ),
            ));
        }
        None => return Err(invalid(path, "must declare an integer objdef_version")),
    }
    for dependency in depends(path, declaration)? {
        if dependency == declaration.name {
            return Err(invalid(path, "depends on itself"));
        }
    }
    Ok(())
}

/// The packages a declaration depends on.
fn depends(
    path: &Path,
    declaration: &PackageDeclaration,
) -> Result<Vec<String>, ObjdefLoaderError> {
    let Some(value) = declaration.attribute("depends") else {
        return Ok(vec![]);
    };
    let Some(list) = value.as_list() else {
        return Err(invalid(path, "depends must be a list of package names"));
    };
    list.iter()
        .map(|entry| match entry.as_string() {
            Some(name) if is_package_name(name) => Ok(name.to_string()),
            _ => Err(invalid(
                path,
                format!("depends names {entry:?}, not a package"),
            )),
        })
        .collect()
}

/// Order source directories for import: directories without a package first, in the order given,
/// then packages so that every package follows those it depends on. Refuses a package declared
/// twice, a dependency on a package that is not given, and a cycle.
pub(crate) fn order(
    directories: Vec<SourceDirectory>,
) -> Result<Vec<SourceDirectory>, ObjdefLoaderError> {
    let (mut ordered, mut packages): (Vec<_>, Vec<_>) = directories
        .into_iter()
        .partition(|directory| directory.declaration.is_none());

    let mut seen = HashMap::new();
    for directory in &packages {
        let name = &directory.declaration.as_ref().unwrap().name;
        if let Some(first) = seen.insert(name.clone(), directory.path.clone()) {
            return Err(invalid(
                &directory.path,
                format!("declares package {name:?}, as {} does", first.display()),
            ));
        }
    }
    for directory in &packages {
        for dependency in depends(&directory.path, directory.declaration.as_ref().unwrap())? {
            if !seen.contains_key(&dependency) {
                return Err(invalid(
                    &directory.path,
                    format!("depends on package {dependency:?}, which is not among the sources"),
                ));
            }
        }
    }

    let mut placed = std::collections::HashSet::new();
    while !packages.is_empty() {
        let ready = packages.iter().position(|directory| {
            depends(&directory.path, directory.declaration.as_ref().unwrap())
                .unwrap_or_default()
                .iter()
                .all(|dependency| placed.contains(dependency))
        });
        let Some(ready) = ready else {
            let names = packages
                .iter()
                .map(|directory| directory.declaration.as_ref().unwrap().name.as_str())
                .collect::<Vec<_>>()
                .join(", ");
            return Err(ObjdefLoaderError::InvalidPackage(format!(
                "packages depend on each other in a cycle: {names}"
            )));
        };
        let directory = packages.remove(ready);
        placed.insert(directory.declaration.as_ref().unwrap().name.clone());
        ordered.push(directory);
    }
    Ok(ordered)
}

/// The value stored under `objdef_packages` for a world's package declarations.
pub(crate) fn declarations_value(declarations: &[PackageDeclaration]) -> Var {
    let entries = declarations
        .iter()
        .map(|declaration| {
            let attributes = declaration
                .attributes
                .iter()
                .map(|(key, value)| v_list(&[v_str(key.as_str()), value.clone()]))
                .collect::<Vec<_>>();
            (v_str(&declaration.name), v_list(&attributes))
        })
        .collect::<Vec<_>>();
    v_map(&entries)
}

/// Package declarations read back from an `objdef_packages` value, in name order.
pub(crate) fn declarations_from_value(value: &Var) -> Vec<PackageDeclaration> {
    let Some(map) = value.as_map() else {
        return vec![];
    };
    let mut declarations = map
        .iter()
        .filter_map(|(name, attributes)| {
            let name = name.as_string()?.to_string();
            let attributes = attributes
                .as_list()?
                .iter()
                .filter_map(|pair| {
                    let pair = pair.as_list()?.iter().collect::<Vec<_>>();
                    let [key, value] = pair.as_slice() else {
                        return None;
                    };
                    Some((Symbol::mk(key.as_string()?), value.clone()))
                })
                .collect();
            Some(PackageDeclaration { name, attributes })
        })
        .collect::<Vec<_>>();
    declarations.sort_by(|a, b| a.name.cmp(&b.name));
    declarations
}

#[cfg(test)]
mod tests {
    use super::*;
    use moor_var::v_int;

    fn package(name: &str, depends: &[&str]) -> SourceDirectory {
        SourceDirectory {
            path: PathBuf::from(name),
            declaration: Some(PackageDeclaration {
                name: name.to_string(),
                attributes: vec![
                    (Symbol::mk("objdef_version"), v_int(2)),
                    (
                        Symbol::mk("depends"),
                        v_list(&depends.iter().map(|d| v_str(d)).collect::<Vec<_>>()),
                    ),
                ],
            }),
        }
    }

    fn names(ordered: &[SourceDirectory]) -> Vec<String> {
        ordered
            .iter()
            .map(|directory| directory.path.display().to_string())
            .collect()
    }

    #[test]
    fn packages_follow_their_dependencies() {
        let legacy = SourceDirectory {
            path: PathBuf::from("legacy"),
            declaration: None,
        };
        let ordered = order(vec![
            package("village", &["minecraft", "core"]),
            package("minecraft", &["core"]),
            legacy,
            package("core", &[]),
        ])
        .unwrap();
        assert_eq!(names(&ordered), ["legacy", "core", "minecraft", "village"]);
    }

    #[test]
    fn missing_duplicate_and_cyclic_packages_are_refused() {
        assert!(order(vec![package("a", &["b"])]).is_err());
        assert!(order(vec![package("a", &[]), package("a", &[])]).is_err());
        assert!(order(vec![package("a", &["b"]), package("b", &["a"])]).is_err());
    }

    #[test]
    fn a_missing_directory_is_not_a_world() {
        let root = tempfile::tempdir().unwrap();
        assert!(
            world_members(&root.path().join("missing"))
                .unwrap()
                .is_none()
        );
    }

    #[test]
    fn declarations_round_trip_through_metadata() {
        let declarations = vec![
            package("core", &[]).declaration.unwrap(),
            package("minecraft", &["core"]).declaration.unwrap(),
        ];
        assert_eq!(
            declarations_from_value(&declarations_value(&declarations)),
            declarations
        );
    }
}
