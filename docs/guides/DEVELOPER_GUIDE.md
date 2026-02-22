# Developer guide

This guide covers how to build, sign, and distribute Mów locally and how that differs from the GitHub Actions workflow.

## Prerequisites

- **Xcode** (macOS, with Command Line Tools)
- **mise** – [install](https://mise.jdx.dev/getting-started.html) then run `mise install` in the repo to install pinned tools (e.g. SwiftLint)
- **.env** (optional) – Create a `.env` in the repo root; mise loads it for `mise run` / `mise exec`. Use `KEY=value` (no `export `). Example:

  ```bash
  APPLE_ID="you@example.com"
  APPLE_APP_SPECIFIC_PASSWORD="xxxx-xxxx-xxxx-xxxx"
  TEAM_ID="XXXXXXXXXX"
  CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAM_ID)"
  ```

  Add `.env` to `.gitignore` and never commit secrets.

---

## Local vs CI: main differences

| Aspect | Local (mise / Xcode) | GitHub Actions (CI) |
|--------|----------------------|--------------------|
| **Build** | `mise run build:release` or Xcode. Uses project’s Release settings; if no Developer ID cert is available, build may be **ad-hoc signed**. | Builds with **ad-hoc** signing (`CODE_SIGN_IDENTITY="-"`) to avoid SPM conflicts. |
| **Signing** | No automatic re-sign. You must either have a Developer ID cert and let Xcode sign the Release build, or **re-sign manually** before notarization. | After build, a dedicated step **re-signs** the app and nested frameworks with Developer ID + **secure timestamp**. |
| **Notarization** | You run `mise run notarize` (or `./scripts/notarize.sh`). Submission requires the app to be signed with Developer ID and **secure timestamp**; otherwise Apple returns “Invalid”. | Workflow notarizes the **re-signed** app (or DMG on tag), so it already has the correct signature and timestamp. |
| **DMG** | `mise run dmg` uses the app from the last mise build (or you pass a path). | Creates DMG from the built and re-signed app in the workflow. |

**Summary:** CI always re-signs with Developer ID + timestamp before notarization. Locally, a plain `mise run build:release` often produces an ad-hoc–signed app, so you must either re-sign before notarizing or set up Xcode to use Developer ID for Release.

---

## Steps to run (local)

### 1. Build for Release

```bash
mise run build:release
```

Output: `build/Build/Products/Release/Mow.app`.

- If you have a **Developer ID Application** certificate in Keychain and the project uses it for Release, the app may already be signed with a secure timestamp.
- If not (e.g. ad-hoc signing), you’ll need to re-sign before notarization (step 2).

### 2. Re-sign for notarization (if needed)

Required when the app was built with ad-hoc signing (e.g. no Developer ID cert, or build overrides). Notarization requires **Developer ID** and a **secure timestamp**.

**Option A – Use notarize script (recommended)**  
Set `CODESIGN_IDENTITY` in `.env` (or in the shell), then run notarize; the script will re-sign the app first:

```bash
# In .env or export in shell:
# CODESIGN_IDENTITY="Developer ID Application: Your Name (XXXXXXX)"

mise run notarize
```

**Option B – Re-sign manually, then notarize**

```bash
./scripts/sign-for-notarization.sh build/Build/Products/Release/Mow.app
mise run notarize
```

To find the exact identity string:

```bash
security find-identity -v -p codesigning | grep "Developer ID Application"
```

### 3. Notarize

Requires `APPLE_ID`, `APPLE_APP_SPECIFIC_PASSWORD`, and optionally `TEAM_ID` (and `CODESIGN_IDENTITY` if re-signing in step 2).

```bash
mise run notarize
```

- Uses `build/Build/Products/Release/Mow.app` by default (mise build output).
- If you set `CODESIGN_IDENTITY`, the script re-signs that app with Developer ID + timestamp, then submits to Apple.
- On success, the notarization ticket is stapled to the app. On failure, the script prints Apple’s log.

### 4. Create DMG (optional)

After the app is notarized:

```bash
mise run dmg
```

By default this uses `build/Build/Products/Release/Mow.app` and writes e.g. `mow-1.0.dmg` in the current directory. You can pass a different app path or output path; see `./scripts/build-dmg.sh`.

---

## Mise tasks reference

| Task | Command | Description |
|------|---------|-------------|
| Build Release | `mise run build:release` | Build app for Release into `build/` (matches CI layout). |
| Notarize | `mise run notarize` | Notarize `build/.../Mow.app`. Optionally re-signs if `CODESIGN_IDENTITY` is set. |
| DMG | `mise run dmg` | Create DMG from built (or given) Mow.app. |
| Reset permissions | `mise run reset-permissions` | Reset Microphone and Accessibility for Mów (quit app first, then relaunch and grant). |

---

## Permissions and new builds

macOS ties **Microphone** and **Accessibility** permissions to the app’s **bundle ID plus code signature and path**. So:

- The build in **Applications** (e.g. notarized Release) can have Microphone “on” in System Settings.
- A **different build** (e.g. from Xcode at `build/.../Mow.app`, or a new archive with a different signature) is treated as a different “client.” That build may see **Denied** or **Not determined** even though the other build shows as allowed.

**Symptom:** System Settings → Privacy shows Mów with Microphone (or Accessibility) enabled, but the app you’re running reports “denied” and can’t get authorized. That usually means the running app is a different build/path than the one that was granted.

**Housekeeping when you switch or install a new version:**

1. **Quit Mów** (menu bar → Quit Mów). Permissions are applied per running process; reset while the app isn’t running.
2. Reset TCC for the bundle ID so the system will prompt again for the next launch:
   ```bash
   mise run reset-permissions
   ```
   Or run the script directly: `./scripts/reset-permissions.sh`. It runs `tccutil reset` for Microphone and Accessibility. If **Microphone** reset fails (e.g. "Operation not permitted"), grant **Terminal** **Full Disk Access** in System Settings → Privacy & Security → Full Disk Access, open a new Terminal window, and run the reset again.
3. **Launch the app you actually want to use** (e.g. the one in Applications, or the Xcode-built app).
4. When the system dialog appears, click **Allow** for Microphone (and enable Mów in **System Settings → Privacy & Security → Accessibility** if needed).

Do this whenever you:

- Run from Xcode (Debug/Release) instead of the installed app, or vice versa.
- Install a new version over the old one (signature or path can change).
- See “denied” in the app while System Settings shows the app as allowed (different build).

After reset, only the **next** app launch that matches the build you’re using will get the prompt; grant there and that build will work.

**Why Microphone works from Xcode but can fail from the DMG (Release)**

- **Entitlements:** Release builds use the Hardened Runtime (for notarization). For microphone access with Hardened Runtime you must use the entitlement `com.apple.security.device.audio-input` only. The sandbox-only key `com.apple.security.device.microphone` can prevent the system permission prompt from appearing when the app is signed with `--options runtime`; the project uses only `audio-input`.
- **Window/key window:** TCC shows the “Allow” dialog attached to the app’s key window. When you run from Xcode (Debug), the microphone permission window is opened from a view that’s in the hierarchy, so the system dialog appears. When you run from the DMG (Release), the permission window is made key and the request is issued in the same run loop so TCC has a key window to attach to. The app also opens the microphone permission window from the menu bar so the prompt can appear in both Debug and Release.
- **Copy to Applications:** For the first run, copy Mów from the DMG to **Applications** and run it from there. Running directly from the mounted DMG volume can leave the app quarantined and may affect permission prompts on some systems.

There is **no conflict** between requesting Microphone and Accessibility: they are separate TCC permissions and are requested at different times (Microphone first, then Accessibility when the shortcut monitor starts). If one fails, the other can still be granted.

**Running from Xcode (Product → Run): enabling Accessibility**

When you run the app from Xcode, macOS usually **does not** show the system Accessibility prompt. The shortcut won’t work until you add the **Xcode-built** app in System Settings (not the one in Applications).

1. With the app running from Xcode, open **System Settings → Privacy & Security → Accessibility**.
2. Click the **+** button to add an app.
3. In the file dialog, you must choose the **Mow.app** that Xcode built. To open its folder:
   - In **Finder**, press **⌘⇧G** (Go to Folder).
   - Enter: `~/Library/Developer/Xcode/DerivedData`
   - Open the folder whose name **starts with `mow`** (e.g. `mow-abcdefghij`).
   - Go to **Build → Products → Debug → Mow.app** (or **Release** if you run a Release scheme).
   - Select **Mow.app** and click **Open**, then turn the switch **on** for Mów in the Accessibility list.
4. **Restart the app** (stop and run again from Xcode) so the shortcut monitor picks up the new permission.

If you use a custom Derived Data path (e.g. project-relative `build/`), use that folder instead: **build/Build/Products/Debug/Mow.app** (or Release).

---

## See also

- [Release checklist (GitHub & manual)](./RELEASE.md) – Tag-based releases, secrets, manual export/notarize/DMG.
- [Build workflow](../../.github/workflows/build.yml) – How CI builds, re-signs, and notarizes.
- [.env and mise](https://mise.jdx.dev/) – Loading env from `.env` for tasks.
- [User guide](./USER_GUIDE.md) – Troubleshooting (microphone dialog, shortcut, etc.) for end users.
