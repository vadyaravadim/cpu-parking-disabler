<#
.SYNOPSIS
    Disables CPU core parking and sets Energy Performance Preference to maximum performance.

.DESCRIPTION
    This script disables CPU core parking (CPMINCORES/CPMINCORES1 = 100%) and sets
    Energy Performance Preference (PERFEPP/PERFEPP1 = 0) on the current power scheme.

    Supports Intel 12th gen+ hybrid CPUs (separate P-core/E-core settings) and
    traditional non-hybrid CPUs (AMD Ryzen, older Intel).

    A backup of the current power scheme is saved to the Desktop before any changes.

.EXAMPLE
    .\cpu-parking-disabler.ps1

    Run as Administrator. No parameters needed.

.LINK
    https://github.com/vadyaravadim/cpu-parking-disabler
#>

# ============================================================================
# Helper: query current AC value for a power setting
# ============================================================================
function Get-PowerSettingAC($Setting) {
    powercfg -query SCHEME_CURRENT SUB_PROCESSOR $Setting |
        Select-String "Current AC Power Setting Index" |
        ForEach-Object { $_.ToString().Split(':')[1].Trim() }
}

# ============================================================================
# Admin check
# ============================================================================
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "ERROR: Run PowerShell as Administrator!" -ForegroundColor Red
    pause
    exit
}

Write-Host ""
Write-Host "===================================" -ForegroundColor Cyan
Write-Host "  CPU PARKING DISABLER" -ForegroundColor Cyan
Write-Host "===================================" -ForegroundColor Cyan
Write-Host ""

# ============================================================================
# Backup current power scheme to Desktop
# ============================================================================
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backupPath = "$env:USERPROFILE\Desktop\power_scheme_backup_$timestamp.pow"
powercfg -export $backupPath SCHEME_CURRENT 2>$null | Out-Null
Write-Host "Backup saved: $backupPath" -ForegroundColor Green
Write-Host ""

# ============================================================================
# Registry pre-config: unhide power settings so powercfg can access them
# Must be done BEFORE setting values — hidden settings may be ignored by OS
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

# E-cores (Class 0) - or all cores on non-hybrid CPUs
powercfg -setacvalueindex SCHEME_CURRENT SUB_PROCESSOR CPMINCORES 100
powercfg -setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR CPMINCORES 100

# P-cores (Class 1) - Intel 12th gen+ hybrid CPUs only
powercfg -setacvalueindex SCHEME_CURRENT SUB_PROCESSOR CPMINCORES1 100
powercfg -setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR CPMINCORES1 100

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

# E-cores (Class 0) - or all cores on non-hybrid CPUs
powercfg -setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PERFEPP 0
powercfg -setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PERFEPP 0

# P-cores (Class 1) - Intel 12th gen+ hybrid CPUs only
powercfg -setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PERFEPP1 0
powercfg -setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PERFEPP1 0

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
Write-Host "Rollback: powercfg -import `"$backupPath`"" -ForegroundColor DarkGray
Write-Host ""

pause
