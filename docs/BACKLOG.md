# Switch Profile demo backlog

[English](../README.md) · [Tiếng Việt](../README.vi.md) · [简体中文](../README.zh-CN.md)

GitHub issues are the source of truth for current status and acceptance criteria. This document records the initial delivery order; it is not a live status dashboard.

**Epic:** [#1 — Deliver the macOS Switch Profile demo](https://github.com/khuepm/switch-profile/issues/1)

## Delivery backlog

P0 means required for correct routing or its verification. P1 means required for a usable, distributable local demo, after the routing foundation.

| Issue | Deliverable | Priority | Depends on |
| --- | --- | --- | --- |
| [#2](https://github.com/khuepm/switch-profile/issues/2) | Repository setup, English/Vietnamese/Simplified Chinese READMEs, epic and backlog | P0 | — |
| [#3](https://github.com/khuepm/switch-profile/issues/3) | Discover existing Chrome profiles and validate display-name/email-to-directory mappings | P0 | #2 |
| [#4](https://github.com/khuepm/switch-profile/issues/4) | Receive HTTP/HTTPS URLs through the macOS default-browser mechanism | P0 | #2 |
| [#5](https://github.com/khuepm/switch-profile/issues/5) | Ordered repository/domain rules, explicit fallback and invalid-input handling | P0 | #2, #3 |
| [#6](https://github.com/khuepm/switch-profile/issues/6) | Reliably launch URLs in the selected Chrome profile | P0 | #2, #3, #5 |
| [#7](https://github.com/khuepm/switch-profile/issues/7) | Menu-bar settings, profile selectors and routing preview | P1 | #2, #3, #4, #5, #6 |
| [#8](https://github.com/khuepm/switch-profile/issues/8) | Automated routing tests and macOS end-to-end acceptance matrix | P0 | #2, #4, #5, #6, #7 |
| [#9](https://github.com/khuepm/switch-profile/issues/9) | Local `.app` packaging and setup/removal instructions | P1 | #2, #7, #8 |

## Rule contract

Items 2–4 are the default rules (R1–R3). Since [#14](https://github.com/khuepm/switch-profile/issues/14) users can add, edit, delete and reorder rules in Settings (exact host, or host plus path prefix on whole segments); the defaults are restored by "Reset to defaults…".

1. Accept HTTP/HTTPS URLs and match their parsed hostname.
2. On `github.com`, match owner `TruckerPoints` and repository `trucker-points` as complete path segments, case-insensitively. Route the repository root and descendants to `khue@truckerpoints.ai` before considering the general GitHub rule.
3. Route every path on exact host `git.fis.vn` to `khuepm18`.
4. Route remaining links on exact host `github.com` to `pmkhue.2013`.
5. Route other hosts to the explicitly configured fallback profile, or by default to Chrome's last active profile (launched without `--profile-directory`, #13).
6. Preserve the original URL, including query and fragment; matching normalization must not rewrite the forwarded URL.
7. Never silently substitute an account, create a missing profile, or send fallback URLs back through the system default-browser handler.

Negative examples include `github.com.example.org`, URLs containing `github.com` only in their query, and `/TruckerPoints/trucker-points-other`. These must not trigger the specific GitHub rule.

## Demo completion

- The three README acceptance links open in the assigned profiles from an external app.
- Correct routing is demonstrated with Chrome closed, running, and showing a different profile in the foreground, and with Switch Profile initially closed.
- Missing/ambiguous profiles and an unset fallback have explicit recovery paths.
- Batched incoming links are not lost or duplicated.
- Automated tests cover precedence, hostname/path boundaries, casing, unsupported schemes, query preservation and fragment preservation.
- Manual results record the macOS and Chrome versions, window/tab behavior and any limitations.
- A local `.app` and accurate install, default-browser setup, restore and removal instructions are available.

Automated and manual results are tracked in the [acceptance matrix](ACCEPTANCE.md).

## Delivery workflow

Use the issue's GitHub Project status when applicable. This repository was initialized without a Project, so status labels are used: `status:in-progress` while working, then `status:done` after verification and merge. Use an issue-prefixed branch and PR title; link the issue in the PR and use `Closes #<id>` only when it is fully resolved. Merge into `main` after required checks pass.

Completing the documentation setup closes only #2. The epic and implementation issues stay open until their deliverables and acceptance criteria are complete.

## Follow-up scope

Additional browsers, organization-wide rules, signing/notarization for wider distribution and automatic updates are outside the first local demo. Rule editing for exact hosts and host plus path prefix shipped in #14; wildcard and subdomain matching remain out of scope. The initial 2–3 developer-day estimate is provisional until profile-launch behavior has been verified.
