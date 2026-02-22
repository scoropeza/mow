# Release checklist (GitHub)

## Automated release (recommended)

When you **push a version tag** (e.g. `v1.0.0`), the [Build workflow](../../.github/workflows/build.yml) runs: it builds the app, **signs with Developer ID** and **notarizes** the app, then creates a DMG and a GitHub Release with that DMG attached. Users get a notarized build with no Gatekeeper warning. **The five Apple secrets below must be set** for tag runs; otherwise the workflow will fail at signing or notarization.

**Required GitHub secrets** (Settings → Secrets and variables → Actions):

| Secret | Description |
|--------|-------------|
| `APPLE_ID` | Your Apple ID email |
| `APPLE_APP_SPECIFIC_PASSWORD` | [App-Specific Password](https://appleid.apple.com) (Sign-In and Security → App-Specific Passwords) |
| `TEAM_ID` | Your 10-character team ID (e.g. from [developer.apple.com/account](https://developer.apple.com/account) → Membership) |
| `MACOS_CERTIFICATE_BASE64` | Developer ID Application certificate: export from Keychain as `.p12`, then `base64 -i YourCert.p12 -o cert.txt` and paste the contents of `cert.txt` |
| `MACOS_CERTIFICATE_PASSWORD` | Password you set when exporting the `.p12` |

After adding the secrets, create and push a tag:

```bash
git tag v1.0.0
git push origin v1.0.0
```

The workflow will build, notarize, and create the release.

---

## Manual release

You can ship a notarized DMG either with **mise** (recommended) or via **Xcode Archive**. Ensure [mise](https://mise.jdx.dev/getting-started.html) is installed and `mise install` has been run in the repo. For notarization, set `APPLE_ID`, `APPLE_APP_SPECIFIC_PASSWORD`, and `TEAM_ID` (e.g. in a `.env` in the repo root; mise loads it for `mise run`). See [Developer guide](./DEVELOPER_GUIDE.md) for full prerequisites and re-signing.

### Option A: Mise build (recommended)

Uses the same layout as CI: build → notarize → dmg. Output app: `build/Build/Products/Release/Mow.app`.

**1. Build for Release**

```bash
mise run build:release
```

**2. Re-sign for notarization (if needed)**

If the build was ad-hoc signed (no Developer ID cert in Xcode), set `CODESIGN_IDENTITY` in `.env` (e.g. `CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAM_ID)"`). The notarize step will re-sign the app before submitting.

**3. Notarize the app**

```bash
mise run notarize
```

When it finishes, **Mow.app** in `build/Build/Products/Release/` is notarized (ticket stapled).

**4. Create the DMG**

```bash
mise run dmg
```

This creates **mow-&lt;version&gt;.dmg** in the current directory (version from the app's `Info.plist`). Optional: `mise run dmg -- build/Build/Products/Release/Mow.app /path/to/output.dmg` to set app path and output path.

If **hdiutil** reports "Operation not permitted", run the dmg step in the **Terminal** app (not inside an IDE); the process may need Full Disk Access to create the DMG.

**5. Upload to GitHub Releases**

1. On GitHub: **Releases → Create a new release** (or **Draft a new release**).
2. Tag version (e.g. `v1.0.0`).
3. Attach **mow-&lt;version&gt;.dmg**.
4. Add release notes and publish.

---

### Option B: Xcode Archive

Use when you prefer **Product → Archive** and exporting from the Organizer.

**1. Export the app from the archive**

1. In Xcode: **Window → Organizer** (or **Product → Organizer**).
2. Select the **Archives** tab and your latest **mow** archive.
3. Click **Distribute App** → **Developer ID** → Next.
4. Leave options as default → Next.
5. Choose **Export** and pick a folder (e.g. `~/Desktop/mow-export`). Xcode writes **Mow.app** there.

**2. Notarize the app**

From the repo root (env from `.env` or export):

```bash
./scripts/notarize.sh ~/Desktop/mow-export/Mow.app
```

When it finishes, that **Mow.app** is notarized (ticket stapled).

**3. Create the DMG**

```bash
./scripts/build-dmg.sh ~/Desktop/mow-export/Mow.app
```

Creates **mow-&lt;version&gt;.dmg** in the current directory. Optional second argument: output path.

**4. Upload to GitHub Releases**

Same as Option A step 5.

---

Users can download the DMG, open it, and drag Mów to Applications. No "unidentified developer" warning if the app was notarized.
