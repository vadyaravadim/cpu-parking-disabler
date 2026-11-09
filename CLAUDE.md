# CPU Parking Disabler

A single self-contained PowerShell script (`cpu-parking-disabler.ps1`) that disables CPU core parking
(`CPMINCORES` / `CPMINCORES1` = 100) and pins Energy Performance Preference (`PERFEPP` / `PERFEPP1` = 0) on
the active power scheme, for AC and DC. `-Status` shows the parked-core count and the four values without
changing anything; `-Undo` restores the per-run `parking_undo_<stamp>.json` snapshot. Part of a family of
six single-script Windows tuning tools that share this layout: one `.ps1`, `Run.bat`,
`PSScriptAnalyzerSettings.psd1`, and the same three workflows.

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
  session.
- **A piped run saves the script into the user profile, not `%TEMP%`.** The undo file is written next to
  the script, so it has to sit somewhere that survives automatic temp cleanup.
- **`Get-ForwardedSwitchList` is the ONE place mode switches are listed.** Both relaunch paths - the
  `irm | iex` bootstrap rerun and the UAC elevation - build their argument list from it, so neither can
  silently drop `-Status` or `-Undo`. Splat it as `@(...)`: on PS 5.1 a single forwarded switch unrolls
  to a scalar string and breaks `powershell.exe -File` switch binding.

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
  the X3D2 has V-Cache on both, so unparking cannot move a game off the cache.
- **`-Status` skips elevation on purpose** - it only reads, and a UAC prompt for a read-only check is what
  makes people stop checking.

## The two CI gates

- **`ascii-check.yml` - the .ps1 must be pure ASCII with no BOM.** Both halves are load-bearing: a BOM
  makes `irm | iex` choke on a leading U+FEFF, and non-ASCII in a BOM-less file turns into mojibake when
  Windows PowerShell 5.1 runs it with `-File`. Write `\uXXXX` regex escapes rather than literals; em-dashes
  and typographic quotes are the usual way this reds. Only the `.ps1` is checked - Markdown is free.
- **`lint.yml` - PSScriptAnalyzer over the whole repo, Error + Warning, any finding fails.** Suppressions
  live in `PSScriptAnalyzerSettings.psd1` with the reason written next to each rule. Extend that file with
  a justification instead of adding an inline suppression attribute.

## Release - the newest CHANGELOG section is the version

`gh workflow run release.yml` (or Actions > release > Run workflow) on `main` releases the newest
`## [X.Y.Z]` section of `CHANGELOG.md`: it gates that commit, stamps the version into `.VERSION`, hashes the
script, attests build provenance, publishes to the PowerShell Gallery and, last, creates the GitHub Release,
which creates the `vX.Y.Z` tag at that commit. A run from any other branch fails in the release job before
anything is written. Nothing ships from a push to `main`, and no tag exists until every gate has passed.

- **The `irm | iex` URL is `releases/latest/download/cpu-parking-disabler.ps1` - in the README AND in the
  script's bootstrap download, never `raw.githubusercontent.com/.../main`.** That is what keeps the
  sentence above true for the one-liner, and makes the saved copy byte-identical to the attested asset.
- **`release.yml` calls `lint.yml`, `ascii-check.yml` and `bench-tests.yml` (Pester over `tests` and
  `bench/tests`) through `workflow_call` and `needs:` all three.** Their push-triggered runs on `main` do not
  block the release, and a PSGallery version cannot be re-published.
- **`v*` tags cannot be moved or deleted (tag ruleset) and releases are immutable (repo setting).** A broken
  release is fixed by releasing a new patch version (a new CHANGELOG section), never by re-tagging. The
  ruleset leaves tag creation open on purpose: the release creates the tag with `GITHUB_TOKEN`.
- **Never push a `v*` tag by hand.** It starts no release and cannot be deleted; unless it sits on the exact
  commit the release then runs on, the release stops before publishing and that version is burned.
- **Finish a failed release with "Re-run failed jobs" on that run, not a new run.** The re-run builds the
  same commit: the Gallery step (`.github/Publish-GalleryScript.ps1`) skips a version already there with
  identical bytes and fails on different bytes. A run cancelled during the GitHub Release step can leave a
  draft - delete it before re-running. Release the next version instead only when that run is older than
  30 days and can no longer be re-run.

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
