BeforeDiscovery {
    $script:x3dCases = @(
        @{ Name = 'AMD Ryzen 9 7900X3D 12-Core Processor'; Cores = 12; Expect = 'nonVCacheCcd' }
        @{ Name = 'AMD Ryzen 9 7950X3D 16-Core Processor'; Cores = 16; Expect = 'nonVCacheCcd' }
        @{ Name = 'AMD Ryzen 9 9900X3D 12-Core Processor'; Cores = 12; Expect = 'nonVCacheCcd' }
        @{ Name = 'AMD Ryzen 9 9950X3D 16-Core Processor'; Cores = 16; Expect = 'nonVCacheCcd' }
        @{ Name = 'AMD Ryzen 9 7945HX3D with Radeon Graphics'; Cores = 16; Expect = 'nonVCacheCcd' }
        @{ Name = 'AMD Ryzen 9 9955HX3D 16-Core Processor'; Cores = 16; Expect = 'nonVCacheCcd' }
        @{ Name = 'AMD Ryzen 9 9950X3D2 16-Core Processor'; Cores = 16; Expect = 'vCacheOnBothCcds' }
        @{ Name = 'AMD Ryzen 7 7800X3D 8-Core Processor'; Cores = 8; Expect = 'none' }
        @{ Name = 'AMD Ryzen 7 9800X3D 8-Core Processor'; Cores = 8; Expect = 'none' }
        @{ Name = 'Intel(R) Core(TM) i9-14900F'; Cores = 24; Expect = 'none' }
    )
    $script:isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

BeforeAll {
    $script:scriptPath = Join-Path $PSScriptRoot '..\cpu-parking-disabler.ps1'
    $script:scriptAst = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$null)

    function Find-ScriptNode([scriptblock]$Predicate) {
        $scriptAst.Find($Predicate, $true)
    }

    function Get-ShippedX3DNote {
        param([string]$Name, [int]$Cores)
        $fn = Find-ScriptNode { param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-X3DParkingNote' }
        if (-not $fn) { throw 'cpu-parking-disabler.ps1 defines no Get-X3DParkingNote' }
        . ([scriptblock]::Create($fn.Extent.Text))
        Get-X3DParkingNote -Name $Name -Cores $Cores
    }

    # A whole-script run (& $copy) may reach only this powercfg stub and Pester's
    # mocks: each check throws before the run can touch this machine.
    function Install-PowercfgStub([string[]]$Lines) {
        $stub = Join-Path $TestDrive 'powercfg.cmd'
        Set-Content -LiteralPath $stub -Value ($Lines -join "`r`n") -Encoding Ascii
        $env:PATH = "$TestDrive;$env:PATH"
        if ((Get-Command powercfg).Source -ne $stub) {
            throw 'the powercfg stub is not first on PATH: the whole-script test would change this machine''s power settings'
        }
        Mock Get-CimInstance { 'mock reached' } -ParameterFilter { $ClassName -eq 'Win32_PesterMockProbe' }
        $probe = Join-Path $TestDrive 'mock-probe.ps1'
        Set-Content -LiteralPath $probe -Value 'Get-CimInstance Win32_PesterMockProbe -ErrorAction SilentlyContinue' -Encoding Ascii
        $probeResult = $null
        try { $probeResult = & $probe } catch { $probeResult = $null }
        if ($probeResult -ne 'mock reached') {
            throw 'Pester mocks do not reach a script run with &: the whole-script tests would touch this machine'
        }
    }
}

Describe 'X3D parking note' {
    It '<Name> (<Cores> cores) gets the <Expect> note' -ForEach $x3dCases {
        $note = Get-ShippedX3DNote -Name $Name -Cores $Cores
        switch ($Expect) {
            'nonVCacheCcd' {
                $note.Text | Should -Match 'V-Cache on one of its two CCDs'
                $note.Prompt | Should -BeTrue -Because 'unparking moves game threads onto the CCD without V-Cache'
            }
            'vCacheOnBothCcds' {
                $note.Text | Should -Match 'V-Cache on both CCDs' -Because 'the 9950X3D2 carries 3D V-Cache on both CCDs'
                $note.Text | Should -Not -Match 'one of its two CCDs|non-V-Cache'
                $note.Prompt | Should -BeFalse -Because 'the 9950X3D2 gets a note only, no prompt'
            }
            'none' { $note | Should -BeNullOrEmpty }
        }
    }
}

Describe '-Undo keeps Windows defaults that had no user value' {
    BeforeAll {
        $guard = $scriptAst.Find({ param($n) $n -is [System.Management.Automation.Language.IfStatementAst] -and $n.Clauses[0].Item1.Extent.Text -match "InvocationName\s+-ne\s+'\.'" }, $false)
        if (-not $guard) {
            throw "cpu-parking-disabler.ps1 has no dot-source seam: wrap the run in if (`$MyInvocation.InvocationName -ne '.') { ... } after the function definitions, as bench\parking-bench.ps1 does, so the tests can load New-UndoSnapshot, Restore-UndoSnapshot and Get-UserPowerSettingIndex without running the script"
        }
        Mock powercfg { }
        Mock powershell { }
        Mock Start-Process { }
        Mock Read-Host { }
        Mock Invoke-RestMethod { }
        Mock Set-ItemProperty { }
        Mock New-ItemProperty { }
        Mock Remove-ItemProperty { }
        Mock Set-Content { }
        Mock Rename-Item { }
        Mock Start-Sleep { }
        Mock Write-Host { }
        . $scriptPath
        $script:balanced = '381b4222-f694-41f0-9685-ff5bb260df2e'
        $script:subgroup = '54533251-82be-4824-96c1-47b60b740d00'
        $script:minCoresGuid = '0cc5b647-c1df-4637-891a-dec35c318583'
        $script:userKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes\$balanced\$subgroup\$minCoresGuid"
    }

    BeforeEach {
        Mock Invoke-Powercfg { [pscustomobject]@{ Ok = $true; Text = '' } }
        Mock Show-PowerSetting { }
        Mock Remove-ItemProperty { }
    }

    It 'reads the explicit AC and DC user values of a setting from the user power scheme key' {
        Mock Get-ItemProperty { [pscustomobject]@{ ACSettingIndex = 100 } } -ParameterFilter { "$Path" -eq $userKey -or "$LiteralPath" -eq $userKey }
        $index = Get-UserPowerSettingIndex -Scheme $balanced -Guid $minCoresGuid
        $index.AC | Should -Be 100
        $index.DC | Should -BeNullOrEmpty
    }

    It 'records in the snapshot which values had an explicit user value' {
        Mock Get-UserPowerSettingIndex { [pscustomobject]@{ AC = $null; DC = 10 } }
        $settings = @([pscustomobject]@{ Name = 'CPMINCORES'; Guid = $minCoresGuid; AC = 4; DC = 10 })
        $snap = New-UndoSnapshot -Scheme ([pscustomobject]@{ Guid = $balanced; Name = 'Balanced' }) -Settings $settings
        $entry = @($snap.Values)[0]
        $entry.Setting | Should -Be 'CPMINCORES'
        $entry.UserAC | Should -BeFalse
        $entry.UserDC | Should -BeTrue
    }

    It 'deletes the user value it created instead of writing the old effective value back' {
        $snap = [pscustomobject]@{ Scheme = $balanced; SchemeName = 'Balanced'; Values = @([pscustomobject]@{ Setting = 'CPMINCORES'; AC = 4; DC = 10; UserAC = $false; UserDC = $false }) }
        Restore-UndoSnapshot -Snapshot $snap
        Should -Invoke Invoke-Powercfg -Times 0 -Exactly -ParameterFilter { $ArgumentList[0] -match '^/set(ac|dc)valueindex$' -and $ArgumentList -contains 'CPMINCORES' }
        Should -Invoke Remove-ItemProperty -Times 1 -Exactly -ParameterFilter { "$Path$LiteralPath" -eq $userKey -and $Name -eq 'ACSettingIndex' }
        Should -Invoke Remove-ItemProperty -Times 1 -Exactly -ParameterFilter { "$Path$LiteralPath" -eq $userKey -and $Name -eq 'DCSettingIndex' }
    }

    It 'writes back a value that had an explicit user value and deletes only the one that had none' {
        $snap = [pscustomobject]@{ Scheme = $balanced; SchemeName = 'Balanced'; Values = @([pscustomobject]@{ Setting = 'CPMINCORES'; AC = 25; DC = 10; UserAC = $true; UserDC = $false }) }
        Restore-UndoSnapshot -Snapshot $snap
        Should -Invoke Invoke-Powercfg -Times 1 -Exactly -ParameterFilter { $ArgumentList[0] -eq '/setacvalueindex' -and $ArgumentList[1] -eq $balanced -and $ArgumentList -contains 'CPMINCORES' -and "$($ArgumentList[-1])" -eq '25' }
        Should -Invoke Invoke-Powercfg -Times 0 -Exactly -ParameterFilter { $ArgumentList[0] -eq '/setdcvalueindex' -and $ArgumentList -contains 'CPMINCORES' }
        Should -Invoke Remove-ItemProperty -Times 1 -Exactly -ParameterFilter { "$Path$LiteralPath" -eq $userKey -and $Name -eq 'DCSettingIndex' }
        Should -Invoke Remove-ItemProperty -Times 0 -Exactly -ParameterFilter { $Name -eq 'ACSettingIndex' }
    }

    It 'unhides the setting before it writes or deletes a value and reapplies the scheme after the restore' {
        $script:calls = [System.Collections.Generic.List[string]]::new()
        Mock Show-PowerSetting { $script:calls.Add('show') }
        Mock Invoke-Powercfg { $script:calls.Add($ArgumentList[0]); [pscustomobject]@{ Ok = $true; Text = '' } }
        Mock Remove-ItemProperty { $script:calls.Add('remove') }
        $snap = [pscustomobject]@{ Scheme = $balanced; SchemeName = 'Balanced'; Values = @([pscustomobject]@{ Setting = 'CPMINCORES'; AC = 25; DC = 10; UserAC = $true; UserDC = $false }) }
        Restore-UndoSnapshot -Snapshot $snap
        Should -Invoke Show-PowerSetting -Times 1 -Exactly
        Should -Invoke Invoke-Powercfg -Times 1 -Exactly -ParameterFilter { $ArgumentList[0] -eq '/setactive' -and $ArgumentList[1] -eq 'SCHEME_CURRENT' }
        $script:calls[0] | Should -Be 'show'
        $script:calls | Should -Contain '/setacvalueindex'
        $script:calls | Should -Contain 'remove'
        $script:calls[-1] | Should -Be '/setactive'
    }

    It 'still writes the recorded values back from an undo file of 1.3.0 that has no user-value flags' {
        $snap = [pscustomobject]@{ Scheme = $balanced; SchemeName = 'Balanced'; Values = @([pscustomobject]@{ Setting = 'CPMINCORES'; AC = 4; DC = 10 }) }
        Restore-UndoSnapshot -Snapshot $snap
        Should -Invoke Invoke-Powercfg -Times 1 -Exactly -ParameterFilter { $ArgumentList[0] -eq '/setacvalueindex' -and $ArgumentList -contains 'CPMINCORES' -and "$($ArgumentList[-1])" -eq '4' }
        Should -Invoke Invoke-Powercfg -Times 1 -Exactly -ParameterFilter { $ArgumentList[0] -eq '/setdcvalueindex' -and $ArgumentList -contains 'CPMINCORES' -and "$($ArgumentList[-1])" -eq '10' }
        Should -Invoke Remove-ItemProperty -Times 0 -Exactly
    }
}

Describe 'PSScriptInfo version placeholder' {
    It 'is exactly .VERSION 0.0.0, the line release.yml stamps' {
        $lines = @(Select-String -LiteralPath $scriptPath -Pattern '^\.VERSION\b' | ForEach-Object Line)
        $lines.Count | Should -Be 1
        $lines[0] | Should -BeExactly '.VERSION 0.0.0'
    }
}

Describe 'Invoke-Powercfg under ErrorActionPreference Stop' {
    BeforeAll {
        $fn = Find-ScriptNode { param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Invoke-Powercfg' }
        . ([scriptblock]::Create($fn.Extent.Text))
        $script:stubError = 'stub powercfg failed'
        Set-Content -LiteralPath (Join-Path $TestDrive 'powercfg.cmd') -Value "@echo $stubError 1>&2`r`n@exit /b 1" -Encoding Ascii
        $script:savedPath = $env:PATH
        $env:PATH = "$TestDrive;$env:PATH"
    }

    AfterAll {
        $env:PATH = $savedPath
    }

    It 'returns a failed call with its stderr text instead of throwing' {
        $ErrorActionPreference = 'Stop'
        $result = Invoke-Powercfg @('/stub')
        $result.Ok | Should -BeFalse
        $result.Text | Should -Match $stubError
    }
}

Describe 'the irm | iex rerun forwards a single mode switch to powershell.exe -File' {
    It 'binds -Status in the rerun when it is the only forwarded switch' {
        $forwarder = Find-ScriptNode { param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-ForwardedSwitchList' }
        $bootstrap = Find-ScriptNode { param($n) $n -is [System.Management.Automation.Language.IfStatementAst] -and $n.Clauses[0].Item1.Extent.Text -eq '-not $PSCommandPath' }
        $rerun = @($bootstrap.Clauses[0].Item2.Statements | Where-Object { $_.Extent.Text -match '^(\$fwd\s*=|powershell\s)' })
        $rerun.Count | Should -Be 2
        $stub = Join-Path $TestDrive 'rerun-stub.ps1'
        Set-Content -LiteralPath $stub -Value 'param([switch]$Status, [switch]$Undo) "Status=$Status Undo=$Undo"' -Encoding Ascii
        $code = @('param($Status, $Undo, $saved)', $forwarder.Extent.Text) + @($rerun | ForEach-Object { $_.Extent.Text })
        & ([scriptblock]::Create($code -join "`n")) $true $false $stub | Should -Be 'Status=True Undo=False'
    }
}

Describe '-Status only reads' {
    BeforeAll {
        $script:copy = Join-Path $TestDrive 'cpu-parking-disabler.ps1'
        Copy-Item -LiteralPath $scriptPath -Destination $copy
        $script:savedPath = $env:PATH
        # Every value off target, so a run that went on past -Status would write
        # all four; the stub logs every call it gets.
        $script:callLog = Join-Path $TestDrive 'powercfg.log'
        Install-PowercfgStub @(
            '@echo off'
            '>>"%~dp0powercfg.log" echo %*'
            'if /i "%~1"=="/getactivescheme" goto scheme'
            'echo     0x00000032'
            'echo     0x00000032'
            'exit /b 0'
            ':scheme'
            'echo Power Scheme GUID: 381b4222-f694-41f0-9685-ff5bb260df2e  (Balanced)'
            'exit /b 0'
        )
    }

    AfterAll {
        $env:PATH = $savedPath
    }

    It 'shows the current state, writes nothing and leaves the undo branch alone when -Undo is given too' {
        Mock Get-CimInstance { [pscustomobject]@{ Name = 'Intel(R) Core(TM) i9-14900F'; NumberOfCores = 24; NumberOfLogicalProcessors = 32 } } -ParameterFilter { $ClassName -eq 'Win32_Processor' }
        Mock Get-CimInstance { }
        Mock Read-Host { 'n' }
        Mock Write-Host { if ("$Object" -like 'ERROR:*') { "$Object" } }
        Mock Start-Process { }
        Mock Set-ItemProperty { }
        Mock Remove-ItemProperty { }
        Mock Start-Sleep { }
        $output = & $copy -Status -Undo
        ($output | Where-Object { "$_" -like 'ERROR:*' }) -join "`n" | Should -BeNullOrEmpty -Because 'the run must not end in the trap'
        Should -Invoke Write-Host -Times 1 -Exactly -ParameterFilter { "$Object" -like 'CPU *:*' }
        Should -Invoke Write-Host -Times 0 -Exactly -ParameterFilter { "$Object" -like '*nothing to undo*' } -Because '-Status skips elevation, so it must never reach a branch that writes'
        $calls = @(Get-Content -LiteralPath $callLog)
        $calls | Should -Contain '/getactivescheme' -Because 'the run reads through the stub'
        $calls -match '^/set' | Should -BeNullOrEmpty -Because '-Status skips elevation, so it must never reach a branch that writes'
        Should -Invoke Set-ItemProperty -Times 0 -Exactly
        Should -Invoke Start-Process -Times 0 -Exactly
    }
}

Describe 'repeat run on an X3D with one V-Cache CCD' {
    BeforeAll {
        $script:copy = Join-Path $TestDrive 'cpu-parking-disabler.ps1'
        Copy-Item -LiteralPath $scriptPath -Destination $copy
        $script:savedPath = $env:PATH
        Install-PowercfgStub @(
            '@echo off'
            'if /i "%~1"=="/getactivescheme" goto scheme'
            'if /i "%~4"=="PERFEPP" goto zero'
            'if /i "%~4"=="PERFEPP1" goto zero'
            'echo     0x00000064'
            'echo     0x00000064'
            'exit /b 0'
            ':scheme'
            'echo Power Scheme GUID: 381b4222-f694-41f0-9685-ff5bb260df2e  (Balanced)'
            'exit /b 0'
            ':zero'
            'echo     0x00000000'
            'echo     0x00000000'
            'exit /b 0'
        )
    }

    AfterAll {
        $env:PATH = $savedPath
    }

    It 'says there is nothing to do without asking' -Skip:(-not $isAdmin) {
        Mock Get-CimInstance { [pscustomobject]@{ Name = 'AMD Ryzen 9 7950X3D 16-Core Processor'; NumberOfCores = 16; NumberOfLogicalProcessors = 32 } } -ParameterFilter { $ClassName -eq 'Win32_Processor' }
        Mock Get-CimInstance { }
        Mock Read-Host { 'n' }
        Mock Write-Host { }
        Mock Set-ItemProperty { }
        Mock Start-Sleep { }
        & $copy
        Should -Invoke Read-Host -Times 0 -Exactly -Because 'a run that will change nothing has nothing to confirm'
        Should -Invoke Write-Host -Times 1 -Exactly -ParameterFilter { "$Object" -like 'All values already at target*' }
    }
}

Describe 'PSScriptInfo metadata for the PowerShell Gallery' {
    BeforeAll {
        $script:infoValue = {
            param([string]$Key)
            $line = @(Select-String -LiteralPath $scriptPath -Pattern "^\.$Key\b" | ForEach-Object Line)
            $line.Count | Should -Be 1 -Because "PSScriptInfo has exactly one .$Key line"
            ($line[0] -replace "^\.$Key\s*", '').Trim()
        }
    }

    It 'PSScriptInfo copyright is the LICENSE copyright line' {
        $license = Join-Path $PSScriptRoot '..\LICENSE'
        & $infoValue 'COPYRIGHT' | Should -BeExactly (Get-Content -LiteralPath $license)[2]
    }

    It 'PSScriptInfo tags list PSEdition_Desktop and PSEdition_Core' {
        $tags = (& $infoValue 'TAGS') -split '\s+'
        $tags | Should -Contain 'PSEdition_Desktop'
        $tags | Should -Contain 'PSEdition_Core'
    }

    It 'PSScriptInfo release notes are the CHANGELOG of .PROJECTURI' {
        & $infoValue 'RELEASENOTES' | Should -BeExactly ((& $infoValue 'PROJECTURI') + '/blob/main/CHANGELOG.md')
    }
}
