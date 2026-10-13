# Switch Profile

[English](README.md) · [Tiếng Việt](README.vi.md) · [简体中文](README.zh-CN.md)

A small macOS utility that routes links opened from other apps to the right Google Chrome profile.

**Status: planning and repository setup.** This repository currently contains documentation and a development backlog. There is no runnable app or downloadable release yet. Google Chrome is the initial target browser.

## How it will work

`Click a link in another app → macOS → Switch Profile → matching rule → Chrome profile`

Set Switch Profile as the default web browser once. It will receive HTTP/HTTPS links handed to the system default browser, choose a profile, and forward the original URL to Chrome. Apps using an embedded browser or explicitly opening another browser may bypass this flow.

The planned app runs in the menu bar and processes routing locally. It needs no backend or GitHub/GitLab API. Repository access uses the existing login session of the selected Chrome profile.

## Demo rules

Rules are evaluated from specific repository matches to general domain matches.

| Match | Chrome profile | Acceptance link |
| --- | --- | --- |
| Exact host `git.fis.vn`, any path | `khuepm18` | [GitLab merge requests](https://git.fis.vn/fis-gs/gs-hn/BTP_CPLQG_S7_2025_PM/plvn-v2-backend/-/merge_requests) |
| Host `github.com`, repository `/TruckerPoints/trucker-points` and its descendants | `khue@truckerpoints.ai` | [trucker-points](https://github.com/TruckerPoints/trucker-points) |
| Other links on exact host `github.com` | `pmkhue.2013` | [LumiBase](https://github.com/khuepm/LumiBase) |
| Other hosts | User-selected fallback profile | Any unrelated website |

The repository rule includes paths such as `/issues` and `/pull/123`, but must not match `/TruckerPoints/trucker-points-other`. Host matching must use the parsed hostname, not a substring search. Routing preserves the original path, query, and fragment.

## Planned demo interface

- Default-browser status and setup instructions.
- Detected Chrome profiles and profile selection for each rule.
- A fallback profile selector.
- A URL input with **Check rule** and **Open test link** actions.
- Clear recovery options when a configured profile is missing.

Profile display names and email addresses are not necessarily directory names. The app must map them to actual existing profile directories such as `Default` or `Profile 2`, without guessing, modifying login data, or silently creating a new profile.

## Implementation plan

1. Verify launching each of the three profiles with Chrome running and closed.
2. Build a native macOS AppKit app that receives HTTP/HTTPS URL-open events.
3. Implement deterministic repository/domain rules, fallback routing, and loop prevention.
4. Add menu-bar access, settings, profile mapping, and a routing preview.
5. Test end-to-end routing and package a local `.app` demo with setup and uninstall instructions.

The target is a new tab in a window of the correct profile, or a new window when needed. Window reuse must be verified against the installed Chrome version. The proposed demo effort is 2–3 developer days, subject to the launch experiment; signing, notarization, and automatic updates are follow-up work.

## Acceptance criteria

- All three example links open in their assigned profiles from an external app.
- Routing remains correct when a different Chrome profile is in the foreground.
- Links work when Chrome or Switch Profile was not already running.
- Other hosts use the explicitly selected fallback without recursively reopening Switch Profile.
- Missing or ambiguous profiles require an explicit recovery choice; no silent account substitution.
- Multiple incoming links are neither lost nor duplicated.
- Query strings and fragments are preserved; lookalike hosts and repository prefixes do not match.
- Users can restore their previous default browser.

## Development and backlog

See [the backlog](docs/BACKLOG.md) for the epic, implementation issues, priorities, dependencies, and completion criteria. Build and installation commands will be added when a runnable implementation exists.

For each change: create or reuse an issue → mark **In Progress** in the GitHub Project (or use `status:in-progress` when no Project is used) → work on an issue-prefixed branch → open a linked PR → pass applicable checks → merge into `main` → mark the resolved issue **Done** and close it. PRs that fully resolve an issue use `Closes #<id>`. Implementation issues remain open until their acceptance criteria are met.

## Technical references

- [Apple: receiving URL-open events with AppKit](https://developer.apple.com/documentation/AppKit/NSApplicationDelegate/application(_:open:))
- [Chromium: user data and profile directories](https://chromium.googlesource.com/chromium/src/+/HEAD/docs/user_data_dir.md)
