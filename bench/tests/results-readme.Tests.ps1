BeforeAll {
    $script:seriesDir = Join-Path $PSScriptRoot '..\results\parking-retest'
    $script:resultsReadme = Get-Content -Path (Join-Path $PSScriptRoot '..\results\README.md') -Raw -Encoding UTF8
    $script:mainReadme = Get-Content -Path (Join-Path $PSScriptRoot '..\..\README.md') -Raw -Encoding UTF8
    $script:sampleRun = Get-Content -Path (Join-Path $PSScriptRoot '..\results\testbed-checks\sample-run.txt') -Raw -Encoding UTF8

    function Get-SampleRunBlock {
        $blocks = @([regex]::Matches($mainReadme, '(?s)```[a-z]*\r?\n(.*?)```') | ForEach-Object { $_.Groups[1].Value } | Where-Object { $_ -match 'Power scheme\s+:' })
        if ($blocks.Count -ne 1) { throw "README.md should hold one sample run block, found $($blocks.Count)" }
        $blocks[0]
    }

    function Get-StateName($Settings) {
        $parts = @()
        if ($Settings.CPMAXCORES -ne 100) { $parts += 'ceil' }
        if ($Settings.CPMINCORES -eq 100) { $parts += 'min' }
        if ($Settings.PERFEPP -eq 0) { $parts += 'epp' }
        if ($parts.Count) { $parts -join '+' } else { 'stock' }
    }

    function Get-DecimalMedian([decimal[]]$Values) {
        $sorted = @($Values | Sort-Object)
        $n = $sorted.Count
        if ($n % 2) { return $sorted[($n - 1) / 2] }
        ($sorted[$n / 2 - 1] + $sorted[$n / 2]) / 2
    }

    function Format-Tenths([decimal]$Value) {
        [Math]::Round($Value, 1, [MidpointRounding]::AwayFromZero).ToString('0.0', [Globalization.CultureInfo]::InvariantCulture)
    }

    $script:runs = @(Get-ChildItem -Path $seriesDir -Filter 'boot*-state*-*.json' -File | ForEach-Object {
            $record = Get-Content -Path $_.FullName -Raw | ConvertFrom-Json
            $result = Get-Content -Path (Join-Path $seriesDir $record.bench.resultFile) -Raw | ConvertFrom-Json
            [pscustomobject]@{ File = $_.Name; Record = $record; Result = $result; State = Get-StateName $record.state.settings; Step = $record.state.step }
        })
    $script:stock = ($runs | Where-Object State -eq 'stock' | Select-Object -First 1).Record.state.settings
    $script:journal = @(Get-Content -Path (Join-Path $seriesDir 'journal.jsonl') | ForEach-Object { $_ | ConvertFrom-Json })

    function Get-StateFps([string]$State) {
        [decimal[]]@($runs | Where-Object { $_.State -eq $State -and $_.Step -eq 'game' } | ForEach-Object { [decimal]$_.Result.frames.avgFps })
    }

    function Get-StateWakeMedian([string]$State) {
        Get-DecimalMedian ([decimal[]]@($runs | Where-Object { $_.State -eq $State -and $_.Step -eq 'burst' } | ForEach-Object { [decimal]$_.Result.burst.lastWorkerWakeMs.median }))
    }

    function Get-SameBootFpsGap([string]$Other) {
        foreach ($ceil in @($runs | Where-Object { $_.State -eq 'ceil' -and $_.Step -eq 'game' })) {
            $peer = @($runs | Where-Object { $_.State -eq $Other -and $_.Step -eq 'game' -and $_.Record.boot -eq $ceil.Record.boot })
            if ($peer.Count -ne 1) { throw "boot $($ceil.Record.boot) has $($peer.Count) $Other game runs" }
            ([decimal]$ceil.Result.frames.avgFps / [decimal]$peer[0].Result.frames.avgFps - 1) * 100
        }
    }

    function Format-Percent([decimal]$Value, [switch]$Signed) {
        $text = [Math]::Round($Value, 2, [MidpointRounding]::AwayFromZero).ToString('0.00', [Globalization.CultureInfo]::InvariantCulture)
        if ($Signed -and $Value -gt 0) { "+$text" } else { $text }
    }
}

Describe 'bench/results/README.md matches the parking-retest files' {
    It 'quotes the CS2 average fps of <_> as the median of its runs rounded half away from zero' -ForEach @('stock', 'min', 'epp', 'min+epp', 'ceil', 'ceil+min', 'ceil+epp') {
        $fps = Get-StateFps $_
        $row = '| {0} | {1} | {2} [' -f $_, $fps.Count, (Format-Tenths (Get-DecimalMedian $fps))
        $resultsReadme.Contains($row) | Should -BeTrue -Because "bench/results/README.md should hold the row '$row'"
    }

    It 'names every result file a retried boot overwrote in the README caveats' {
        $overwritten = @(foreach ($boot in $journal | Where-Object event -eq 'boot') {
            foreach ($state in @($boot.states | Where-Object { $_.status -eq 'ok' -and $_.result })) {
                $captured = [datetime](Get-Content -Path (Join-Path $seriesDir $state.result) -Raw | ConvertFrom-Json).capturedAt
                if ($captured -lt [datetime]$boot.startedAt -or $captured -gt [datetime]$boot.endedAt) { $state.result }
            }
        })
        $caveats = [regex]::Match($resultsReadme, '(?ms)^## Caveats\r?\n(.*?)(?=^## |\z)').Groups[1].Value
        foreach ($file in $overwritten) {
            $caveats | Should -Match ([regex]::Escape($file)) -Because "the retry overwrote $file, so the README caveats must say so"
        }
    }

    It 'quotes the same-boot ceiling comparison: ceil beat ceil+min in every ceiling boot, by the published range' {
        $vsMin = @(Get-SameBootFpsGap 'ceil+min')
        $vsEpp = @(Get-SameBootFpsGap 'ceil+epp')
        @($vsMin | Where-Object { $_ -le 0 }) | Should -BeNullOrEmpty -Because 'the README says ceil beat ceil+min in every ceiling boot'
        $minRange = 'by {0}% to {1}%' -f (Format-Percent ($vsMin | Measure-Object -Minimum).Minimum), (Format-Percent ($vsMin | Measure-Object -Maximum).Maximum)
        $eppRange = 'from {0}% to {1}%' -f (Format-Percent ($vsEpp | Measure-Object -Minimum).Minimum -Signed), (Format-Percent ($vsEpp | Measure-Object -Maximum).Maximum -Signed)
        $resultsReadme.Contains($minRange) | Should -BeTrue -Because "bench/results/README.md should say '$minRange'"
        $resultsReadme.Contains($eppRange) | Should -BeTrue -Because "bench/results/README.md should say '$eppRange'"
    }

    It 'says updaters were kept off only when no run recorded a Windows Update service running' {
        $updaterRuns = @($runs | Where-Object { @($_.Record.environment.services.name) -match '^(wuauserv|UsoSvc|DoSvc)$' })
        if ($resultsReadme -match 'updaters? (were|was) (switched|turned) off|switched off[^.]{0,80}\bupdaters\b') {
            $updaterRuns.Count | Should -Be 0 -Because 'the README says background services and updaters were switched off'
        }
    }

    It 'claims <Claim> only when a recorded file shows it' -ForEach @(
        @{ Claim = 'DirectX 11'; Pattern = 'DirectX 11'; Backed = { @($runs.Result.load.extraLaunchFlags) -contains '-dx11' } }
        @{ Claim = 'Steam offline mode'; Pattern = 'offline mode'; Backed = { @($runs | Where-Object { $_.Step -eq 'game' -and $_.Result.load.steamOffline }).Count -gt 0 } }
        @{ Claim = 'a 640x360 run'; Pattern = '640x360'; Backed = { @(Get-ChildItem -Path $seriesDir -Recurse -File | Select-String -Pattern '640x360|"setting\.defaultres"\s+"640"' -List).Count -gt 0 } }
        @{ Claim = 'a default-buffer run'; Pattern = 'default buffer drops frames'; Backed = { @($runs | Where-Object { $_.Step -eq 'game' -and $_.Result.presentMon.circularBufferSize -and $_.Result.presentMon.circularBufferSize -ne 16384 }).Count -gt 0 } }
    ) {
        if ($resultsReadme -match $Pattern) { (& $Backed) | Should -BeTrue -Because "bench/results/README.md states '$Pattern'" }
    }
}

Describe 'README.md matches the parking-retest files' {
    It 'says every state ran in its own boots only when no boot ran two states' {
        $shared = @($runs | Group-Object { $_.Record.boot } | Where-Object { @($_.Group.State | Sort-Object -Unique).Count -gt 1 })
        if ($mainReadme -match 'Every state ran in its own boots') {
            $shared.Count | Should -Be 0 -Because 'README.md says every state ran in its own boots'
        }
    }

    It 'quotes how many times sooner the script wakes the last burst thread within 10%' {
        $ratio = (Get-StateWakeMedian 'stock') / (Get-StateWakeMedian 'min+epp')
        $m = [regex]::Match($mainReadme, 'about (\d+) times sooner')
        $m.Success | Should -BeTrue
        [decimal]$m.Groups[1].Value | Should -BeGreaterOrEqual ($ratio * 0.9)
        [decimal]$m.Groups[1].Value | Should -BeLessOrEqual ($ratio * 1.1)
    }

    It 'counts the runs behind the stock-versus-script fps comparison' {
        $n = (Get-StateFps 'stock').Count + (Get-StateFps 'min+epp').Count
        $m = [regex]::Match($mainReadme, 'after the script across (\d+) runs')
        if ($m.Success) { [int]$m.Groups[1].Value | Should -Be $n }
    }

    It 'quotes the forced-parking fps as the median of its runs rounded half away from zero' {
        $fps = Get-StateFps 'ceil'
        $cell = '| {0} [' -f (Format-Tenths (Get-DecimalMedian $fps))
        $mainReadme.Contains($cell) | Should -BeTrue -Because "README.md should hold the cell '$cell'"
    }

    It 'gives one parking minimum only when both core classes share it' {
        if ($mainReadme -match 'park down to \d+% of cores') {
            $stock.CPMINCORES1 | Should -Be $stock.CPMINCORES -Because 'README.md quotes a single parking minimum'
        }
    }

    It 'shows the sample run on the stock power plan of the series' {
        Get-SampleRunBlock | Should -Match 'Power scheme\s+:\s+Balanced\s'
    }

    It 'shows the stock AC value of <_> in the sample run' -ForEach @('CPMINCORES', 'CPMINCORES1', 'PERFEPP', 'PERFEPP1') {
        $m = [regex]::Match((Get-SampleRunBlock), "(?m)^\s+$_\s+(\d+)\s+(\d+)\s+\d+")
        $m.Success | Should -BeTrue
        [int]$m.Groups[1].Value | Should -Be $stock.$_
    }

    It 'the README sample run is the published capture, verbatim' {
        ((Get-SampleRunBlock) -replace '\r\n', "`n").Trim() | Should -BeExactly (($sampleRun -replace '\r\n', "`n").Trim())
    }

    It 'lists the stock value of <_> in the Before column of Settings Changed' -ForEach @('CPMINCORES', 'CPMINCORES1', 'PERFEPP', 'PERFEPP1') {
        $m = [regex]::Match($mainReadme, "(?m)^\|\s*``$_``\s*\|[^|]*\|([^|]*)\|")
        $m.Success | Should -BeTrue
        $numbers = @([regex]::Matches($m.Groups[1].Value, '\d+') | ForEach-Object { [int]$_.Value })
        $numbers | Should -Be @($stock.$_)
    }
}
