BeforeAll {
    $script:tool = Join-Path $PSScriptRoot '..\tools\Get-ParkingSeriesTable.ps1'
    . $script:tool -SeriesPath 'unit-test'

    $script:fixtureProfile = 12
    $script:aliasGuid = [ordered]@{ CPMAXCORES = 'g-maxcores'; CPMINCORES = 'g-mincores'; CPMINCORES1 = 'g-mincores1'; PERFEPP = 'g-epp'; PERFEPP1 = 'g-epp1' }
    $script:defaultLabels = @('stock', 'min', 'cap-stock', 'cap-min', 'gm-off-stock')

    function New-PowerSetting {
        param([System.Collections.IDictionary]$Settings)
        @(foreach ($name in $aliasGuid.Keys) { [ordered]@{ guid = $aliasGuid[$name]; alias = $name; name = $name; ac = $Settings[$name]; dc = $Settings[$name] } }) + @([ordered]@{ guid = 'g-other'; alias = 'PERFINCTHRESHOLD'; name = 'other'; ac = 60; dc = 90 })
    }

    function New-Series {
        param(
            [string]$Root,
            [string]$Series = 'fixture',
            [string[]]$Labels = $defaultLabels,
            [int]$Boots = 2,
            [scriptblock]$Mutate = {},
            [scriptblock]$MutateJournal = {},
            [scriptblock]$MutatePlan = {}
        )
        $null = New-Item -ItemType Directory -Path $Root -Force
        $planBoots = foreach ($boot in 0..($Boots - 1)) {
            $states = foreach ($label in $Labels) {
                foreach ($step in $units[$label].steps) {
                    $state = [ordered]@{ kind = 'parking'; label = $label; scheme = $planScheme; settings = (Get-UnitSetting -Label $label); gameMode = $units[$label].gameMode }
                    if ($units[$label].fpsMax -gt 0) { $state.fpsMax = $units[$label].fpsMax }
                    $state.step = $step
                    $state
                }
            }
            [ordered]@{ states = @($states) }
        }
        $plan = [ordered]@{ series = $Series; benchPath = 'bench'; settleSeconds = 300; load = 'cs2'; loadBuild = '9.9.9'; captureSeconds = 100; allow = @(); gameModeProfileId = $fixtureProfile; boots = @($planBoots) }
        & $MutatePlan $plan
        $journal = New-Object System.Collections.Generic.List[object]
        $journal.Add([ordered]@{ at = '2026-01-01T09:00:00'; event = 'start'; boots = $Boots; services = 3; tasks = 2; startup = 0; network = 1; noReboot = $false })
        for ($boot = 0; $boot -lt $plan.boots.Count; $boot++) {
            $day = 10 + $boot
            $entries = New-Object System.Collections.Generic.List[object]
            $planStates = @($plan.boots[$boot].states)
            for ($index = 0; $index -lt $planStates.Count; $index++) {
                $state = $planStates[$index]
                $label = $state.label
                $step = $state.step
                $rank = @($units.Keys).IndexOf($label)
                $phase = 'boot{0:00}-state{1:00}' -f $boot, $index
                $name = "$phase-$step"
                $benchName = "parking-bench-$name.json"
                $wakeName = "parking-bench-$name-wake.csv"
                $metadata = [ordered]@{
                    benchScript       = [ordered]@{ name = 'parking-bench.ps1'; sha256 = 'aaaa' }
                    os                = [ordered]@{ build = '26300'; displayVersion = 'XX'; ubr = 100 }
                    power             = [ordered]@{ schemeGuid = $state.scheme; overlayAc = 'overlay-0'; overlayDc = $null; processorSettings = @(New-PowerSetting -Settings $state.settings) }
                    load              = $(if ($step -eq 'game') { 'cs2' } else { 'none' })
                    presentMonVersion = $(if ($step -eq 'game') { '2.6.0' } else { $null })
                    qpcFrequency      = 10000000
                }
                $bench = [ordered]@{ test = $step; phase = $phase; highQos = $true }
                $files = @()
                if ($step -eq 'burst') {
                    $wake = [math]::Round(20 - $rank + 0.25 * $boot, 3)
                    $bench.ppm = [ordered]@{ session = 'rigpolice-ppm'; keyword = '0x44'; startedBeforeLoad = $null; buffersLost = 0; profileChanges = @(); captureProfile = $null; captureChanges = 0 }
                    $bench.threads = 4
                    $bench.bursts = 20
                    $bench.idleSeconds = 2
                    $bench.burstMs = 200
                    $bench.windowMs = 1
                    $bench.chunkIterations = 1000
                    $bench.itersPerMs = 5000.5
                    $bench.parkedBeforeBurst = [ordered]@{ logicalCpus = 4; samples = 20; unavailable = 0; parked = [ordered]@{ median = $rank + 1; min = 0; max = 12 } }
                    $bench.burst = [ordered]@{
                        earlyWindowMs    = 5
                        earlyCoreMs      = [ordered]@{ median = 10 + $rank; min = 1; max = 30 }
                        totalCoreMs      = [ordered]@{ median = 700 + $rank; min = 600; max = 800 }
                        lastWorkerWakeMs = [ordered]@{ median = $wake; min = 0.1; max = 40 }
                        busyCoresPerWindowMedian = @(1.5, 3)
                    }
                    $files = @("parking-bench-$name-work.csv", $wakeName)
                }
                else {
                    $capped = $units[$label].fpsMax -gt 0
                    $bench.autoGameModeEnabled = $state.gameMode
                    $bench.ppm = if ($state.gameMode -eq 1) {
                        [ordered]@{ session = 'rigpolice-ppm'; keyword = '0x44'; startedBeforeLoad = $true; buffersLost = 0; profileChanges = @([ordered]@{ offsetSeconds = -30.5; from = 0; to = $fixtureProfile }); captureProfile = $fixtureProfile; captureChanges = 0 }
                    }
                    else {
                        [ordered]@{ session = 'rigpolice-ppm'; keyword = '0x44'; startedBeforeLoad = $true; buffersLost = 0; profileChanges = @(); captureProfile = $null; captureChanges = 0 }
                    }
                    $bench.load = [ordered]@{ name = 'cs2'; build = '9.9.9'; videoConfig = [ordered]@{ found = $true; mismatchedKeys = @() }; extraLaunchFlags = @() }
                    $bench.presentMon = [ordered]@{ sha256 = 'cccc'; overflowedPresents = 0 }
                    $bench.frames = [ordered]@{
                        frames = 50000; spanSeconds = 100
                        avgFps = $(if ($capped) { 144 } else { 500 + $rank + $boot })
                        p50Ms = $(if ($capped) { 6.94 } else { 2 })
                        low1PctMs = [math]::Round($(if ($capped) { 8 + 0.1 * $rank + 0.01 * $boot } else { 4 + 0.1 * $rank }), 3)
                        low01PctMs = [math]::Round($(if ($capped) { 10 + 0.1 * $rank + 0.01 * $boot } else { 5 + 0.1 * $rank }), 3)
                        cpuBusyP50Ms = 1.8; gpuBusyP50Ms = 1.5
                        syncIntervals = @('0'); presentModes = @('Hardware: Independent Flip'); refreshHz = 165; capped = $false; cappedReason = ''
                    }
                    $bench.cap = if ($capped) { [ordered]@{ fpsMax = $state.fpsMax; periodMs = 6.944; tolerance = 0.02; slowFrameFactor = 1.5; slowFrames = $rank + $boot; pressedAfterStartSeconds = 6; echoSeen = $false } } else { $null }
                    $bench.rejected = $null
                    $bench.parkedDuringRun = [ordered]@{ logicalCpus = 4; samples = 400; unavailable = 0; parked = [ordered]@{ median = $rank + 1; min = 0; max = 12 } }
                    $files = @("parking-bench-$name-presentmon.csv", "parking-bench-$name-parked.csv")
                }
                $bench.powerStateChanged = $false
                $bench.files = $files
                $bench.powerEnd = $metadata.power
                $bench.metadata = $metadata
                $explicit = @('sub\g-explicit:ac=2', 'sub\g-explicit:dc=2') + @(foreach ($alias in $aliasGuid.Keys) { 'sub\{0}:ac={1}' -f $aliasGuid[$alias], $state.settings[$alias]; 'sub\{0}:dc={1}' -f $aliasGuid[$alias], $state.settings[$alias] })
                $wrapper = [ordered]@{
                    series      = $plan.series
                    boot        = $boot
                    stateIndex  = $index
                    state       = $state
                    load        = 'cs2'
                    capturedAt  = '2026-01-{0:00}T10:{1:00}:00' -f $day, (10 + $index)
                    bench       = [ordered]@{ exitCode = 0; resultFile = $benchName; files = @($files + $benchName); log = "$name-bench.log" }
                    environment = [ordered]@{
                        cpu                    = [ordered]@{ name = 'Test CPU' }
                        microcodeRaw           = '01-02'
                        bios                   = [ordered]@{ version = '1.0'; board = 'Test board' }
                        drivers                = [ordered]@{ gpu = @([ordered]@{ device = 'GPU'; version = '1.2.3' }); audio = @([ordered]@{ device = 'Audio'; version = '4.5.6'; enumerator = 'HDAUDIO' }) }
                        hvciEnabled            = 1
                        clockFlags             = [ordered]@{ useplatformclock = 'not set' }
                        powerExplicit          = $explicit
                        enabledNetworkAdapters = 0
                    }
                }
                $wakeLines = New-Object System.Collections.Generic.List[string]
                $wakeLines.Add('burst,thread,wakeMs,cpuAtWake,cpuAtEnd')
                for ($burst = 0; $burst -lt 20; $burst++) {
                    $wakeLines.Add(('{0},0,{1},1,1' -f $burst, ([math]::Round(0.1 * (($burst * 7) % 20 + 1) + 0.01 * $boot, 3)).ToString('0.###', [System.Globalization.CultureInfo]::InvariantCulture)))
                    $wakeLines.Add(('{0},1,0.05,2,2' -f $burst))
                }
                $ctx = @{ Boot = $boot; StateIndex = $index; Label = $label; Step = $step; Bench = $bench; Wrapper = $wrapper; Wake = $wakeLines; Root = $Root }
                & $Mutate $ctx
                ConvertTo-Json -InputObject $ctx.Bench -Depth 12 | Set-Content -LiteralPath (Join-Path $Root $benchName) -Encoding UTF8
                ConvertTo-Json -InputObject $ctx.Wrapper -Depth 12 | Set-Content -LiteralPath (Join-Path $Root "$name.json") -Encoding UTF8
                if ($step -eq 'burst') { Set-Content -LiteralPath (Join-Path $Root $wakeName) -Value $ctx.Wake -Encoding UTF8 }
                $entries.Add([ordered]@{ index = $index; kind = 'parking'; step = $step; status = 'ok'; result = "$name.json" })
            }
            $journal.Add([ordered]@{ at = ('2026-01-{0:00}T11:00:00' -f $day); event = 'boot'; index = $boot; startedAt = ('2026-01-{0:00}T10:00:00' -f $day); endedAt = ('2026-01-{0:00}T11:00:00' -f $day); outcome = 'success'; states = $entries.ToArray() })
        }
        $journal.Add([ordered]@{ at = '2026-02-01T00:00:00'; event = 'restored'; reason = 'finished' })
        & $MutateJournal $journal
        ConvertTo-Json -InputObject $plan -Depth 12 | Set-Content -LiteralPath (Join-Path $Root 'plan.json') -Encoding UTF8
        $journal | ForEach-Object { ConvertTo-Json -InputObject $_ -Depth 8 -Compress } | Set-Content -LiteralPath (Join-Path $Root 'journal.jsonl') -Encoding UTF8
        $Root
    }

    function Get-State {
        param($Report, [string]$Label, [string]$Step)
        $Report.Summary.states | Where-Object { $_.label -eq $Label -and $_.step -eq $Step }
    }

    function Get-Test {
        param($Report, [string]$Comparison, [string]$Metric)
        $Report.Summary.analysis.tests | Where-Object { $_.comparison -eq $Comparison -and $_.metric -eq $Metric }
    }
}

Describe 'the report of a clean series' {
    BeforeAll {
        $script:clean = New-SeriesReport -SeriesPath (New-Series -Root (Join-Path $TestDrive 'clean'))
    }
    It 'prints every section in order' {
        $at = @('## Testbed', '## Checks that passed before these tables were written', '## Failed attempts', '## Steps left out', '## Pre-registered comparisons', '## Pre-registered tests', '## Described comparisons', '## Burst', '## Uncapped game', '## Capped game', '## Table to file map', '## Boots and files') | ForEach-Object { $clean.Markdown.IndexOf("$_`n") }
        @($at | Where-Object { $_ -lt 0 }).Count | Should -Be 0
        ($at -join ',') | Should -Be ((@($at) | Sort-Object) -join ',')
        $clean.Markdown | Should -Match 'No failed attempt\.'
        $clean.Markdown | Should -Match 'No step was left out\.'
        $clean.Markdown | Should -Match 'No described comparison in this series\.'
    }
    It 'writes the summary keys of the MSI table plus the paired fields' {
        @($clean.Summary.PSObject.Properties.Name) | Should -Be @('series', 'constants', 'checks', 'testbed', 'analysis', 'states', 'fileMap')
        @($clean.Summary.constants.Keys) | Should -Be @('alpha', 'confidence', 'scheme', 'units', 'seriesDesigns', 'metrics', 'margins', 'comparisons', 'cannotShowWhenReferenceParkedIsZero')
        $clean.Summary.constants.margins.shareOfReferenceMedian.lastWorkerWakeMs | Should -Be 0.1d
        @($clean.Summary.analysis.Keys) | Should -Be @('family', 'tests', 'described', 'excluded', 'failedAttempts', 'profileChanges')
        @($clean.Summary.analysis.tests[0].PSObject.Properties.Name) | Should -Be @('comparison', 'block', 'reference', 'state', 'step', 'metric', 'change', 'mixed', 'boots', 'differences', 'referenceValues', 'stateValues', 'referenceMedian', 'stateMedian', 'shift', 'shiftPctOfReference', 'ciLow', 'ciHigh', 'ciConfidence', 'lower', 'level', 'higher', 'margin', 'extreme', 'permutations', 'p', 'pHolm', 'verdict', 'cannotShow')
        @($clean.Summary.checks[0].PSObject.Properties.Name) | Should -Be @('name', 'source', 'benchJson', 'status')
        @($clean.Summary.fileMap[0].PSObject.Properties.Name) | Should -Be @('table', 'files', 'fields', 'runner')
    }
    It 'runs the comparisons whose labels are present and names an unknown series' {
        $clean.Summary.analysis.family['main'] | Should -Be 7
        @($clean.Summary.analysis.tests | ForEach-Object { '{0} | {1}' -f $_.comparison, $_.metric }) | Should -Be @(
            'min vs stock | lastWorkerWakeMs', 'min vs stock | avgFps', 'min vs stock | low1PctMs', 'gm-off-stock vs stock | avgFps', 'gm-off-stock vs stock | low1PctMs', 'cap-min vs cap-stock | low01PctMs', 'cap-min vs cap-stock | low1PctMs'
        )
        @($clean.Summary.analysis.tests | ForEach-Object { $_.verdict } | Select-Object -Unique) | Should -Be @('cannot tell')
        $clean.Markdown | Should -Match 'fixture is not a pre-registered series: its boot count and units were not checked'
        ($clean.Summary.checks | Where-Object { $_.name -like 'pre-registered boot count*' }).status | Should -Be 'not a pre-registered series'
    }
    It 'pairs the two states within each boot' {
        $wake = Get-Test $clean 'min vs stock' 'lastWorkerWakeMs'
        $wake.referenceValues | Should -Be @(20, 20.25)
        $wake.stateValues | Should -Be @(19, 19.25)
        $wake.differences | Should -Be @(-1, -1)
        $wake.lower | Should -Be 2
        $wake.change | Should -Be @('CPMINCORES', 'CPMINCORES1')
        (Get-Test $clean 'gm-off-stock vs stock' 'avgFps').change | Should -Be @('gameMode')
    }
    It 'takes the testbed from the data' {
        $testbed = $clean.Summary.testbed
        $testbed['Windows'] | Should -Be 'XX build 26300.100'
        $testbed['CPU'] | Should -Be 'Test CPU'
        $testbed['Board and BIOS'] | Should -Be 'Test board, BIOS 1.0'
        $testbed['Logical CPUs'] | Should -Be '4'
        $testbed['Burst'] | Should -Be '4 threads, 20 bursts of 200 ms after 2 s idle'
        $testbed['Refresh rate'] | Should -Be '165 Hz'
        $testbed['Load'] | Should -Be 'cs2 9.9.9'
        $testbed['Game Mode power profile'] | Should -Be '12'
        $testbed['Boots'] | Should -Be '2'
        $testbed['Steps per boot'] | Should -Be '7'
        $testbed['Disabled services'] | Should -Be '3'
        $testbed['Disabled network'] | Should -Be '1'
    }
    It 'prints the capped and uncapped game tables' {
        $capped = Get-State $clean 'cap-stock' 'game'
        $capped.low01PctMsOverPeriod.median | Should -Be 3.461
        $capped.slowFrames.max | Should -Be 5
        $clean.Markdown | Should -Match '\| cap-stock \| 2 \| 144 \| 144 \[144-144\] \| 6\.94 \[6\.94-6\.94\] \|'
        $uncapped = Get-State $clean 'stock' 'game'
        $uncapped.gpuBusySharePct.median | Should -Be 75
        $uncapped.gameModeProfileSteps.steps | Should -Be 2
        (Get-State $clean 'gm-off-stock' 'game').gameModeProfileSteps.steps | Should -Be 0
        $clean.Markdown | Should -Match '\| gm-off-stock \| 2 \|.*\| 0 of 2 \|'
    }
}

Describe 'the wake columns' {
    It 'takes the p90 and the slowest per-burst wake of each run from wake.csv' {
        $report = New-SeriesReport -SeriesPath (New-Series -Root (Join-Path $TestDrive 'wake'))
        $stock = Get-State $report 'stock' 'burst'
        $stock.wakeP90Ms.min | Should -Be 1.9
        $stock.wakeP90Ms.max | Should -Be 1.91
        $stock.slowestWakeMs.min | Should -Be 2
        $stock.slowestWakeMs.max | Should -Be 2.01
        $stock.lastWorkerWakeMs.median | Should -Be 20.125
        $report.Markdown | Should -Match '\| stock \| 2 \| 20\.12 \[20-20\.25\] \| 1\.9 \[1\.9-1\.91\] \| 2 \[2-2\.01\] \|'
    }
    It 'refuses a burst whose wake file is missing' {
        $root = New-Series -Root (Join-Path $TestDrive 'wake-missing') -Mutate { param($ctx) if ($ctx.Boot -eq 1 -and $ctx.StateIndex -eq 2) { $ctx.Wrapper.bench.files = @($ctx.Wrapper.bench.files | Where-Object { $_ -notlike '*-wake.csv' }) } }
        { New-SeriesReport -SeriesPath $root } | Should -Throw '*boot 1 state 2 wrapper field bench.files lists no -wake.csv file*'
    }
}

Describe 'a pre-registered series' {
    BeforeAll {
        $script:ceiling = New-SeriesReport -SeriesPath (New-Series -Root (Join-Path $TestDrive 'ceiling') -Series 'parking-retest-2-ceiling' -Labels $seriesDesigns['parking-retest-2-ceiling'].units -Boots 6)
    }
    It 'checks the design and prints no unregistered line' {
        ($ceiling.Summary.checks | Where-Object { $_.name -like 'pre-registered boot count*' }).status | Should -Be 'passed'
        $ceiling.Markdown | Should -Not -Match 'not a pre-registered series'
        $ceiling.Summary.analysis.family['ceiling'] | Should -Be 1
        @($ceiling.Summary.analysis.described).Count | Should -Be 5
    }
    It 'labels the ceiling states as forced in every table' {
        $ceiling.Markdown | Should -Match '\| maxcores25-min \(forced: the ceiling\) vs maxcores25 \(forced: the ceiling\) \| Burst wake, median of the run \(ms\) \| 6 \|'
        $ceiling.Markdown | Should -Match '\| maxcores25 \(forced: the ceiling\) \| 6 \|'
        $ceiling.Markdown | Should -Match '\| maxcores25-epp \(forced: the ceiling\) \| game \|'
        (Get-State $ceiling 'maxcores25' 'burst').ceiling | Should -BeTrue
    }
    It 'refuses another boot count' {
        $root = New-Series -Root (Join-Path $TestDrive 'ceiling-5') -Series 'parking-retest-2-ceiling' -Labels $seriesDesigns['parking-retest-2-ceiling'].units -Boots 5
        { New-SeriesReport -SeriesPath $root } | Should -Throw '*plan.json lists 5 boots, the pre-registered series parking-retest-2-ceiling has 6*'
    }
    It 'refuses a boot without every step of its units' {
        $root = New-Series -Root (Join-Path $TestDrive 'ceiling-units') -Series 'parking-retest-2-ceiling' -Labels @('maxcores25', 'maxcores25-min') -Boots 6
        { New-SeriesReport -SeriesPath $root } | Should -Throw '*boot 0 holds maxcores25 burst, maxcores25 game, maxcores25-min burst, maxcores25-min game; the pre-registered series parking-retest-2-ceiling holds every step of maxcores25, maxcores25-min, maxcores25-epp once in every boot*'
    }
}

Describe 'the tier-1 refusals' {
    It 'refuses <Name>' -ForEach @(
        @{ Name = 'a planned step without an accepted result'; Message = '*boot 1 state 3 : expected exactly one accepted result*found 0*'; MutateJournal = { param($j) $j[2].states = @($j[2].states | Where-Object { $_.index -ne 3 }) } }
        @{ Name = 'a step held twice in one boot'; Message = '*boot 0 holds the stock burst step 2 times*'; MutatePlan = { param($plan) $plan.boots[0].states = @($plan.boots[0].states) + @($plan.boots[0].states[0]) } }
        @{ Name = 'a wrapper of another series'; Message = "*boot 1 state 1 (stock game) wrapper field series is 'other'*"; Mutate = { param($ctx) if ($ctx.Boot -eq 1 -and $ctx.StateIndex -eq 1) { $ctx.Wrapper.series = 'other' } } }
        @{ Name = 'a wrapper state other than the plan'; Message = '*boot 0 state 2 (min burst) wrapper field state is*plan.json says*'; Mutate = { param($ctx) if ($ctx.Boot -eq 0 -and $ctx.StateIndex -eq 2) { $ctx.Wrapper.state = [ordered]@{ label = 'min'; step = 'burst' } } } }
        @{ Name = 'a bench that ran another test'; Message = "*boot 0 state 0 (stock burst) bench field test is 'framesim'*"; Mutate = { param($ctx) if ($ctx.Boot -eq 0 -and $ctx.StateIndex -eq 0) { $ctx.Bench.test = 'framesim' } } }
        @{ Name = 'a plan state off its unit'; Message = '*boot 0 state 2 (min burst) plan state CPMINCORES is 50, the pre-registered unit min sets 100*'; MutatePlan = { param($plan) $plan.boots[0].states[2].settings.CPMINCORES = 50 } }
        @{ Name = 'a label that is no unit'; Message = "*plan state label 'mystery' is not a pre-registered unit*"; MutatePlan = { param($plan) $plan.boots[1].states[4].label = 'mystery' } }
        @{ Name = 'a capture outside its boot'; Message = '*boot 1 state 5 (cap-min game) wrapper field capturedAt 2026-01-11T11:00:01 is outside its boot: the journal says 2026-01-11T10:00:00 to 2026-01-11T11:00:00*'; Mutate = { param($ctx) if ($ctx.Boot -eq 1 -and $ctx.StateIndex -eq 5) { $ctx.Wrapper.capturedAt = '2026-01-11T11:00:01' } } }
        @{ Name = 'another power scheme'; Message = "*boot 1 state 0 (stock burst) bench field metadata.power.schemeGuid is 'other-scheme'*"; Mutate = { param($ctx) if ($ctx.Boot -eq 1 -and $ctx.StateIndex -eq 0) { $ctx.Bench.metadata.power.schemeGuid = 'other-scheme' } } }
        @{ Name = 'a planned value off the state'; Message = '*boot 1 state 3 (min game) bench field metadata.power.processorSettings CPMINCORES is AC 5 DC 100, the state sets 100*'; Mutate = { param($ctx) if ($ctx.Boot -eq 1 -and $ctx.StateIndex -eq 3) { ($ctx.Bench.metadata.power.processorSettings | Where-Object { $_.alias -eq 'CPMINCORES' }).ac = 5 } } }
        @{ Name = 'a Game Mode registry value off the state'; Message = '*boot 0 state 6 (gm-off-stock game) bench field autoGameModeEnabled is 1, the state sets Game Mode 0*'; Mutate = { param($ctx) if ($ctx.Boot -eq 0 -and $ctx.StateIndex -eq 6) { $ctx.Bench.autoGameModeEnabled = 1 } } }
        @{ Name = 'a Game Mode run without the Game Mode profile'; Message = "*boot 1 state 1 (stock game) Game Mode 1 check failed: ppm captureProfile is '3', expected 12*"; Mutate = { param($ctx) if ($ctx.Boot -eq 1 -and $ctx.StateIndex -eq 1) { $ctx.Bench.ppm.captureProfile = 3 } } }
        @{ Name = 'a Game Mode off run whose trace started late'; Message = "*boot 0 state 6 (gm-off-stock game) Game Mode 0 check failed: the trace did not start before the load*"; Mutate = { param($ctx) if ($ctx.Boot -eq 0 -and $ctx.StateIndex -eq 6) { $ctx.Bench.ppm.startedBeforeLoad = $false } } }
        @{ Name = 'a capped state without a cap record'; Message = '*boot 0 state 4 (cap-stock game) bench field cap is missing, the state caps at 144 fps*'; Mutate = { param($ctx) if ($ctx.Boot -eq 0 -and $ctx.StateIndex -eq 4) { $ctx.Bench.cap = $null } } }
        @{ Name = 'a cap at another rate'; Message = '*boot 1 state 5 (cap-min game) bench field cap.fpsMax is 120, the state caps at 144 fps*'; Mutate = { param($ctx) if ($ctx.Boot -eq 1 -and $ctx.StateIndex -eq 5) { $ctx.Bench.cap.fpsMax = 120 } } }
        @{ Name = 'an uncapped state with a cap'; Message = '*boot 0 state 1 (stock game) bench field cap is set (fpsMax 144), the state runs uncapped*'; Mutate = { param($ctx) if ($ctx.Boot -eq 0 -and $ctx.StateIndex -eq 1) { $ctx.Bench.cap = [ordered]@{ fpsMax = 144; periodMs = 6.944; slowFrames = 0 } } } }
        @{ Name = 'a rejected run'; Message = '*boot 1 state 3 (min game) bench field rejected is not empty: the load stopped*'; Mutate = { param($ctx) if ($ctx.Boot -eq 1 -and $ctx.StateIndex -eq 3) { $ctx.Bench.rejected = 'the load stopped' } } }
        @{ Name = 'a PresentMon overflow'; Message = '*boot 0 state 3 (min game) bench field presentMon.overflowedPresents is 3, expected 0*'; Mutate = { param($ctx) if ($ctx.Boot -eq 0 -and $ctx.StateIndex -eq 3) { $ctx.Bench.presentMon.overflowedPresents = 3 } } }
        @{ Name = 'a bench without high QoS'; Message = "*boot 1 state 2 (min burst) bench field highQos is 'False'*"; Mutate = { param($ctx) if ($ctx.Boot -eq 1 -and $ctx.StateIndex -eq 2) { $ctx.Bench.highQos = $false } } }
        @{ Name = 'an enabled network adapter'; Message = '*boot 1 state 0 (stock burst) wrapper field environment.enabledNetworkAdapters is 1*'; Mutate = { param($ctx) if ($ctx.Boot -eq 1 -and $ctx.StateIndex -eq 0) { $ctx.Wrapper.environment.enabledNetworkAdapters = 1 } } }
        @{ Name = 'a bench JSON of another phase'; Message = "*boot 1 state 2 (min burst) bench field phase is 'boot01-state03', expected 'boot01-state02'*"; Mutate = { param($ctx) if ($ctx.Boot -eq 1 -and $ctx.StateIndex -eq 2) { $ctx.Bench.phase = 'boot01-state03' } } }
        @{ Name = 'two wrappers that name the same bench file'; Message = "*boot 1 state 3 (min game) wrapper field bench.resultFile is 'parking-bench-boot01-state01-game.json', expected 'parking-bench-boot01-state03-game.json'*"; Mutate = { param($ctx) if ($ctx.Boot -eq 1 -and $ctx.StateIndex -eq 3) { $ctx.Wrapper.bench.resultFile = 'parking-bench-boot01-state01-game.json' } } }
        @{ Name = 'a Game Mode off run whose profile left the id after the window started'; Message = '*boot 0 state 6 (gm-off-stock game) Game Mode 0 check failed: the power profile left 12 after the capture window started (ppm profileChanges)*'; Mutate = { param($ctx) if ($ctx.Boot -eq 0 -and $ctx.StateIndex -eq 6) { $ctx.Bench.ppm.profileChanges = @([ordered]@{ offsetSeconds = 150; from = 12; to = 0 }) } } }
        @{ Name = 'a Game Mode off run whose profile changed to the id'; Message = '*boot 1 state 6 (gm-off-stock game) Game Mode 0 check failed: the power profile changed to 12 (ppm profileChanges)*'; Mutate = { param($ctx) if ($ctx.Boot -eq 1 -and $ctx.StateIndex -eq 6) { $ctx.Bench.ppm.profileChanges = @([ordered]@{ offsetSeconds = -5; from = 0; to = 12 }) } } }
        @{ Name = 'a game whose profile changed inside the window'; Message = '*boot 1 state 3 (min game) Game Mode 1 check failed: the power profile changed 1 time(s) inside the capture window (ppm captureChanges)*'; Mutate = { param($ctx) if ($ctx.Boot -eq 1 -and $ctx.StateIndex -eq 3) { $ctx.Bench.ppm.captureChanges = 1 } } }
        @{ Name = 'a game whose trace lost buffers'; Message = "*boot 0 state 4 (cap-stock game) Game Mode 1 check failed: ppm buffersLost is '2', expected 0*"; Mutate = { param($ctx) if ($ctx.Boot -eq 0 -and $ctx.StateIndex -eq 4) { $ctx.Bench.ppm.buffersLost = 2 } } }
        @{ Name = 'a capture before its boot started'; Message = '*boot 0 state 1 (stock game) wrapper field capturedAt 2026-01-10T09:59:59 is outside its boot: the journal says 2026-01-10T10:00:00 to 2026-01-10T11:00:00*'; Mutate = { param($ctx) if ($ctx.Boot -eq 0 -and $ctx.StateIndex -eq 1) { $ctx.Wrapper.capturedAt = '2026-01-10T09:59:59' } } }
        @{ Name = 'a planned DC value off the state'; Message = '*boot 0 state 2 (min burst) bench field metadata.power.processorSettings CPMINCORES is AC 100 DC 5, the state sets 100*'; Mutate = { param($ctx) if ($ctx.Boot -eq 0 -and $ctx.StateIndex -eq 2) { ($ctx.Bench.metadata.power.processorSettings | Where-Object { $_.alias -eq 'CPMINCORES' }).dc = 5 } } }
        @{ Name = 'a wake file without the wakeMs column'; Message = '*boot 1 state 2 wake file parking-bench-boot01-state02-burst-wake.csv has no column wakeMs*'; Mutate = { param($ctx) if ($ctx.Boot -eq 1 -and $ctx.StateIndex -eq 2) { $ctx.Wake[0] = 'burst,thread,wake,cpuAtWake,cpuAtEnd' } } }
        @{ Name = 'a wake file without the burst column'; Message = '*boot 0 state 0 wake file parking-bench-boot00-state00-burst-wake.csv has no column burst*'; Mutate = { param($ctx) if ($ctx.Boot -eq 0 -and $ctx.StateIndex -eq 0) { $ctx.Wake[0] = 'run,thread,wakeMs,cpuAtWake,cpuAtEnd' } } }
        @{ Name = 'a wake file without bursts'; Message = '*boot 0 state 2 wake file parking-bench-boot00-state02-burst-wake.csv has no burst row*'; Mutate = { param($ctx) if ($ctx.Boot -eq 0 -and $ctx.StateIndex -eq 2) { $header = $ctx.Wake[0]; $ctx.Wake.Clear(); $ctx.Wake.Add($header) } } }
        @{ Name = 'a game without a tested metric'; Message = '*boot 1 state 3 (min game) has no field frames.low1PctMs*'; Mutate = { param($ctx) if ($ctx.Boot -eq 1 -and $ctx.StateIndex -eq 3) { $ctx.Bench.frames.Remove('low1PctMs') } } }
        @{ Name = 'a burst without a state-table field'; Message = '*boot 0 state 2 (min burst) has no field burst.earlyCoreMs.median*'; Mutate = { param($ctx) if ($ctx.Boot -eq 0 -and $ctx.StateIndex -eq 2) { $ctx.Bench.burst.Remove('earlyCoreMs') } } }
        @{ Name = 'a capped game without the cap period'; Message = '*boot 1 state 5 (cap-min game) has no field cap.periodMs*'; Mutate = { param($ctx) if ($ctx.Boot -eq 1 -and $ctx.StateIndex -eq 5) { $ctx.Bench.cap.Remove('periodMs') } } }
    ) {
        $arguments = @{ Root = (Join-Path $TestDrive ('r-' + ($Name -replace '[^a-z]', ''))) }
        foreach ($key in 'Mutate', 'MutateJournal', 'MutatePlan') { if ($_.ContainsKey($key)) { $arguments[$key] = $_[$key] } }
        $root = New-Series @arguments
        { New-SeriesReport -SeriesPath $root -ChecksOnly } | Should -Throw $Message
        { New-SeriesReport -SeriesPath $root } | Should -Throw $Message
    }
    It 'refuses a step whose <Field> differs from the first step that records it' -ForEach @(
        @{ Field = 'metadata.os.build'; State = 0; Against = 0; Mutate = { param($bench, $wrapper) $bench.metadata.os.build = '26301' } }
        @{ Field = 'metadata.os.ubr'; State = 0; Against = 0; Mutate = { param($bench, $wrapper) $bench.metadata.os.ubr = 101 } }
        @{ Field = 'metadata.qpcFrequency'; State = 0; Against = 0; Mutate = { param($bench, $wrapper) $bench.metadata.qpcFrequency = 24000000 } }
        @{ Field = 'metadata.benchScript.sha256'; State = 0; Against = 0; Mutate = { param($bench, $wrapper) $bench.metadata.benchScript.sha256 = 'bbbb' } }
        @{ Field = 'metadata.power.processorSettings'; State = 0; Against = 0; Mutate = { param($bench, $wrapper) ($bench.metadata.power.processorSettings | Where-Object { $_.alias -eq 'PERFINCTHRESHOLD' }).ac = 61 } }
        @{ Field = 'environment.powerExplicit'; State = 0; Against = 0; Mutate = { param($bench, $wrapper) $wrapper.environment.powerExplicit = @($wrapper.environment.powerExplicit | ForEach-Object { $_ -replace 'g-explicit:ac=2', 'g-explicit:ac=3' }) } }
        @{ Field = 'metadata.power.overlayAc'; State = 0; Against = 0; Mutate = { param($bench, $wrapper) $bench.metadata.power.overlayAc = 'overlay-1' } }
        @{ Field = 'environment.drivers.gpu'; State = 0; Against = 0; Mutate = { param($bench, $wrapper) $wrapper.environment.drivers.gpu[0].version = '1.2.4' } }
        @{ Field = 'environment.drivers.audio'; State = 0; Against = 0; Mutate = { param($bench, $wrapper) $wrapper.environment.drivers.audio[0].version = '4.5.7' } }
        @{ Field = 'environment.hvciEnabled'; State = 0; Against = 0; Mutate = { param($bench, $wrapper) $wrapper.environment.hvciEnabled = 0 } }
        @{ Field = 'environment.bios.version'; State = 0; Against = 0; Mutate = { param($bench, $wrapper) $wrapper.environment.bios.version = '1.1' } }
        @{ Field = 'environment.microcodeRaw'; State = 0; Against = 0; Mutate = { param($bench, $wrapper) $wrapper.environment.microcodeRaw = '01-03' } }
        @{ Field = 'environment.clockFlags'; State = 0; Against = 0; Mutate = { param($bench, $wrapper) $wrapper.environment.clockFlags.useplatformclock = 'Yes' } }
        @{ Field = 'logicalCpus'; State = 1; Against = 0; Mutate = { param($bench, $wrapper) $bench.parkedDuringRun.logicalCpus = 8 } }
        @{ Field = 'threads'; State = 0; Against = 0; Mutate = { param($bench, $wrapper) $bench.threads = 8 } }
        @{ Field = 'itersPerMs'; State = 0; Against = 0; Mutate = { param($bench, $wrapper) $bench.itersPerMs = 5000.6 } }
        @{ Field = 'metadata.presentMonVersion'; State = 1; Against = 1; Mutate = { param($bench, $wrapper) $bench.metadata.presentMonVersion = '2.7.0' } }
        @{ Field = 'presentMon.sha256'; State = 1; Against = 1; Mutate = { param($bench, $wrapper) $bench.presentMon.sha256 = 'dddd' } }
        @{ Field = 'load.build'; State = 1; Against = 1; Mutate = { param($bench, $wrapper) $bench.load.build = '9.9.10' } }
        @{ Field = 'load.videoConfig'; State = 1; Against = 1; Mutate = { param($bench, $wrapper) $bench.load.videoConfig.mismatchedKeys = @('width') } }
        @{ Field = 'frames.refreshHz'; State = 1; Against = 1; Mutate = { param($bench, $wrapper) $bench.frames.refreshHz = 144 } }
        @{ Field = 'frames.presentModes'; State = 1; Against = 1; Mutate = { param($bench, $wrapper) $bench.frames.presentModes = @('Composed: Flip') } }
    ) {
        $change = $Mutate
        $target = $State
        $mutate = { param($ctx) if ($ctx.Boot -eq 1 -and $ctx.StateIndex -eq $target) { & $change $ctx.Bench $ctx.Wrapper } }.GetNewClosure()
        $root = New-Series -Root (Join-Path $TestDrive ('h-' + ($Field -replace '[^a-zA-Z]', ''))) -Mutate $mutate
        { New-SeriesReport -SeriesPath $root -ChecksOnly } | Should -Throw ("*boot 1 state $State field $Field differs from boot 0 state $Against*")
        { New-SeriesReport -SeriesPath $root } | Should -Throw ("*boot 1 state $State field $Field differs from boot 0 state $Against*")
    }
}

Describe 'the homogeneity check' {
    It 'ignores the five planned power values, in the bench JSON and in the explicit settings' {
        $root = New-Series -Root (Join-Path $TestDrive 'planned-values') -Mutate {
            param($ctx)
            if ($ctx.Boot -eq 1 -and $ctx.StateIndex -eq 0) { $ctx.Wrapper.environment.powerExplicit = @($ctx.Wrapper.environment.powerExplicit | ForEach-Object { $_ -replace 'g-epp:ac=33', 'g-epp:ac=50' }) }
        }
        $report = New-SeriesReport -SeriesPath $root
        $report.Summary.analysis.family['main'] | Should -Be 7
        ($report.Summary.checks | Where-Object { $_.name -like 'power settings other than*' }).status | Should -Be 'passed'
    }
}

Describe 'the steps left out' {
    BeforeAll {
        $root = New-Series -Root (Join-Path $TestDrive 'left-out') -Mutate {
            param($ctx)
            if ($ctx.Boot -eq 0 -and $ctx.StateIndex -eq 0) { $ctx.Bench.ppm.buffersLost = 2 }
            if ($ctx.Boot -eq 0 -and $ctx.StateIndex -eq 2) { $ctx.Bench.ppm.captureProfile = 12; $ctx.Bench.ppm.captureChanges = 1 }
            if ($ctx.Boot -eq 0 -and $ctx.StateIndex -eq 4) { $ctx.Bench.powerStateChanged = $true }
        }
        $script:leftOut = New-SeriesReport -SeriesPath $root
    }
    It 'lists each step with its reasons' {
        @($leftOut.Summary.analysis.excluded | ForEach-Object { '{0}/{1}' -f $_.boot, $_.stateIndex }) | Should -Be @('0/0', '0/2', '0/4')
        ($leftOut.Summary.analysis.excluded | Where-Object { $_.stateIndex -eq 0 }).reason | Should -Be "ppm buffersLost is '2', expected 0"
        ($leftOut.Summary.analysis.excluded | Where-Object { $_.stateIndex -eq 0 }).leftOutOf | Should -Be @('every row and state table')
        ($leftOut.Summary.analysis.excluded | Where-Object { $_.stateIndex -eq 2 }).reason | Should -Be 'the power profile changed 1 time(s) inside the burst window (ppm captureChanges); the Game Mode power profile 12 was active in the burst window (ppm captureProfile)'
        $leftOut.Markdown | Should -Match '\| 0 \| cap-stock \| game \| the power scheme or a processor setting changed during the run \(powerStateChanged\) \|'
    }
    It 'leaves the steps out of the rows and states that use them and keeps their boot elsewhere' {
        @((Get-Test $leftOut 'min vs stock' 'lastWorkerWakeMs').boots) | Should -Be @(1)
        @((Get-State $leftOut 'stock' 'burst').boots) | Should -Be @(1)
        @((Get-Test $leftOut 'min vs stock' 'avgFps').boots) | Should -Be @(0, 1)
        @((Get-Test $leftOut 'cap-min vs cap-stock' 'low01PctMs').boots) | Should -Be @(1)
        $leftOut.Markdown | Should -Match '\| cap-min vs cap-stock \| 0\.1% low \(ms\) \| 1 \|.*\| boots left out: 0 \|'
        @((Get-State $leftOut 'cap-stock' 'game').boots) | Should -Be @(1)
    }
    It 'leaves out a burst whose power state changed' {
        $report = New-SeriesReport -SeriesPath (New-Series -Root (Join-Path $TestDrive 'burst-power') -Mutate { param($ctx) if ($ctx.Boot -eq 1 -and $ctx.StateIndex -eq 2) { $ctx.Bench.powerStateChanged = $true } })
        @($report.Summary.analysis.excluded | ForEach-Object { '{0}/{1}' -f $_.boot, $_.stateIndex }) | Should -Be @('1/2')
        $report.Summary.analysis.excluded[0].reason | Should -Be 'the power scheme or a processor setting changed during the run (powerStateChanged)'
        @((Get-Test $report 'min vs stock' 'lastWorkerWakeMs').boots) | Should -Be @(0)
        @((Get-State $report 'min' 'burst').boots) | Should -Be @(0)
    }
}

Describe 'a step without a parked-core reading' {
    BeforeAll {
        $script:parkedRoot = New-Series -Root (Join-Path $TestDrive 'no-parked') -Mutate {
            param($ctx)
            if ($ctx.Boot -eq 1 -and $ctx.StateIndex -eq 0) { $ctx.Bench.parkedBeforeBurst.parked = $null }
            if ($ctx.Boot -eq 1 -and $ctx.StateIndex -eq 1) { $ctx.Bench.parkedDuringRun.parked = $null }
            if ($ctx.StateIndex -eq 4) { $ctx.Bench.parkedDuringRun.parked = $null }
        }
        $script:noParked = New-SeriesReport -SeriesPath $parkedRoot
    }
    It 'leaves the boot out only of the rows that test a CPMINCORES change against that step' {
        @((Get-Test $noParked 'min vs stock' 'lastWorkerWakeMs').boots) | Should -Be @(0)
        @((Get-Test $noParked 'min vs stock' 'avgFps').boots) | Should -Be @(0)
        @((Get-Test $noParked 'min vs stock' 'low1PctMs').boots) | Should -Be @(0)
        @((Get-Test $noParked 'gm-off-stock vs stock' 'avgFps').boots) | Should -Be @(0, 1)
        @((Get-Test $noParked 'gm-off-stock vs stock' 'low1PctMs').boots) | Should -Be @(0, 1)
    }
    It 'lists each such step under Steps left out with the rows it leaves' {
        $rows = @($noParked.Summary.analysis.excluded)
        @($rows | ForEach-Object { '{0}/{1}' -f $_.boot, $_.stateIndex }) | Should -Be @('0/4', '1/0', '1/1', '1/4')
        @($rows | ForEach-Object { $_.reason } | Select-Object -Unique) | Should -Be @('no parked-core reading')
        ($rows | Where-Object { $_.boot -eq 1 -and $_.stateIndex -eq 0 }).leftOutOf | Should -Be @('min vs stock: lastWorkerWakeMs')
        ($rows | Where-Object { $_.boot -eq 1 -and $_.stateIndex -eq 1 }).leftOutOf | Should -Be @('min vs stock: avgFps', 'min vs stock: low1PctMs')
        ($rows | Where-Object { $_.boot -eq 1 -and $_.stateIndex -eq 4 }).leftOutOf | Should -Be @('cap-min vs cap-stock: low01PctMs', 'cap-min vs cap-stock: low1PctMs')
        $noParked.Markdown | Should -Match '\| 1 \| stock \| burst \| no parked-core reading \| min vs stock: lastWorkerWakeMs \|'
    }
    It 'keeps the steps in the state tables and prints n/a where no step has a reading' {
        @((Get-State $noParked 'stock' 'burst').boots) | Should -Be @(0, 1)
        (Get-State $noParked 'stock' 'burst').parkedBeforeBurst.n | Should -Be 1
        (Get-State $noParked 'cap-stock' 'game').parkedDuringRun | Should -BeNullOrEmpty
        $noParked.Markdown | Should -Match '\| cap-stock \| 2 \| 144 \|.*\| n/a \|'
    }
    It 'keeps a tested row with no boot in its family and prints dashes and the note' {
        $noParked.Summary.analysis.family['main'] | Should -Be 7
        $row = Get-Test $noParked 'cap-min vs cap-stock' 'low01PctMs'
        @($row.boots).Count | Should -Be 0
        $row.p | Should -Be 1
        $row.verdict | Should -Be 'cannot tell'
        $noParked.Markdown | Should -Match '\| cap-min vs cap-stock \| 0\.1% low \(ms\) \| 0 \| - \| - \| - \| - \| - \| - \| 0 / 0 / 0 \| 1 \| cannot tell \| no boot holds every step this row pairs \|'
    }
    It 'passes the checks-only run and counts the boots of every tested row' {
        $checks = New-SeriesReport -SeriesPath $parkedRoot -ChecksOnly
        @($checks.Summary.analysis.excluded).Count | Should -Be 4
        @($checks.Summary.analysis.rowBoots | ForEach-Object { '{0} | {1} | {2}' -f $_.comparison, $_.metric, $_.boots }) | Should -Be @(
            'min vs stock | lastWorkerWakeMs | 1', 'min vs stock | avgFps | 1', 'min vs stock | low1PctMs | 1', 'gm-off-stock vs stock | avgFps | 2', 'gm-off-stock vs stock | low1PctMs | 2', 'cap-min vs cap-stock | low01PctMs | 0', 'cap-min vs cap-stock | low1PctMs | 0'
        )
        $checks.Markdown | Should -Match '\| cap-min vs cap-stock \| 0\.1% low \(ms\) \| 0 \|'
    }
}

Describe 'a described row with no boot' {
    It 'prints it with boots 0 and dashes' {
        $root = New-Series -Root (Join-Path $TestDrive 'described-empty') -Series 'parking-retest-2-ceiling' -Labels $seriesDesigns['parking-retest-2-ceiling'].units -Boots 6 -Mutate { param($ctx) if ($ctx.Label -eq 'maxcores25' -and $ctx.Step -eq 'game') { $ctx.Bench.powerStateChanged = $true } }
        $report = New-SeriesReport -SeriesPath $root
        $row = $report.Summary.analysis.described | Where-Object { $_.comparison -eq 'maxcores25-min vs maxcores25' -and $_.metric -eq 'avgFps' }
        @($row.boots).Count | Should -Be 0
        $row.shift | Should -BeNullOrEmpty
        $report.Markdown | Should -Match '\| maxcores25-min \(forced: the ceiling\) vs maxcores25 \(forced: the ceiling\) \| Average FPS \| 0 \| - \| - \| - \| - \| - \| 0 / 0 / 0 \| no boot holds every step this row pairs \|'
    }
}

Describe 'the power profile changes before the window' {
    It 'lists an excursion and leaves the single change into the Game Mode profile out' {
        $root = New-Series -Root (Join-Path $TestDrive 'excursion') -Mutate {
            param($ctx)
            if ($ctx.Boot -eq 1 -and $ctx.StateIndex -eq 3) {
                $ctx.Bench.ppm.profileChanges = @([ordered]@{ offsetSeconds = -40.5; from = 0; to = 12 }, [ordered]@{ offsetSeconds = -40.25; from = 12; to = 3 }, [ordered]@{ offsetSeconds = -38; from = 3; to = 12 })
            }
        }
        $report = New-SeriesReport -SeriesPath $root
        @($report.Summary.analysis.profileChanges).Count | Should -Be 1
        $report.Summary.analysis.profileChanges[0].stateIndex | Should -Be 3
        $report.Markdown | Should -Match '\| 1 \| min \| game \| 0 -> 12 at -40\.5 s, 12 -> 3 at -40\.25 s, 3 -> 12 at -38 s \|'
    }
}

Describe 'the failed attempts' {
    BeforeAll {
        $script:failedRoot = New-Series -Root (Join-Path $TestDrive 'failed') -MutateJournal {
            param($j)
            $j.Insert(2, [ordered]@{ at = '2026-01-11T09:30:00'; event = 'boot'; index = 1; startedAt = '2026-01-11T09:00:00'; endedAt = '2026-01-11T09:30:00'; outcome = 'failure'; states = @([ordered]@{ index = 0; kind = 'parking'; step = 'burst'; status = 'ok'; result = 'failed\boot01-20260111T093000\boot01-state00-burst.json' }, [ordered]@{ index = 1; kind = 'parking'; step = 'game'; status = 'failed'; result = 'failed\boot01-20260111T093000\boot01-state01-game-20260111T092900' }) })
            $j.Insert(3, [ordered]@{ at = '2026-01-11T09:40:00'; event = 'boot'; index = 1; startedAt = '2026-01-11T09:32:00'; endedAt = '2026-01-11T09:40:00'; outcome = 'failure'; states = @([ordered]@{ index = 0; kind = 'parking'; step = 'burst'; status = 'failed'; result = 'failed\boot01-20260111T094000\boot01-state00-burst-20260111T093900' }) })
            $j.Insert(4, [ordered]@{ at = '2026-01-11T09:45:00'; event = 'boot'; index = 1; startedAt = '2026-01-11T09:42:00'; endedAt = '2026-01-11T09:45:00'; outcome = 'failure'; states = @([ordered]@{ index = 0; kind = 'parking'; step = 'burst'; status = 'failed'; result = $null }) })
            $j.Insert(5, [ordered]@{ at = '2026-01-11T09:58:00'; event = 'boot'; index = 1; startedAt = '2026-01-11T09:51:00'; endedAt = '2026-01-11T09:58:00'; outcome = 'killed'; states = @(); failedDir = 'failed\boot01-20260111T095800' })
        }
        $boot = Join-Path $failedRoot 'failed\boot01-20260111T093000'
        $attempt = Join-Path $boot 'boot01-state01-game-20260111T092900'
        $null = New-Item -ItemType Directory -Path $attempt -Force
        ConvertTo-Json -InputObject ([ordered]@{ test = 'burst'; phase = 'boot01-state00'; highQos = $true }) | Set-Content -LiteralPath (Join-Path $boot 'parking-bench-boot01-state00-burst.json') -Encoding UTF8
        ConvertTo-Json -InputObject ([ordered]@{ series = 'fixture'; boot = 1; stateIndex = 0 }) | Set-Content -LiteralPath (Join-Path $boot 'boot01-state00-burst.json') -Encoding UTF8
        ConvertTo-Json -InputObject ([ordered]@{ test = 'game'; phase = 'boot01-state01'; rejected = 'the median frame time is outside the cap (the cap did not hold)' }) | Set-Content -LiteralPath (Join-Path $attempt 'parking-bench-boot01-state01-game.json') -Encoding UTF8
        ConvertTo-Json -InputObject ([ordered]@{ series = 'fixture'; boot = 1; stateIndex = 1 }) | Set-Content -LiteralPath (Join-Path $attempt 'boot01-state01-game.json') -Encoding UTF8
        $burst = Join-Path $failedRoot 'failed\boot01-20260111T094000\boot01-state00-burst-20260111T093900'
        $null = New-Item -ItemType Directory -Path $burst -Force
        ConvertTo-Json -InputObject ([ordered]@{ test = 'burst'; phase = 'boot01-state00'; highQos = $true }) | Set-Content -LiteralPath (Join-Path $burst 'parking-bench-boot01-state00-burst.json') -Encoding UTF8
        $null = New-Item -ItemType Directory -Path (Join-Path $failedRoot 'failed\boot01-20260111T095800') -Force
        $script:failed = New-SeriesReport -SeriesPath $failedRoot
    }
    It 'takes the boot folder and the public reason from the failing state''s result' {
        $rows = @($failed.Summary.analysis.failedAttempts)
        @($rows | ForEach-Object { $_.outcome }) | Should -Be @('failure', 'failure', 'failure', 'killed')
        $rows[0].failingStep | Should -Be 'state 1 game'
        $rows[0].failedDir | Should -Be 'failed\boot01-20260111T093000'
        $rows[0].reason | Should -Be 'the median frame time is outside the cap (the cap did not hold)'
        $rows[0].startedAt | Should -Be '2026-01-11T09:00:00'
        $failed.Markdown | Should -Match '\| 1 \| 2026-01-11T09:00:00 \| 2026-01-11T09:30:00 \| failure \| state 1 game \| failed\\boot01-20260111T093000 \| the median frame time is outside the cap \(the cap did not hold\) \|'
    }
    It 'says no public reason for a bench JSON without rejected, a step that left no file and a killed boot' {
        $rows = @($failed.Summary.analysis.failedAttempts)
        $rows[1].failingStep | Should -Be 'state 0 burst'
        $rows[1].failedDir | Should -Be 'failed\boot01-20260111T094000'
        $rows[1].reason | Should -Be 'no public reason'
        $rows[2].failingStep | Should -Be 'state 0 burst'
        $rows[2].failedDir | Should -BeNullOrEmpty
        $rows[2].reason | Should -Be 'no public reason'
        $rows[3].failingStep | Should -BeNullOrEmpty
        $rows[3].failedDir | Should -Be 'failed\boot01-20260111T095800'
        $rows[3].reason | Should -Be 'no public reason'
        $failed.Markdown | Should -Match '\| 1 \| 2026-01-11T09:42:00 \| 2026-01-11T09:45:00 \| failure \| state 0 burst \| - \| no public reason \|'
        $failed.Markdown | Should -Match '\| 1 \| 2026-01-11T09:51:00 \| 2026-01-11T09:58:00 \| killed \| - \| failed\\boot01-20260111T095800 \| no public reason \|'
    }
    It 'prints the rejection text as recorded under -ChecksOnly too' {
        $checks = New-SeriesReport -SeriesPath $failedRoot -ChecksOnly
        $checks.Summary.analysis.failedAttempts[0].reason | Should -Be 'the median frame time is outside the cap (the cap did not hold)'
        $checks.Markdown | Should -Match 'the median frame time is outside the cap \(the cap did not hold\)'
    }
    It 'takes only the successful boot into the tables' {
        @((Get-State $failed 'stock' 'burst').boots) | Should -Be @(0, 1)
    }
}

Describe 'the checks-only run' {
    BeforeAll {
        $script:checksRoot = New-Series -Root (Join-Path $TestDrive 'checks-only') -Mutate { param($ctx) if ($ctx.Boot -eq 1 -and $ctx.StateIndex -eq 4) { $ctx.Bench.powerStateChanged = $true } }
        $script:checksReport = New-SeriesReport -SeriesPath $checksRoot -ChecksOnly
    }
    It 'prints the testbed, the checks, the failed attempts and the steps left out, and nothing read from an outcome' {
        foreach ($heading in '## Testbed', '## Checks that passed before these tables were written', '## Failed attempts', '## Steps left out') { $checksReport.Markdown | Should -Match ([regex]::Escape($heading)) }
        foreach ($heading in '## Pre-registered comparisons', '## Pre-registered tests', '## Described comparisons', '## Burst', '## Uncapped game', '## Capped game', '## Table to file map', '## Boots and files') { $checksReport.Markdown | Should -Not -Match ([regex]::Escape($heading)) }
        $checksReport.Markdown | Should -Match '\| 1 \| cap-stock \| game \| the power scheme or a processor setting changed'
        $checksReport.Markdown | Should -Not -Match '20\.25|19\.25|verdict|cannot tell'
        @($checksReport.Summary.PSObject.Properties.Name) | Should -Be @('series', 'constants', 'checks', 'testbed', 'analysis')
        @($checksReport.Summary.analysis.Keys) | Should -Be @('excluded', 'failedAttempts', 'profileChanges', 'rowBoots')
    }
    It 'counts the boots each tested row will pair, and nothing else of the row' {
        $checksReport.Markdown | Should -Match '## Boots per tested row'
        $checksReport.Markdown | Should -Match '\| min vs stock \| Burst wake, median of the run \(ms\) \| 2 \|'
        $checksReport.Markdown | Should -Match '\| cap-min vs cap-stock \| 0\.1% low \(ms\) \| 1 \|'
        @($checksReport.Summary.analysis.rowBoots[0].PSObject.Properties.Name) | Should -Be @('comparison', 'metric', 'boots')
        @($checksReport.Summary.analysis.rowBoots).Count | Should -Be 7
    }
    It 'runs the same refusals' {
        $root = New-Series -Root (Join-Path $TestDrive 'checks-only-refused') -Mutate { param($ctx) if ($ctx.Boot -eq 0 -and $ctx.StateIndex -eq 1) { $ctx.Bench.highQos = $false } }
        { New-SeriesReport -SeriesPath $root -ChecksOnly } | Should -Throw '*bench field highQos*'
    }
    It 'takes -ChecksOnly at the script entry point' {
        $md = Join-Path $TestDrive 'checks-only.md'
        & $tool -SeriesPath $checksRoot -MarkdownPath $md -ChecksOnly
        (Get-Content -LiteralPath $md -Raw) | Should -Be $checksReport.Markdown
    }
}

Describe 'the rules block' {
    BeforeAll {
        $script:rules = (Format-RulesBlock) -join "`n"
    }
    It 'names every field the gates read, from the constants the code uses' {
        $fields = @($requiredFingerprintFields) + @($optionalFingerprintFields) + @($optionalEnvironmentFields) + @($driverFingerprintFields) + @($burstFingerprintFields) + @($gameFingerprintFields) + @($presentModesField, $processorSettingsField, $powerExplicitField) + @($stepParked.Values | ForEach-Object { "$_.$logicalCpusField" }) + @($gateFields.Values) + @($exclusionFields.Values)
        $fields.Count | Should -BeGreaterThan 30
        foreach ($field in $fields) { $rules.Contains($field) | Should -BeTrue -Because $field }
    }
    It 'states the verdict, the parked-core and the empty-row rules and how failed attempts are printed' {
        $rules.Contains('(3) cannot tell when at least one boot differs and every boot that differs lies on one side') | Should -BeTrue
        $rules.Contains('no parked-core reading') | Should -BeTrue
        $rules.Contains('A tested row with no boot that holds every step it pairs stays in its family with p = 1 and reads cannot tell') | Should -BeTrue
        $rules.Contains("A failed attempt's rejection text is printed as recorded; failed attempts are never read for outcomes.") | Should -BeTrue
    }
}

Describe 'the script entry point' {
    It 'writes the markdown and summary.json files with the same numbers' {
        $root = New-Series -Root (Join-Path $TestDrive 'entry')
        $md = Join-Path $TestDrive 'entry.md'
        $json = Join-Path $TestDrive 'entry.json'
        & $tool -SeriesPath $root -MarkdownPath $md -SummaryPath $json
        $summary = Get-Content -LiteralPath $json -Raw | ConvertFrom-Json
        $summary.series | Should -Be 'fixture'
        $summary.constants.margins.shareOfReferenceMedian.low01PctMs | Should -Be 0.033
        $summary.analysis.family.main | Should -Be 7
        ($summary.states | Where-Object { $_.label -eq 'stock' -and $_.step -eq 'burst' }).wakeP90Ms.max | Should -Be 1.91
        (Get-Content -LiteralPath $md -Raw) | Should -Match '## Pre-registered tests'
    }
    It 'writes the same bytes from two separate runs' {
        $root = New-Series -Root (Join-Path $TestDrive 'twice')
        $engine = (Get-Process -Id $PID).Path
        $bytes = foreach ($run in 1, 2) {
            $md = Join-Path $TestDrive "twice-$run.md"
            $json = Join-Path $TestDrive "twice-$run.json"
            & $engine -NoProfile -ExecutionPolicy Bypass -File $tool -SeriesPath $root -MarkdownPath $md -SummaryPath $json
            [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($md)) + '|' + [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($json))
        }
        $bytes[0].Length | Should -BeGreaterThan 1
        $bytes[0] | Should -Be $bytes[1]
    }
    It 'writes byte-identical markdown and a summary.json that parses to the same values under pwsh and Windows PowerShell on midpoint values' {
        $engines = @('pwsh', 'powershell') | ForEach-Object { Get-Command $_ -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1 }
        if (@($engines).Count -lt 2) { Set-ItResult -Skipped -Because 'one of the two engines is not installed'; return }
        $root = New-Series -Root (Join-Path $TestDrive 'engines') -Mutate {
            param($ctx)
            if ($ctx.Step -eq 'game' -and -not $ctx.Bench.cap) { $ctx.Bench.frames.low1PctMs = @(2.675, 0.285)[$ctx.Boot]; $ctx.Bench.frames.gpuBusyP50Ms = @(1.115, 1.005)[$ctx.Boot] }
            if ($ctx.Step -eq 'burst') { $ctx.Bench.burst.lastWorkerWakeMs.median = @(1.115, 2.675)[$ctx.Boot] + $ctx.StateIndex }
        }
        $bytes = foreach ($engine in $engines) {
            $name = [System.IO.Path]::GetFileNameWithoutExtension($engine.Source)
            $md = Join-Path $TestDrive "engines-$name.md"
            $json = Join-Path $TestDrive "engines-$name.json"
            & $engine.Source -NoProfile -ExecutionPolicy Bypass -File $tool -SeriesPath $root -MarkdownPath $md -SummaryPath $json
            [System.Convert]::ToBase64String([System.IO.File]::ReadAllBytes($md)) + '|' + ((Get-Content -LiteralPath $json -Raw | ConvertFrom-Json | ConvertTo-Json -Depth 20 -Compress) -replace '(\d)\.0(?=[,}\]])', '$1')
        }
        $bytes[0] | Should -Be $bytes[1]
    }
    It 'prints the markdown to stdout without -MarkdownPath' {
        $root = New-Series -Root (Join-Path $TestDrive 'stdout')
        (& $tool -SeriesPath $root) -join "`n" | Should -Match '## Capped game'
    }
}
