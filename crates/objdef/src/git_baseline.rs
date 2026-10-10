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

use crate::ObjDefSet;
use eyre::{Context, Result, bail, eyre};
use moor_compiler::CompileOptions;
use moor_var::{Var, v_bool, v_int, v_map, v_str};
use std::{path::Path, process::Command};

fn git(directory: &Path, args: &[&str]) -> Result<Vec<u8>> {
    let output = Command::new("git")
        .arg("--literal-pathspecs")
        .arg("-C")
        .arg(directory)
        .args(args)
        .env("GIT_OPTIONAL_LOCKS", "0")
        .output()
        .wrap_err("could not run Git; Git-backed preparation requires the git executable")?;
    if !output.status.success() {
        bail!(
            "git {} failed: {}",
            args[0],
            String::from_utf8_lossy(&output.stderr).trim()
        );
    }
    Ok(output.stdout)
}

fn git_text(directory: &Path, args: &[&str]) -> Result<String> {
    Ok(String::from_utf8(git(directory, args)?)?
        .trim_end()
        .to_owned())
}

/// Prepare baselines from local Git history. No fetch, checkout, or working-tree writes occur.
pub(crate) fn prepare(
    directory: &Path,
    upstream: &str,
    options: &CompileOptions,
) -> Result<(ObjDefSet, Var)> {
    let directory = directory.canonicalize()?;
    let root = git_text(&directory, &["rev-parse", "--show-toplevel"])?;
    let root = Path::new(&root).canonicalize()?;
    let relative = directory
        .strip_prefix(&root)
        .wrap_err("objdef directory is outside the Git working tree")?;
    let path = relative
        .to_str()
        .ok_or_else(|| eyre!("Git source path must be UTF-8"))?
        .replace(std::path::MAIN_SEPARATOR, "/");
    let reference = git_text(
        &root,
        &[
            "rev-parse",
            "--symbolic-full-name",
            "--verify",
            "--end-of-options",
            upstream,
        ],
    )?;
    let tracked = reference.strip_prefix("refs/remotes/").ok_or_else(|| {
        eyre!("--git-upstream must name a remote-tracking branch, such as origin/main")
    })?;
    let remotes = git_text(&root, &["remote"])?;
    let remote = remotes
        .lines()
        .filter(|remote| tracked.starts_with(&format!("{remote}/")))
        .max_by_key(|remote| remote.len())
        .ok_or_else(|| eyre!("no remote configured for {reference}"))?;
    let repository = git_text(&root, &["remote", "get-url", remote])?;
    let revision = format!("refs/heads/{}", &tracked[remote.len() + 1..]);
    if revision == "refs/heads/HEAD" {
        bail!("use the upstream branch name rather than the remote HEAD alias");
    }
    let head = git_text(&root, &["rev-parse", "--verify", "HEAD^{commit}"])?;
    let incoming = git_text(
        &root,
        &["rev-parse", "--verify", &format!("{reference}^{{commit}}")],
    )?;
    let bases = git_text(&root, &["merge-base", "--all", &head, &incoming])
        .wrap_err("cannot establish an upstream ancestor; fetch missing history or supply --baseline-objdef-dir")?;
    let commits = bases.lines().collect::<Vec<_>>();
    if commits.len() != 1 {
        bail!("Git history has no unique common ancestor; supply --baseline-objdef-dir explicitly");
    }
    let base = commits[0];
    let object_format = git_text(&root, &["rev-parse", "--show-object-format"])?;
    let oid = |hash: &str| v_str(&format!("{object_format}:{hash}"));
    let tree_spec = if path.is_empty() {
        format!("{base}^{{tree}}")
    } else {
        format!("{base}:{path}")
    };
    let tree = git_text(&root, &["rev-parse", "--verify", &tree_spec])?;
    let dirty = !git(
        &root,
        &[
            "status",
            "--porcelain=v1",
            "-z",
            "--untracked-files=all",
            "--",
            if path.is_empty() { "." } else { &path },
        ],
    )?
    .is_empty();
    let snapshot = tempfile::tempdir()?;
    let entries = git(&root, &["ls-tree", "-r", "-z", &tree])?;
    for entry in entries
        .split(|byte| *byte == 0)
        .filter(|entry| !entry.is_empty())
    {
        let (header, name) = entry.split_at(
            entry
                .iter()
                .position(|byte| *byte == b'\t')
                .ok_or_else(|| eyre!("invalid Git tree entry"))?,
        );
        let header = std::str::from_utf8(header)?
            .split_whitespace()
            .collect::<Vec<_>>();
        if header.len() != 3 || !matches!(header[0], "100644" | "100755") || header[1] != "blob" {
            bail!(
                "baseline source contains a symlink or submodule; use a self-contained objdef directory"
            );
        }
        let name = std::str::from_utf8(&name[1..])?;
        let relative = Path::new(name);
        if relative
            .components()
            .any(|part| !matches!(part, std::path::Component::Normal(_)))
        {
            bail!("invalid path in Git source tree");
        }
        let destination = snapshot.path().join(relative);
        std::fs::create_dir_all(destination.parent().unwrap())?;
        std::fs::write(destination, git(&root, &["cat-file", "blob", header[2]])?)?;
    }
    let baseline = ObjDefSet::read_directory(options, snapshot.path())?;
    if baseline.graph().object_definitions().is_empty() {
        bail!(
            "upstream ancestor has no objdefs at {path}; supply --baseline-objdef-dir explicitly"
        );
    }
    let provenance = v_map(&[
        (v_str("schema"), v_int(1)),
        (v_str("transport"), v_str("git")),
        (v_str("repository"), v_str(&repository)),
        (v_str("path"), v_str(&path)),
        (
            v_str("revision"),
            v_map(&[(v_str("ref"), v_str(&revision))]),
        ),
        (v_str("commit"), oid(base)),
        (v_str("tree"), oid(&tree)),
        (v_str("import_commit"), oid(&head)),
        (v_str("upstream_commit"), oid(&incoming)),
        (v_str("dirty"), v_bool(dirty)),
    ]);
    tracing::info!(
        baseline = base,
        checkout = head,
        upstream = incoming,
        dirty,
        "Prepared Git import baseline"
    );
    Ok((baseline, provenance))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::fingerprint::program_fingerprint;
    use moor_var::{Associative, Obj};
    use std::fs;

    fn fixture() -> tempfile::TempDir {
        let repository = tempfile::tempdir().unwrap();
        let root = repository.path();
        git(root, &["init", "--object-format=sha1", "-b", "main"]).unwrap();
        git(root, &["config", "user.name", "Baseline test"]).unwrap();
        git(root, &["config", "user.email", "baseline@example.invalid"]).unwrap();
        git(root, &["config", "commit.gpgsign", "false"]).unwrap();
        git(
            root,
            &[
                "remote",
                "add",
                "origin",
                "https://example.invalid/core.git",
            ],
        )
        .unwrap();
        fs::create_dir(root.join("core src")).unwrap();
        write_program(root, 1);
        commit(root);
        let base = git_text(root, &["rev-parse", "HEAD"]).unwrap();
        git(root, &["update-ref", "refs/remotes/origin/main", &base]).unwrap();
        repository
    }

    fn write_program(root: &Path, value: i32) {
        fs::write(root.join("core src/root.moo"), format!(
            "object #1 [import_export_id -> \"root\"]\nowner: #1\nwizard: true\nverb test (this none this) owner: #1 flags: \"rxd\"\nreturn {value};\nendverb\nendobject\n"
        )).unwrap();
    }

    fn commit(root: &Path) {
        git(root, &["add", "--", "core src"]).unwrap();
        git(root, &["commit", "-qm", "Change program"]).unwrap();
    }

    fn field(value: &Var, key: &str) -> Var {
        value.as_map().unwrap().get(&v_str(key)).unwrap()
    }

    #[test]
    fn ancestor_baselines_preserve_committed_and_uncommitted_local_edits() {
        let repository = fixture();
        let root = repository.path();
        let directory = root.join("core src");
        let options = CompileOptions::default();
        let ancestor = git_text(root, &["rev-parse", "HEAD"]).unwrap();
        let expected = ObjDefSet::read_directory(&options, &directory).unwrap();
        // Upstream and the checkout diverge from the original commit.
        git(root, &["switch", "-c", "upstream-work"]).unwrap();
        write_program(root, 10);
        commit(root);
        let upstream = git_text(root, &["rev-parse", "HEAD"]).unwrap();
        git(root, &["update-ref", "refs/remotes/origin/main", &upstream]).unwrap();
        git(root, &["switch", "main"]).unwrap();
        write_program(root, 2);
        commit(root);
        let local = git_text(root, &["rev-parse", "HEAD"]).unwrap();
        write_program(root, 3);
        let before = fs::read(directory.join("root.moo")).unwrap();
        let (baseline, provenance) = prepare(&directory, "origin/main", &options).unwrap();
        assert_eq!(
            field(&provenance, "commit"),
            v_str(&format!("sha1:{ancestor}"))
        );
        assert_eq!(
            field(&provenance, "import_commit"),
            v_str(&format!("sha1:{local}"))
        );
        assert_eq!(
            field(&provenance, "upstream_commit"),
            v_str(&format!("sha1:{upstream}"))
        );
        assert_eq!(field(&provenance, "dirty"), v_bool(true));
        let object = Obj::mk_id(1);
        let base_program = &baseline.graph().object_definitions()[&object].1.verbs[0].program;
        let expected_program = &expected.graph().object_definitions()[&object].1.verbs[0].program;
        assert_eq!(
            program_fingerprint(base_program).unwrap(),
            program_fingerprint(expected_program).unwrap()
        );
        let prepared = ObjDefSet::read_directory_with_baseline(
            &options,
            &directory,
            Some("origin/main"),
            None,
        )
        .unwrap();
        let live = &prepared.graph().object_definitions()[&object].1.verbs[0].program;
        assert_ne!(
            program_fingerprint(live).unwrap(),
            program_fingerprint(base_program).unwrap()
        );
        assert_eq!(fs::read(directory.join("root.moo")).unwrap(), before);
        assert_eq!(git_text(root, &["rev-parse", "HEAD"]).unwrap(), local);

        // When upstream is simply older, that upstream commit is the common base.
        git(root, &["update-ref", "refs/remotes/origin/main", &ancestor]).unwrap();
        let (_, provenance) = prepare(&directory, "origin/main", &options).unwrap();
        assert_eq!(
            field(&provenance, "commit"),
            v_str(&format!("sha1:{ancestor}"))
        );
    }

    #[test]
    fn unrelated_history_does_not_fall_back_to_live_or_upstream_head() {
        let repository = fixture();
        let root = repository.path();
        let unrelated = git_text(
            root,
            &["commit-tree", "HEAD^{tree}", "-m", "Unrelated root"],
        )
        .unwrap();
        git(
            root,
            &["update-ref", "refs/remotes/origin/main", &unrelated],
        )
        .unwrap();
        assert!(
            prepare(
                &root.join("core src"),
                "origin/main",
                &CompileOptions::default()
            )
            .is_err()
        );
    }
}
