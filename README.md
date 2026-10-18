# Switch Profile

[English](README.md) · [Tiếng Việt](README.vi.md) · [简体中文](README.zh-CN.md)

A small macOS utility that routes links opened from other apps to the right Google Chrome profile.

**Status: local demo (v0.2.0).** The app builds from source into a local, ad-hoc signed `.app` (or download from GitHub Releases). Google Chrome is the initial target browser.

## How it works

`Click a link in another app → macOS → Switch Profile → matching rule → Chrome profile`

Set Switch Profile as the default web browser once. It receives HTTP/HTTPS links handed to the system default browser, chooses a profile, and forwards the original URL to Chrome. Apps using an embedded browser or explicitly opening another browser may bypass this flow.

The app runs in the menu bar and processes routing locally. It needs no backend or GitHub/GitLab API. Repository access uses the existing login session of the selected Chrome profile.

## Demo rules

These are the default rules (R1–R4). You can add, edit, delete and reorder rules in Settings (see **Manage rules** below). Rules are evaluated from top to bottom: specific repository matches first, then general domain matches.

| Match | Chrome profile | Acceptance link |
| --- | --- | --- |
| Exact host `git.fis.vn`, any path | `khuepm18` | [GitLab merge requests](https://git.fis.vn/fis-gs/gs-hn/BTP_CPLQG_S7_2025_PM/plvn-v2-backend/-/merge_requests) |
| Host `github.com`, repository `/TruckerPoints/trucker-points` and its descendants | `khue@truckerpoints.ai` | [trucker-points](https://github.com/TruckerPoints/trucker-points) |
| Other links on exact host `github.com` | `pmkhue.2013` | [LumiBase](https://github.com/khuepm/LumiBase) |
| Other hosts | Fallback: last active Chrome profile (default) or a chosen profile | Any unrelated website |

The repository rule includes paths such as `/issues` and `/pull/123`, but must not match `/TruckerPoints/trucker-points-other`. Host matching must use the parsed hostname, not a substring search. Routing preserves the original path, query, and fragment.

Hosts match exactly. Subdomains such as `www.github.com`, `api.github.com`, `gist.github.com` or `sub.git.fis.vn` do not match the GitHub or GitLab rules; they go to the fallback profile.

## Interface

- Default-browser status and setup instructions.
- An ordered rule list: add, edit, delete and reorder rules.
- Detected Chrome profiles and profile selection for each rule.
- A fallback selector: last active Chrome profile or a fixed profile.
- Clear recovery options when a configured profile is missing.

Profile display names and email addresses are not necessarily directory names. The app maps them to actual existing profile directories such as `Default` or `Profile 2`, without guessing, modifying login data, or silently creating a new profile.

## What v0.2.0 includes

1. A native macOS AppKit menu bar app that receives HTTP/HTTPS URL-open events.
2. Ordered repository/domain rules (editable in Settings), fallback routing, and loop prevention.
3. Menu bar access, settings and profile mapping. Routing is checked from Terminal with `--dry-run`.
4. A local `.app` built by one script, with setup and removal instructions below.
5. Automated tests for routing, configuration, and launching. The manual checks (each profile with Chrome running and closed, and the end-to-end matrix) are tracked in the [acceptance matrix](docs/ACCEPTANCE.md).

The target is a new tab in a window of the correct profile, or a new window when needed. Window reuse must be verified against the installed Chrome version. Signing, notarization, and automatic updates are follow-up work.

<!-- sp:requirements -->
## Requirements

- macOS 13 or later (deployment target). Tested on macOS 27 only.
- Google Chrome (stable channel) in `/Applications`, run at least once so its profiles exist.
- Command Line Tools for Xcode (`xcode-select --install`). Xcode itself is not needed.

<!-- sp:build-install -->
## Build and install

From a checkout of this repository:

```sh
scripts/build-app.sh            # builds and ad-hoc signs build/SwitchProfile.app
scripts/build-app.sh --install  # also copies it to ~/Applications/SwitchProfile.app, registers it and opens it
```

The app appears as an icon in the menu bar. It has no Dock icon.

<!-- sp:configuration -->
## Configure profile mapping

Open **Settings…** from the menu bar icon. **Routing rules** lists the rules in the order they are checked, ending with the fallback (R4). Each rule has a profile Picker that lists the profiles found in Chrome. The defaults are R1 git.fis.vn, R2 github.com/TruckerPoints/trucker-points and R3 github.com.

- On first run, Switch Profile detects the profiles for R1–R3 from the identities in the rule table. Such rows show "Auto-detected: matched by …". Press **Confirm** to accept, or choose another profile.
- **Detect** looks up a rule's identity again. If more than one profile matches, nothing is chosen and you pick one.
- R4 is the fallback for every other host. It defaults to "Last active Chrome profile": unmatched links open in the profile of the Chrome window you used last, or in Chrome's last used profile when Chrome is closed, as without Switch Profile. Choose a profile to fix the fallback instead. Existing configurations without a fallback switch to this mode automatically. A fixed fallback whose profile disappears waits in the pending links window.
- To see the rule and profile for a URL without opening Chrome, use the dry run (see **Check routing from Terminal** under Troubleshooting).
- Text fields support the standard edit shortcuts: Cmd+X, Cmd+C, Cmd+V, Cmd+A, Cmd+Z and Shift-Cmd-Z.
- A missing profile or an account change is flagged in the row and in the menu ("Profile mapping needs attention …").

### Manage rules

- **Add rule** (above the fallback) opens an editor: choose **Match** (Exact host, or Host and path prefix), enter the **Host** and, for a prefix, the **Path prefix**, optionally choose a **Profile**, then press **Save**. A new rule is added directly above the fallback and gets the next unused id (R5, R6, …; ids are never reused).
- **Edit** changes a rule's match; its profile is changed with the row's Picker. **Delete…** asks for confirmation. **Move up** / **Move down** change the order.
- Rules are checked from top to bottom and the first match wins. The fallback is always last and cannot be edited, moved or deleted.
- Exact host: the host must be equal (case-insensitive, a trailing dot is ignored, port and user info are ignored). Subdomains and wildcards (`*.github.com`) are not supported: add each host as its own rule.
- Host and path prefix: the path must start with the prefix on whole segments, case-insensitive. `/acme/app` matches `/acme/app`, `/acme/app/pull/1` and `/acme/app.git`, but not `/acme/app-other`. Query and fragment never take part. The original path, query and fragment are always forwarded unchanged.
- Invalid input is shown in red under the field: an empty or invalid host (no `http://`, path, port or spaces), a path that does not start with `/`, or a rule that duplicates another.
- An orange warning appears when a rule can never match because a broader rule above it always wins (for example `github.com/acme` below `github.com`). Move the narrower rule up.
- Adding, editing, deleting or moving a rule re-routes the links waiting in the pending links window.

The configuration is stored in `~/Library/Application Support/SwitchProfile/config.json` (schema version 2). A file from an earlier version is read as is and saved in the new format on the next change, with the same routing. If the file is invalid or from a newer version, it is never overwritten: the menu shows "Configuration error – Reset to defaults…", and Reset keeps a backup named `config.corrupt-<date>.json`.

<!-- sp:default-browser -->
## Set as default browser

In Settings, press **Set as default browser…** (also in the menu as "Set as Default Browser…") and confirm the macOS prompt. Settings then shows Switch Profile as the handler for `http` and `https`.

You can also choose it in System Settings → Desktop & Dock → Default web browser.

<!-- sp:troubleshooting -->
## Troubleshooting

- **"Chrome profiles unavailable" / Local State errors.** Switch Profile reads `~/Library/Application Support/Google/Chrome/Local State`. Make sure Chrome is installed and has been started once. On macOS 27, the system may deny this read to the app; grant Switch Profile access in System Settings → Privacy & Security (App Data or Full Disk Access), then press **Refresh** in Settings or **Refresh profiles** in the pending links window. Settings and the dry run say "Chrome profiles unavailable" with this fix, instead of "no profile set". The dry run runs with the terminal's access, so the terminal app that runs `--dry-run` needs the same App Data or Full Disk Access.
- **Pending links window.** Links that cannot be opened yet (no profile set, missing profile, Chrome could not be opened) are kept, never dropped. Open the window from "Pending links (n)…" in the menu and use **Open once**, **Open and use for R…**, **Retry** or **Discard**.
- **Another copy is the default.** If Settings says "Another copy at … is the default; remove it.", delete that copy, unregister it with `lsregister -u <path>` (full path below), then set the default again.
- **Gatekeeper.** The app is ad-hoc signed and not notarized. If macOS blocks it, Control-click the app and choose Open, or allow it in System Settings → Privacy & Security.
- **Check routing from Terminal.** The dry run prints the rule, profile directory and exact Chrome arguments without opening or writing anything:

  ```sh
  build/SwitchProfile.app/Contents/MacOS/SwitchProfile --dry-run [--assume-chrome running|closed] URL...
  ```

  It uses your rules from `config.json` and prints them in order on a `rules:` line. In last-active mode the fallback shows `R4: last active Chrome profile` and argv without `--profile-directory`.

<!-- sp:restore -->
## Restore the previous default browser

When you set Switch Profile as default, it records the previous browser. In Settings, press **Restore previous default (…)…**. You can also pick the browser again in System Settings → Desktop & Dock → Default web browser.

<!-- sp:remove -->
## Remove

1. Restore the previous default browser (above).
2. Quit Switch Profile from its menu ("Quit Switch Profile").
3. Delete `~/Applications/SwitchProfile.app` (and `build/SwitchProfile.app` if you built it).
4. Unregister it from Launch Services:

   ```sh
   /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u ~/Applications/SwitchProfile.app
   ```

5. Delete the settings folder `~/Library/Application Support/SwitchProfile/`.

<!-- sp:version -->
## Version

0.2.0 (build 2). Minimum macOS 13 (deployment target); tested on macOS 27 only.

<!-- sp:signing -->
## Signing limitations

The app is ad-hoc signed by `scripts/build-app.sh` and is not notarized. It is meant for local use on the machine that built it. Developer ID signing, notarization and automatic updates are future scope.

<!-- sp:known-limitations -->
## Known limitations

- Apps with an embedded browser, and apps that open a specific browser directly, bypass Switch Profile.
- Whether a link opens in a new tab or a new window is decided by Chrome.
- Only Google Chrome is supported.
- Rules match exact hosts only; there are no wildcard or subdomain rules.

## Acceptance criteria

- All three example links open in their assigned profiles from an external app.
- Routing remains correct when a different Chrome profile is in the foreground.
- Links work when Chrome or Switch Profile was not already running.
- Other hosts open in the last active Chrome profile or the selected fallback, without re-opening Switch Profile.
- Missing or ambiguous profiles require an explicit recovery choice; no silent account substitution.
- Multiple incoming links are neither lost nor duplicated.
- Query strings and fragments are preserved; lookalike hosts and repository prefixes do not match.
- Users can restore their previous default browser.

Test status for each criterion is in the [acceptance matrix](docs/ACCEPTANCE.md).

## Development and backlog

See [the backlog](docs/BACKLOG.md) for the epic, implementation issues, priorities, dependencies, and completion criteria. Build with `swift build` and run the tests with `swift test`.

For each change: create or reuse an issue → mark **In Progress** in the GitHub Project (or use `status:in-progress` when no Project is used) → work on an issue-prefixed branch → open a linked PR → pass applicable checks → merge into `main` → mark the resolved issue **Done** and close it. PRs that fully resolve an issue use `Closes #<id>`. Implementation issues remain open until their acceptance criteria are met.

## Technical references

- [Apple: receiving URL-open events with AppKit](https://developer.apple.com/documentation/AppKit/NSApplicationDelegate/application(_:open:))
- [Chromium: user data and profile directories](https://chromium.googlesource.com/chromium/src/+/HEAD/docs/user_data_dir.md)
