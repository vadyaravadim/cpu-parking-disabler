# CPU Parking Disabler

Maintainer notes for Claude Code and the maintainer. Contributors start with [CONTRIBUTING.md](https://github.com/vadyaravadim/.github/blob/main/CONTRIBUTING.md); `rigpolice`, named below, is the maintainer's private website repository.

A single self-contained PowerShell script (`cpu-parking-disabler.ps1`) that disables CPU core parking
(`CPMINCORES` / `CPMINCORES1` = 100) and pins Energy Performance Preference (`PERFEPP` / `PERFEPP1` = 0) on
the active power scheme, for AC and DC. `-Status` shows the parked-core count and the four values without
changing anything; `-Undo` restores the per-run `parking_undo_<stamp>.json` snapshot. Part of a family of
six single-script Windows tuning tools that share this layout: one `.ps1`, `Run.bat`,
`PSScriptAnalyzerSettings.psd1`, and two thin workflows, `ci.yml` and `release.yml`, that call the family's
shared pipeline in `vadyaravadim/latency-toolbox-ci`.

**The registry unhide must stay BEFORE the `powercfg` writes, on apply AND on undo.** The four settings are
hidden by default, and a hidden processor setting can be ignored by the OS even after `powercfg` writes a
value - `Show-PowerSetting` (`Attributes = 0`) first is what makes the write take effect, not cosmetics. Undo
repeats it because a major Windows update can hide the settings again. Reads go through `/qh`, not `/q`, so
`-Status` sees hidden settings without touching the registry.

**A Class 1 setting existing says nothing about the CPU.** Windows ships the power-efficiency-class
settings with the OS, not per CPU: this 2-class i9-14900F also lists the Class 2 ones (`PERFEPP2`, ...),
written by an OS update. So `CPMINCORES1` / `PERFEPP1` show up on AMD and older Intel too, where Windows
ignores them and writing them is harmless. 1.2.0 and 1.2.1 printed `hybrid P+E` from their presence -
never infer hybrid that way. A setting `powercfg` does not know still makes `Get-PowerSettingValue`
return `$null` and drops the row; keep that silent, no "setting not found" warning.

## Invariants the undo file depends on

- **A run that changes nothing writes NO undo file.** A repeat run would otherwise snapshot the
  already-tweaked values as "previous", and the next `-Undo` would restore the tweak instead of the
  original. Files are per-run snapshots applied newest-to-oldest; only the oldest holds the original state.
- **`-Undo` writes to the scheme GUID recorded in the file, not `SCHEME_CURRENT`.** The user may have
  switched schemes since; restoring Balanced's old values into High performance would be the wrong fix.
- **`-Undo` deletes a value that had no explicit user value before the run (`UserAC`/`UserDC`), never
  writes the effective one back: a written value freezes Windows' provisioning default.** The flags come from
  `ACSettingIndex`/`DCSettingIndex` under `Power\User\PowerSchemes`; an undo file without them (1.3.0) is
  written back as before.
- **The run sits under `$MyInvocation.InvocationName -ne '.'`; tests dot-source the functions.** The
  `irm | iex` bootstrap stays above the helpers, so a piped run defines nothing beyond it in the caller's
  session. One test runs the whole script on a copy in `TestDrive` (the X3D prompt order): `powercfg` is a
  stub on `PATH`, CIM and host prompts are mocked, it runs only elevated, and its `BeforeAll` first proves the
  mocks reach a script started with `&`.
- **A piped run saves the script into the user profile, not `%TEMP%`.** The undo file is written next to
  the script, so it has to sit somewhere that survives automatic temp cleanup.
- **`Get-ForwardedSwitchList` is the ONE place mode switches are listed.** Both relaunch paths - the
  `irm | iex` bootstrap rerun and the UAC elevation - build their argument list from it, so neither can
  silently drop `-Status` or `-Undo`. Splat it as `@(...)`: a single forwarded switch unrolls to a scalar
  string, and splatting it breaks `powershell.exe -File` switch binding under 5.1 and pwsh 7 alike.

## powercfg and locale gotchas

- **Every `powercfg` call goes through `Invoke-Powercfg` and checks `Ok`.** `powercfg` reports failure by
  exit code only; the 1.1.x script piped `-export` to `Out-Null` and printed "Backup saved" over a failed
  export. `Invoke-Powercfg` runs with `$ErrorActionPreference = 'Continue'` on purpose: under Windows
  PowerShell 5.1 (which the elevated relaunch always is) a stderr line captured with `2>&1` becomes a
  terminating error while the preference is `Stop`, and the absent-Class-1 query would trip the `trap`.
- **Never match `powercfg` labels.** "Current AC Power Setting Index" is localized on non-English Windows;
  the 1.1.x script matched it and showed nothing on Russian builds. The last two hex values of a setting
  block are AC then DC on every locale, and the scheme name is whatever sits in the trailing parentheses.
- **Parked cores come from the `Win32_PerfFormattedData_Counters_ProcessorInformation` CIM class**, never
  from `Get-Counter '\Processor Information(*)\Parking Status'` - that path is localized, the class name is not.
  `bench/parking-bench.ps1` samples every 250 ms, so it opens the same counter through `PdhAddEnglishCounter`
  (one path per instance name taken from the class; a wildcard would not expand). `$null` (counters disabled
  or corrupt) renders as "unavailable", never as 0.
- **`parking-bench.ps1` opts its own process out of power throttling (`SetHighQos`) and records the CPU each
  burst thread ran on.** Without it a background burst can measure Windows QoS instead of parking: in the
  2026-11-04 series every burst after the first game of a boot did ~11 core-equivalents instead of ~25 in
  every power state. `coreClass` in the result shows where the threads actually ran.
- **`Get-X3DParkingNote` owns the X3D rule: a 12+ core X3D with V-Cache on one CCD gets the prompt, an X3D2
  a note only, a single-CCD part nothing.** In Game Mode AMD's chipset driver parks the CCD without V-Cache;
  the X3D2 has V-Cache on both, so unparking cannot move a game off the cache. The prompt comes after the
  "all values already at target" check: a run that will change nothing asks nothing (1.3.2 and earlier asked
  first).
- **`-Status` skips elevation on purpose** - it only reads, and a UAC prompt for a read-only check is what
  makes people stop checking. It also wins over `-Undo`: the undo branch runs only without `-Status` (1.3.2 and
  earlier reverted the newest undo file on `-Status -Undo`).

## The CI gates

The gates and the release job live in `.github/workflows/pipeline.yml` of `vadyaravadim/latency-toolbox-ci`,
not here: `ci.yml` runs it on every push and pull request, `release.yml` from a dispatch. Change a gate there.

**`main` moves only to a commit whose `ci` passed on a branch.** Its ruleset requires `ci / psanalyzer`,
`ci / ascii`, `ci / pester (5.1)` and `ci / pester (runner)` from GitHub Actions, so a commit made on `main`
is rejected. Push the branch, wait for `ci`, then merge it into `main` (`--no-ff` works while the branch is
up to date with `main`) and push; push a commit made on `main` to a branch first (`git push origin
main:<branch>`). A pin bump that renames one of these checks needs the new name in the ruleset before it is
pushed to `main`. The preview leg is not required: it only warns. Neither is `sync`: it stays red until the
second repo of a shared bench change lands, so requiring it would block that change.

- **The ASCII gate - every tracked `.ps1` must be pure ASCII with no BOM.** Both halves are load-bearing: a
  BOM makes `irm | iex` choke on a leading U+FEFF, and non-ASCII in a BOM-less file turns into mojibake when
  Windows PowerShell 5.1 runs it with `-File`. Write `\uXXXX` regex escapes rather than literals; em-dashes
  and typographic quotes are the usual way this reds. Only `.ps1` files are checked - Markdown is free.
- **The lint gate - PSScriptAnalyzer over the whole repo, Error + Warning, any finding fails.** Suppressions
  live in `PSScriptAnalyzerSettings.psd1` with the reason written next to each rule; add a justified
  exclusion there instead of an inline suppression attribute. The file is the family's: lint fails unless it
  is byte-identical to the one in `vadyaravadim/latency-toolbox-ci` at the pinned commit, so change it there
  and copy it into all six repos. Lint also fails unless `ci.yml` and `release.yml` pin `latency-toolbox-ci`
  to the full SHA of the commit the run uses. It also checks syntax and .NET types against Windows
  PowerShell 5.1 (`PSUseCompatibleSyntax`/`PSUseCompatibleTypes`). The type check knows APIs only up to .NET
  Core 3.1, so a newer one such as `[Convert]::ToHexString` passes lint and only the 5.1 test leg catches
  it. `PSUseCompatibleCommands` stays off: it flagged every Pester 5 parameter against the Pester 3.4 built
  into 5.1.
- **The Pester gate runs every tracked `*.Tests.ps1` under Windows PowerShell 5.1 and the runner's `pwsh`,
  and both legs block the release:** 5.1 is what `Run.bat` and the elevated relaunch always run, so test code
  stays 5.1-safe too - no .NET Core-only APIs, and `ConvertFrom-Json` there emits a top-level array as one
  object. A third leg on a pinned PowerShell preview (downloaded, SHA256-checked) only warns: it is
  `continue-on-error`, red without blocking. Nothing bumps that pin - move it by hand in `pipeline.yml`: to
  the final release when it ships, and once `windows-latest` itself ships that version, on to the next
  preview, or drop the leg if there is none. A repo with no test file passes the gate with a notice.

## Release - the newest CHANGELOG section is the version

`gh workflow run release.yml` (or Actions > release > Run workflow) on `main` releases the newest
`## [X.Y.Z]` section of `CHANGELOG.md`: it gates that commit, stamps the version into `.VERSION`, hashes the
script, attests build provenance, publishes to the PowerShell Gallery and, last, creates the GitHub Release,
which creates the `vX.Y.Z` tag at that commit. A run from any other branch fails in the release job before
anything is written. Nothing ships from a push to `main`, and no tag exists until every gate has passed.

- **The `irm | iex` URL is `releases/latest/download/cpu-parking-disabler.ps1` - in the README AND in the
  script's bootstrap download, never `raw.githubusercontent.com/.../main`.** That is what keeps the
  sentence above true for the one-liner, and makes the saved copy byte-identical to the attested asset.
- **`ci.yml` and `release.yml` pin `pipeline.yml` of `vadyaravadim/latency-toolbox-ci` to the same full
  commit SHA, with its version tag as a comment.** There the release job `needs:` the lint, ASCII and Pester
  jobs of the same run, on the same commit: the push-triggered `ci` runs on `main` do not block a release,
  and a PSGallery version cannot be re-published. A pipeline change reaches this repo only when the pin
  moves: Dependabot proposes the bump monthly, a hand bump changes both lines together (lint fails while
  they differ), and reverting the whole bump - including a `PSScriptAnalyzerSettings.psd1` copy it brought -
  undoes it.
- **The provenance is signed by `pipeline.yml` of `vadyaravadim/latency-toolbox-ci`, not by this repo.**
  `gh attestation verify` needs
  `--signer-workflow vadyaravadim/latency-toolbox-ci/.github/workflows/pipeline.yml` (SECURITY.md); 1.1.2 to
  1.3.2 were signed by this repo's own `release.yml`, earlier releases carry no provenance. Never rename or
  delete `latency-toolbox-ci`: GitHub does not redirect a renamed reusable workflow, so every caller breaks.
- **`v*` tags cannot be moved or deleted (tag ruleset) and releases are immutable (repo setting).** A broken
  release is fixed by releasing a new patch version (a new CHANGELOG section), never by re-tagging. The
  ruleset leaves tag creation open on purpose: the release creates the tag with `GITHUB_TOKEN`.
- **Never push a `v*` tag by hand.** It starts no release and cannot be deleted; unless it sits on the exact
  commit the release then runs on, the release stops before publishing and that version is burned.
- **A data release - bench logs, not the script - is created with `--latest=false`:** `gh release create
  bench-data-<name> --latest=false --title "Bench data: <name>" --notes "<what it holds>" <file>`. GitHub makes
  every newly published release Latest unless told otherwise, and a Latest release without
  `cpu-parking-disabler.ps1` breaks `releases/latest/download/cpu-parking-disabler.ps1` - the README one-liner
  and the script's own bootstrap - until the next script release. Afterwards
  `gh api repos/vadyaravadim/cpu-parking-disabler/releases/latest --jq .tag_name` must print the newest `v*`
  tag; if it does not, `gh release edit <that tag> --latest` puts it back (allowed on immutable releases).
- **Finish a failed release with "Re-run failed jobs" on that run, not a new run.** The re-run builds the
  same commit with the same pinned pipeline: the Gallery step (`.github/Publish-GalleryScript.ps1` of
  `vadyaravadim/latency-toolbox-ci`) skips a version already there with identical bytes and fails on
  different bytes. A run cancelled during the GitHub Release step can leave a draft - delete it before
  re-running. Release the next version instead only when that run is older than 30 days and can no longer
  be re-run. A failure inside the pipeline itself needs a fixed `latency-toolbox-ci` version, a bump here and
  a new run.

**Before releasing, move the `## [Unreleased]` bullets in `CHANGELOG.md` into a `## [X.Y.Z] - YYYY-MM-DD`
section and add its `[X.Y.Z]: .../compare/vPREV...vX.Y.Z` link at the bottom.** That section is the
version. The release job copies exactly that section into the release body and **fails before anything is
tagged or published when it is empty or its compare link is missing**; a newest section that is already
released fails the same way. This is a gate on purpose, not a fallback: notes are hand-written because
GitHub's `--generate-notes` lists merged PRs, and this repo lands nearly everything as direct commits to
`main`, so it published releases whose whole body was a compare link.

Write the entries for someone who runs the tool, not for someone reading the diff: what changed on their
machine and why it matters. A fix says what was broken and what it cost them.

Do NOT bump `.VERSION` in the `.ps1` by hand - it is a placeholder the workflow overwrites, and a
hand-edited value that disagrees with the tag would only mislead whoever reads the committed file.
**The placeholder is `0.0.0` and must stay exactly that**: the banner reads its own `.VERSION` line and
prints `dev build` for `0.0.0`, the stamped tag otherwise. It used to be `1.0.0`, which is also a real tag,
so a clone of `main` was indistinguishable from the v1.0.0 release.

## README claims

**The README claims only what a published measurement shows** (the companion article, `bench/results`).
An effect nobody measured, on frame times, DPC latency, stutter or input lag, is attributed to the guides
that recommend the tweak or marked as not measured, never stated as fact, and the star ask names no
effect. Frame time and ISR/DPC time are not input lag. The method lives in rigpolice's
`.claude/rules/bench-methodology.md`, section "Conclusions".

**`results-readme.Tests.ps1` turns every recorded number into a decimal with `ConvertTo-WrittenDecimal`
(`bench/bench-env.ps1`, shared with msi-mode-utility), never with a `[decimal]` cast or `Measure-Object`.**
From .NET 11 (PowerShell 7.7) a double converts to its exact binary value: the stock fps median 769.95 became
769.9499... and rounded to 769.9 where the data and the README say 770.0. Formatting the number and parsing
the text yields what the JSON holds on every PowerShell. A cast of text is no exception: PowerShell scans
`'1.005'` as a double before it converts, and `Measure-Object` returns doubles.

## The RigPolice pages that mirror this script

- **The hub card.** `src/lib/latency-toolbox.ts` in the rigpolice repo holds this script's card on
  https://rigpolice.com/system/latency-toolbox/: what it does, what was measured with it, and whether it
  writes an undo file. A release that changes any of those updates the card in the same pass; nothing
  there reads this repo, so the card drifts silently otherwise.
- **The companion article.** `src/content/articles/disable-cpu-core-parking.md` (the "How to disable it"
  section) quotes the `irm | iex` one-liner, describes what a run prints and explains the undo. A
  change to the one-liner URL, the run output or the undo mechanism updates that article in the same
  pass. rigpolice's `src/lib/latency-toolbox.test.ts` reds on a one-liner that is not the release URL and
  on a sample run that is not on Balanced or keeps the undo file elsewhere. The README sample is a verbatim
  capture in `bench/results/testbed-checks/`, pinned by `results-readme.Tests.ps1`; the article's copy of
  it and its undo text are updated by hand, so check them against this README.
- **The rest of the measured copy.** The intro and FAQ of `src/pages/system/latency-toolbox/index.astro`,
  `src/content/articles/bufferbloat-ping-spikes.md` and the FAQ of `src/content/categories/system.md` quote
  what this script measured; a change to `bench/results` updates them in the same pass.
