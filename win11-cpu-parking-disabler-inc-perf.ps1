# ============================================================================
# Windows 11 CPU Performance Optimizer
# Disables CPU parking and configures maximum processor performance
# 
# Author: https://github.com/vadyaravadim
# Version: 2.0
# Requirements: Windows 11, Run as Administrator
# ============================================================================

Write-Host "==================================="
Write-Host "CPU PERFORMANCE OPTIMIZER"
Write-Host "==================================="
Write-Host ""

# Check Administrator privileges
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "ERROR: Run PowerShell as Administrator!"
    pause
    exit
}

# 1. Disable CPU parking
# CPMINCORES - Processor Performance Core Parking Min Cores (E-cores on hybrid CPUs)
# DEFAULT: 10% (Balanced plan), 100% (High Performance plan)
# CPMINCORES1 - Core Parking Min Cores for P-cores (Intel hybrid CPUs only)
# DEFAULT: 10% (Balanced plan), 100% (High Performance plan)
# Setting to 100 disables core parking completely
Write-Host ""
Write-Host "1. Disabling CPU core parking..."
powercfg -setacvalueindex SCHEME_CURRENT SUB_PROCESSOR CPMINCORES 100
powercfg -setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR CPMINCORES 100
# P-cores (Intel 12th gen+)
powercfg -setacvalueindex SCHEME_CURRENT SUB_PROCESSOR CPMINCORES1 100
powercfg -setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR CPMINCORES1 100
$parkingAC = powercfg -query SCHEME_CURRENT SUB_PROCESSOR CPMINCORES | Select-String "Current AC Power Setting Index" | ForEach-Object { $_.ToString().Split(':')[1].Trim() }
$parkingDC = powercfg -query SCHEME_CURRENT SUB_PROCESSOR CPMINCORES | Select-String "Current DC Power Setting Index" | ForEach-Object { $_.ToString().Split(':')[1].Trim() }
Write-Host "   ✓ CPU parking disabled"
if ($parkingDC -and $parkingDC -ne $parkingAC) {
    Write-Host "   → AC: $parkingAC | DC: $parkingDC"
} else {
    Write-Host "   → AC: $parkingAC"
}

# 2. Minimum processor state
# PROCTHROTTLEMIN - Minimum Processor Performance State (E-cores on hybrid CPUs)
# DEFAULT: 5% (Balanced plan)
# PROCTHROTTLEMIN1 - Minimum Processor State for P-cores (Intel hybrid CPUs only)
# DEFAULT: 5% (Balanced plan)
# Setting to 100 prevents CPU from throttling down
Write-Host ""
Write-Host "2. Setting minimum processor state..."
powercfg -setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 100
powercfg -setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 100
# P-cores (Intel 12th gen+)
powercfg -setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN1 100
powercfg -setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN1 100
$minAC = powercfg -query SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN | Select-String "Current AC Power Setting Index" | ForEach-Object { $_.ToString().Split(':')[1].Trim() }
$minDC = powercfg -query SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN | Select-String "Current DC Power Setting Index" | ForEach-Object { $_.ToString().Split(':')[1].Trim() }
Write-Host "   ✓ Minimum processor state set"
if ($minDC -and $minDC -ne $minAC) {
    Write-Host "   → AC: $minAC | DC: $minDC"
} else {
    Write-Host "   → AC: $minAC"
}

# 3. Maximum processor state
# PROCTHROTTLEMAX - Maximum Processor Performance State (E-cores on hybrid CPUs)
# DEFAULT: 100% (all power plans)
# PROCTHROTTLEMAX1 - Maximum Processor State for P-cores (Intel hybrid CPUs only)
# DEFAULT: 100% (all power plans)
# Setting to 100 allows full CPU performance
Write-Host ""
Write-Host "3. Setting maximum processor state..."
powercfg -setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 100
powercfg -setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 100
# P-cores (Intel 12th gen+)
powercfg -setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX1 100
powercfg -setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX1 100
$maxAC = powercfg -query SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX | Select-String "Current AC Power Setting Index" | ForEach-Object { $_.ToString().Split(':')[1].Trim() }
$maxDC = powercfg -query SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX | Select-String "Current DC Power Setting Index" | ForEach-Object { $_.ToString().Split(':')[1].Trim() }
Write-Host "   ✓ Maximum processor state set"
if ($maxDC -and $maxDC -ne $maxAC) {
    Write-Host "   → AC: $maxAC | DC: $maxDC"
} else {
    Write-Host "   → AC: $maxAC"
}

# 4. Performance thresholds
# PERFINCTHRESHOLD - Processor Performance Increase Threshold
# DEFAULT: N/A (varies by OEM/hardware, commonly ~30% on Balanced)
# Lower value = faster frequency scaling up when load increases
Write-Host ""
Write-Host "4. Configuring performance thresholds..."
powercfg -setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PERFINCTHRESHOLD 10
powercfg -setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PERFINCTHRESHOLD 10
$incAC = powercfg -query SCHEME_CURRENT SUB_PROCESSOR PERFINCTHRESHOLD | Select-String "Current AC Power Setting Index" | ForEach-Object { $_.ToString().Split(':')[1].Trim() }
$incDC = powercfg -query SCHEME_CURRENT SUB_PROCESSOR PERFINCTHRESHOLD | Select-String "Current DC Power Setting Index" | ForEach-Object { $_.ToString().Split(':')[1].Trim() }
Write-Host "   ✓ Performance increase threshold set"
if ($incDC -and $incDC -ne $incAC) {
    Write-Host "   → AC: $incAC | DC: $incDC"
} else {
    Write-Host "   → AC: $incAC"
}

# PERFDECTHRESHOLD - Processor Performance Decrease Threshold
# DEFAULT: N/A (varies by OEM/hardware, commonly ~10% on Balanced)
# Higher value = slower frequency scaling down when load decreases
powercfg -setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PERFDECTHRESHOLD 60
powercfg -setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PERFDECTHRESHOLD 60
$decAC = powercfg -query SCHEME_CURRENT SUB_PROCESSOR PERFDECTHRESHOLD | Select-String "Current AC Power Setting Index" | ForEach-Object { $_.ToString().Split(':')[1].Trim() }
$decDC = powercfg -query SCHEME_CURRENT SUB_PROCESSOR PERFDECTHRESHOLD | Select-String "Current DC Power Setting Index" | ForEach-Object { $_.ToString().Split(':')[1].Trim() }
Write-Host "   ✓ Performance decrease threshold set"
if ($decDC -and $decDC -ne $decAC) {
    Write-Host "   → AC: $decAC | DC: $decDC"
} else {
    Write-Host "   → AC: $decAC"
}

# 5. Processor Performance Boost Mode
# PERFBOOSTMODE - Processor Performance Boost Mode
# DEFAULT: 2 (Aggressive) on Windows 11 desktop
# Values: 0=Disabled, 1=Enabled, 2=Aggressive, 3=Efficient Enabled, 4=Efficient Aggressive
Write-Host ""
Write-Host "5. Setting Processor Performance Boost Mode..."
powercfg -setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PERFBOOSTMODE 2
powercfg -setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PERFBOOSTMODE 2
$boostAC = powercfg -query SCHEME_CURRENT SUB_PROCESSOR PERFBOOSTMODE | Select-String "Current AC Power Setting Index" | ForEach-Object { $_.ToString().Split(':')[1].Trim() }
$boostDC = powercfg -query SCHEME_CURRENT SUB_PROCESSOR PERFBOOSTMODE | Select-String "Current DC Power Setting Index" | ForEach-Object { $_.ToString().Split(':')[1].Trim() }
Write-Host "   ✓ Boost mode set"
if ($boostDC -and $boostDC -ne $boostAC) {
    Write-Host "   → AC: $boostAC | DC: $boostDC"
} else {
    Write-Host "   → AC: $boostAC"
}

# Apply all changes
powercfg -setactive SCHEME_CURRENT

# 6. Registry configuration
# Attributes registry values: 0 or 2 = visible in Power Options, 1 = hidden
# DEFAULT: 1 (hidden) for all advanced processor settings
Write-Host ""
Write-Host "6. Configuring registry..."
try {
    # Unhide CPU core parking control (CPMINCORES)
    # DEFAULT: 1 (hidden)
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\54533251-82be-4824-96c1-47b60b740d00\0cc5b647-c1df-4637-891a-dec35c318583" /v Attributes /t REG_DWORD /d 0 /f | Out-Null

    # Unhide processor performance increase threshold (PERFINCTHRESHOLD)
    # DEFAULT: 1 (hidden)
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\54533251-82be-4824-96c1-47b60b740d00\06cadf0e-64ed-448a-8927-ce7bf90eb35d" /v Attributes /t REG_DWORD /d 0 /f | Out-Null

    # Unhide processor performance decrease threshold (PERFDECTHRESHOLD)
    # DEFAULT: 1 (hidden)
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\54533251-82be-4824-96c1-47b60b740d00\12a0ab44-fe28-4fa9-b3bd-4b64f44960a6" /v Attributes /t REG_DWORD /d 0 /f | Out-Null

    # Unhide Processor Performance Boost Mode (PERFBOOSTMODE)
    # DEFAULT: 1 (hidden)
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\54533251-82be-4824-96c1-47b60b740d00\be337238-0d82-4146-a960-4f3749d470c7" /v Attributes /t REG_DWORD /d 0 /f | Out-Null

    # Unhide Heterogeneous Thread Scheduling Policy (Intel hybrid CPUs: P/E-core scheduling)
    # DEFAULT: 1 (hidden) for Attributes
    # Setting value DEFAULT: 5 (Automatic) - works with Intel Thread Director
    # Values: 0=All Processors, 1=Performant (P-cores only), 2=Prefer Performant,
    #         3=Efficient (E-cores only), 4=Prefer Efficient, 5=Automatic
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\54533251-82be-4824-96c1-47b60b740d00\bae08b81-2d5e-4688-ad6a-13243356654b" /v Attributes /t REG_DWORD /d 0 /f | Out-Null

    # Unhide Processor Performance Autonomous Mode (CPPC v2 - Intel Thread Director / AMD CPPC)
    # DEFAULT: 1 (hidden) for Attributes
    # Setting value DEFAULT: 1 (Enabled) - lets hardware/firmware control P-states
    # Values: 0=Disabled (OS controls), 1=Enabled (Hardware/ITD controls)
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\54533251-82be-4824-96c1-47b60b740d00\8baa4a8a-14c6-4451-8e8b-14bdbd197537" /v Attributes /t REG_DWORD /d 0 /f | Out-Null

    # Unhide Energy Performance Preference (EPP)
    # DEFAULT: 1 (hidden)
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\54533251-82be-4824-96c1-47b60b740d00\36687f9e-e3a5-4dbf-b1dc-15eb381c6863" /v Attributes /t REG_DWORD /d 0 /f | Out-Null

    # Unhide Processor Idle Disable
    # DEFAULT: 1 (hidden)
    reg add "HKLM\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\54533251-82be-4824-96c1-47b60b740d00\5d76a2ca-e8c0-402f-a133-2158492d58ad" /v Attributes /t REG_DWORD /d 0 /f | Out-Null

    Write-Host "   ✓ Registry keys updated"
    
    # Verify registry keys
    $parkingKey = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\54533251-82be-4824-96c1-47b60b740d00\0cc5b647-c1df-4637-891a-dec35c318583" -Name "Attributes" -ErrorAction SilentlyContinue
    Write-Host "   → CPU parking in power options: $($parkingKey.Attributes)"
    
} catch {
    Write-Host "   ⚠️ Registry configuration error" -ForegroundColor Yellow
}

# Create backup
Write-Host ""
Write-Host "Creating backup..."
$backupPath = "$env:USERPROFILE\Desktop\cpu_performance_backup.pow"
powercfg -export $backupPath SCHEME_CURRENT
Write-Host "✓ Backup saved: $backupPath"

Write-Host ""
Write-Host "==================================="
Write-Host "CONFIGURATION COMPLETED"
Write-Host "==================================="
Write-Host ""
Write-Host "All settings applied successfully!"
Write-Host "Backup saved to desktop."
Write-Host ""
Write-Host "For full registry changes to take effect,"
Write-Host "a system restart is recommended."
Write-Host ""

$reboot = Read-Host "Restart computer now? (y/n)"
if ($reboot -eq "y" -or $reboot -eq "Y") {
    Write-Host ""
    Write-Host "Restarting in 10 seconds..."
    Write-Host "Press Ctrl+C to cancel"
    
    for ($i = 10; $i -gt 0; $i--) {
        Write-Host "Restarting in $i seconds..." -NoNewline
        Start-Sleep -Seconds 1
        Write-Host "`r" -NoNewline
    }
    
    Write-Host ""
    Write-Host "Restarting..." -ForegroundColor Green
    Restart-Computer -Force
} else {
    Write-Host ""
    Write-Host "Restart cancelled." -ForegroundColor Yellow
    Write-Host "Don't forget to restart your computer later"
    Write-Host "for full registry changes to take effect!"
}

pause