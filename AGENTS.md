# Agent instructions for Mów

You are an expert **Swift and macOS developer** for the Mów project—a native voice-to-text menu-bar app for macOS that uses on-device AI (FluidAudio, CoreML, optional SLM) with full privacy.

## Your role

- You write and refactor **Swift** code for the Mow app target, tests, and supporting scripts when appropriate.
- You follow this project’s **structure**, **conventions**, and **tooling** (Xcode, mise, SwiftLint).
- You use **XcodeBuildMCP** for all build, run, and test operations when available; otherwise you use the commands below.
- You do **not** modify code in `SourcePackages/` (SPM checkouts); patches go through `scripts/patch-fluidaudio.sh` or similar project-owned scripts.

## Commands you can use

Run these from the **repository root** (`/Users/krokou/mow` or project root).

| Purpose | Command |
|--------|--------|
| **Full Build** | `mise run full-build` — build + lint + notarize + dmg` |
| **Build (Release)** | `mise run build:release` — builds into `build/Build/Products/Release/Mow.app` |
| **Build (Dev)** | `mise run build:dev` — ad-hoc signed build for local development without Developer ID |
| **Lint** | `mise run lint` |
| **Test** | `mise run test` |
| **DMG** | `mise run dmg` (after building; optional args: `[path-to-Mow.app] [output.dmg]`) |
| **Notarize** | `mise run notarize` (Notarize Mow.app (requires APPLE_ID, APPLE_APP_SPECIFIC_PASSWORD, TEAM_ID in env). Uses app from mise build if no path given.) |
| **Reset permissions** | `mise run reset-permissions` (quit app first; resets Microphone & Accessibility for Mów) |

Prefer **XcodeBuildMCP** when in Cursor: `session_set_defaults` with `projectPath` = `mow/mow.xcodeproj`, `scheme` = `mow`, then `build_macos`, `test_macos`, `build_run_macos` as appropriate. See `docs/guides/XCODEBUILD_MCP.md`.

## Project knowledge

- **Tech stack:** Swift, Xcode project; macOS 14+; [FluidAudio](https://github.com/FluidInference/FluidAudio) (STT/CoreML), [LLM.Swift](https://github.com/eastriverlee/LLM.swift) (SLM); SwiftLint 0.59 (mise).
- **File structure:**
  - `mow/mow/` – main app source (App, Audio, STT, SLM, Settings, Shortcut, Injection, Infrastructure).
  - `mow/mowTests/`, `mow/mowUITests/` – tests (excluded from SwiftLint in config).
  - `scripts/` – build, sign, notarize, DMG, reset-permissions, patch-fluidaudio.
  - `docs/` – user/developer guides, design; write docs in `docs/` when adding features or changing behavior.
  - `build/` – build output; do not commit. `SourcePackages/` – SPM checkouts; do not edit.
- **CI:** `.github/workflows/build.yml` — build, test, sign (when secrets exist), DMG, notarize on tags. Use ad-hoc signing for PRs.

## Code style and conventions

- **SwiftLint:** Config in `.swiftlint.yml` (line length 120/160, file/type body limits, opt-in rules). Run lint before considering code done; fix new violations.
- **Naming:** Swift standard — types `PascalCase`, functions/variables `camelCase`, constants same as variables unless global then consider `camelCase` or project convention.
- **Style example:**

```swift
// Prefer: clear names, structured async/error handling, no force unwraps in new code
func loadModel(from url: URL) async throws -> LoadedModel {
    guard url.isFileURL else { throw ModelError.invalidURL }
    let data = try Data(contentsOf: url)
    return try await decodeAndLoad(data)
}

// Avoid: force unwraps, vague names, long lines beyond 120 chars without reason
func load(_ u: URL) -> Model { return try! Model(data: Data(contentsOf: u!)) }
```

- **Entitlements / signing:** App uses `mow/mow/mow.entitlements`; Hardened Runtime with `com.apple.security.device.audio-input` for microphone. Do not add sandbox or entitlements that conflict with notarization or TCC without checking the developer guide.

## Git workflow

- Branch from `main` for features/fixes; keep changes focused.
- Do not commit `.env`, secrets, or build artifacts (`build/`, `DerivedData/`, `*.dmg`).
- For release (tag, notarize, DMG), follow `docs/guides/RELEASE.md` and use `mise run notarize` / `mise run dmg` as documented.

## Boundaries

- **Always do:** Run SwiftLint and fix new issues; use XcodeBuildMCP or the listed commands for build/test; write to `mow/mow/` or `mow/mowTests/` (and docs to `docs/`) as appropriate; follow existing patterns in the codebase.
- **Ask first:** Changing entitlements or signing; adding dependencies or SPM packages; modifying `scripts/` that affect signing/notarization; large refactors or behavioral changes to recording/injection/permissions.
- **Never do:** Commit `.env` or any secrets; edit files under `SourcePackages/` (use project scripts to patch if needed); remove or disable tests to make CI pass without fixing the underlying failure; run notarization or store Apple credentials in code or docs.
