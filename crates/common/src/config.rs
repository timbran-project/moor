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

use eyre::{WrapErr, bail, eyre};
use serde::{Serialize, de::DeserializeOwned};
use serde_yaml::{Mapping, Value};
use std::path::Path;

pub fn apply_yaml_config_file<T>(base: T, path: Option<&Path>) -> Result<T, eyre::Report>
where
    T: Serialize + DeserializeOwned,
{
    apply_yaml_config_file_with_flattened_sections(base, path, &[])
}

pub fn apply_yaml_config_file_with_flattened_sections<T>(
    base: T,
    path: Option<&Path>,
    flattened_sections: &[&str],
) -> Result<T, eyre::Report>
where
    T: Serialize + DeserializeOwned,
{
    let Some(path) = path else {
        return Ok(base);
    };

    let mut base = serde_yaml::to_value(base).wrap_err("failed to serialize default config")?;
    let reader = std::fs::File::open(path)
        .map_err(|e| eyre!("failed to open configuration file {path:?}: {e}"))?;
    let mut overlay: Value = serde_yaml::from_reader(reader)
        .map_err(|e| eyre!("failed to parse configuration file {path:?}: {e}"))?;

    flatten_sections(&mut overlay, flattened_sections)?;
    reject_unknown_fields(&base, &overlay, "$")?;
    merge_yaml(&mut base, overlay);

    serde_yaml::from_value(base)
        .map_err(|e| eyre!("failed to deserialize merged configuration from {path:?}: {e}"))
}

fn flatten_sections(value: &mut Value, sections: &[&str]) -> Result<(), eyre::Report> {
    if sections.is_empty() {
        return Ok(());
    }

    let Some(mapping) = value.as_mapping_mut() else {
        return Ok(());
    };

    for section in sections {
        let section_key = Value::String((*section).to_string());
        let Some(section_value) = mapping.remove(&section_key) else {
            continue;
        };
        let Value::Mapping(section_mapping) = section_value else {
            bail!("configuration section {section:?} must be a mapping");
        };
        for (key, value) in section_mapping {
            mapping.insert(key, value);
        }
    }

    Ok(())
}

fn reject_unknown_fields(base: &Value, overlay: &Value, path: &str) -> Result<(), eyre::Report> {
    let (Value::Mapping(base), Value::Mapping(overlay)) = (base, overlay) else {
        return Ok(());
    };

    if base.is_empty() {
        return Ok(());
    }

    for (key, overlay_value) in overlay {
        let Some(base_value) = base.get(key) else {
            bail!("unknown configuration key {path}.{}", display_key(key));
        };
        reject_unknown_fields(
            base_value,
            overlay_value,
            &format!("{path}.{}", display_key(key)),
        )?;
    }

    Ok(())
}

fn display_key(key: &Value) -> String {
    match key {
        Value::String(s) => s.clone(),
        other => format!("{other:?}"),
    }
}

fn merge_yaml(base: &mut Value, overlay: Value) {
    match (base, overlay) {
        (Value::Mapping(base), Value::Mapping(overlay)) => merge_mapping(base, overlay),
        (base, overlay) => *base = overlay,
    }
}

fn merge_mapping(base: &mut Mapping, overlay: Mapping) {
    for (key, value) in overlay {
        match base.get_mut(&key) {
            Some(base_value) => merge_yaml(base_value, value),
            None => {
                base.insert(key, value);
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{apply_yaml_config_file, apply_yaml_config_file_with_flattened_sections};
    use serde::{Deserialize, Serialize};

    #[derive(Clone, Debug, Default, Deserialize, PartialEq, Serialize)]
    struct TestConfig {
        enabled: bool,
        nested: NestedConfig,
    }

    #[derive(Clone, Debug, Deserialize, PartialEq, Serialize)]
    struct NestedConfig {
        name: String,
        count: u32,
    }

    impl Default for NestedConfig {
        fn default() -> Self {
            Self {
                name: "default".to_string(),
                count: 3,
            }
        }
    }

    fn write_config(contents: &str) -> (tempfile::TempDir, std::path::PathBuf) {
        let dir = tempfile::tempdir().expect("create temp dir");
        let path = dir.path().join("config.yaml");
        std::fs::write(&path, contents).expect("write config");
        (dir, path)
    }

    #[test]
    fn overlays_partial_yaml_on_defaults() {
        let (_dir, path) = write_config(
            r#"
nested:
  count: 7
"#,
        );

        let config = apply_yaml_config_file(TestConfig::default(), Some(&path)).unwrap();

        assert_eq!(
            config,
            TestConfig {
                enabled: false,
                nested: NestedConfig {
                    name: "default".to_string(),
                    count: 7,
                },
            }
        );
    }

    #[test]
    fn rejects_unknown_nested_keys() {
        let (_dir, path) = write_config(
            r#"
nested:
  typo: 7
"#,
        );

        assert!(apply_yaml_config_file(TestConfig::default(), Some(&path)).is_err());
    }

    #[test]
    fn flattens_named_sections_before_overlaying() {
        let (_dir, path) = write_config(
            r#"
legacy:
  enabled: true
"#,
        );

        let config = apply_yaml_config_file_with_flattened_sections(
            TestConfig::default(),
            Some(&path),
            &["legacy"],
        )
        .unwrap();

        assert!(config.enabled);
    }
}
