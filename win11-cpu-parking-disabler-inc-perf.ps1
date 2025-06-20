# ============================================================================
# Windows 11 CPU Performance Optimizer
# Disables CPU parking and configures maximum processor performance
# 
# Author: https://github.com/vadyaravadim
# Version: 1.0
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
Write-Host ""
Write-Host "2. Disabling CPU core parking..."
powercfg -setacvalueindex SCHEME_CURRENT SUB_PROCESSOR CPMINCORES 100
powercfg -setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR CPMINCORES 100
$parkingAC = powercfg -query SCHEME_CURRENT SUB_PROCESSOR CPMINCORES | Select-String "Current AC Power Setting Index" | ForEach-Object { $_.ToString().Split(':')[1].Trim() }
$parkingDC = powercfg -query SCHEME_CURRENT SUB_PROCESSOR CPMINCORES | Select-String "Current DC Power Setting Index" | ForEach-Object { $_.ToString().Split(':')[1].Trim() }
Write-Host "   ✓ CPU parking disabled"
if ($parkingDC -and $parkingDC -ne $parkingAC) {
    Write-Host "   → AC: $parkingAC | DC: $parkingDC"
} else {
    Write-Host "   → AC: $parkingAC"
}

# 2. Minimum processor state
Write-Host ""
Write-Host "3. Setting minimum processor state..."
powercfg -setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 100
powercfg -setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 100
$minAC = powercfg -query SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN | Select-String "Current AC Power Setting Index" | ForEach-Object { $_.ToString().Split(':')[1].Trim() }
$minDC = powercfg -query SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN | Select-String "Current DC Power Setting Index" | ForEach-Object { $_.ToString().Split(':')[1].Trim() }
Write-Host "   ✓ Minimum processor state set"
if ($minDC -and $minDC -ne $minAC) {
    Write-Host "   → AC: $minAC | DC: $minDC"
} else {
    Write-Host "   → AC: $minAC"
}

# 3. Maximum processor state
Write-Host ""
Write-Host "4. Setting maximum processor state..."
powercfg -setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 100
powercfg -setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 100
$maxAC = powercfg -query SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX | Select-String "Current AC Power Setting Index" | ForEach-Object { $_.ToString().Split(':')[1].Trim() }
$maxDC = powercfg -query SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX | Select-String "Current DC Power Setting Index" | ForEach-Object { $_.ToString().Split(':')[1].Trim() }
Write-Host "   ✓ Maximum processor state set"
if ($maxDC -and $maxDC -ne $maxAC) {
    Write-Host "   → AC: $maxAC | DC: $maxDC"
} else {
    Write-Host "   → AC: $maxAC"
}

# 4. Performance thresholds
Write-Host ""
Write-Host "5. Configuring performance thresholds..."

# Performance increase threshold (aggressive: 10%)
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

# Performance decrease threshold (conservative: 40%) 
powercfg -setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PERFDECTHRESHOLD 40
powercfg -setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PERFDECTHRESHOLD 40
$decAC = powercfg -query SCHEME_CURRENT SUB_PROCESSOR PERFDECTHRESHOLD | Select-String "Current AC Power Setting Index" | ForEach-Object { $_.ToString().Split(':')[1].Trim() }
$decDC = powercfg -query SCHEME_CURRENT SUB_PROCESSOR PERFDECTHRESHOLD | Select-String "Current DC Power Setting Index" | ForEach-Object { $_.ToString().Split(':')[1].Trim() }
Write-Host "   ✓ Performance decrease threshold set"
if ($decDC -and $decDC -ne $decAC) {
    Write-Host "   → AC: $decAC | DC: $decDC"
} else {
    Write-Host "   → AC: $decAC"
}

# 5. Registry configuration
Write-Host ""
Write-Host "6. Configuring registry..."
try {
    # Show CPU parking settings in power options
    reg add "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\54533251-82be-4824-96c1-47b60b740d00\0cc5b647-c1df-4637-891a-dec35c318583" /v Attributes /t REG_DWORD /d 0 /f | Out-Null
    
    # Show additional processor performance settings
    reg add "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\54533251-82be-4824-96c1-47b60b740d00\06cadf0e-64ed-448a-8927-ce7bf90eb35d" /v Attributes /t REG_DWORD /d 0 /f | Out-Null
    reg add "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\54533251-82be-4824-96c1-47b60b740d00\12a0ab44-fe28-4fa9-b3bd-4b64f44960a6" /v Attributes /t REG_DWORD /d 0 /f | Out-Null
    
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