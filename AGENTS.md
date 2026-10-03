# Working on mooR

mooR is a Rust implementation of LambdaMOO for persistent, programmable, multi-user worlds. It
combines a compiler, virtual machine, transactional database, and network services. Execution is
multithreaded, with optimistic concurrency and snapshot isolation. Start with `README.md`. Read the
relevant code and local documentation for details.

## Human and agent responsibilities

- The human owns scope and design decisions. Ask before major changes beyond the agreed task.
- Work within the agreed scope. Preserve unrelated work.
- Do not run Git commands unless the user explicitly requests them. Permission to commit does not
  include permission to push.
- Report what changed, what you checked, and any remaining problems. Do not claim results you did
  not verify.

## Required checks

- Always use `licensure`, `dprint`, and `./scripts/format-rust.sh` before handing off changes.
- Use `licensure -i <files>` for license headers, following `.licensure.yml`. Check with
  `licensure --check <files>`.
- Use `dprint fmt <files>` for supported files, following `dprint.json`. Check with
  `dprint check <files>`.
- Use `./scripts/format-rust.sh` for Rust formatting. Check with `./scripts/format-rust.sh --check`.
- Limit formatting changes to the task. For unchanged file types, use check mode to avoid unrelated
  edits.
- Run the tests and lint checks relevant to the change. Report blocked or failing checks.

## Commits and history

- Use [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/#summary):
  `type(scope): description`. The scope is optional.
- Every commit must include a descriptive body, separated from the subject by a blank line. Explain
  the problem, the change, and the validation. Mark breaking changes with `!` or a
  `BREAKING CHANGE:` footer.
- Keep history linear and bisectable. Each commit must build and pass the relevant tests.
- Keep each commit focused on one logical change. Include relevant tests and, when warranted, a
  changelog entry in the same commit.
- Do not create merge commits. Fold temporary fixes into unpublished commits before submission.
- Do not rewrite published history without explicit permission.
- Before committing, review the staged changes. Include only files that belong to the task.

## Documents and artifacts

- Do not commit LLM-generated scratch documents or artifacts: plans, sketches, design proposals,
  session notes, reports, or tool output.
- Creating local working files is fine. Keep them out of commits, including files under `doc/` and
  `docs/`.
- A request to create a document does not authorize committing it. Require explicit approval to
  commit that document.
- Maintain requested project documentation and `ChangeLog.md` in place. Do not add unsolicited
  documents.
- Update `ChangeLog.md` only for relevant, user-facing changes: features, significant bug fixes,
  compatibility changes, and changes that affect upgrades or operation. Use the appropriate
  unreleased section and explain the user-facing effect in short, simple English.
- Omit routine internal maintenance, development script fixes, formatting, refactoring, and
  test-only changes unless they have a significant user-facing effect. Not every commit needs an
  entry.
- Use factual language in code, comments, documentation, and responses. Avoid praise, marketing
  claims, and filler.
