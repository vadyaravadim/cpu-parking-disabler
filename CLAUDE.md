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

**Class 1 settings are hybrid-only and are meant to fail silently.** `CPMINCORES1` / `PERFEPP1` exist only
on Intel 12th-gen and newer; on AMD and older Intel `powercfg` errors and `Get-PowerSettingValue` returns
`$null`, which drops the row everywhere. Do not add a "setting not found" warning - it fires on every
non-hybrid machine.

## Invariants the undo file depends on

- **A run that changes nothing writes NO undo file.** A repeat run would otherwise snapshot the
  already-tweaked values as "previous", and the next `-Undo` would restore the tweak instead of the
  original. Files are per-run snapshots applied newest-to-oldest; only the oldest holds the original state.
- **`-Undo` writes to the scheme GUID recorded in the file, not `SCHEME_CURRENT`.** The user may have
  switched schemes since; restoring Balanced's old values into High performance would be the wrong fix.
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
- **Parked cores come from the `Win32_PerfFormattedData_Counters_ProcessorInformation` CIM class**, not the
  `'\Processor Information(*)\Parking Status'` counter path `bench/bench.ps1` uses - the path is localized,
  the class name is not. `$null` (counters disabled or corrupt) renders as "unavailable", never as 0.
- **The dual-CCD X3D guard is `X3D` in the name AND `NumberOfCores -ge 12`.** AMD's 3D V-Cache Performance
  Optimizer parks the non-V-Cache CCD during games through core parking; single-CCD parts (7800X3D,
  9800X3D) have nothing to park and must not get the prompt.
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

## Release - the tag is the only source of truth

`git tag vX.Y.Z && git push origin vX.Y.Z` runs `release.yml`, which stamps the tag into `.VERSION`, hashes
the script, attests build provenance, creates the GitHub Release and publishes to the PowerShell Gallery.
Nothing ships from a push to `main`.

**Before tagging, move the `## [Unreleased]` bullets in `CHANGELOG.md` into a `## [X.Y.Z] - YYYY-MM-DD`
section and add the compare link at the bottom.** The release job copies exactly that section into the
release body and **fails the release when the tag's section is missing**. This is a gate on purpose, not a
fallback: notes are hand-written because GitHub's `--generate-notes` lists merged PRs, and this repo lands
nearly everything as direct commits to `main`, so it published releases whose whole body was a compare
link.

Write the entries for someone who runs the tool, not for someone reading the diff: what changed on their
machine and why it matters. A fix says what was broken and what it cost them.

Do NOT bump `.VERSION` in the `.ps1` by hand - it is a placeholder the workflow overwrites, and a
hand-edited value that disagrees with the tag would only mislead whoever reads the committed file.
