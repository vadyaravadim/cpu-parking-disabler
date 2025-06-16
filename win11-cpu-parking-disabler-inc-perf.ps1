# ============================================================================
# Windows 11 CPU Performance Optimizer
# Отключает паркинг CPU и настраивает максимальную производительность процессора
# 
# Автор: https://github.com/[ваш-username]
# Версия: 1.0
# Требования: Windows 11, запуск от имени администратора
# ============================================================================

# Настройка максимальной производительности процессора
# Запускать от имени администратора!

Write-Host "==================================="
Write-Host "НАСТРОЙКА ПРОИЗВОДИТЕЛЬНОСТИ CPU"
Write-Host "==================================="
Write-Host ""

# Проверка прав администратора
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "ОШИБКА: Запустите PowerShell от имени администратора!"
    pause
    exit
}

# 1. Активация схемы Ultimate Performance
Write-Host "1. Настройка схемы электропитания..."
try {
    powercfg -setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c
    $currentScheme = powercfg -getactivescheme
    Write-Host "   ✓ Активная схема: $currentScheme"
} catch {
    $currentScheme = powercfg -getactivescheme
    Write-Host "   - Текущая схема: $currentScheme"
}

# 2. Отключение паркинга CPU
Write-Host ""
Write-Host "2. Отключение паркинга процессора..."
powercfg -setacvalueindex SCHEME_CURRENT SUB_PROCESSOR CPMINCORES 100
powercfg -setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR CPMINCORES 100
$parkingAC = powercfg -query SCHEME_CURRENT SUB_PROCESSOR CPMINCORES | Select-String "Current AC Power Setting Index" | ForEach-Object { $_.ToString().Split(':')[1].Trim() }
$parkingDC = powercfg -query SCHEME_CURRENT SUB_PROCESSOR CPMINCORES | Select-String "Current DC Power Setting Index" | ForEach-Object { $_.ToString().Split(':')[1].Trim() }
Write-Host "   ✓ Паркинг CPU отключен"
Write-Host "   → AC: $parkingAC | DC: $parkingDC"

# 3. Минимальное состояние процессора
Write-Host ""
Write-Host "3. Минимальное состояние процессора..."
powercfg -setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 100
powercfg -setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 100
$minAC = powercfg -query SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN | Select-String "Current AC Power Setting Index" | ForEach-Object { $_.ToString().Split(':')[1].Trim() }
$minDC = powercfg -query SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN | Select-String "Current DC Power Setting Index" | ForEach-Object { $_.ToString().Split(':')[1].Trim() }
Write-Host "   ✓ Минимальное состояние установлено"
Write-Host "   → AC: $minAC | DC: $minDC"

# 4. Максимальное состояние процессора
Write-Host ""
Write-Host "4. Максимальное состояние процессора..."
powercfg -setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 100
powercfg -setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 100
$maxAC = powercfg -query SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX | Select-String "Current AC Power Setting Index" | ForEach-Object { $_.ToString().Split(':')[1].Trim() }
$maxDC = powercfg -query SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX | Select-String "Current DC Power Setting Index" | ForEach-Object { $_.ToString().Split(':')[1].Trim() }
Write-Host "   ✓ Максимальное состояние установлено"
Write-Host "   → AC: $maxAC | DC: $maxDC"

# 5. Пороги производительности процессора
Write-Host ""
Write-Host "5. Настройка порогов производительности..."

# Порог увеличения производительности (агрессивный: 10%)
powercfg -setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PERFINCTHRESHOLD 10
powercfg -setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PERFINCTHRESHOLD 10
$incAC = powercfg -query SCHEME_CURRENT SUB_PROCESSOR PERFINCTHRESHOLD | Select-String "Current AC Power Setting Index" | ForEach-Object { $_.ToString().Split(':')[1].Trim() }
$incDC = powercfg -query SCHEME_CURRENT SUB_PROCESSOR PERFINCTHRESHOLD | Select-String "Current DC Power Setting Index" | ForEach-Object { $_.ToString().Split(':')[1].Trim() }
Write-Host "   ✓ Порог увеличения производительности установлен"
Write-Host "   → AC: $incAC | DC: $incDC"

# Порог снижения производительности (консервативный: 80%) 
powercfg -setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PERFDECTHRESHOLD 80
powercfg -setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PERFDECTHRESHOLD 80
$decAC = powercfg -query SCHEME_CURRENT SUB_PROCESSOR PERFDECTHRESHOLD | Select-String "Current AC Power Setting Index" | ForEach-Object { $_.ToString().Split(':')[1].Trim() }
$decDC = powercfg -query SCHEME_CURRENT SUB_PROCESSOR PERFDECTHRESHOLD | Select-String "Current DC Power Setting Index" | ForEach-Object { $_.ToString().Split(':')[1].Trim() }
Write-Host "   ✓ Порог снижения производительности установлен"
Write-Host "   → AC: $decAC | DC: $decDC"

# 7. Настройки реестра для CPU
Write-Host ""
Write-Host "6. Настройка реестра..."
try {
    # Показываем настройки паркинга CPU в панели управления
    reg add "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\54533251-82be-4824-96c1-47b60b740d00\0cc5b647-c1df-4637-891a-dec35c318583" /v Attributes /t REG_DWORD /d 0 /f | Out-Null
    
    # Показываем дополнительные настройки производительности процессора
    reg add "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\54533251-82be-4824-96c1-47b60b740d00\06cadf0e-64ed-448a-8927-ce7bf90eb35d" /v Attributes /t REG_DWORD /d 0 /f | Out-Null
    reg add "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\54533251-82be-4824-96c1-47b60b740d00\12a0ab44-fe28-4fa9-b3bd-4b64f44960a6" /v Attributes /t REG_DWORD /d 0 /f | Out-Null
    
    Write-Host "   ✓ Ключи реестра обновлены"
    
    # Проверка ключей реестра
    $parkingKey = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\54533251-82be-4824-96c1-47b60b740d00\0cc5b647-c1df-4637-891a-dec35c318583" -Name "Attributes" -ErrorAction SilentlyContinue
    Write-Host "   → Паркинг CPU в панели управления: $($parkingKey.Attributes)"
    
} catch {
    Write-Host "   ⚠️ Ошибка настройки реестра" -ForegroundColor Yellow
}

# Применение настроек
Write-Host ""
Write-Host "Применение настроек..."
powercfg -setactive SCHEME_CURRENT

# Создание резервной копии
$backupPath = "$env:USERPROFILE\Desktop\cpu_performance_backup.pow"
powercfg -export $backupPath SCHEME_CURRENT
Write-Host "✓ Резервная копия: $backupPath"

Write-Host ""
Write-Host "==================================="
Write-Host "НАСТРОЙКА ЗАВЕРШЕНА"
Write-Host "==================================="
Write-Host ""
Write-Host "Все настройки применены успешно!"
Write-Host "Резервная копия сохранена на рабочем столе."
Write-Host ""
Write-Host "Для полного применения изменений реестра"
Write-Host "рекомендуется перезагрузить компьютер."
Write-Host ""

$reboot = Read-Host "Перезагрузить компьютер сейчас? (y/n)"
if ($reboot -eq "y" -or $reboot -eq "Y" -or $reboot -eq "да" -or $reboot -eq "Да") {
    Write-Host ""
    Write-Host "Перезагрузка через 10 секунд..."
    Write-Host "Нажмите Ctrl+C для отмены"
    
    for ($i = 10; $i -gt 0; $i--) {
        Write-Host "Перезагрузка через $i секунд..." -NoNewline
        Start-Sleep -Seconds 1
        Write-Host "`r" -NoNewline
    }
    
    Write-Host ""
    Write-Host "Перезагрузка..." -ForegroundColor Green
    Restart-Computer -Force
} else {
    Write-Host ""
    Write-Host "Перезагрузка отменена." -ForegroundColor Yellow
    Write-Host "Не забудьте перезагрузить компьютер позже для"
    Write-Host "полного применения изменений реестра!"
}

pause