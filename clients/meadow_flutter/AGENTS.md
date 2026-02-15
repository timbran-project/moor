# Agent Guidelines for meadow_flutter

This repository contains a Flutter desktop client (spike) for the mooR system and Cowbell core. Agentic tools should follow these guidelines to maintain consistency and quality.

## Project Goals

1.  **Fun and Dynamic Social Experience:** Create a social-media-like experience for interacting with shared authoring and virtual worlds.
2.  **Accessibility (A11Y):** Ensure the application is fully accessible and works correctly with screenreaders.
3.  **Clean and Performant Code:** Prioritize code quality and execution efficiency, utilizing zero-cost abstractions where possible.
4.  **Cross-Platform (Mobile First):** Target mobile, desktop, and web platforms, with mobile UX driving the primary design and use cases.

## General Principles

- **No Shortcuts:** Do not make executive decisions based on laziness or expediency. **ALWAYS ASK THE USER** if you are unsure of the best path.
- **Clean Patterns:** DO NOT introduce "legacy adaptors" or "normalize to old version" code. Bias towards **CLEAN AND CONSISTENT PATTERNS**. If you feel a legacy bridge is absolutely necessary, **ASK THE USER FIRST**.

## Project Structure

- `lib/fbs/`: Generated FlatBuffers code (DO NOT EDIT).
- `lib/moor/`: Core mooR logic, models, and types.
- `lib/moor/types/`: Domain-specific types using `extension type`.
- `lib/theme/`: App-wide styling and theme definitions.
- `lib/widgets/`: Reusable UI components and feature-specific widgets.
- `test/`: Unit and widget tests following the `*_test.dart` pattern.

## Build, Lint, and Test Commands

The project uses helper scripts in the `tool/` directory for common developer tasks.

- **Format code:** `./tool/fmt.sh` (Runs `dart format .`)
- **Lint code:** `./tool/lint.sh` (Runs `flutter analyze`)
- **Run tests:** `./tool/test.sh` (Runs `flutter test`)
- **Run a single test:** `flutter test test/path_to_test.dart`
- **Comprehensive check:** `./tool/check.sh` (Runs format, lint, and tests)
- **FlatBuffers codegen:** `./tool/gen_flatbuffers.sh` (Requires `flatc` and the schema files in the parent directory)
- **Run the app (Linux):** `./tool/run_linux.sh --server=URL --username=USER --password=PASS --login`

## Code Style Guidelines

### File Headers
All new `.dart` and `.sh` files must include the GPL v3 license header found in existing files.

```dart
// Copyright (C) 2026 Ryan Daum <ryan.daum@gmail.com>
//
// This program is free software: you can redistribute it and/or modify it under
// the terms of the GNU General Public License as published by the Free Software
// Foundation, version 3.
// ...
```

### Imports
- Use absolute `package:meadow_flutter/` imports for all internal files.
- Group imports alphabetically:
  1. `dart:` imports
  2. `package:` imports (external)
  3. `package:meadow_flutter/` imports (internal)
- Use `as` prefixes for generated FlatBuffers code (e.g., `import '.../moor_var_generated.dart' as fbs;`).

### Naming Conventions
- **Classes/Enums:** `PascalCase`
- **Variables/Functions/Parameters:** `camelCase`
- **Private members:** Prefix with `_` (e.g., `_myPrivateVariable`).
- **Constants:** `camelCase` (e.g., `moorNoneVar`).
- **Extension types:** Use `extension type` for zero-cost wrappers (e.g., `extension type const MoorVar(Object value)`).
- **Files:** `snake_case.dart`

### Types and Safety
- Favor strong typing. Avoid `dynamic` unless strictly necessary.
- Use `extension type` to wrap native Dart types when representing domain-specific data (see `lib/moor/types/`).
- Use `@immutable` for value objects.
- Prefer `final` for variables that do not change.
- Use `required` for named parameters instead of making them nullable when they are mandatory.

### Formatting
- Adhere to `dart format` standards.
- Use trailing commas for all multi-line function signatures, constructor calls, and collection literals to ensure clean formatting.
- `analysis_options.yaml` relaxes the 80-column limit, but aim for readability.

### Error Handling
- Use `try...on Object catch (e)` for generic error handling to ensure all exceptions are caught.
- Use specific exception types where possible.
- Avoid empty catch blocks; at least log the error using a system message or print.

### Flutter/Widget Best Practices
- Use `super.key` in constructor parameters.
- Use `const` constructors whenever possible.
- Use `StatefulWidget` only when internal state management is required.
- Use `WidgetsBinding.instance.addPostFrameCallback` for actions that must happen after build.
- Follow the established `ThemeScope` and `ChangeNotifier` patterns for state distribution.
- **Accessibility:** Wrap interactive elements in `Semantics` widgets where necessary. Ensure `TextField`s have appropriate labels and `IconButton`s have `tooltip`s.

## Architecture and State Management

- **State Distribution:** Use `InheritedWidget` or `InheritedNotifier` (see `_ThemeScope` in `main.dart`) to provide state to the widget tree.
- **Controllers:** Complex UI logic should be encapsulated in `ChangeNotifier` or `ValueNotifier` controllers (e.g., `CommandEditingController`).
- **Communication:** Use the `MoorWsClient` for real-time narrative updates and `MoorHttpApi` for request-response actions.
- **Models:** Favor `@immutable` data classes. Use the generated FlatBuffers models as an intermediate layer, converting them to domain models for UI use.

## Git Guidelines

- **Surgical Commits:** NEVER use blanket commands like `git add .` or `git add -A`. Be surgical and only stage files specifically related to the task.
- **Conventional Commits:** Use the [Conventional Commits](https://www.conventionalcommits.org/) specification for all commit messages (e.g., `feat:`, `fix:`, `docs:`, `style:`, `refactor:`, `test:`, `chore:`).
- **User Approval:** Always ask for explicit user confirmation before performing any git operations (add, commit, push, etc.).
- **Commit Messages:** Draft concise (1-2 sentences) commit messages that focus on the "why" rather than the "what". Ensure the message accurately reflects the nature of the changes (e.g., "feat: add support for inline images").
- **Secrets:** Do not commit files that likely contain secrets (.env, credentials.json, etc.).

## Generated Code
- **DO NOT** manually edit files in `lib/fbs/`. These are generated from FlatBuffers schemas. If the schema changes, run `./tool/gen_flatbuffers.sh`.

## Testing
- Tests are located in the `test/` directory and follow the `*_test.dart` naming convention.
- Use `group` to organize tests and `test` for individual test cases.
- Use `expect` with appropriate matchers (e.g., `equals`, `isTrue`, `isA<Type>`).
- **Running Tests:** Always run the relevant tests before and after making changes. Use `./tool/test.sh` to run the full suite or `flutter test test/path_to_test.dart` for targeted verification.

## Development Workflow

1.  **Analyze:** Use `grep` and `glob` to find existing patterns.
2.  **Schema Check:** If you need to change data structures, check the FlatBuffers schemas in `../../crates/schema/schema/`.
3.  **Implement:** Follow the style guidelines above.
4.  **Verify:** Run `./tool/check.sh` before finalizing any changes. This ensures formatting, linting, and tests all pass.
5.  **Commit:** Follow surgical git practices and Conventional Commits.

## System Context and References

- **Reference Implementation:** The React/TypeScript client in `../meadow/` serves as the primary reference for feature parity and UI/UX behavior.
- **Web Services API:** The OpenAPI specification for the backend web services can be found in `../../crates/web-host/openapi.yaml`.

## Final Reminder

- **Consistency:** Always prioritize consistency with existing patterns.
- **Safety:** Never perform destructive operations without explicit confirmation.
- **Verification:** Always run lint and tests after implementation.
