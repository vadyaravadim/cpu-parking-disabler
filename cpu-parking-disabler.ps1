<#
.SYNOPSIS
    Disables CPU core parking and sets Energy Performance Preference to maximum performance.

.DESCRIPTION
    This script disables CPU core parking (CPMINCORES/CPMINCORES1 = 100%) and sets
    Energy Performance Preference (PERFEPP/PERFEPP1 = 0) on the current power scheme.

    Supports Intel 12th gen+ hybrid CPUs (separate P-core/E-core settings) and
    traditional non-hybrid CPUs (AMD Ryzen, older Intel). Class 1 (P-core) settings
    that don't exist on non-hybrid CPUs are skipped silently.

    The script relaunches itself as Administrator if needed, and saves a backup of
    the current power scheme to the Desktop before any changes.

.EXAMPLE
    .\cpu-parking-disabler.ps1

    Double-click Run.bat, or right-click this file > Run with PowerShell.
    No parameters needed - it elevates itself.

.LINK
    https://github.com/vadyaravadim/cpu-parking-disabler
#>

# ============================================================================
# Self-elevation: relaunch as Administrator if not already elevated
# ============================================================================
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")

if (-not $isAdmin) {
    $scriptPath = $PSCommandPath
    if (-not $scriptPath) {
        # Launched via `irm ... | iex` - no file on disk to relaunch. Persist the
        # text that is actually executing and elevate that, not a re-download:
        # what the user piped in (a fork, a branch, a local copy) is what must
        # run under Administrator. UTF-8 with BOM: -File reads it correctly on
        # PS 5.1 whatever the piped content contains.
        $body = $MyInvocation.MyCommand.Definition
        if (-not $body) { Write-Host "ERROR: cannot recover the executing script text; save the script to a file and run it with -File." -ForegroundColor Red; return }
        $scriptPath = Join-Path $env:TEMP 'cpu-parking-disabler.ps1'
        [IO.File]::WriteAllText($scriptPath, $body, [Text.Encoding]::UTF8)
    }
    try {
        # -ExecutionPolicy Bypass keeps a downloaded script from being blocked
        # by ExecutionPolicy / Mark-of-the-Web.
        Start-Process powershell -Verb RunAs -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$scriptPath`"")
    } catch {
        Write-Host "ERROR: elevation was refused. Run this script as Administrator." -ForegroundColor Red
    }
    return
}

# ============================================================================
# Helpers
# ============================================================================
# Query current AC value for a processor power setting (silent if it doesn't exist)
function Get-PowerSettingAC($Setting) {
    powercfg -query SCHEME_CURRENT SUB_PROCESSOR $Setting 2>$null |
        Select-String "Current AC Power Setting Index" |
        ForEach-Object { $_.ToString().Split(':')[1].Trim() }
}

# Apply a processor setting to both AC and DC. Settings absent on this CPU
# (e.g. Class 1 / P-core settings on non-hybrid CPUs) are skipped silently.
function Set-PowerSettingValue($Setting, $Value) {
    powercfg -setacvalueindex SCHEME_CURRENT SUB_PROCESSOR $Setting $Value 2>$null
    powercfg -setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR $Setting $Value 2>$null
}

Write-Host ""
Write-Host "===================================" -ForegroundColor Cyan
Write-Host "  CPU PARKING DISABLER" -ForegroundColor Cyan
Write-Host "===================================" -ForegroundColor Cyan
Write-Host ""

# ============================================================================
# Backup current power scheme to Desktop
# ============================================================================
# The suffix loop keeps two runs within the same second from clobbering
# each other's backup (powercfg -export overwrites silently).
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backupPath = "$env:USERPROFILE\Desktop\power_scheme_backup_$timestamp.pow"
$n = 1
while (Test-Path $backupPath) { $backupPath = "$env:USERPROFILE\Desktop\power_scheme_backup_${timestamp}_$n.pow"; $n++ }
powercfg -export $backupPath SCHEME_CURRENT 2>$null | Out-Null
Write-Host "Backup saved: $backupPath" -ForegroundColor Green
Write-Host ""

# ============================================================================
# Registry pre-config: unhide power settings so powercfg can access them
# Must be done BEFORE setting values - hidden settings may be ignored by OS
# ============================================================================
$regBase = "HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\54533251-82be-4824-96c1-47b60b740d00"

# CPMINCORES - Core Parking Min Cores (E-cores / all cores)
reg add "$regBase\0cc5b647-c1df-4637-891a-dec35c318583" /v Attributes /t REG_DWORD /d 0 /f 2>$null | Out-Null

# CPMINCORES1 - Core Parking Min Cores (P-cores, hybrid CPUs)
reg add "$regBase\0cc5b647-c1df-4637-891a-dec35c318584" /v Attributes /t REG_DWORD /d 0 /f 2>$null | Out-Null

# PERFEPP - Energy Performance Preference (E-cores / all cores)
reg add "$regBase\36687f9e-e3a5-4dbf-b1dc-15eb381c6863" /v Attributes /t REG_DWORD /d 0 /f 2>$null | Out-Null

# PERFEPP1 - Energy Performance Preference (P-cores, hybrid CPUs)
reg add "$regBase\36687f9e-e3a5-4dbf-b1dc-15eb381c6864" /v Attributes /t REG_DWORD /d 0 /f 2>$null | Out-Null

# ============================================================================
# 1. Disable CPU core parking (all cores always active)
# ============================================================================
Write-Host "1. Disabling CPU core parking..."

Set-PowerSettingValue "CPMINCORES" 100    # E-cores (Class 0) / all cores on non-hybrid
Set-PowerSettingValue "CPMINCORES1" 100   # P-cores (Class 1) - hybrid CPUs only

$parkingE = Get-PowerSettingAC "CPMINCORES"
$parkingP = Get-PowerSettingAC "CPMINCORES1"

if ($parkingP) {
    Write-Host "   E-cores: $parkingE | P-cores: $parkingP" -ForegroundColor Yellow
} else {
    Write-Host "   All cores: $parkingE" -ForegroundColor Yellow
}

# ============================================================================
# 2. Energy Performance Preference = max performance
# ============================================================================
Write-Host ""
Write-Host "2. Setting Energy Performance Preference to max performance..."

Set-PowerSettingValue "PERFEPP" 0    # E-cores (Class 0) / all cores on non-hybrid
Set-PowerSettingValue "PERFEPP1" 0   # P-cores (Class 1) - hybrid CPUs only

$eppE = Get-PowerSettingAC "PERFEPP"
$eppP = Get-PowerSettingAC "PERFEPP1"

if ($eppP) {
    Write-Host "   E-cores: $eppE | P-cores: $eppP" -ForegroundColor Yellow
} else {
    Write-Host "   All cores: $eppE" -ForegroundColor Yellow
}

# ============================================================================
# Apply changes
# ============================================================================
powercfg -setactive SCHEME_CURRENT

# ============================================================================
# Summary
# ============================================================================
Write-Host ""
Write-Host "===================================" -ForegroundColor Cyan
Write-Host "  DONE" -ForegroundColor Cyan
Write-Host "===================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Applied to current power scheme:"
Write-Host "  - CPU parking: DISABLED (all cores always active)"
Write-Host "  - EPP: 0 (max performance)"
Write-Host ""
Write-Host "Backup: $backupPath"
Write-Host "Roll back (in an Administrator PowerShell) - re-imports this backup and activates it:" -ForegroundColor DarkGray
Write-Host "  `$g=[regex]::Match((powercfg -import `"$backupPath`"),'[0-9a-fA-F-]{36}').Value; powercfg -setactive `$g" -ForegroundColor DarkGray
Write-Host ""

pause
