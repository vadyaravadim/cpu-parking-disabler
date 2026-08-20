# CPU Parking Disabler

A single self-contained PowerShell script (`cpu-parking-disabler.ps1`) that disables CPU core parking
(`CPMINCORES` / `CPMINCORES1` = 100) and pins Energy Performance Preference (`PERFEPP` / `PERFEPP1` = 0) on
the active power scheme, for AC and DC. Part of a family of six single-script Windows tuning tools that
share this layout: one `.ps1`, `Run.bat`, `PSScriptAnalyzerSettings.psd1`, and the same three workflows.

**The registry unhide must stay BEFORE the `powercfg` calls.** The four settings are hidden by default, and
a hidden processor setting can be ignored by the OS even after `powercfg` writes a value - setting
`Attributes = 0` first is what makes the write take effect, not cosmetics.

**Class 1 settings are hybrid-only and are meant to fail silently.** `CPMINCORES1` / `PERFEPP1` exist only
on Intel 12th-gen and newer; on AMD and older Intel the `powercfg` call errors and that is the intended
path (`2>$null`). Do not add a "setting not found" warning - it fires on every non-hybrid machine.

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
