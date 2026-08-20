# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Each released section below IS the GitHub Release body for that tag: `release.yml` copies the section
verbatim into the release and fails the release if the tag has no section here.

## [Unreleased]

### Added

- `bench/bench.ps1` - the frame-pacing benchmark used to measure this tweak's effect, so the numbers in the
  README can be reproduced on your own machine rather than taken on trust.

### Fixed

- The copy a piped `irm ... | iex` run saves into your user profile was written with a UTF-8 BOM, which
  then broke running that saved copy through `irm | iex` again - the parser chokes on the leading byte
  order mark. It is now written without one.

## [1.1.2] - 2026-07-19

### Added

- The tool is on the PowerShell Gallery. `Install-Script cpu-parking-disabler` now works, so you no longer
  have to download the file by hand to keep a copy on disk.
- Every tagged release ships a `SHA256SUMS.txt` alongside the script plus a signed build-provenance
  attestation, so you can verify the file you downloaded is the one the workflow built from this source.

### Fixed

- Elevation under `irm | iex` re-ran the one-liner you typed instead of the script. 1.1.1 saved what it
  believed was the executing script text before asking for Administrator rights, but in a piped run that
  value is the caller's command line, not the script body - so the elevated window silently re-downloaded
  and re-executed the one-liner, and a run started from inside a wrapper script would have saved the
  wrapper instead. The script is now fetched from its canonical raw URL and that file is what gets
  elevated, with a guard so UAC is never asked to relaunch a file that failed to download. Note the
  trade-off this makes explicit: a piped fork or branch is replaced by canonical `main`, so a fork has to
  point the URL at itself.

### Changed

- A piped run now saves the script into your user profile and reruns it from there, rather than leaving a
  copy in `%TEMP%`. If a file of that name already exists and differs, the previous copy is kept as `.bak`
  instead of being overwritten.
- A failed download or a failed elevation now prints the actual reason - no internet, UAC refused, UAC
  service disabled - and keeps the window open, instead of the console closing on an empty screen.

## [1.1.1] - 2026-07-18

### Fixed

- Non-ASCII characters in the script showed up as mojibake when Windows PowerShell 5.1 ran the file with
  `-File`. The script is now pure ASCII with no BOM, and a CI check keeps it that way: a BOM would break
  `irm | iex`, and non-ASCII in a BOM-less file breaks the 5.1 `-File` path.

### Changed

- Elevation under `irm | iex` was reworked to relaunch the text that was actually executing rather than
  re-fetching `main`, so that a fork or a pinned commit would keep running after the UAC prompt. This did
  not hold in practice - see the 1.1.2 fix.

## [1.1.0] - 2026-07-18

### Added

- The `irm | iex` one-liner self-elevates. Before this, a piped run from a non-elevated console could only
  print "open PowerShell as Administrator and run the command again" and stop, because there was no file on
  disk to relaunch; it now writes itself out and reruns through the UAC prompt.

## [1.0.1] - 2026-07-18

### Fixed

- Two runs within the same second silently destroyed the first run's backup. The backup file is named from
  a whole-second timestamp and `powercfg -export` overwrites without asking, so the `.pow` you would have
  rolled back to was gone. Colliding names now get a numeric suffix.

## [1.0.0] - 2026-07-01

### Added

- First release. Disables CPU core parking (`CPMINCORES` / `CPMINCORES1` = 100) and sets Energy Performance
  Preference (`PERFEPP` / `PERFEPP1` = 0) on your current power scheme, for both AC and battery.
- Supports Intel 12th-gen and newer hybrid CPUs, where P-cores and E-cores carry separate settings, as well
  as non-hybrid CPUs (AMD Ryzen, older Intel) - the P-core-only settings are skipped silently when the CPU
  does not have them.
- The four settings are unhidden in the registry first, because a hidden power setting can be ignored by
  the OS even after `powercfg` sets it.
- Exports your current power scheme to the Desktop before touching anything, and prints the exact
  one-liner that re-imports and reactivates that backup.
- Self-elevates through UAC, so `Run.bat` or right-click > Run with PowerShell is all that is needed.

[Unreleased]: https://github.com/vadyaravadim/cpu-parking-disabler/compare/v1.1.2...HEAD
[1.1.2]: https://github.com/vadyaravadim/cpu-parking-disabler/compare/v1.1.1...v1.1.2
[1.1.1]: https://github.com/vadyaravadim/cpu-parking-disabler/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/vadyaravadim/cpu-parking-disabler/compare/v1.0.1...v1.1.0
[1.0.1]: https://github.com/vadyaravadim/cpu-parking-disabler/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/vadyaravadim/cpu-parking-disabler/releases/tag/v1.0.0
