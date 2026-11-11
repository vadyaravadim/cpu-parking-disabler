# Security Policy

## Reporting a Vulnerability

Please report security issues **privately** via
[GitHub Security Advisories](https://github.com/vadyaravadim/cpu-parking-disabler/security/advisories/new)
— not through a public issue.

Expect a first response within 7 days. If a fix is warranted, it ships as a new
tagged release and the advisory is published once the fix is available.

## Supported Versions

Only the latest release receives fixes. Older tags are left as-is — update to the
newest version before reporting.

## Scope

This script runs **with administrator rights** and modifies the active Windows
power scheme via `powercfg`. That is its intended purpose, not a vulnerability.

In scope:

- The self-elevation path (`irm | iex` saving to `%USERPROFILE%` and re-running
  from there) — e.g. a way to make it execute attacker-controlled content
- The saved-copy / `.bak` handling — e.g. a path that overwrites an unrelated file
- The undo file (`parking_undo_*.json`) — e.g. a crafted file that makes `-Undo`
  write outside the recorded power scheme or settings
- The release pipeline — checksums, provenance, or the PowerShell Gallery package
  not matching the tagged source

Out of scope:

- Requiring admin rights, or the UAC prompt
- Possibly higher idle power draw and temperatures, described in
  [Side Effects](README.md#side-effects)
- Changes persisting across reboots — documented in the
  [FAQ](README.md#do-the-changes-survive-a-reboot), and reversible per
  [Rollback](README.md#rollback)
- Running `-Undo` against an undo file you edited by hand

## Verifying a Release

Each release publishes `SHA256SUMS.txt` and Sigstore build provenance. Verify a
download before running it.

Releases from v1.2.0 on are immutable: when one is published, GitHub itself attests
its tag, its commit and every file attached to it. This check works for every one of
them, whichever workflow built the file. Without a tag it checks against the latest
release; to check an older one, put its tag (`vX.Y.Z`) before the file name. It needs
the [GitHub CLI](https://cli.github.com/):

```powershell
gh release verify-asset .\cpu-parking-disabler.ps1 -R vadyaravadim/cpu-parking-disabler
```

Without the GitHub CLI, compare the file's hash against the one in the corresponding
[release](https://github.com/vadyaravadim/cpu-parking-disabler/releases):

```powershell
Get-FileHash .\cpu-parking-disabler.ps1 -Algorithm SHA256
```

The hash only proves the file matches the release page. The provenance proves the
file was built from the tagged commit of this repository. Releases after v1.3.2 are
built by the release workflow shared by the six RigPolice Latency Toolbox scripts,
[`vadyaravadim/latency-toolbox-ci`](https://github.com/vadyaravadim/latency-toolbox-ci):

```powershell
gh attestation verify .\cpu-parking-disabler.ps1 -R vadyaravadim/cpu-parking-disabler --signer-workflow vadyaravadim/latency-toolbox-ci/.github/workflows/pipeline.yml
```

Without `--signer-workflow` the command rejects these releases: by default it only
accepts a signature from this repository's own workflows.

Releases v1.1.2 to v1.3.2 were built by this repository's own `release.yml`
(earlier ones carry no provenance). Verify those with:

```powershell
gh attestation verify .\cpu-parking-disabler.ps1 -R vadyaravadim/cpu-parking-disabler --signer-workflow vadyaravadim/cpu-parking-disabler/.github/workflows/release.yml
```
