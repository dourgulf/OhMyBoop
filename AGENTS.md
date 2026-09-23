# Repository Guidelines

## Project Structure & Module Organization

OhMyBoop is a native macOS 14+ toolbox using SwiftUI, AppKit, and JavaScriptCore.

- `Sources/OhMyBoop/`: application code. `Workspace.swift` owns editor sessions and undo; `FormatCatalog.swift` defines actions; `ScriptEngine.swift` runs script workers; `Highlighting.swift` manages Tree-sitter highlighting.
- `Sources/OhMyBoop/Resources/`: bundled scripts, highlighting queries, English/Simplified Chinese strings, and license notices.
- `Resources/Assets.xcassets/`: application artwork; `Vendor/BoopGrammars/`: bundled grammar package.
- `Tests/OhMyBoopTests/`: XCTest suites. `docs/`: design decisions and validation notes.
- `project.yml`: XcodeGen configuration; `Package.swift`: Swift Package configuration.

## Build, Test, and Development Commands

Run commands from the repository root with Xcode installed:

```sh
swift run                              # Launch through Swift Package Manager
swift test --disable-swift-testing      # Run XCTest suites
xcodegen generate                      # Regenerate the Xcode project
zsh scripts/build-app.sh                # Build Release app and verify signing
open dist/OhMyBoop.app                  # Launch the packaged app
python3 scripts/validate-localization.py # Verify packaged localization
```

Run `xcodegen generate` after adding source files or changing `project.yml`. Deliver runnable updates through `scripts/build-app.sh`; Swift Package builds alone do not verify application packaging. Output is `dist/OhMyBoop.app`.

## Coding Style & Naming Conventions

Follow existing Swift style: four-space indentation, `UpperCamelCase` types, and `lowerCamelCase` members. Keep filenames aligned with their principal type. Use `@MainActor` for UI-owned state and preserve editor text, selection, scroll position, and undo across actions. Route UI strings through `L10n` and update both language tables. Preserve bundled script author/license metadata. No dedicated formatter or linter is configured; run `git diff --check`.

## Testing Guidelines

Name suites `*Tests.swift` and methods `test<Behavior>`. Add focused regression coverage for changed behavior, especially persistence, UTF-16 selections, undo, and script errors. No numeric coverage threshold is configured. Match CI by running tests with `OHMYBOOP_LANGUAGE=en` and `OHMYBOOP_LANGUAGE=zh-Hans`; the second run can use `--skip-build`. Follow README validation commands for packaged resources. Off-screen AppKit screenshots do not replace real-window interaction checks.

## Commit & Pull Request Guidelines

Use concise imperative subjects, following history: `Add ...`, `Implement ...`, or `Document ...`. Keep commits scoped. PRs should explain the problem, resulting behavior, and validation performed; link relevant issues and include screenshots for visible UI changes. Distinguish tests, packaging checks, and manual verification.

## Agent Instructions

Do not send optional commentary.
