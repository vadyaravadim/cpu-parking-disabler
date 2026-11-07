BeforeAll {
    . (Join-Path $PSScriptRoot '..\bench-env.ps1')
    $script:repoRoot = Join-Path $PSScriptRoot '..\..'
    $script:seriesDir = Join-Path $PSScriptRoot '..\results\parking-retest'
    $script:checksDir = Join-Path $PSScriptRoot '..\results\testbed-checks'
    $script:wakeOverMs = 20
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

    function Format-Fixed([decimal]$Value, [int]$Digits, [switch]$Signed) {
        $pattern = if ($Digits) { '0.' + ('0' * $Digits) } else { '0' }
        $text = [Math]::Round($Value, $Digits, [MidpointRounding]::AwayFromZero).ToString($pattern, [Globalization.CultureInfo]::InvariantCulture)
        if ($Signed -and $Value -gt 0) { "+$text" } else { $text }
    }

    $script:runs = @(Get-ChildItem -Path $seriesDir -Filter 'boot*-state*-*.json' -File | ForEach-Object {
            $record = Get-Content -Path $_.FullName -Raw | ConvertFrom-Json
            $result = Get-Content -Path (Join-Path $seriesDir $record.bench.resultFile) -Raw | ConvertFrom-Json
            [pscustomobject]@{ File = $_.Name; Record = $record; Result = $result; State = Get-StateName $record.state.settings; Step = $record.state.step }
        })
    $script:stock = ($runs | Where-Object State -eq 'stock' | Select-Object -First 1).Record.state.settings
    $script:journal = @(Get-Content -Path (Join-Path $seriesDir 'journal.jsonl') | ForEach-Object { $_ | ConvertFrom-Json })

    $script:lastWakes = @{}
    foreach ($run in @($runs | Where-Object Step -eq 'burst')) {
        $wakeFile = @($run.Result.files | Where-Object { $_ -like '*-wake.csv' })
        if ($wakeFile.Count -ne 1) { throw "$($run.File) lists $($wakeFile.Count) wake files" }
        $lines = [IO.File]::ReadAllLines((Join-Path $seriesDir $wakeFile[0]))
        if ($lines[0] -ne 'burst,thread,wakeMs,cpuAtWake,cpuAtEnd') { throw "$($wakeFile[0]) has the header '$($lines[0])'" }
        $slowest = @{}
        for ($i = 1; $i -lt $lines.Count; $i++) {
            $cells = $lines[$i].Split(',')
            $wake = [decimal]::Parse($cells[2], [Globalization.CultureInfo]::InvariantCulture)
            if (-not $slowest.ContainsKey($cells[0]) -or $wake -gt $slowest[$cells[0]]) { $slowest[$cells[0]] = $wake }
        }
        if ($slowest.Count -ne $run.Result.bursts) { throw "$($wakeFile[0]) holds $($slowest.Count) bursts, the result says $($run.Result.bursts)" }
        if (-not $lastWakes.ContainsKey($run.State)) { $lastWakes[$run.State] = [Collections.Generic.List[decimal]]::new() }
        $lastWakes[$run.State].AddRange([decimal[]]@($slowest.Values))
    }

    function Get-StateLastWakes([string]$State) {
        [decimal[]]@($lastWakes[$State] | Sort-Object)
    }

    function Get-StateFps([string]$State) {
        [decimal[]]@($runs | Where-Object { $_.State -eq $State -and $_.Step -eq 'game' } | ForEach-Object { [decimal]$_.Result.frames.avgFps })
    }

    function Get-StateWakeMedian([string]$State) {
        Get-DecimalMedian ([decimal[]]@($runs | Where-Object { $_.State -eq $State -and $_.Step -eq 'burst' } | ForEach-Object { [decimal]$_.Result.burst.lastWorkerWakeMs.median }))
    }

    function Get-SameBootGap([string]$Anchor, [string]$Other, [scriptblock]$Gap) {
        foreach ($anchorRun in @($runs | Where-Object { $_.State -eq $Anchor -and $_.Step -eq 'game' })) {
            $peer = @($runs | Where-Object { $_.State -eq $Other -and $_.Step -eq 'game' -and $_.Record.boot -eq $anchorRun.Record.boot })
            if ($peer.Count -ne 1) { throw "boot $($anchorRun.Record.boot) has $($peer.Count) $Other game runs" }
            & $Gap $anchorRun.Result.frames $peer[0].Result.frames
        }
    }

    $script:anchorFpsGain = { param($Anchor, $Other) ([decimal]$Anchor.avgFps / [decimal]$Other.avgFps - 1) * 100 }
    $script:otherFpsGain = { param($Anchor, $Other) ([decimal]$Other.avgFps / [decimal]$Anchor.avgFps - 1) * 100 }
    $script:otherLow1Ms = { param($Anchor, $Other) [decimal]$Other.low1PctMs - [decimal]$Anchor.low1PctMs }
    $script:otherLow01Ms = { param($Anchor, $Other) [decimal]$Other.low01PctMs - [decimal]$Anchor.low01PctMs }
    $script:sameBootMetrics = @(
        @{ Label = 'average fps'; Gap = $otherFpsGain }
        @{ Label = '1% low'; Gap = $otherLow1Ms }
        @{ Label = '0.1% low'; Gap = $otherLow01Ms }
    )
    $script:flatResultsReadme = $resultsReadme -replace '\s+', ' '
    $script:flatMainReadme = $mainReadme -replace '\s+', ' '

    function Get-SplitOdds([int]$Count, [int]$AtLeast) {
        $ways = [double]0
        $choose = [double]1
        for ($i = 0; $i -le $Count; $i++) {
            if ($i -ge $AtLeast) { $ways += $choose }
            $choose = $choose * ($Count - $i) / ($i + 1)
        }
        [Math]::Pow(2, $Count) / (2 * $ways)
    }

    function Get-QhAcValue([string]$File, [string]$Alias) {
        $capture = Get-Content -Path (Join-Path $checksDir $File) -Raw
        $m = [regex]::Match($capture, "(?s)GUID Alias: $Alias\r?\n.*?Current AC Power Setting Index: 0x([0-9a-f]+)")
        if (-not $m.Success) { throw "$File has no AC value for $Alias" }
        [Convert]::ToInt32($m.Groups[1].Value, 16)
    }

    function Get-GitShowBytes([string]$Spec) {
        $info = [Diagnostics.ProcessStartInfo]::new('git')
        foreach ($arg in @('-C', $repoRoot, 'show', $Spec)) { $info.ArgumentList.Add($arg) }
        $info.RedirectStandardOutput = $true
        $info.RedirectStandardError = $true
        $info.UseShellExecute = $false
        $process = [Diagnostics.Process]::Start($info)
        $stderr = $process.StandardError.ReadToEndAsync()
        $buffer = [IO.MemoryStream]::new()
        $process.StandardOutput.BaseStream.CopyTo($buffer)
        $process.WaitForExit()
        if ($process.ExitCode) { throw "git show $Spec failed: $($stderr.Result)" }
        $buffer.ToArray()
    }
}

Describe 'bench/results/README.md matches the parking-retest files' {
    It 'quotes the CS2 average fps of <_> as the median of its runs rounded half away from zero' -ForEach @('stock', 'min', 'epp', 'min+epp', 'ceil', 'ceil+min', 'ceil+epp') {
        $fps = Get-StateFps $_
        $row = '| {0} | {1} | {2} [' -f $_, $fps.Count, (Format-Fixed (Get-DecimalMedian $fps) 1)
        $resultsReadme.Contains($row) | Should -BeTrue -Because "bench/results/README.md should hold the row '$row'"
    }

    It 'prints every cell of the <_> rows as the median of its runs rounded half away from zero' -ForEach @('stock', 'min', 'epp', 'min+epp', 'ceil', 'ceil+min', 'ceil+epp') {
        $state = $_
        $game = @($runs | Where-Object { $_.State -eq $state -and $_.Step -eq 'game' } | ForEach-Object { $_.Result })
        $burst = @($runs | Where-Object { $_.State -eq $state -and $_.Step -eq 'burst' } | ForEach-Object { $_.Result })
        $fps = [decimal[]]@($game | ForEach-Object { [decimal]$_.frames.avgFps })
        $total = [decimal[]]@($burst | ForEach-Object { [decimal]$_.burst.totalCoreMs.median })
        $wake = [decimal[]]@($burst | ForEach-Object { [decimal]$_.burst.lastWorkerWakeMs.median })
        $gameRow = '| {0} | {1} | {2} [{3}-{4}] | {5} | {6} | {7} | {8} |' -f $state, $game.Count,
            (Format-Fixed (Get-DecimalMedian $fps) 1), (Format-Fixed ($fps | Measure-Object -Minimum).Minimum 1), (Format-Fixed ($fps | Measure-Object -Maximum).Maximum 1),
            (Format-Fixed (Get-DecimalMedian ([decimal[]]@($game | ForEach-Object { [decimal]$_.frames.p50Ms }))) 3),
            (Format-Fixed (Get-DecimalMedian ([decimal[]]@($game | ForEach-Object { [decimal]$_.frames.low1PctMs }))) 2),
            (Format-Fixed (Get-DecimalMedian ([decimal[]]@($game | ForEach-Object { [decimal]$_.frames.low01PctMs }))) 2),
            (Format-Fixed (Get-DecimalMedian ([decimal[]]@($game | ForEach-Object { [decimal]$_.parkedDuringRun.parked.median }))) 0)
        $burstRow = '| {0} | {1} | {2} | {3} [{4}-{5}] | {6} | {7} [{8}-{9}] |' -f $state, $burst.Count,
            (Format-Fixed (Get-DecimalMedian ([decimal[]]@($burst | ForEach-Object { [decimal]$_.parkedBeforeBurst.parked.median }))) 0),
            (Format-Fixed (Get-DecimalMedian $total) 0), (Format-Fixed ($total | Measure-Object -Minimum).Minimum 0), (Format-Fixed ($total | Measure-Object -Maximum).Maximum 0),
            (Format-Fixed (Get-DecimalMedian ([decimal[]]@($burst | ForEach-Object { [decimal]$_.burst.earlyCoreMs.median }))) 1),
            (Format-Fixed (Get-DecimalMedian $wake) 2), (Format-Fixed ($wake | Measure-Object -Minimum).Minimum 2), (Format-Fixed ($wake | Measure-Object -Maximum).Maximum 2)
        $resultsReadme.Contains($gameRow) | Should -BeTrue -Because "bench/results/README.md should hold the CS2 row '$gameRow'"
        $resultsReadme.Contains($burstRow) | Should -BeTrue -Because "bench/results/README.md should hold the burst row '$burstRow'"
    }

    It 'prints every row of the per-burst wake table from the wake files of <_>' -ForEach @('stock', 'min', 'epp', 'min+epp', 'ceil', 'ceil+min', 'ceil+epp') {
        $wakes = Get-StateLastWakes $_
        $row = '| {0} | {1} | {2} | {3} | {4} | {5} |' -f $_, $wakes.Count,
            (Format-Fixed ([decimal](Get-Percentile ([double[]]$wakes) 0.50)) 2), (Format-Fixed ([decimal](Get-Percentile ([double[]]$wakes) 0.90)) 2),
            (Format-Fixed $wakes[-1] 2), @($wakes | Where-Object { $_ -gt $wakeOverMs }).Count
        $resultsReadme.Contains(('| State | Bursts | p50 ms | p90 ms | Slowest ms | Over {0} ms |' -f $wakeOverMs)) | Should -BeTrue -Because 'bench/results/README.md should hold the per-burst wake table'
        $resultsReadme.Contains($row) | Should -BeTrue -Because "bench/results/README.md should hold the per-burst wake row '$row'"
    }

    It 'prints every row of the same-boot table against stock for <_>' -ForEach @('min', 'epp', 'min+epp') {
        $state = $_
        $cells = foreach ($metric in @(@{ Gap = $otherFpsGain; Digits = 2 }, @{ Gap = $otherLow1Ms; Digits = 3 }, @{ Gap = $otherLow01Ms; Digits = 3 })) {
            $gaps = [decimal[]]@(Get-SameBootGap 'stock' $state $metric.Gap)
            '{0} [{1} of {2}]' -f (Format-Fixed (Get-DecimalMedian $gaps) $metric.Digits -Signed), @($gaps | Where-Object { $_ -lt 0 }).Count, $gaps.Count
        }
        $row = '| {0} | {1} |' -f $state, ($cells -join ' | ')
        $resultsReadme.Contains($row) | Should -BeTrue -Because "bench/results/README.md should hold the same-boot row '$row'"
    }

    It 'quotes the chance odds of a same-boot split and calls out only the cells chance gives least often' {
        $n = @(Get-SameBootGap 'stock' 'min' $otherFpsGain).Count
        $m = [regex]::Match($flatResultsReadme, 'chance alone puts (\d+) of (\d+) on one side about once in (\d+) tries, (\d+) or more of \2 about once in (\d+) tries, and (\d+) or more of \2 more than once in (\d+) tries')
        $m.Success | Should -BeTrue
        [int]$m.Groups[2].Value | Should -Be $n
        [int]$m.Groups[1].Value | Should -Be $n
        [int]$m.Groups[3].Value | Should -Be ([Math]::Round((Get-SplitOdds $n $n)))
        [int]$m.Groups[4].Value | Should -Be ($n - 1)
        [int]$m.Groups[5].Value | Should -Be ([Math]::Round((Get-SplitOdds $n ($n - 1))))
        [int]$m.Groups[6].Value | Should -Be ($n - 2)
        (Get-SplitOdds $n ($n - 2)) | Should -BeLessThan ([int]$m.Groups[7].Value)
        $extreme = [Collections.Generic.List[string]]::new()
        $nearExtreme = [Collections.Generic.List[string]]::new()
        foreach ($state in @('min', 'epp', 'min+epp')) {
            foreach ($metric in $sameBootMetrics) {
                $lower = @(Get-SameBootGap 'stock' $state $metric.Gap | Where-Object { $_ -lt 0 }).Count
                if ($lower -in 0, $n) { $extreme.Add(('`{0}` {1}' -f $state, $metric.Label)) }
                if ($lower -eq 1) { $nearExtreme.Add(('`{0}` {1}, higher in {2} of {3} boots' -f $state, $metric.Label, ($n - 1), $n)) }
                if ($lower -eq $n - 1) { $nearExtreme.Add(('`{0}` {1}, lower in {2} of {3} boots' -f $state, $metric.Label, ($n - 1), $n)) }
            }
        }
        $extreme.Count | Should -Be 1
        $flatResultsReadme.Contains(('only the {0} stands out' -f $extreme[0])) | Should -BeTrue
        foreach ($cell in $nearExtreme) {
            $flatResultsReadme.Contains($cell) | Should -BeTrue -Because "bench/results/README.md should name the $($n - 1)-of-$n split '$cell'"
        }
    }

    It 'quotes the GPU busy share of the median frame and the CPU-bound check of every game run' {
        $game = @($runs | Where-Object Step -eq 'game' | ForEach-Object { $_.Result.frames })
        $shares = [decimal[]]@($game | ForEach-Object { [decimal]$_.gpuBusyP50Ms / [decimal]$_.p50Ms * 100 })
        $quote = 'the GPU was busy for {0} to {1}% of the median frame' -f (Format-Fixed ($shares | Measure-Object -Minimum).Minimum 0), (Format-Fixed ($shares | Measure-Object -Maximum).Maximum 0)
        $flatResultsReadme.Contains($quote) | Should -BeTrue -Because "bench/results/README.md should say '$quote'"
        if ($flatResultsReadme -match 'in every run the median of PresentMon') {
            @($game | Where-Object { [decimal]$_.cpuBusyP50Ms -ne [decimal]$_.p50Ms }) | Should -BeNullOrEmpty
        }
    }

    It 'quotes the EPP and soft park latency values of both overlays from their /qh captures' {
        foreach ($file in @('qh-overlay-max.txt', 'qh-overlay-min.txt')) {
            Get-QhAcValue $file 'PERFEPP1' | Should -Be (Get-QhAcValue $file 'PERFEPP') -Because "the README says both EPP values match in $file"
        }
        $latency = Get-QhAcValue 'qh-overlay-max.txt' 'SOFTPARKLATENCY'
        Get-QhAcValue 'qh-overlay-min.txt' 'SOFTPARKLATENCY' | Should -Be $latency
        Get-QhAcValue 'qh-balanced.txt' 'SOFTPARKLATENCY' | Should -Be $latency -Because 'the README calls it Balanced''s value'
        $quote = 'the Max Performance overlay sets both EPP values to {0} on AC, the Better Battery-life overlay to {1}, and both keep `SOFTPARKLATENCY` at {2} microseconds, Balanced''s value' -f (Get-QhAcValue 'qh-overlay-max.txt' 'PERFEPP'), (Get-QhAcValue 'qh-overlay-min.txt' 'PERFEPP'), $latency
        $flatResultsReadme.Contains($quote) | Should -BeTrue -Because "bench/results/README.md should say '$quote'"
    }

    It 'quotes the parked counts of the idle checks from parked-samples.json' {
        $samples = @(Get-Content -Path (Join-Path $checksDir 'parked-samples.json') -Raw | ConvertFrom-Json)
        $cpus = @($runs | ForEach-Object { $_.Result.parkedDuringRun.logicalCpus } | Where-Object { $_ } | Sort-Object -Unique)
        $cpus.Count | Should -Be 1
        $balanced = @($samples | Where-Object Plan -eq 'balanced' | ForEach-Object { [int]$_.Median } | Sort-Object)
        $high = @($samples | Where-Object Plan -eq 'high-performance' | ForEach-Object { [int]$_.Median } | Sort-Object -Unique)
        $high.Count | Should -Be 1 -Because 'the README gives one High performance count for every round'
        $quote = 'The median sample was {0} of {1} parked on High performance in every round and {2} to {3} of {1} on Balanced' -f $high[0], $cpus[0], $balanced[0], $balanced[-1]
        $flatResultsReadme.Contains($quote) | Should -BeTrue -Because "bench/results/README.md should say '$quote'"
        $mainQuotes = @([regex]::Matches($flatMainReadme, '\d+ to \d+ of \d+ threads parked at desktop idle') | ForEach-Object { $_.Value })
        $mainQuotes.Count | Should -BeGreaterThan 0
        foreach ($mainQuote in $mainQuotes) { $mainQuote | Should -Be ('{0} to {1} of {2} threads parked at desktop idle' -f $balanced[0], $balanced[-1], $cpus[0]) }
    }

    It 'quotes the script hash every result records and links the script at a commit, not HEAD' {
        $hashes = @($runs | ForEach-Object { $_.Result.metadata.benchScript.sha256 } | Sort-Object -Unique)
        $hashes.Count | Should -Be 1 -Because 'every result of the series ran the same parking-bench.ps1'
        $resultsReadme.Contains($hashes[0]) | Should -BeTrue -Because 'bench/results/README.md should quote the script hash the results record'
        $resultsReadme | Should -Match 'blob/[0-9a-f]{7,40}/bench/parking-bench\.ps1'
        $resultsReadme.Contains('](../parking-bench.ps1)') | Should -BeFalse -Because 'a relative link shows HEAD, not the script that produced the results'
    }

    It 'links the commit whose parking-bench.ps1 hashes to the script hash every result records' {
        $commits = @([regex]::Matches($resultsReadme, 'blob/([0-9a-f]{7,40})/bench/parking-bench\.ps1') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
        $commits.Count | Should -Be 1
        $recorded = @($runs | ForEach-Object { $_.Result.metadata.benchScript.sha256 } | Sort-Object -Unique)
        $recorded.Count | Should -Be 1
        $bytes = Get-GitShowBytes ('{0}:bench/parking-bench.ps1' -f $commits[0])
        [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant() | Should -Be $recorded[0]
    }

    It 'names the workshop map by the title in loads/cs2.json' {
        $cs2 = Get-Content -Path (Join-Path $PSScriptRoot '..\loads\cs2.json') -Raw | ConvertFrom-Json
        $cs2.workshop.title | Should -Not -BeNullOrEmpty
        $resultsReadme.Contains(('Workshop map {0} ({1})' -f $cs2.workshop.id, $cs2.workshop.title)) | Should -BeTrue
    }

    It 'names every setting the <_> overlay carries in its /qh capture' -ForEach @('max', 'min') {
        $capture = Get-Content -Path (Join-Path $checksDir "qh-overlay-$_.txt") -Raw
        $aliases = @([regex]::Matches($capture, '(?m)^\s*Power Setting GUID:[^\r\n]*\r?\n\s*GUID Alias: (\S+)') | ForEach-Object { $_.Groups[1].Value })
        $aliases.Count | Should -BeGreaterThan 0
        $checks = [regex]::Match($resultsReadme, '(?ms)^## Testbed checks\r?\n(.*?)(?=^## |\z)').Groups[1].Value
        $checks.Contains("``qh-overlay-$_.txt``") | Should -BeTrue
        foreach ($alias in $aliases) {
            $checks.Contains("``$alias``") | Should -BeTrue -Because "qh-overlay-$_.txt carries $alias"
        }
        if ($checks -match 'never a parking minimum') {
            @($aliases -match '^CPM(IN|AX)CORES') | Should -BeNullOrEmpty
        }
    }

    It 'names every result file a retried boot overwrote in the README caveats' {
        $overwritten = @(foreach ($boot in $journal | Where-Object event -eq 'boot') {
            foreach ($state in @($boot.states | Where-Object { $_.status -eq 'ok' -and $_.result })) {
                $captured = [datetime](Get-Content -Path (Join-Path $seriesDir $state.result) -Raw | ConvertFrom-Json).capturedAt
                if ($captured -lt [datetime]$boot.startedAt -or $captured -gt [datetime]$boot.endedAt) { $state.result }
            }
        })
        if (@($journal | Where-Object { $_.event -eq 'boot' -and $_.outcome -eq 'failure' -and @($_.states | Where-Object status -eq 'ok').Count }).Count) {
            $overwritten | Should -Not -BeNullOrEmpty -Because 'a failed attempt finished runs that its rerun wrote again under the same names'
        }
        $caveats = [regex]::Match($resultsReadme, '(?ms)^## Caveats\r?\n(.*?)(?=^## |\z)').Groups[1].Value
        foreach ($file in $overwritten) {
            $caveats | Should -Match ([regex]::Escape($file)) -Because "the retry overwrote $file, so the README caveats must say so"
        }
    }

    It 'quotes the same-boot ceiling comparison: ceil beat ceil+min in every ceiling boot, by the published range' {
        $vsMin = @(Get-SameBootGap 'ceil' 'ceil+min' $anchorFpsGain)
        $vsEpp = @(Get-SameBootGap 'ceil' 'ceil+epp' $anchorFpsGain)
        @($vsMin | Where-Object { $_ -le 0 }) | Should -BeNullOrEmpty -Because 'the README says ceil beat ceil+min in every ceiling boot'
        $minRange = 'by {0}% to {1}%' -f (Format-Fixed ($vsMin | Measure-Object -Minimum).Minimum 2), (Format-Fixed ($vsMin | Measure-Object -Maximum).Maximum 2)
        $eppRange = 'from {0}% to {1}%' -f (Format-Fixed ($vsEpp | Measure-Object -Minimum).Minimum 2 -Signed), (Format-Fixed ($vsEpp | Measure-Object -Maximum).Maximum 2 -Signed)
        $resultsReadme.Contains($minRange) | Should -BeTrue -Because "bench/results/README.md should say '$minRange'"
        $resultsReadme.Contains($eppRange) | Should -BeTrue -Because "bench/results/README.md should say '$eppRange'"
    }

    It 'never says updaters were switched off, since Windows Update kept running in this series' {
        $resultsReadme | Should -Not -Match 'updaters? (were|was) (switched|turned) off|switched off[^.]{0,80}\bupdaters\b'
        $resultsReadme | Should -Match 'Windows Update'
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

    It 'quotes the bursts over the wake threshold of <State> in the Measured Impact table' -ForEach @(
        @{ Label = 'Stock'; State = 'stock' }
        @{ Label = 'After this script'; State = 'min+epp' }
        @{ Label = 'Parking forced'; State = 'ceil' }
    ) {
        $wakes = Get-StateLastWakes $State
        $mainReadme | Should -Match ('Bursts with a wait over {0} ms' -f $wakeOverMs)
        $row = [regex]::Match($mainReadme, ('(?m)^\| {0}[^\r\n]*' -f [regex]::Escape($Label)))
        $row.Success | Should -BeTrue
        $row.Value | Should -Match ('\| {0} of {1} \|\s*$' -f @($wakes | Where-Object { $_ -gt $wakeOverMs }).Count, $wakes.Count)
    }

    It 'quotes the script''s same-boot fps gap against stock as the paired median' {
        $gaps = [decimal[]]@(Get-SameBootGap 'stock' 'min+epp' $otherFpsGain)
        $median = Get-DecimalMedian $gaps
        $median | Should -BeLessThan 0
        $quotes = @([regex]::Matches($mainReadme, '(\d+\.\d+)% slower') | ForEach-Object { $_.Groups[1].Value })
        $quotes.Count | Should -BeGreaterThan 0
        foreach ($quote in $quotes) { $quote | Should -Be (Format-Fixed (-$median) 2) }
        $mainReadme | Should -Match ('slower in {0} of {1} boots' -f @($gaps | Where-Object { $_ -lt 0 }).Count, $gaps.Count)
        foreach ($count in @([regex]::Matches($flatMainReadme, 'median of (\d+) same-boot comparisons|(\d+) boots cannot tell') | ForEach-Object { "$($_.Groups[1].Value)$($_.Groups[2].Value)" })) {
            [int]$count | Should -Be $gaps.Count
        }
    }

    It 'bounds the script''s same-boot change of the <Label> by the quoted percent in every boot' -ForEach @(
        @{ Label = '1% low'; Field = 'low1PctMs' }
        @{ Label = '0.1% low'; Field = 'low01PctMs' }
    ) {
        $m = [regex]::Match($flatMainReadme, 'With the script''s settings, the 1% and 0\.1% lows stayed within (\d+(?:\.\d+)?)% of stock in every boot')
        $m.Success | Should -BeTrue
        $changes = [decimal[]]@(Get-SameBootGap 'stock' 'min+epp' { param($Anchor, $Other) [Math]::Abs(([decimal]$Other.$Field / [decimal]$Anchor.$Field - 1) * 100) }.GetNewClosure())
        $changes.Count | Should -BeGreaterThan 0
        ($changes | Measure-Object -Maximum).Maximum | Should -BeLessThan ([decimal]$m.Groups[1].Value)
    }

    It 'quotes the typical and slowest stock burst wake from the wake files' {
        $wakes = Get-StateLastWakes 'stock'
        $quote = 'woke about {0} ms late in a typical burst and up to {1} ms late' -f (Format-Fixed ([decimal](Get-Percentile ([double[]]$wakes) 0.50)) 0), (Format-Fixed $wakes[-1] 0)
        $flatMainReadme.Contains($quote) | Should -BeTrue -Because "README.md should say '$quote'"
    }

    It 'counts the runs behind the stock-versus-script fps comparison' {
        $n = (Get-StateFps 'stock').Count + (Get-StateFps 'min+epp').Count
        $m = [regex]::Match($mainReadme, 'after the script across (\d+) runs')
        if ($m.Success) { [int]$m.Groups[1].Value | Should -Be $n }
    }

    It 'quotes the forced-parking fps as the median of its runs rounded half away from zero' {
        $fps = Get-StateFps 'ceil'
        $cell = '| {0} [' -f (Format-Fixed (Get-DecimalMedian $fps) 1)
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
