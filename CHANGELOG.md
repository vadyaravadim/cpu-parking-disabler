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

- Non-ASCII characters in the script showed up as mojibake when Windows PowerShell 5.1 ran the file
  with `-File`. The script is now pure ASCII - the em-dashes were replaced - with no BOM, and an
  `ascii-check` CI workflow keeps it that way: a BOM would break `irm | iex`, and non-ASCII in a
  BOM-less file breaks the 5.1 `-File` path.

### Changed

- Elevation under `irm | iex` was reworked to relaunch the text that was actually executing rather
  than re-fetching `main`, so that a fork, a branch, a pinned commit or a local copy would keep
  running after the UAC prompt: the text you piped in is saved to `%TEMP%` and elevated with
  `-File`. Until now the elevated window silently ran whatever `main` held at that moment, which
  could differ from the text you reviewed and ran. It also drops the second network fetch, and with
  it the download-failure case handled in 1.1.0, since there is nothing left to download. This did
  not hold in practice - see the 1.1.2 fix.

## [1.1.0] - 2026-07-18

### Added

- The `irm | iex` one-liner self-elevates, so it now runs from any PowerShell rather than only from
  an already elevated console. Before this, a piped run from a non-elevated console could only print
  "open PowerShell as Administrator and run the command again" and stop, because there was no file
  on disk to relaunch; it now relaunches the same one-liner in an elevated Windows PowerShell window
  through the UAC prompt.

### Fixed

- Refusing the UAC prompt threw an unhandled exception at you instead of printing a plain message
  saying elevation was declined.
- If the script download inside the elevated relaunch failed - no network, GitHub unreachable - the
  elevated window closed instantly and you never saw why. It now shows the error and waits for
  Enter.

### Changed

- The README Quick Start now describes the one-liner as working in any PowerShell because it
  self-elevates.

## [1.0.1] - 2026-07-18

### Fixed

- Two runs within the same second silently destroyed the first run's backup. The backup file is
  named from a whole-second timestamp and `powercfg -export` overwrites without asking, so the
  `.pow` you would have rolled back to was gone. Colliding names now get a numeric suffix, the first
  free of `_1`, `_2` and so on.

### Changed

- The README was reworked for search: keyword headings, 'unpark' terminology throughout, FAQ entries
  covering Quick CPU and the registry method, and alt text on the images.
- The Related section now links MSI Mode Utility, Timer Resolution Utility, GameDVR & FSO Disabler
  and Interrupt Affinity Utility.

## [1.0.0] - 2026-07-01

### Added

- First stable release. One command disables CPU core parking (`CPMINCORES` / `CPMINCORES1` = 100,
  so the minimum share of unparked cores is 100 percent and every core stays awake) and sets Energy
  Performance Preference to maximum (`PERFEPP` / `PERFEPP1` = 0) on your current power scheme, for
  both AC and battery - which is what clears the micro-stutters, input lag and frame-time spikes
  that parked cores cause.
- Supports Intel 12th-gen and newer hybrid CPUs, where P-cores and E-cores carry separate settings
  (the `1`-suffixed Class 1 pair), as well as non-hybrid CPUs (AMD Ryzen, older Intel) - the
  P-core-only settings are skipped silently when the CPU does not have them.
- The four settings are unhidden in the registry first, because a hidden power setting can be
  ignored by the OS even after `powercfg` sets it.
- Exports your current power scheme to the Desktop before touching anything, and prints the exact
  one-liner that re-imports and reactivates that backup.
- Self-elevates through UAC, so `Run.bat` or right-click > Run with PowerShell is all that is
  needed. An `irm ... | iex` one-liner is there as well, though at this version it has to be started
  from a console that is already running as Administrator.
- Runs on Windows 10 and Windows 11 (23H2 and 24H2), on Intel 10th-gen and newer - 12th-gen and
  newer for the hybrid path - and on AMD Ryzen 5000, 7000 and 9000. Nothing to install and no
  dependencies beyond what Windows already ships.

[Unreleased]: https://github.com/vadyaravadim/cpu-parking-disabler/compare/v1.1.2...HEAD
[1.1.2]: https://github.com/vadyaravadim/cpu-parking-disabler/compare/v1.1.1...v1.1.2
[1.1.1]: https://github.com/vadyaravadim/cpu-parking-disabler/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/vadyaravadim/cpu-parking-disabler/compare/v1.0.1...v1.1.0
[1.0.1]: https://github.com/vadyaravadim/cpu-parking-disabler/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/vadyaravadim/cpu-parking-disabler/releases/tag/v1.0.0
