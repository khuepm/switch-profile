# Switch Profile acceptance matrix

[Backlog](BACKLOG.md) · [English README](../README.md) · [Tiếng Việt](../README.vi.md) · [简体中文](../README.zh-CN.md)

This document tracks acceptance criteria AC-1 to AC-40 for epic [#1](https://github.com/khuepm/switch-profile/issues/1). A criterion is `automated-pass` only when a test or a recorded script run proves it. Everything that needs a person at the Mac is `manual-pending` until someone observes it and fills in the results. Results are recorded from real observations only.

## Environment

| Item | Value |
| --- | --- |
| macOS | 27.0.1 (26A434), arm64 |
| Google Chrome | 155.0.8059.40, `/Applications/Google Chrome.app` |
| Switch Profile | 0.1.0 (1), ad-hoc signed |
| Supported systems | minimum macOS 13 (deployment target); tested on macOS 27 only |
| Toolchain | Swift 6.4, Command Line Tools only (no Xcode) |
| Date | 2026-10-13 |

Environment note (macOS 27 App Data protection): when `SwitchProfile.app` is started through LaunchServices, macOS denied it read access to Chrome's `Local State` (tccd: `kTCCServiceSystemPolicyAppDataDetailed ... returning denied`). The app then reports "Chrome profiles unavailable" and keeps every link pending. The `--dry-run` command is not affected, because it runs with the terminal's access. Before the manual rows below, grant Switch Profile access in System Settings → Privacy & Security (App Data or Full Disk Access), then check the result in row P-1. Until P-1 passes, AC-25 to AC-36 and AC-40 cannot be run.

## Acceptance criteria

Suites are in `Tests/SwitchProfileCoreTests/`. `Suite.test` names a swift-testing function; parameterized tests are written with `(_:)`.

| AC | Criterion | Status | Evidence or manual steps |
| --- | --- | --- | --- |
| AC-1 | The git.fis.vn merge-requests URL → R1 → the profile mapped to `khuepm18` | automated-pass | `URLClassifierTests.matchesR1(_:)`; `RouterTests.readmeSamplesRouteToTheirBoundDirectories`; `ProfileResolverTests.displayNameAndLocalPartIsUniqueByDisplayName`; `ConfigSeederTests.uniqueIdentitiesBecomeAutoDetectedBindings` |
| AC-2 | `https://github.com/TruckerPoints/trucker-points` → R2 | automated-pass | `URLClassifierTests.matchesR2(_:)`; `RouterTests.readmeSamplesRouteToTheirBoundDirectories` |
| AC-3 | `/pull/1`, `/issues`, `/pull/123` under the repository → R2 | automated-pass | `URLClassifierTests.matchesR2(_:)` (all three vectors) |
| AC-4 | `https://github.com/truckerpoints/TRUCKER-POINTS/pull/1` → R2 | automated-pass | `URLClassifierTests.matchesR2(_:)` |
| AC-5 | `.../TruckerPoints/trucker-points-other` → R3, not R2 | automated-pass | `URLClassifierTests.matchesR3(_:)`; `RouterTests.siblingRepositoryGoesToR3`; `RouterTests.r2TakesPrecedenceOverR3` |
| AC-6 | `https://github.com/TruckerPoints` (owner page) → R3 | automated-pass | `URLClassifierTests.matchesR3(_:)` |
| AC-7 | `https://github.com/khuepm/LumiBase` → R3 → the profile mapped to `pmkhue.2013` | automated-pass | `URLClassifierTests.matchesR3(_:)`; `RouterTests.readmeSamplesRouteToTheirBoundDirectories`; `ProfileResolverTests.localPartIsUniqueByLocalPart` |
| AC-8 | `https://github.com.example.org/TruckerPoints/trucker-points` → R4 | automated-pass | `URLClassifierTests.matchesR4(_:)` |
| AC-9 | `https://example.com/?u=https://github.com/TruckerPoints/trucker-points` → R4 | automated-pass | `URLClassifierTests.matchesR4(_:)` |
| AC-10 | `https://git.fis.vn.example.org/` and `https://notgithub.com/` → R4 | automated-pass | `URLClassifierTests.matchesR4(_:)` |
| AC-11 | The URL passed to the launcher equals the received URL, query and fragment included | automated-pass | `RouterTests.forwardedURLIsTheReceivedAbsoluteString(_:)` (every accepted vector, through `ChromeLauncher.makeRequest`); `RouterTests.queryAndFragmentAreForwardedLiterally`; `RouterTests.launchCarriesTheOriginalURLObject`; `URLClassifierTests.classificationNeverAltersTheURL` |
| AC-12 | No fallback configured: an R4 URL gives an "unset fallback" decision, not a launch | automated-pass | `RouterTests.unsetFallbackNeedsProfile`; `RouterTests.unsetRuleNeverFallsBack` |
| AC-13 | A rule whose profile is missing gives "missing profile", no launch elsewhere, no fallback launch | automated-pass | `RouterTests.missingDirectoryNeverLaunchesEvenWithFallbackBound` |
| AC-14 | `ftp:`, `file:`, `mailto:`, `javascript:` are rejected and never launch | automated-pass | `URLClassifierTests.rejectsUnsupportedScheme(_:_:)`; `RouterTests.rejectedNeverLaunches(_:)`; `RouterTests.rejectionWinsOverUnavailableConfig` |
| AC-15 | Rule evaluation runs without AppKit, Chrome or file access | automated-pass | `URLClassifierTests` and `RouterTests` run on in-memory values only; `SourceInvariantTests.coreImportsNoUIFramework` |
| AC-16 | An identity matching exactly one profile resolves to its directory | automated-pass | `ProfileResolverTests.displayNameAndLocalPartIsUniqueByDisplayName`, `fullEmailIsUniqueByEmail`, `localPartIsUniqueByLocalPart`, `caseAndWhitespaceInsensitive(_:)` |
| AC-17 | An identity matching two profiles is ambiguous and returns no directory | automated-pass | `ProfileResolverTests.duplicateEmailIsAmbiguousAndSorted`; `ProfileResolverTests.unionOfNameAndLocalPartAcrossProfilesIsAmbiguous`; `ConfigSeederTests.ambiguousAndNotFoundStayNil` |
| AC-18 | An identity matching nothing is reported missing | automated-pass | `ProfileResolverTests.notFound(_:)` |
| AC-19 | Absent or malformed `Local State` gives a typed error, not a crash or an empty list | automated-pass | `LocalStateLoaderTests.nonexistentPathIsNotFound`, `unreadableFileIsUnreadable`, `truncatedFileIsMalformed`, `missingProfileSectionIsMalformed`, `wrongInfoCacheTypeIsMalformed`, `emptyInfoCacheIsNoProfiles`, `onlyInvalidKeysIsNoProfiles` |
| AC-20 | The resolver reads no file other than `Local State` | automated-pass | API: `LocalStateLoader.load(from:)` takes one path and `ProfileResolver` works on an in-memory `ProfileCatalog`; `SourceInvariantTests.chromePathsAreConfined` |
| AC-21 | The profile directory and URL are separate argv elements; no shell | automated-pass | `ChromeLauncherTests.requestIsExactlyTwoArguments`; `ChromeLauncherTests.directoryWithSpacesStaysOneElement`; `SourceInvariantTests.noForbiddenCall(_:)` (`Process(`, `/bin/sh`, `/bin/zsh`, `/usr/bin/open`) |
| AC-22 | The launcher always targets Google Chrome and never the "open with default handler" path | automated-pass | `ChromeLauncherTests.loopGuardNeverCallsTheOpener(_:_:)`; `ChromeLauncherTests.missingChromeIsNotInstalled`; `SourceInvariantTests.noForbiddenCall(_:)` (`NSWorkspace.shared.open(`, `.open(urls`, `withApplicationAt`, `LSOpenCFURLRef`); `SourceInvariantTests.chromeLauncherIsConfined` |
| AC-23 | A burst of N ≥ 5 URLs (one event and separate events) gives exactly N launches, in order | automated-pass | `RoutingCoordinatorTests.burstOfSixPlusSixOpensTwelveInSeqOrder`; `sameURLTwiceOpensTwice`; `urlsBeforeMarkReadyAreBufferedThenLaunched`; `batchRuleLoadsTheCatalogOncePerBatch` |
| AC-24 | A Chrome launch failure is surfaced and the URL is not silently dropped | automated-pass | `RoutingCoordinatorTests.launchFailureBecomesPendingAndLaterURLsStillLaunch`; `retryOfAFailedLaunchThatFailsAgain`; `ChromeLauncherTests.openerErrorBecomesOpenFailed`, `missingChromeIsNotInstalled`. The on-screen pending window is checked in matrix row M-PEND-1. |
| AC-25 | After the build script, macOS lists Switch Profile as a default-browser choice | manual-pending | Run `scripts/build-app.sh --install`. Open System Settings → Desktop & Dock → Default web browser and check that "Switch Profile" is listed. Packaging evidence so far: `Info.plist` declares `http`/`https` (`plutil -p` in the build log). |
| AC-26 | The in-app status shows default / not default for http and https | manual-pending | Open Settings. With Chrome as default, the status reads not default. After AC-27, it reads Switch Profile for both schemes. Also check "Another copy at … is the default" with a second copy registered. |
| AC-27 | Set-as-default runs only on user action and makes Switch Profile the handler for both schemes | manual-pending | Press "Set as default browser…" in Settings (or the menu item). Answer the macOS prompt. Fill in rows D-1 to D-3. |
| AC-28 | The documented restore steps bring back the previous default browser | manual-pending | Press "Restore previous default (…)…" in Settings, or pick the old browser in System Settings → Desktop & Dock → Default web browser. Check that both schemes go back to the old browser. |
| AC-29 | The menu bar icon opens a menu with Settings; Settings lists detected profiles | manual-pending | Click the menu bar icon and choose "Settings…". The header shows "N profiles found in Chrome Local State" and each rule's Picker lists them. Logic tests: `LocalStateLoaderTests.validFixtureProducesSortedCatalog`; `ConfigValidatorTests.statusCoversEveryCase`. |
| AC-30 | Mappings for R1–R3 and the fallback persist across quit and relaunch | manual-pending | Map all four rules, quit from the menu, relaunch, and check that Settings shows the same profiles (row S-6). Logic tests: `ConfigStoreTests.roundTrip`; `ConfigControllerTests.updateBeforeSeedingPersistsSeedPending`. |
| AC-31 | On launch, a mapping to a profile that no longer exists is an actionable error | manual-pending | Rows S-1 to S-4. Logic tests: `ConfigValidatorTests.needsAttentionCountsOnlyBrokenBindings`; `RouterTests.missingDirectoryNeverLaunchesEvenWithFallbackBound`; `RoutingCoordinatorTests.tM2_updateBindingReroutesAllPendingLinksOfTheRuleInSeqOrder`, `tM3_updateBindingToNilReroutesNothing`, `tM4_failedUpdateBindingReroutesNothing`, `openAndRememberSavesLaunchesAndReroutesTheSameRule`. |
| AC-32 | "Check rule" shows rule and profile without opening Chrome; "Open test link" uses the real routing path | manual-pending | In Settings, type each sample URL and press "Check rule": no Chrome window appears. Press "Open test link": the link opens in the expected profile. Logic tests: `ConfigValidatorTests.agreesWithRouter(_:)`; `RoutingCoordinatorTests.tM5_loadCatalogReroutesCatalogUnavailableItems` (the preview load uses `reroutingBlocked: false`); `SourceInvariantTests.dryRunIsSynchronousAndReadOnly(_:)`. |
| AC-33 | Each sample URL from an external app opens in the right profile with Chrome closed / running same profile / running other profile frontmost, and with Switch Profile not running | manual-pending | Matrix rows M-1 to M-36. Gate: the launch experiment below must show that `--profile-directory` is honored while Chrome is running. |
| AC-34 | An unrelated-host link opens in the fallback profile with no re-entry into Switch Profile | manual-pending | Rows F-1 and F-2. |
| AC-35 | A burst of links opens each link exactly once | manual-pending | Rows B-1 and B-2. |
| AC-36 | The results record macOS and Chrome versions, window/tab behavior, and embedded-browser limits without claiming them | manual-pending | Environment table above, the "Tab or window" column of the matrix, and "Known limitations" below. Pending until the matrix is filled in. |
| AC-37 | One documented command builds and signs the `.app` from a clean checkout with CLT only | automated-pass | `scripts/build-app.sh` exited 0 under CLT only: release build, `plutil -lint` OK, `codesign --sign -` then `codesign --verify --strict` passed, `codesign -dv` shows `Signature=adhoc` (Chunk C verification log). |
| AC-38 | `swift test` passes | automated-pass | `swift test`: all suites pass, `DocsParityTests` included. |
| AC-39 | All three READMEs have equivalent build/install, mapping, default-browser, troubleshooting, restore, removal, version, minimum macOS and signing sections | automated-pass | `DocsParityTests` checks that `README.md`, `README.vi.md` and `README.zh-CN.md` each contain the ten `<!-- sp:… -->` section markers exactly once, in the same order. |
| AC-40 | The matrix (AC-33 to AC-35) was run against the packaged `.app` | manual-pending | Run every matrix row against `~/Applications/SwitchProfile.app` installed by `scripts/build-app.sh --install`. |

## Prerequisite (manual-pending)

| Row | Check | Expected | Observed | Pass |
| --- | --- | --- | --- | --- |
| P-1 | Grant Switch Profile App Data / Full Disk Access, relaunch it, open Settings | "N profiles found in Chrome Local State"; no "Chrome profiles unavailable" | | |

## Launch experiment (manual-pending)

This checks the assumption the launcher rests on: `--profile-directory` selects the profile even when Chrome is already running. It opens windows in real Chrome profiles, so a person runs it. The commands are the CLI form of what the app does:

```sh
open -na "Google Chrome" --args --profile-directory="Profile 30" "https://git.fis.vn/fis-gs/gs-hn/BTP_CPLQG_S7_2025_PM/plvn-v2-backend/-/merge_requests"
open -na "Google Chrome" --args --profile-directory="Profile 47" "https://github.com/TruckerPoints/trucker-points"
open -na "Google Chrome" --args --profile-directory="Default" "https://github.com/khuepm/LumiBase"
```

The directories are the ones the dry run resolved on the test Mac. Use the directories your own Settings or `--dry-run` shows.

| Profile directory | Chrome state | Observed profile | Picker appeared | Tab or window | Pass |
| --- | --- | --- | --- | --- | --- |
| Profile 30 | closed | | | | |
| Profile 30 | running, same profile frontmost | | | | |
| Profile 30 | running, other profile frontmost | | | | |
| Profile 47 | closed | | | | |
| Profile 47 | running, same profile frontmost | | | | |
| Profile 47 | running, other profile frontmost | | | | |
| Default | closed | | | | |
| Default | running, same profile frontmost | | | | |
| Default | running, other profile frontmost | | | | |
| Any | cold start with the profile picker enabled at startup | | | | |

Gate: if `--profile-directory` is ignored while Chrome is running, the launch design must be revisited before AC-33 is claimed.

## Dry-run evidence (automated)

`build/SwitchProfile.app/Contents/MacOS/SwitchProfile --dry-run` runs the real router and `ChromeLauncher.makeRequest` and prints the request without opening or writing anything. It was run with `--assume-chrome running`, `--assume-chrome closed` and with detected state (Chrome running), using the real `Local State` (33 profiles) and the in-memory seed (no config file). The three runs differ only in the `chrome-state` line. Each exited 0.

| URL | Decision | argv |
| --- | --- | --- |
| `https://git.fis.vn/fis-gs/gs-hn/BTP_CPLQG_S7_2025_PM/plvn-v2-backend/-/merge_requests` | R1, `Profile 30` | `["--profile-directory=Profile 30","https://git.fis.vn/fis-gs/gs-hn/BTP_CPLQG_S7_2025_PM/plvn-v2-backend/-/merge_requests"]` |
| `https://github.com/TruckerPoints/trucker-points` | R2, `Profile 47` | `["--profile-directory=Profile 47","https://github.com/TruckerPoints/trucker-points"]` |
| `https://github.com/khuepm/LumiBase` | R3, `Default` | `["--profile-directory=Default","https://github.com/khuepm/LumiBase"]` |

Application in every case: `/Applications/Google Chrome.app`. After the runs, `~/Library/Application Support/SwitchProfile` still did not exist.

## Manual matrix (manual-pending)

Run against `~/Applications/SwitchProfile.app` (from `scripts/build-app.sh --install`) with Switch Profile set as the default browser. "Terminal" means `open '<url>'`; "Link" means clicking the link in a TextEdit rich-text document or a Note. Chrome states: closed; running with the target profile frontmost; running with a different profile frontmost.

### Sample URLs (AC-33, AC-40)

URL 1 = git.fis.vn merge requests (R1), URL 2 = trucker-points (R2), URL 3 = LumiBase (R3).

| Row | URL | Chrome | Switch Profile | Source | Expected profile | Observed profile | Tab or window | Pass | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| M-1 | 1 | closed | running | Terminal | R1 profile | | | | |
| M-2 | 1 | closed | running | Link | R1 profile | | | | |
| M-3 | 1 | closed | not running | Terminal | R1 profile | | | | |
| M-4 | 1 | closed | not running | Link | R1 profile | | | | |
| M-5 | 1 | same profile | running | Terminal | R1 profile | | | | |
| M-6 | 1 | same profile | running | Link | R1 profile | | | | |
| M-7 | 1 | same profile | not running | Terminal | R1 profile | | | | |
| M-8 | 1 | same profile | not running | Link | R1 profile | | | | |
| M-9 | 1 | other profile | running | Terminal | R1 profile | | | | |
| M-10 | 1 | other profile | running | Link | R1 profile | | | | |
| M-11 | 1 | other profile | not running | Terminal | R1 profile | | | | |
| M-12 | 1 | other profile | not running | Link | R1 profile | | | | |
| M-13 | 2 | closed | running | Terminal | R2 profile | | | | |
| M-14 | 2 | closed | running | Link | R2 profile | | | | |
| M-15 | 2 | closed | not running | Terminal | R2 profile | | | | |
| M-16 | 2 | closed | not running | Link | R2 profile | | | | |
| M-17 | 2 | same profile | running | Terminal | R2 profile | | | | |
| M-18 | 2 | same profile | running | Link | R2 profile | | | | |
| M-19 | 2 | same profile | not running | Terminal | R2 profile | | | | |
| M-20 | 2 | same profile | not running | Link | R2 profile | | | | |
| M-21 | 2 | other profile | running | Terminal | R2 profile | | | | |
| M-22 | 2 | other profile | running | Link | R2 profile | | | | |
| M-23 | 2 | other profile | not running | Terminal | R2 profile | | | | |
| M-24 | 2 | other profile | not running | Link | R2 profile | | | | |
| M-25 | 3 | closed | running | Terminal | R3 profile | | | | |
| M-26 | 3 | closed | running | Link | R3 profile | | | | |
| M-27 | 3 | closed | not running | Terminal | R3 profile | | | | |
| M-28 | 3 | closed | not running | Link | R3 profile | | | | |
| M-29 | 3 | same profile | running | Terminal | R3 profile | | | | |
| M-30 | 3 | same profile | running | Link | R3 profile | | | | |
| M-31 | 3 | same profile | not running | Terminal | R3 profile | | | | |
| M-32 | 3 | same profile | not running | Link | R3 profile | | | | |
| M-33 | 3 | other profile | running | Terminal | R3 profile | | | | |
| M-34 | 3 | other profile | running | Link | R3 profile | | | | |
| M-35 | 3 | other profile | not running | Terminal | R3 profile | | | | |
| M-36 | 3 | other profile | not running | Link | R3 profile | | | | |

### Burst (AC-35)

`open url1 … url6`, mixing rules (for example URL 1, 2, 3, then 1, 2, 3 with different paths).

| Row | Chrome | Expected | Observed (opened once each, right profiles) | Tab order per profile | Pass |
| --- | --- | --- | --- | --- | --- |
| B-1 | closed | 6 links, each once, in its rule's profile | | | |
| B-2 | running | 6 links, each once, in its rule's profile | | | |

### Fallback (AC-34)

| Row | Setup | Action | Expected | Observed | Pass |
| --- | --- | --- | --- | --- | --- |
| F-1 | Fallback set in Settings | `open 'https://example.com/'` | Opens in the fallback profile; Switch Profile is not re-entered (Recent shows one entry) | | |
| F-2 | Fallback "Not set" | `open 'https://example.com/'` | Pending links window appears; nothing opens; no re-entry | | |

### Default browser (AC-25 to AC-28)

| Row | Check | Expected | Observed | Pass |
| --- | --- | --- | --- | --- |
| D-1 | Press "Set as default browser…" | macOS asks for confirmation; Switch Profile becomes the handler for `http` and `https` | | |
| D-2 | One dialog for both schemes? | Record yes or no | | |
| D-3 | Did the set call return before or after the dialog was answered? | Record before or after ("Waiting for macOS confirmation…" shown meanwhile) | | |
| D-4 | Restore previous default | The browser recorded at set time is the handler again for both schemes | | |

### Pending links

| Row | Action | Expected | Observed | Pass |
| --- | --- | --- | --- | --- |
| M-PEND-1 | Produce a pending link with F-2 or S-3 and inspect the pending window | Window titled "Switch Profile – Pending Links" shows the link, its rule and the reason, with Open once / Retry / Discard as applicable | | |

### Missing profile (AC-31)

Setup: bind R3 to a directory in Settings, quit, edit `~/Library/Application Support/SwitchProfile/config.json` so R3's `directory` names a profile that does not exist, relaunch, and open no URL.

| Row | Step | Expected | Observed | Pass |
| --- | --- | --- | --- | --- |
| S-1 | Look at the menu bar | The icon shows attention; the menu has "Profile mapping needs attention (R3)…" | | |
| S-2 | Choose that item | Settings opens; the R3 row is flagged and the Picker shows "<dir> (missing)", not a blank | | |
| S-3 | Open an R3 link | The pending links window appears with the link | | |
| S-4 | Choose a profile, either "Open and use" in the window or the R3 Picker in Settings | The link opens; the row turns ✓; the attention item disappears | | |
| S-5 | Repeat S-3 with two R3 links, then fix the mapping in Settings | Both pending R3 links open, in the order received | | |

Note on "Refresh profiles": in the pending window, "Refresh profiles" reloads Chrome's profiles. Once they load, links that were waiting only because profiles were unavailable are re-routed and open if their rule is bound. So are unset links whose rule now has a binding, for example one that first-run auto-detect just seeded. Links that come back as unset or missing still need "Open once" or "Open and use". Fixing a rule in Settings also opens that rule's pending links.

### Other scenarios

| Row | Scenario | Steps | Expected | Observed | Pass |
| --- | --- | --- | --- | --- | --- |
| S-6 | Persistence (AC-30) | Map R1 to R4, quit, relaunch | Same mappings shown | | |
| S-7a | Chrome data unavailable, R3 already bound (`config.json` exists) | Bind R3 in Settings first. Quit Chrome completely. Back up `Local State`, rename it to `Local State.off`, and do not start Chrome while it is renamed. Open an R3 link. Rename the file back and press Retry. Repeat, using "Refresh profiles" instead of Retry | Pending as "Chrome profiles unavailable", Picker disabled, Retry shown; after Retry or Refresh the link opens in the bound profile | | |
| S-7b | Genuine first run without Chrome data (no `config.json`) | Quit Switch Profile. Back up and delete `config.json`. Quit Chrome completely, rename `Local State` to `Local State.off`, and do not start Chrome while it is renamed. Launch Switch Profile and open an R3 link. Rename the file back and press "Refresh profiles" | Pending as "No profile is set for R3" (seeding could not run), Picker disabled, Retry hidden; after Refresh, seeding binds R3 and the link opens automatically in the seeded profile without "Open once" or "Open and use" | | |
| S-8 | Identity mismatch | Set R1's `binding.email` in `config.json` to `other@example.com`, relaunch | The row says the profile was bound to other@example.com and is now another account; the Picker shows "<dir> (account changed)"; "Use '<name>' (now <email>)" rewrites the binding and the row turns ✓ | | |
| S-9 | First-run auto-detect | Delete `config.json`, relaunch | Seeded rows show "Auto-detected: matched by …"; "Confirm" clears the note | | |
| S-10 | Corrupt config | Write `{` to `config.json`, relaunch | Menu shows "Configuration error – Reset to defaults…"; Settings rows are disabled with the Reset hint; the pending window has no "Open and use"; after quitting, the file is still `{` | | |

## Known limitations

- Apps with an embedded browser, and apps that open a specific browser directly, never hand the link to the default browser. They bypass Switch Profile. These cases are not claimed.
- Hosts are matched exactly. `www.github.com`, `api.github.com`, `gist.github.com` and subdomains of `git.fis.vn` go to the fallback rule.
- Whether a link opens as a tab or a new window is Chrome's choice. It is recorded as observed, not guaranteed.
- Switch Profile sees only whether Chrome accepted the launch request. A failure inside Chrome after that (for example a profile that fails to load) is not observable.
- The app is ad-hoc signed and not notarized, so Gatekeeper may ask for confirmation on first open.
- On macOS 27, reading Chrome's `Local State` needs App Data or Full Disk Access for Switch Profile (see the environment note).
