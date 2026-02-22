# XcodeBuildMCP setup for Mów

This project uses [XcodeBuildMCP](https://github.com/getsentry/XcodeBuildMCP) for **all build, run, and test operations** from Cursor or other MCP clients. Do not use raw `xcodebuild` or shell for builds—use MCP tools.

## Build operations (MCP only)

- **Build**: `session_show_defaults` → `session_set_defaults` (if needed) → **build_macos**
- **Build & run**: **build_run_macos**
- **Test**: **test_macos**
- **App path**: **get_mac_app_path**

Session defaults for this repo: `projectPath` = path to `mow/mow.xcodeproj`, `scheme` = `mow`.

## Enable the macOS workflow (required for build_macos)

By default only `session-management` and `simulator` are enabled, so **build_macos** is not available until you enable the `macos` workflow:

1. Open Cursor **Settings** → **MCP** (or your MCP configuration).
2. Find the **XcodeBuildMCP** server and add to its **env**:
   - **Key**: `XCODEBUILDMCP_ENABLED_WORKFLOWS`
   - **Value**: `session-management,simulator,macos,project-discovery`
3. Restart the MCP server or Cursor so **build_macos**, **build_run_macos**, **test_macos**, etc. are registered.

Check **xcodebuildmcp://doctor** → “Enabled Workflows” to confirm `macos` is listed.

## Project config

Repository root contains `.xcodebuildmcp/config.yaml` with:

- **Enabled workflows**: `session-management`, `simulator`, `macos`, `project-discovery`
- **Session defaults**: scheme `mow`, project path `./mow/mow.xcodeproj`

If your MCP client reads this file when its working directory is the repo root, the macOS workflow may be enabled automatically; otherwise use the env var above.

## Useful MCP resources

- **xcodebuildmcp://session-status** – current logging/debug session state
- **xcodebuildmcp://doctor** – environment, Xcode version, enabled workflows, tool availability
- **xcodebuildmcp://xcode-ide-state** – detected Xcode project/workspace (when cwd contains one)

## Typical flow

1. **session_show_defaults** – confirm or set project/scheme.
2. **discover_projs** – locate `mow/mow.xcodeproj`.
3. **build_macos** – build the app.
4. **build_run_macos** or **launch_mac_app** – run the app.
5. **test_macos** – run tests.

AI agents in this repo are instructed to use these tools instead of raw `xcodebuild` (see `.cursor/rules/xcodebuild-mcp.mdc`).
