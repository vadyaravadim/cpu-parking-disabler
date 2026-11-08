BeforeAll {
    . (Join-Path $PSScriptRoot '..\parking-bench.ps1') -Phase 'import-test'
}

Describe 'Get-BurstSummary' {
    BeforeAll {
        $script:work = New-Object 'long[,]' 2, 4
        $values = @(@(10, 20, 30, 40), @(50, 60, 70, 80))
        for ($b = 0; $b -lt 2; $b++) { for ($w = 0; $w -lt 4; $w++) { $work[$b, $w] = $values[$b][$w] * 1000 } }
        $script:wake = New-Object 'double[,]' 2, 3
        $wake[0, 0] = 0.1; $wake[0, 1] = 0.4; $wake[0, 2] = 0.2
        $wake[1, 0] = 0.3; $wake[1, 1] = 0.1; $wake[1, 2] = 0.9
        $script:summary = Get-BurstSummary -Work $work -WakeMs $wake -ItersPerMs 1000 -WindowMs 1 -EarlyMs 2
    }
    It 'sums the early windows per burst in core-ms' {
        $summary.earlyWindowMs | Should -Be 2
        $summary.earlyCoreMs.min | Should -Be 30
        $summary.earlyCoreMs.max | Should -Be 110
    }
    It 'sums the whole burst per burst in core-ms' {
        $summary.totalCoreMs.min | Should -Be 100
        $summary.totalCoreMs.max | Should -Be 260
    }
    It 'takes the last worker wake of each burst' {
        $summary.lastWorkerWakeMs.min | Should -Be 0.4
        $summary.lastWorkerWakeMs.max | Should -Be 0.9
    }
    It 'reports the median busy cores per window across bursts' {
        $summary.busyCoresPerWindowMedian | Should -Be @(50, 60, 70, 80)
    }
}

Describe 'Get-ParkedSummary' {
    It 'keeps unavailable samples out of the spread and counts them' {
        $s = Get-ParkedSummary -Values @(4, -1, 8, 6) -Total 32
        $s.samples | Should -Be 4
        $s.unavailable | Should -Be 1
        $s.parked.min | Should -Be 4
        $s.parked.max | Should -Be 8
        $s.parked.median | Should -Be 6
    }
    It 'reports no spread when the counter never answered' {
        (Get-ParkedSummary -Values @(-1, -1) -Total 32).parked | Should -BeNullOrEmpty
    }
}

Describe 'Get-CoreClassSummary' {
    It 'counts the logical CPUs per efficiency class and the share of threads that ended on each' {
        $cpu = New-Object 'int[,]' 2, 2
        $cpu[0, 0] = 0; $cpu[0, 1] = 2; $cpu[1, 0] = 3; $cpu[1, 1] = -1
        $s = Get-CoreClassSummary -Cpu $cpu -EfficiencyClass @(1, 1, 0, 0)
        ($s.logicalCpusPerClass | Where-Object efficiencyClass -eq 1).cpus | Should -Be 2
        ($s.threadShareAtEndPerClass | Where-Object efficiencyClass -eq 0).share | Should -Be 0.5
        ($s.threadShareAtEndPerClass | Where-Object efficiencyClass -eq 1).share | Should -Be 0.25
        $s.unknown | Should -Be 1
    }
}

Describe 'Get-ParkingBenchConfig' {
    It 'pins the trace session, provider, keyword and Game Mode registry names the bench and the runner share' {
        $cfg = Get-ParkingBenchConfig
        $cfg.TraceSession | Should -BeExactly 'rigpolice-ppm'
        $cfg.EtlPrefix | Should -BeExactly 'rigpolice-ppm-'
        $cfg.KppProvider | Should -BeExactly '{0F67E49F-FE51-4E9F-B490-6F2948CC6027}'
        $cfg.KppProviderName | Should -BeExactly 'Microsoft-Windows-Kernel-Processor-Power'
        $cfg.KppKeyword | Should -BeExactly '0x44'
        $cfg.KppLevel | Should -Be 4
        $cfg.ProfileChangeEventId | Should -Be 104
        $cfg.GameBarKey | Should -BeExactly 'HKCU:\Software\Microsoft\GameBar'
        $cfg.GameModeValue | Should -BeExactly 'AutoGameModeEnabled'
        $cfg.CapTolerance | Should -Be 0.02
        $cfg.SlowFrameFactor | Should -Be 1.5
    }
}

Describe 'Assert-FpsMaxArgument' {
    It 'accepts 0 with any test and a positive rate with the game test' {
        { Assert-FpsMaxArgument -FpsMax 0 -Test 'burst' } | Should -Not -Throw
        { Assert-FpsMaxArgument -FpsMax 144 -Test 'game' } | Should -Not -Throw
    }
    It 'refuses a negative rate' {
        { Assert-FpsMaxArgument -FpsMax -1 -Test 'game' } | Should -Throw '*-FpsMax*'
    }
    It 'refuses a rate with a test other than game' {
        { Assert-FpsMaxArgument -FpsMax 144 -Test 'burst' } | Should -Throw '*-Test game*'
        { Assert-FpsMaxArgument -FpsMax 144 -Test 'framesim' } | Should -Throw '*-Test game*'
    }
}

Describe 'Get-CapSummary' {
    BeforeAll {
        function New-CapRow([double]$Ms) { [pscustomobject]@{ MsBetweenPresents = "$Ms" } }
    }
    It 'reports the period of 144 fps as 6.944 ms with the tolerance and the slow factor' {
        $s = Get-CapSummary -Row @(New-CapRow 6.9) -FpsMax 144
        $s.fpsMax | Should -Be 144
        $s.periodMs | Should -Be 6.944
        $s.tolerance | Should -Be 0.02
        $s.slowFrameFactor | Should -Be 1.5
    }
    It 'counts only frames strictly above 1.5 periods' {
        $rows = @((New-CapRow 8), (New-CapRow 12.0), (New-CapRow 12.001), (New-CapRow 30))
        (Get-CapSummary -Row $rows -FpsMax 125).slowFrames | Should -Be 2
        (Get-CapSummary -Row @(New-CapRow 12.0) -FpsMax 125).slowFrames | Should -Be 0
        (Get-CapSummary -Row @(New-CapRow 12.001) -FpsMax 125).slowFrames | Should -Be 1
    }
}

Describe 'Get-CapRejection' {
    It 'accepts a median inside 2% of the period' -ForEach @(6.806, 6.944, 7.083) {
        Get-CapRejection -Stats ([pscustomobject]@{ p50Ms = $_ }) -FpsMax 144 | Should -BeNullOrEmpty
    }
    It 'rejects a median outside 2% of the period' -ForEach @(6.804, 7.084, 1.14) {
        Get-CapRejection -Stats ([pscustomobject]@{ p50Ms = $_ }) -FpsMax 144 | Should -Not -BeNullOrEmpty
    }
    It 'names the cap, the period and the tolerance in the reason' {
        $reason = Get-CapRejection -Stats ([pscustomobject]@{ p50Ms = 1.14 }) -FpsMax 144
        $reason | Should -BeLike '*fps_max 144*'
        $reason | Should -BeLike '*6.944*'
        $reason | Should -BeLike '*2%*'
    }
}

Describe 'Assert-CapOffRefresh' {
    It 'passes 144 fps at <_> Hz' -ForEach @(180, 149) {
        { Assert-CapOffRefresh -FpsMax 144 -RefreshHz $_ } | Should -Not -Throw
    }
    It 'throws 144 fps at <_> Hz' -ForEach @(144, 148) {
        { Assert-CapOffRefresh -FpsMax 144 -RefreshHz $_ } | Should -Throw '*refresh*'
    }
    It 'throws when the refresh rate is unknown (<_>)' -ForEach @(0, -1) {
        { Assert-CapOffRefresh -FpsMax 144 -RefreshHz $_ } | Should -Throw '*refresh rate*'
    }
}

Describe 'ConvertFrom-PpmEvent' {
    BeforeAll {
        $script:start = [datetime]'2026-11-08T12:00:00'
        $script:end = $start.AddSeconds(100)
        function New-PpmEvent([int]$Id, [double]$Offset, [object[]]$Value) {
            [pscustomobject]@{ Id = $Id; Time = $start.AddSeconds($Offset); Values = $Value }
        }
        function Convert-Ppm($Record, $Before = $true, $Lost = 0) {
            ConvertFrom-PpmEvent -Record $Record -Start $start -End $end -StartedBeforeLoad $Before -BuffersLost $Lost
        }
    }
    It 'takes the profile of a change before the window as the capture profile' {
        $ppm = Convert-Ppm @(New-PpmEvent 104 -40 @(0, 12))
        $ppm.captureProfile | Should -Be 12
        $ppm.captureChanges | Should -Be 0
        $ppm.profileChanges.Count | Should -Be 1
        $ppm.profileChanges[0].offsetSeconds | Should -Be -40
        $ppm.profileChanges[0].from | Should -Be 0
        $ppm.profileChanges[0].to | Should -Be 12
    }
    It 'treats a change exactly at the window start as before the window' {
        $ppm = Convert-Ppm @(New-PpmEvent 104 0 @(5, 7))
        $ppm.captureProfile | Should -Be 7
        $ppm.captureChanges | Should -Be 0
        $ppm.profileChanges[0].offsetSeconds | Should -Be 0
    }
    It 'gives no capture profile and one change for a change inside the window' {
        $ppm = Convert-Ppm @((New-PpmEvent 104 -40 @(0, 12)), (New-PpmEvent 104 10 @(12, 0)))
        $ppm.captureProfile | Should -BeNullOrEmpty
        $ppm.captureChanges | Should -Be 1
        $ppm.profileChanges.Count | Should -Be 2
    }
    It 'counts a change exactly at the window end as inside and one after it as outside' {
        (Convert-Ppm @(New-PpmEvent 104 100 @(1, 2))).captureChanges | Should -Be 1
        $late = Convert-Ppm @((New-PpmEvent 104 -3 @(0, 12)), (New-PpmEvent 104 105 @(12, 0)))
        $late.captureChanges | Should -Be 0
        $late.captureProfile | Should -Be 12
        $late.profileChanges.Count | Should -Be 2
    }
    It 'takes the last change before the window whatever the input order' {
        $ppm = Convert-Ppm @((New-PpmEvent 104 -5 @(12, 0)), (New-PpmEvent 104 -40 @(0, 12)))
        $ppm.captureProfile | Should -Be 0
        $ppm.profileChanges[0].offsetSeconds | Should -Be -40
    }
    It 'returns an empty list and no capture profile without any profile change' {
        $ppm = Convert-Ppm @()
        @($ppm.profileChanges).Count | Should -Be 0
        $ppm.captureProfile | Should -BeNullOrEmpty
        $ppm.captureChanges | Should -Be 0
    }
    It 'ignores events with other ids' {
        $ppm = Convert-Ppm @((New-PpmEvent 102 -50 @('Game Mode', 12)), (New-PpmEvent 105 5 @(1, 2)), (New-PpmEvent 104 -40 @(0, 12)))
        $ppm.profileChanges.Count | Should -Be 1
        $ppm.captureChanges | Should -Be 0
        $ppm.captureProfile | Should -Be 12
    }
    It 'rounds the offsets to 3 decimals' {
        (Convert-Ppm @(New-PpmEvent 104 -1.23456 @(1, 2))).profileChanges[0].offsetSeconds | Should -Be -1.235
    }
    It 'has exactly the ppm key list and carries the session facts' {
        $ppm = Convert-Ppm @() $false 3
        @($ppm.PSObject.Properties.Name) | Should -Be @('session', 'keyword', 'startedBeforeLoad', 'buffersLost', 'profileChanges', 'captureProfile', 'captureChanges')
        $ppm.session | Should -BeExactly 'rigpolice-ppm'
        $ppm.keyword | Should -BeExactly '0x44'
        $ppm.startedBeforeLoad | Should -BeFalse
        $ppm.buffersLost | Should -Be 3
    }
    It 'keeps unknown start state and unknown loss as null' {
        $ppm = Convert-Ppm @() $null $null
        $ppm.startedBeforeLoad | Should -BeNullOrEmpty
        $ppm.buffersLost | Should -BeNullOrEmpty
    }
}

Describe 'ConvertFrom-PpmLossText' {
    BeforeAll {
        $script:sample = @'
Name:                 rigpolice-ppm
Status:               Running
Root Path:            %systemdrive%\PerfLogs\Admin
Segment:              Off

Name:                 rigpolice-ppm\rigpolice-ppm
Type:                 Trace
Append:               Off
Circular:             Off
Overwrite:            Off
Buffer Size:          64
Buffers Lost:         {0}
Buffers Written:      12792
Buffer Flush Timer:   1
Clock Type:           System
File Mode:            Real-time
'@
    }
    It 'reads Buffers Lost as a number (<Count>)' -ForEach @(@{ Count = 0 }, @{ Count = 3 }) {
        ConvertFrom-PpmLossText -Text ($sample -f $Count) | Should -Be $Count
    }
    It 'returns null when the line is missing' {
        $null -eq (ConvertFrom-PpmLossText -Text "Name:  rigpolice-ppm`nStatus:  Running") | Should -BeTrue
        $null -eq (ConvertFrom-PpmLossText -Text '') | Should -BeTrue
    }
}

Describe 'Open-BenchPpm, Complete-BenchPpm and Close-BenchPpm' {
    BeforeEach {
        $script:calls = New-Object System.Collections.Generic.List[string]
        $script:etl = Join-Path $TestDrive 'rigpolice-ppm-test.etl'
        Set-Content -Path $script:etl -Value 'etl'
        Mock Start-PpmTrace { $script:calls.Add('start') }
        Mock Stop-PpmTrace { $script:calls.Add('stop') }
        Mock Get-PpmTraceLoss { 0 }
        Mock Get-Process { $script:calls.Add('process'); $null }
        Mock Read-PpmEvent {
            @([pscustomobject]@{ Id = 104; Time = ([datetime]'2026-11-08T12:00:00').AddSeconds(-30); Values = @(0, 12) })
        }
    }
    It 'starts the trace before it looks for the load process' {
        $trace = Open-BenchPpm -Etl $etl -LoadProcess 'cs2'
        $calls | Should -Be @('start', 'process')
        $trace.on | Should -BeTrue
        $trace.etl | Should -Be $etl
        $trace.startedBeforeLoad | Should -BeTrue
    }
    It 'marks the trace as started late when the load process already runs' {
        Mock Get-Process { [pscustomobject]@{ Name = 'cs2' } }
        (Open-BenchPpm -Etl $etl -LoadProcess 'cs2').startedBeforeLoad | Should -BeFalse
    }
    It 'leaves startedBeforeLoad null without a load process' {
        $trace = Open-BenchPpm -Etl $etl
        $trace.startedBeforeLoad | Should -BeNullOrEmpty
        Should -Invoke Get-Process -Times 0 -Exactly
    }
    It 'stops once for Complete then Close and removes the ETL' {
        $trace = Open-BenchPpm -Etl $etl -LoadProcess 'cs2'
        $from = [datetime]'2026-11-08T12:00:00'
        $ppm = Complete-BenchPpm -Trace $trace -Start $from -End $from.AddSeconds(100)
        $trace.on | Should -BeFalse
        Close-BenchPpm -Trace $trace
        Should -Invoke Stop-PpmTrace -Times 1 -Exactly
        Test-Path -Path $etl | Should -BeFalse
        $ppm.captureProfile | Should -Be 12
        $ppm.buffersLost | Should -Be 0
        $ppm.startedBeforeLoad | Should -BeTrue
    }
    It 'reads the loss before it stops the session' {
        $script:order = New-Object System.Collections.Generic.List[string]
        Mock Get-PpmTraceLoss { $script:order.Add('loss'); 0 }
        Mock Stop-PpmTrace { $script:order.Add('stop') }
        $trace = Open-BenchPpm -Etl $etl
        $from = [datetime]'2026-11-08T12:00:00'
        Complete-BenchPpm -Trace $trace -Start $from -End $from.AddSeconds(1) | Out-Null
        $order | Should -Be @('loss', 'stop')
    }
    It 'stops once and removes the ETL when the body failed before Complete' {
        $trace = Open-BenchPpm -Etl $etl -LoadProcess 'cs2'
        Close-BenchPpm -Trace $trace
        Should -Invoke Stop-PpmTrace -Times 1 -Exactly
        Test-Path -Path $etl | Should -BeFalse
    }
}

Describe 'Wait-LogPattern' {
    BeforeEach {
        $script:log = Join-Path $TestDrive 'console.log'
        Set-Content -Path $script:log -Value 'x'
        $script:reads = @()
        $script:readIndex = 0
        $script:alive = [pscustomobject]@{ HasExited = $false }
        Mock Start-Sleep { }
        Mock Read-SharedText {
            $i = [math]::Min($script:readIndex, $script:reads.Count - 1)
            $script:readIndex++
            $script:reads[$i]
        }
    }
    It 'ignores a match before the offset and returns the length once one appears after it' {
        $old = 'old PATTERN'
        $script:reads = @($old, "$old and more PATTERN")
        $length = Wait-LogPattern -Path $log -Pattern 'PATTERN' -Process $alive -From $old.Length -TimeoutSeconds 30
        $length | Should -Be ($old.Length + ' and more PATTERN'.Length)
        Should -Invoke Start-Sleep -Times 1 -Exactly
    }
    It 'searches from the start when the log shrank below the last length seen' {
        $script:reads = @('short PATTERN')
        Wait-LogPattern -Path $log -Pattern 'PATTERN' -Process $alive -From 500 -TimeoutSeconds 30 | Should -Be 13
    }
    It 'sleeps in milliseconds between polls' {
        $script:reads = @('a', 'a PATTERN')
        Wait-LogPattern -Path $log -Pattern 'PATTERN' -Process $alive -From 1 -TimeoutSeconds 30 | Out-Null
        Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Milliseconds -eq 500 }
    }
    It 'throws when the process exited' {
        $script:reads = @('nothing')
        $gone = [pscustomobject]@{ HasExited = $true }
        { Wait-LogPattern -Path $log -Pattern 'PATTERN' -Process $gone -From 0 -TimeoutSeconds 30 } | Should -Throw '*exited*'
    }
    It 'throws on timeout' {
        $script:reads = @('nothing')
        { Wait-LogPattern -Path $log -Pattern 'PATTERN' -Process $alive -From 0 -TimeoutSeconds 0 } | Should -Throw '*PATTERN*'
    }
}

Describe 'Wait-GameCapture' {
    BeforeEach {
        $script:calls = New-Object System.Collections.Generic.List[string]
        $script:timeouts = New-Object System.Collections.Generic.List[double]
        $script:log = Join-Path $TestDrive 'console.log'
        Set-Content -Path $script:log -Value 'x'
        $script:fakeProcess = [pscustomobject]@{ Name = 'cs2'; HasExited = $false }
        $script:recipe = Get-Content -Path (Join-Path $PSScriptRoot '..\loads\cs2.json') -Raw | ConvertFrom-Json
        Mock Wait-LoadStart { $script:calls.Add('start'); $script:fakeProcess }
        Mock Get-LoadLogPath { $script:log }
        Mock Wait-LogPattern { $script:calls.Add('pattern'); $script:timeouts.Add($TimeoutSeconds); 42 }
        Mock Send-CapKey { $script:calls.Add('key') }
        Mock Start-Sleep { $script:calls.Add("sleep $Milliseconds") }
        Mock New-CaptureClock { [pscustomobject]@{ Elapsed = [timespan]::FromSeconds(6.2) } }
    }
    It 'waits for the write line, presses the key, then sleeps the rest of the load pause' {
        $capture = Wait-GameCapture -Recipe $recipe -FpsMax 144
        $calls | Should -Be @('start', 'pattern', 'key', 'sleep 8800')
        $timeouts[0] | Should -Be 8.8
        Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Milliseconds -eq 8800 }
        Should -Invoke Wait-LogPattern -Times 1 -Exactly -ParameterFilter { $Pattern -eq $recipe.cap.pressAfter -and $Path -eq $log }
        $capture.Process | Should -Be $fakeProcess
        $capture.LogPath | Should -Be $log
        $capture.PressOffset | Should -Be 42
        $capture.PressedAfterStartSeconds | Should -Be 6.2
    }
    It 'sleeps the whole load pause in milliseconds and presses nothing without a cap' {
        Mock New-CaptureClock { [pscustomobject]@{ Elapsed = [timespan]::Zero } }
        $capture = Wait-GameCapture -Recipe $recipe -FpsMax 0
        $calls | Should -Be @('start', 'sleep 15000')
        Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Milliseconds -eq 15000 }
        $capture.PressOffset | Should -BeNullOrEmpty
        $capture.PressedAfterStartSeconds | Should -BeNullOrEmpty
    }
    It 'does not sleep when the pause is already used up' {
        Mock New-CaptureClock { [pscustomobject]@{ Elapsed = [timespan]::FromSeconds(20) } }
        Wait-GameCapture -Recipe $recipe -FpsMax 0 | Out-Null
        Should -Invoke Start-Sleep -Times 0 -Exactly
    }
    It 'searches for the write line only from the log length at the start line' {
        Set-Content -Path $script:log -Value 'menu line' -NoNewline
        Wait-GameCapture -Recipe $recipe -FpsMax 144 | Out-Null
        Should -Invoke Wait-LogPattern -Times 1 -Exactly -ParameterFilter { $From -eq 9 }
    }
    It 'takes the press time before the key is sent' {
        $script:seconds = 6.2
        Mock Send-CapKey { $script:calls.Add('key'); $script:seconds = 6.3 }
        Mock New-CaptureClock {
            $clock = [pscustomobject]@{}
            $clock | Add-Member -MemberType ScriptProperty -Name Elapsed -Value { [timespan]::FromSeconds($script:seconds) }
            $clock
        }
        (Wait-GameCapture -Recipe $recipe -FpsMax 144).PressedAfterStartSeconds | Should -Be 6.2
    }
}

Describe 'Test-CapForeground' {
    It 'refreshes the process before it reads the window handle' {
        if (-not ('ParkBench' -as [type])) { Add-Type -TypeDefinition $parkBenchSource }
        $fake = [pscustomobject]@{ MainWindowHandle = [IntPtr]::Zero; Refreshed = $false }
        $fake | Add-Member -MemberType ScriptMethod -Name Refresh -Value { $this.Refreshed = $true }
        Test-CapForeground -Process $fake | Should -BeFalse
        $fake.Refreshed | Should -BeTrue
    }
}

Describe 'Send-CapKey' {
    BeforeEach {
        Mock Invoke-CapPress { }
        $script:fakeProcess = [pscustomobject]@{ Name = 'cs2' }
        $script:cap = [pscustomobject]@{ key = 'F9'; virtualKey = 120; scanCode = 67 }
    }
    It 'throws and presses nothing when CS2 is not in front' {
        Mock Test-CapForeground { $false }
        { Send-CapKey -Cap $cap -Process $fakeProcess } | Should -Throw '*foreground*'
        Should -Invoke Invoke-CapPress -Times 0 -Exactly
    }
    It 'presses the key once when CS2 is in front' {
        Mock Test-CapForeground { $true }
        Send-CapKey -Cap $cap -Process $fakeProcess
        Should -Invoke Invoke-CapPress -Times 1 -Exactly
    }
}

Describe 'Test-CapEcho' {
    BeforeEach {
        $script:log = Join-Path $TestDrive 'console.log'
        $script:cap = [pscustomobject]@{ echo = 'rigpolice_cap_key' }
    }
    It 'finds the echo only after the press offset' {
        $menu = 'bind F9 "echo rigpolice_cap_key; fps_max 144"'
        Set-Content -Path $log -Value $menu -NoNewline
        Test-CapEcho -Path $log -Cap $cap -From $menu.Length | Should -BeFalse
        Set-Content -Path $log -Value "$menu`nrigpolice_cap_key" -NoNewline
        Test-CapEcho -Path $log -Cap $cap -From $menu.Length | Should -BeTrue
    }
    It 'reports false when the log does not exist' {
        Test-CapEcho -Path (Join-Path $TestDrive 'missing.log') -Cap $cap -From 0 | Should -BeFalse
    }
}

Describe 'Get-GameVerdict' {
    BeforeAll {
        function New-Stats([double]$P50, [double]$Span = 100) { [pscustomobject]@{ p50Ms = $P50; spanSeconds = $Span; capped = $false; cappedReason = $null } }
    }
    BeforeEach {
        $script:recipe = Get-Content -Path (Join-Path $PSScriptRoot '..\loads\cs2.json') -Raw | ConvertFrom-Json
        $script:capture = [pscustomobject]@{ overflowedPresents = 0 }
        $script:rows = @([pscustomobject]@{ MsBetweenPresents = '6.9' }, [pscustomobject]@{ MsBetweenPresents = '11' })
        $script:gameCapture = [pscustomobject]@{ LogPath = 'C:\g\console.log'; PressOffset = 42; PressedAfterStartSeconds = 6.2 }
        Mock Test-CapEcho { $true }
    }
    It 'rejects a capped run whose median missed the cap' {
        $v = Get-GameVerdict -Row $rows -Stats (New-Stats 9.5) -Capture $capture -Recipe $recipe -FpsMax 144 -GameCapture $gameCapture
        $v.rejected | Should -BeLike '*fps_max 144*'
    }
    It 'accepts a capped run inside the window and records the cap with the press facts' {
        $v = Get-GameVerdict -Row $rows -Stats (New-Stats 6.9) -Capture $capture -Recipe $recipe -FpsMax 144 -GameCapture $gameCapture
        $v.rejected | Should -BeNullOrEmpty
        $v.cap.fpsMax | Should -Be 144
        $v.cap.slowFrames | Should -Be 1
        $v.cap.pressedAfterStartSeconds | Should -Be 6.2
        $v.cap.echoSeen | Should -BeTrue
    }
    It 'searches for the echo from the press offset' {
        Get-GameVerdict -Row $rows -Stats (New-Stats 6.9) -Capture $capture -Recipe $recipe -FpsMax 144 -GameCapture $gameCapture | Out-Null
        Should -Invoke Test-CapEcho -Times 1 -Exactly -ParameterFilter { $From -eq 42 -and $Path -eq 'C:\g\console.log' }
    }
    It 'joins the cap reason to the load reasons' {
        $v = Get-GameVerdict -Row $rows -Stats (New-Stats 9.5 50) -Capture $capture -Recipe $recipe -FpsMax 144 -GameCapture $gameCapture
        $v.rejected | Should -BeLike '*cover 50 s*fps_max 144*'
    }
    It 'records no cap and keeps only the load reasons on an uncapped run' {
        $v = Get-GameVerdict -Row $rows -Stats (New-Stats 9.5 50) -Capture $capture -Recipe $recipe
        $v.cap | Should -BeNullOrEmpty
        $v.rejected | Should -BeLike '*cover 50 s*'
        $v.rejected | Should -Not -BeLike '*fps_max*'
        Should -Invoke Test-CapEcho -Times 0 -Exactly
    }
}

Describe 'ParkBench C# source' {
    It 'compiles with the running PowerShell compiler and reports no foreground window for a null handle' {
        if (-not ('ParkBench' -as [type])) { Add-Type -TypeDefinition $parkBenchSource }
        [ParkBench]::IsForeground([IntPtr]::Zero) | Should -BeFalse
    }
}

Describe 'README of the cap procedure' {
    BeforeAll {
        $script:readme = (Get-Content -Path (Join-Path $PSScriptRoot '..\README.md') -Raw) -replace "`r`n", "`n"
        $script:recipe = Get-Content -Path (Join-Path $PSScriptRoot '..\loads\cs2.json') -Raw | ConvertFrom-Json
        $script:cfg = Get-ParkingBenchConfig
    }
    It 'quotes the cap console line with the key, the echo and a rate placeholder' {
        $line = $recipe.cap.consoleLine -f $recipe.cap.key, $recipe.cap.echo, '<N>'
        $readme.Contains($line) | Should -BeTrue -Because "README.md should quote $line"
    }
    It 'names the key, the write line the press waits for, the tolerances and the trace session' {
        $readme.Contains($recipe.cap.key) | Should -BeTrue
        $readme.Contains($recipe.cap.pressAfter) | Should -BeTrue
        $readme.Contains(('within {0}% of 1000 / N ms' -f ($cfg.CapTolerance * 100))) | Should -BeTrue
        $readme.Contains(('within {0}% of the refresh period' -f ((Get-BenchConfig).Limits.RefreshTolerance * 100))) | Should -BeTrue
        $readme.Contains($cfg.TraceSession) | Should -BeTrue
        $readme.Contains($cfg.KppKeyword) | Should -BeTrue
    }
    It 'gives the undo for fps_max and the F9 bind' {
        $readme | Should -Match 'fps_max <noted value>'
        $readme | Should -Match 'bind F9'
        $readme | Should -Match 'unbind F9'
    }
    It 'names the new result fields' {
        foreach ($name in 'ppm', 'captureProfile', 'captureChanges', 'profileChanges', 'buffersLost', 'startedBeforeLoad', 'autoGameModeEnabled', 'pressedAfterStartSeconds', 'echoSeen', 'slowFrames') {
            $readme.Contains($name) | Should -BeTrue -Because "README.md should name $name"
        }
    }
}
