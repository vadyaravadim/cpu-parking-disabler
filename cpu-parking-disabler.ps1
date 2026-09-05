<#PSScriptInfo

.VERSION 1.0.0

.GUID 3c68d1e3-ff2b-4cc2-b7c1-6c384c72cd0d

.AUTHOR vadyaravadim

.COMPANYNAME

.COPYRIGHT

.TAGS Windows Windows10 Windows11 Gaming CPU CoreParking PowerPlan Performance Latency Stutter Tweak

.LICENSEURI https://github.com/vadyaravadim/cpu-parking-disabler/blob/main/LICENSE

.PROJECTURI https://github.com/vadyaravadim/cpu-parking-disabler

.ICONURI

.EXTERNALMODULEDEPENDENCIES

.REQUIREDSCRIPTS

.EXTERNALSCRIPTDEPENDENCIES

.RELEASENOTES

.PRIVATEDATA

#>

<#
.SYNOPSIS
    Disables CPU core parking and sets Energy Performance Preference to maximum performance.

.DESCRIPTION
    Shows how many cores Windows has parked right now and the four power
    settings behind it, then sets Core Parking Min Cores (CPMINCORES /
    CPMINCORES1) to 100 and Energy Performance Preference (PERFEPP / PERFEPP1)
    to 0 on the active power scheme, for AC and DC, and shows the parked-core
    count again so the effect is visible on screen.

    Supports Intel 12th gen+ hybrid CPUs (separate P-core/E-core settings) and
    non-hybrid CPUs (AMD Ryzen, older Intel), where the Class 1 (P-core)
    settings do not exist and are skipped. Dual-CCD X3D Ryzens (7900X3D,
    7950X3D, 9900X3D, 9950X3D) get a warning first: AMD parks the non-V-Cache
    CCD during games THROUGH core parking, and this tweak defeats that.

    The previous values are written to parking_undo_<stamp>.json next to the
    script before anything changes; -Undo puts them back. The script relaunches
    itself as Administrator when needed.

.PARAMETER Status
    Show the parked-core count and the current settings, change nothing.
    Does not need Administrator rights.

.PARAMETER Undo
    Restore the values recorded by the newest parking_undo_*.json next to the
    script. Files are per-run snapshots: after several runs, -Undo once per
    run, newest to oldest - only the oldest holds the original state.

.EXAMPLE
    .\cpu-parking-disabler.ps1

    Double-click Run.bat, or right-click this file > Run with PowerShell.
    No parameters needed - it elevates itself.

.EXAMPLE
    .\cpu-parking-disabler.ps1 -Status

.EXAMPLE
    .\cpu-parking-disabler.ps1 -Undo

.LINK
    https://github.com/vadyaravadim/cpu-parking-disabler
#>
[CmdletBinding()]
param(
    [switch]$Status,
    [switch]$Undo,
    [switch]$Elevated   # internal: set by the self-elevation relaunch
)

$ErrorActionPreference = 'Stop'

# Keep the self-elevated window open so the user can read the output.
function Wait-IfElevatedWindow {
    if ($Elevated) { Read-Host "Press Enter to close" | Out-Null }
}

# Without this, an unhandled error closes the self-elevated window before
# the user can read the message.
trap {
    Write-Host "ERROR: $_" -ForegroundColor Red
    Wait-IfElevatedWindow
    # Under `irm | iex` this runs inside the user's own session, where `exit`
    # would close their console - rethrow so only the piped script stops.
    if ($PSCommandPath) { exit 1 }
    break
}

# Mode switches forwarded on every relaunch (the irm|iex bootstrap rerun below
# and the self-elevation later) - one list so neither path can silently drop one.
function Get-ForwardedSwitchList {
    $a = @()
    if ($Status) { $a += '-Status' }
    if ($Undo)   { $a += '-Undo' }
    $a
}

# Launched via `irm <url> | iex` - no file on disk. The undo file is written
# next to the script, so a stable path is required: save the script to the
# user profile (not TEMP - the undo file must survive automatic temp cleanup)
# and rerun it from there (the rerun handles elevation).
if (-not $PSCommandPath) {
    # The piped text is not recoverable from inside iex ($MyInvocation there
    # holds the caller's command line, not the script body) - download the
    # script.
    try {
        $body = Invoke-RestMethod 'https://raw.githubusercontent.com/vadyaravadim/cpu-parking-disabler/main/cpu-parking-disabler.ps1' -TimeoutSec 30
    } catch {
        Write-Host "ERROR: could not download the script ($($_.Exception.Message)). Check your internet connection, or save the script to a file and run it from there." -ForegroundColor Red
        return
    }
    $saved = Join-Path $env:USERPROFILE 'cpu-parking-disabler.ps1'
    if ((Test-Path $saved) -and ([IO.File]::ReadAllText($saved) -cne $body)) {
        Copy-Item $saved "$saved.bak" -Force
        Write-Host "Existing $saved differs - previous copy kept as $saved.bak" -ForegroundColor Yellow
    }
    # UTF8Encoding($false) = no BOM: a BOM would break a later `irm | iex` of
    # the saved copy and violates the ASCII/no-BOM invariant the repo enforces.
    [IO.File]::WriteAllText($saved, $body, [Text.UTF8Encoding]::new($false))
    Write-Host "Script saved to: $saved (the undo file will be written next to it)" -ForegroundColor Cyan
    # @(): a single forwarded switch unrolls to a scalar, and splatting a
    # scalar string breaks powershell.exe -File switch binding on PS 5.1.
    $fwd = @(Get-ForwardedSwitchList)
    powershell -NoProfile -ExecutionPolicy Bypass -File $saved @fwd
    # The rerun's exit code stays in $LASTEXITCODE for scripted callers.
    return
}

# ---- Everything below -Status writes power settings: Administrator required ----
$principal = New-Object Security.Principal.WindowsPrincipal(
    [Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $Status -and -not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Not running as Administrator. Requesting elevation..." -ForegroundColor Yellow
    try {
        $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass',
                     '-File', "`"$PSCommandPath`"", '-Elevated') + (Get-ForwardedSwitchList)
        Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -Verb RunAs
    } catch {
        # Not always a refusal (UAC service disabled, ...) - show the real cause.
        Write-Host "ERROR: elevation failed ($($_.Exception.Message)). Run this script as Administrator." -ForegroundColor Red
        Read-Host "Press Enter to close" | Out-Null
    }
    return
}

# ---- Helpers ----

# powercfg reports failure by exit code and writes the reason to stderr. Under
# Windows PowerShell 5.1 a stderr line captured with 2>&1 becomes a terminating
# error while $ErrorActionPreference is Stop, so the call runs with Continue
# and the caller decides what a failure means (absent setting vs. real error).
function Invoke-Powercfg([string[]]$ArgumentList) {
    $ErrorActionPreference = 'Continue'
    $out = & powercfg @ArgumentList 2>&1
    [pscustomobject]@{ Ok = ($LASTEXITCODE -eq 0); Text = (@($out | ForEach-Object { "$_" }) -join "`n") }
}

# $null when the setting does not exist on this CPU (Class 1 on non-hybrid).
# /qh includes hidden settings, so this works before the registry unhide too.
# Labels are localized on non-English Windows, so they are not matched: the
# last two hex values of the block are AC then DC on every locale.
function Get-PowerSettingValue([string]$Setting, [string]$Scheme = 'SCHEME_CURRENT') {
    $r = Invoke-Powercfg @('/qh', $Scheme, 'SUB_PROCESSOR', $Setting)
    if (-not $r.Ok) { return $null }
    $hex = @([regex]::Matches($r.Text, '0x([0-9a-fA-F]{8})') | ForEach-Object { [Convert]::ToInt32($_.Groups[1].Value, 16) })
    if ($hex.Count -lt 2) { throw "unexpected powercfg output for $Setting`n$($r.Text)" }
    [pscustomobject]@{ AC = $hex[-2]; DC = $hex[-1] }
}

function Set-PowerSettingValue([string]$Setting, [int]$AC, [int]$DC, [string]$Scheme = 'SCHEME_CURRENT') {
    foreach ($call in @(@('/setacvalueindex', $AC), @('/setdcvalueindex', $DC))) {
        $r = Invoke-Powercfg @($call[0], $Scheme, 'SUB_PROCESSOR', $Setting, $call[1])
        if (-not $r.Ok) { throw "powercfg $($call[0]) $Setting failed: $($r.Text)" }
    }
}

# A hidden processor setting can be ignored by the OS even after powercfg
# writes it, so Attributes = 0 comes BEFORE any write. Idempotent; the
# settings stay visible in Power Options afterwards, which is harmless.
$PowerSettingsKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\54533251-82be-4824-96c1-47b60b740d00'
function Show-PowerSetting([string]$Guid) {
    Set-ItemProperty -Path (Join-Path $PowerSettingsKey $Guid) -Name Attributes -Value 0 -Type DWord
}

# Language-independent, unlike the '\Processor Information(*)\Parking Status'
# counter path, which is localized on non-English Windows. Instance names are
# "group,index"; the _Total rows are skipped. $null when the performance
# counters are disabled or corrupt on this system.
function Get-ParkedCoreCount {
    $rows = @(Get-CimInstance Win32_PerfFormattedData_Counters_ProcessorInformation -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^\d+,\d+$' })
    if (-not $rows.Count) { return $null }
    [pscustomobject]@{ Parked = @($rows | Where-Object { $_.ParkingStatus -eq 1 }).Count; Total = $rows.Count }
}

function Format-ParkedCount($Count) {
    if ($null -eq $Count) { return 'unavailable (performance counters are disabled on this system)' }
    '{0} of {1}' -f $Count.Parked, $Count.Total
}

function Get-ActiveScheme {
    $r = Invoke-Powercfg @('/getactivescheme')
    if (-not $r.Ok) { throw "powercfg /getactivescheme failed: $($r.Text)" }
    [pscustomobject]@{
        Guid = [regex]::Match($r.Text, '[0-9a-fA-F-]{36}').Value
        Name = [regex]::Match($r.Text, '\(([^)]+)\)\s*$').Groups[1].Value
    }
}

# Rows are skipped when the setting is absent (Class 1 on non-hybrid CPUs).
$settingDefs = @(
    [pscustomobject]@{ Name = 'CPMINCORES';  Guid = '0cc5b647-c1df-4637-891a-dec35c318583'; Target = 100; Label = 'core parking min cores, E-cores / all cores' }
    [pscustomobject]@{ Name = 'CPMINCORES1'; Guid = '0cc5b647-c1df-4637-891a-dec35c318584'; Target = 100; Label = 'core parking min cores, P-cores' }
    [pscustomobject]@{ Name = 'PERFEPP';     Guid = '36687f9e-e3a5-4dbf-b1dc-15eb381c6863'; Target = 0;   Label = 'energy performance preference, E-cores / all cores' }
    [pscustomobject]@{ Name = 'PERFEPP1';    Guid = '36687f9e-e3a5-4dbf-b1dc-15eb381c6864'; Target = 0;   Label = 'energy performance preference, P-cores' }
)

Write-Host ""
Write-Host "===================================" -ForegroundColor Cyan
Write-Host "  CPU PARKING DISABLER" -ForegroundColor Cyan
Write-Host "===================================" -ForegroundColor Cyan
Write-Host ""

# ---- Undo mode ----
if ($Undo) {
    # Sort by the name stamp - LastWriteTime survives renames and can mislead.
    $undoFile = Get-ChildItem -Path $PSScriptRoot -Filter 'parking_undo_*.json' -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notmatch '\.applied\.json$' } |
        Sort-Object Name | Select-Object -Last 1
    if (-not $undoFile) {
        Write-Host "No parking_undo_*.json found next to the script - nothing to undo." -ForegroundColor Yellow
        Wait-IfElevatedWindow; return
    }
    $snap = Get-Content $undoFile.FullName -Raw | ConvertFrom-Json
    Write-Host "Reverting: $($undoFile.Name)" -ForegroundColor Cyan
    Write-Host "Power scheme  : $($snap.SchemeName) ($($snap.Scheme))"
    # Written to the scheme that was changed, not whatever is active now - the
    # user may have switched schemes since. Unhide first, as on apply: a major
    # Windows update can hide the settings again.
    foreach ($v in $snap.Values) {
        Show-PowerSetting ($settingDefs | Where-Object Name -eq $v.Setting).Guid
        Set-PowerSettingValue $v.Setting $v.AC $v.DC $snap.Scheme
        Write-Host ("  [OK ] {0,-12} AC {1,3}  DC {2,3}" -f $v.Setting, $v.AC, $v.DC) -ForegroundColor Green
    }
    # Re-reads the active scheme so the restored values take effect right away.
    $r = Invoke-Powercfg @('/setactive', 'SCHEME_CURRENT')
    if (-not $r.Ok) { throw "powercfg /setactive failed: $($r.Text)" }
    Rename-Item $undoFile.FullName ($undoFile.FullName -replace '\.json$', '.applied.json')
    if ((Get-ActiveScheme).Guid -ne $snap.Scheme) {
        Write-Host "That scheme is not the active one - the restored values take effect when you switch back to it." -ForegroundColor Yellow
    }
    $remaining = @(Get-ChildItem -Path $PSScriptRoot -Filter 'parking_undo_*.json' -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notmatch '\.applied\.json$' })
    if ($remaining.Count) {
        Write-Host "$($remaining.Count) older undo file(s) remain - run -Undo again to revert earlier runs." -ForegroundColor Yellow
    }
    # The kernel re-evaluates parking within a few hundred ms of the scheme change.
    Start-Sleep -Milliseconds 1000
    Write-Host ""
    Write-Host "Parked cores  : $(Format-ParkedCount (Get-ParkedCoreCount))"
    Write-Host "Done." -ForegroundColor Green
    Wait-IfElevatedWindow; return
}

# ---- Current state ----
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$scheme = Get-ActiveScheme
$parkedBefore = Get-ParkedCoreCount
$settings = @(foreach ($d in $settingDefs) {
    $v = Get-PowerSettingValue $d.Name
    if ($null -ne $v) {
        $d | Add-Member NoteProperty AC $v.AC -PassThru | Add-Member NoteProperty DC $v.DC -PassThru |
            Add-Member NoteProperty Ok (($v.AC -eq $d.Target) -and ($v.DC -eq $d.Target)) -PassThru
    }
})
$hybrid = [bool]($settings | Where-Object Name -eq 'CPMINCORES1')
# Dual-CCD X3D parts: AMD's 3D V-Cache Performance Optimizer parks the
# non-V-Cache CCD during games THROUGH core parking. Single-CCD X3D parts
# (7800X3D, 9800X3D) have nothing to park and are not affected.
$dualCcdX3D = ($cpu.Name -match 'X3D') -and ($cpu.NumberOfCores -ge 12)

$parkedColor = if ($null -eq $parkedBefore) { 'Yellow' } elseif ($parkedBefore.Parked) { 'Red' } else { 'Green' }
Write-Host ("CPU           : {0}  ({1} cores / {2} threads{3})" -f $cpu.Name.Trim(), $cpu.NumberOfCores, $cpu.NumberOfLogicalProcessors, $(if ($hybrid) { ', hybrid P+E' } else { '' }))
Write-Host "Power scheme  : $($scheme.Name)"
Write-Host "Parked cores  : " -NoNewline
Write-Host (Format-ParkedCount $parkedBefore) -ForegroundColor $parkedColor
Write-Host ""
Write-Host ("  {0,-12} {1,4} {2,4} {3,6}" -f 'Setting', 'AC', 'DC', 'Target') -ForegroundColor DarkGray
foreach ($s in $settings) {
    $mark = if ($s.Ok) { 'ok' } else { '->' }
    Write-Host ("  {0,-12} {1,4} {2,4} {3,6}  {4} ({5})" -f $s.Name, $s.AC, $s.DC, $s.Target, $mark, $s.Label) -ForegroundColor $(if ($s.Ok) { 'DarkGray' } else { 'Yellow' })
}
Write-Host ""
if ($dualCcdX3D) {
    Write-Host "NOTE: $($cpu.Name.Trim()) is a dual-CCD X3D part. AMD parks the non-V-Cache CCD during games through core parking on purpose - keeping every core awake defeats that, and games can run worse, not better." -ForegroundColor Yellow
    Write-Host ""
}

if ($Status) { Wait-IfElevatedWindow; return }

if ($dualCcdX3D) {
    $answer = Read-Host "Continue anyway? [y/N]"
    if ($answer -notmatch '^y') {
        Write-Host "Nothing changed." -ForegroundColor Green
        Wait-IfElevatedWindow; return
    }
    Write-Host ""
}

# Nothing to change -> no undo file: a repeat-run snapshot would record the
# already-tweaked state, and the next -Undo would "revert" to it instead of
# the original.
if (-not ($settings | Where-Object { -not $_.Ok })) {
    Write-Host "All values already at target - nothing to do, no undo file written." -ForegroundColor Green
    Wait-IfElevatedWindow
    return
}

# ---- Undo file: the CURRENT values of every setting, BEFORE changing anything ----
# The suffix loop keeps two runs within the same second from clobbering
# each other's undo file.
$base = Get-Date -Format 'yyyyMMdd_HHmmss'
$stamp = $base
$n = 1
while (Test-Path (Join-Path $PSScriptRoot "parking_undo_$stamp.json")) { $stamp = '{0}_{1}' -f $base, $n++ }
$undoPath = Join-Path $PSScriptRoot "parking_undo_$stamp.json"
$snapshot = [ordered]@{
    Scheme     = $scheme.Guid
    SchemeName = $scheme.Name
    Values     = @(foreach ($s in $settings) { [ordered]@{ Setting = $s.Name; AC = $s.AC; DC = $s.DC } })
}
ConvertTo-Json $snapshot -Depth 4 | Set-Content -Path $undoPath -Encoding UTF8
Write-Host "Undo file saved: $undoPath (revert with -Undo)" -ForegroundColor Cyan
Write-Host ""

# ---- Apply ----
Write-Host "Applying..."
foreach ($s in $settings) {
    Show-PowerSetting $s.Guid
    Set-PowerSettingValue $s.Name $s.Target $s.Target
    Write-Host ("  [OK ] {0,-12} AC {1,3} -> {2,-3}  DC {3,3} -> {4}" -f $s.Name, $s.AC, $s.Target, $s.DC, $s.Target) -ForegroundColor Green
}
$r = Invoke-Powercfg @('/setactive', 'SCHEME_CURRENT')
if (-not $r.Ok) { throw "powercfg /setactive failed: $($r.Text)" }

# The kernel re-evaluates parking within a few hundred ms of the scheme change.
Start-Sleep -Milliseconds 1000
$parkedAfter = Get-ParkedCoreCount

Write-Host ""
Write-Host "===================================" -ForegroundColor Cyan
Write-Host "  DONE" -ForegroundColor Cyan
Write-Host "===================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Parked cores  : " -NoNewline
Write-Host (Format-ParkedCount $parkedBefore) -ForegroundColor $parkedColor -NoNewline
Write-Host " -> " -NoNewline
Write-Host (Format-ParkedCount $parkedAfter) -ForegroundColor $(if ($null -eq $parkedAfter) { 'Yellow' } elseif ($parkedAfter.Parked) { 'Red' } else { 'Green' })
Write-Host ""
Write-Host "Applied to power scheme '$($scheme.Name)':"
Write-Host "  - CPU parking: DISABLED (all cores always active)"
Write-Host "  - EPP: 0 (max performance)"
Write-Host ""
Write-Host "Revert any time with: .\cpu-parking-disabler.ps1 -Undo" -ForegroundColor DarkGray
Wait-IfElevatedWindow
