BeforeAll {
    $script:tool = Join-Path $PSScriptRoot '..\tools\Get-ParkingSeriesTable.ps1'
    . $script:tool -SeriesPath 'unit-test'

    $script:mainLabels = @($seriesDesigns['parking-retest-2'].units)
    $script:ceilingLabels = @($seriesDesigns['parking-retest-2-ceiling'].units)

    function New-TestStep {
        param([int]$Boot, [string]$Label, [string]$Step, [System.Collections.IDictionary]$Value, $Excluded)
        $bench = if ($Step -eq 'burst') {
            [pscustomobject]@{
                burst             = [pscustomobject]@{ lastWorkerWakeMs = [pscustomobject]@{ median = $Value.lastWorkerWakeMs } }
                parkedBeforeBurst = [pscustomobject]@{ parked = [pscustomobject]@{ median = $Value.parked } }
            }
        }
        else {
            [pscustomobject]@{
                frames          = [pscustomobject]@{ avgFps = $Value.avgFps; low1PctMs = $Value.low1PctMs; low01PctMs = $Value.low01PctMs }
                parkedDuringRun = [pscustomobject]@{ parked = [pscustomobject]@{ median = $Value.parked } }
            }
        }
        [pscustomobject]@{ Boot = $Boot; Label = $Label; Step = $Step; Bench = $bench; Excluded = $Excluded }
    }

    function New-TestSeries {
        param([string[]]$Labels, [int]$Boots, [scriptblock]$Set = {})
        foreach ($boot in 0..($Boots - 1)) {
            foreach ($label in $Labels) {
                foreach ($step in $units[$label].steps) {
                    $ctx = @{ Boot = $boot; Label = $label; Step = $step; Value = @{ lastWorkerWakeMs = 10; avgFps = 100; low1PctMs = 5; low01PctMs = 8; parked = 4 }; Excluded = $null }
                    & $Set $ctx
                    New-TestStep -Boot $boot -Label $label -Step $step -Value $ctx.Value -Excluded $ctx.Excluded
                }
            }
        }
    }

    function Invoke-TestAnalysis {
        param([string[]]$Labels, [int]$Boots, [scriptblock]$Set = {})
        Get-PairedAnalysis -Labels $Labels -Steps @(New-TestSeries -Labels $Labels -Boots $Boots -Set $Set)
    }

    function Get-Row {
        param($Analysis, [string]$Comparison, [string]$Metric)
        @(@($Analysis.tests) + @($Analysis.described)) | Where-Object { $_.comparison -eq $Comparison -and $_.metric -eq $Metric }
    }

    function Get-BruteMidRank {
        param([decimal[]]$Values)
        $sorted = [decimal[]]$Values.Clone()
        [Array]::Sort($sorted)
        foreach ($value in $Values) { [Array]::IndexOf($sorted, $value) + [Array]::LastIndexOf($sorted, $value) + 2 }
    }

    function Get-BruteSubsetCount {
        param([int[]]$Ranks)
        $total = 0
        foreach ($rank in $Ranks) { $total += $rank }
        $count = New-Object 'decimal[]' ($total + 1)
        for ($mask = 0; $mask -lt [int][math]::Pow(2, $Ranks.Count); $mask++) {
            $sum = 0
            for ($i = 0; $i -lt $Ranks.Count; $i++) { if ($mask -band (1 -shl $i)) { $sum += $Ranks[$i] } }
            $count[$sum]++
        }
        , $count
    }

    function Get-BruteSignedRank {
        param([decimal[]]$Differences)
        $nonzero = [decimal[]]@($Differences | Where-Object { $_ -ne 0 })
        $ranks = [int[]]@()
        if ($nonzero.Count) { $ranks = [int[]]@(Get-BruteMidRank -Values ([decimal[]]@($nonzero | ForEach-Object { [math]::Abs($_) }))) }
        $total = 0
        $observed = 0
        for ($i = 0; $i -lt $ranks.Count; $i++) {
            $total += $ranks[$i]
            if ($nonzero[$i] -gt 0) { $observed += $ranks[$i] }
        }
        $distance = [math]::Abs(2 * $observed - $total)
        $patterns = [int][math]::Pow(2, $ranks.Count)
        $extreme = 0
        for ($mask = 0; $mask -lt $patterns; $mask++) {
            $sum = 0
            for ($i = 0; $i -lt $ranks.Count; $i++) { if ($mask -band (1 -shl $i)) { $sum += $ranks[$i] } }
            if ([math]::Abs(2 * $sum - $total) -ge $distance) { $extreme++ }
        }
        [pscustomobject]@{ extreme = $extreme; permutations = $patterns }
    }

    function Get-BruteInterval {
        param([decimal[]]$Differences, [decimal]$Confidence)
        $size = $Differences.Count
        $walsh = [decimal[]]@(for ($i = 0; $i -lt $size; $i++) { for ($j = $i; $j -lt $size; $j++) { ($Differences[$i] + $Differences[$j]) / 2 } })
        [Array]::Sort($walsh)
        $noTies = Get-BruteSubsetCount -Ranks ([int[]]@(1..$size))
        $patterns = [decimal][math]::Pow(2, $size)
        $cumulative = 0d
        $below = 0d
        $k = 0
        foreach ($count in $noTies) {
            $cumulative += $count
            if ($cumulative * 2 -gt (1 - $Confidence) * $patterns) { break }
            $below = $cumulative
            $k++
        }
        $middle = [int][math]::Floor($walsh.Count / 2)
        [pscustomobject]@{
            shift        = $(if ($walsh.Count % 2) { $walsh[$middle] } else { ($walsh[$middle - 1] + $walsh[$middle]) / 2 })
            k            = $k
            ciLow        = $(if ($k) { $walsh[$k - 1] })
            ciHigh       = $(if ($k) { $walsh[$walsh.Count - $k] })
            ciConfidence = $(if ($k) { 1 - 2 * $below / $patterns })
        }
    }
}

Describe 'the paired signed-rank test' {
    It 'counts the subsets of the doubled ranks 2, 4, 6 as 1, 1, 1, 2, 1, 1, 1 and agrees with every sign pattern' {
        $count = Get-SignedRankCount -Ranks 2, 4, 6
        $count.Count | Should -Be 13
        @(0, 2, 4, 6, 8, 10, 12 | ForEach-Object { $count[$_] }) | Should -Be @(1, 1, 1, 2, 1, 1, 1)
        @(1, 3, 5, 7, 9, 11 | ForEach-Object { $count[$_] }) | Should -Be @(0, 0, 0, 0, 0, 0)
        foreach ($ranks in @([int[]]@(2, 4, 6), [int[]]@(1..10), [int[]]@(3, 3, 7, 7, 10), [int[]]@(2, 5, 5, 8, 9, 9, 9, 14, 17, 20))) {
            $dp = Get-SignedRankCount -Ranks $ranks
            $brute = Get-BruteSubsetCount -Ranks $ranks
            ($dp -join ',') | Should -Be ($brute -join ',') -Because ($ranks -join ',')
        }
    }
    It 'gives 2 of 64 for six boots all one way and 2 of 262144 for eighteen, in either direction' {
        $up = Get-SignedRankTest -Differences ([decimal[]]@(1..6))
        $up.extreme | Should -Be 2
        $up.permutations | Should -Be 64
        $up.direction | Should -Be 1
        $brute = Get-BruteSignedRank -Differences ([decimal[]]@(1..6))
        $brute.extreme | Should -Be 2
        $brute.permutations | Should -Be 64
        $down = Get-SignedRankTest -Differences ([decimal[]]@(1..6 | ForEach-Object { -$_ }))
        $down.extreme | Should -Be 2
        $down.direction | Should -Be -1
        $long = Get-SignedRankTest -Differences ([decimal[]]@(1..18))
        $long.extreme | Should -Be 2
        $long.permutations | Should -Be 262144
    }
    It 'leaves the zero differences out of the test and counts them level' {
        $test = Get-SignedRankTest -Differences ([decimal[]]@(0, 0, 1, 2, 3))
        $test.n | Should -Be 3
        $test.level | Should -Be 2
        $test.extreme | Should -Be 2
        $test.permutations | Should -Be 8
        $brute = Get-BruteSignedRank -Differences ([decimal[]]@(0, 0, 1, 2, 3))
        $test.extreme | Should -Be $brute.extreme
        $test.permutations | Should -Be $brute.permutations
    }
    It 'gives tied absolute differences their mid-rank: 1, -1, 2, 2, 3 is 6 of 32 and 1, -1, 1, 2 is 8 of 16' {
        $differences = [decimal[]]@(1, -1, 2, 2, 3)
        $test = Get-SignedRankTest -Differences $differences
        $test.extreme | Should -Be 6
        $test.permutations | Should -Be 32
        $brute = Get-BruteSignedRank -Differences $differences
        $brute.extreme | Should -Be 6
        $brute.permutations | Should -Be 32
        $threeTied = [decimal[]]@(1, -1, 1, 2)
        $tiedTest = Get-SignedRankTest -Differences $threeTied
        $tiedTest.extreme | Should -Be 8
        $tiedTest.permutations | Should -Be 16
        (Get-BruteSignedRank -Differences $threeTied).extreme | Should -Be 8
    }
}

Describe 'the paired shift estimate' {
    It 'gives the six-boot shift 3.5 with the interval [2, 5] at 0.90625, as every sign pattern does' {
        $differences = [decimal[]]@(1..6)
        $shift = Get-PairedShiftEstimate -Differences $differences
        $shift.shift | Should -Be 3.5
        $shift.ciLow | Should -Be 2
        $shift.ciHigh | Should -Be 5
        $shift.ciConfidence | Should -Be 0.90625
        $brute = Get-BruteInterval -Differences $differences -Confidence $confidence
        $brute.k | Should -Be 3
        $shift.shift | Should -Be $brute.shift
        $shift.ciLow | Should -Be $brute.ciLow
        $shift.ciHigh | Should -Be $brute.ciHigh
        $shift.ciConfidence | Should -Be $brute.ciConfidence
        $tied = [decimal[]]@(0, 2, -1, 2, 5, 3, 0, 1)
        $tiedShift = Get-PairedShiftEstimate -Differences $tied
        $tiedBrute = Get-BruteInterval -Differences $tied -Confidence $confidence
        $tiedShift.shift | Should -Be $tiedBrute.shift
        $tiedShift.ciLow | Should -Be $tiedBrute.ciLow
        $tiedShift.ciHigh | Should -Be $tiedBrute.ciHigh
        $tiedShift.ciConfidence | Should -Be $tiedBrute.ciConfidence
    }
    It 'takes k = 48 of the 171 Walsh averages for eighteen boots, at 0.9013' {
        $differences = [decimal[]]@(1..18 | ForEach-Object { [decimal][math]::Pow(2, $_) })
        $walsh = [decimal[]]@(for ($i = 0; $i -lt 18; $i++) { for ($j = $i; $j -lt 18; $j++) { ($differences[$i] + $differences[$j]) / 2 } })
        [Array]::Sort($walsh)
        $walsh.Count | Should -Be 171
        @($walsh | Select-Object -Unique).Count | Should -Be 171
        $shift = Get-PairedShiftEstimate -Differences $differences
        $shift.shift | Should -Be $walsh[85]
        $shift.ciLow | Should -Be $walsh[47]
        $shift.ciHigh | Should -Be $walsh[123]
        $shift.ciConfidence | Should -Be 0.9012603759765625d
        [math]::Round($shift.ciConfidence, 4) | Should -Be 0.9013d
    }
    It 'gives no interval for four boots and one for five' {
        $four = Get-PairedShiftEstimate -Differences ([decimal[]]@(1..4))
        $four.shift | Should -Be 2.5
        $four.ciLow | Should -BeNullOrEmpty
        $four.ciHigh | Should -BeNullOrEmpty
        $four.ciConfidence | Should -BeNullOrEmpty
        (Get-BruteInterval -Differences ([decimal[]]@(1..4)) -Confidence $confidence).k | Should -Be 0
        $five = Get-PairedShiftEstimate -Differences ([decimal[]]@(1..5))
        $five.ciLow | Should -Be 1
        $five.ciHigh | Should -Be 5
        $five.ciConfidence | Should -Be 0.9375
    }
}

Describe 'the paired analysis' {
    It 'reads a higher average FPS as helped and a higher 1% low as hurt' {
        $analysis = Invoke-TestAnalysis -Labels $mainLabels -Boots 18 -Set {
            param($ctx)
            if ($ctx.Label -eq 'min') { $ctx.Value.avgFps = 105; $ctx.Value.low1PctMs = 5.5 }
            if ($ctx.Label -eq 'epp') { $ctx.Value.avgFps = 95 }
        }
        (Get-Row $analysis 'min vs stock' 'avgFps').verdict | Should -Be 'helped'
        (Get-Row $analysis 'min vs stock' 'low1PctMs').verdict | Should -Be 'hurt'
        (Get-Row $analysis 'epp vs stock' 'avgFps').verdict | Should -Be 'hurt'
        (Get-Row $analysis 'epp vs stock' 'low1PctMs').verdict | Should -Be 'no difference'
    }
    It 'takes the interaction as (epp - stock) - (gm-off-epp - gm-off-stock) within each boot' {
        $analysis = Invoke-TestAnalysis -Labels $mainLabels -Boots 6 -Set {
            param($ctx)
            $base = 100 + $ctx.Boot
            $ctx.Value.avgFps = switch ($ctx.Label) { 'epp' { $base + 2 } 'gm-off-epp' { $base + 1 } default { $base } }
        }
        $row = Get-Row $analysis '(epp - stock) - (gm-off-epp - gm-off-stock)' 'avgFps'
        $row.differences | Should -Be @(1, 1, 1, 1, 1, 1)
        $row.referenceValues | Should -Be @(100, 101, 102, 103, 104, 105)
        $row.stateValues | Should -Be @(102, 103, 104, 105, 106, 107)
        $row.referenceMedian | Should -Be 102.5
        $row.mixed | Should -BeFalse
    }
    It 'runs one family of the 21 main rows in the pre-registered order and one of the single ceiling row' {
        $main = Invoke-TestAnalysis -Labels $mainLabels -Boots 2
        @($main.family.Keys) | Should -Be @('main')
        $main.family['main'] | Should -Be 21
        @($main.tests | ForEach-Object { '{0} | {1}' -f $_.comparison, $_.metric }) | Should -Be @(
            'min vs stock | lastWorkerWakeMs'
            'epp vs stock | lastWorkerWakeMs'
            'min-epp vs stock | lastWorkerWakeMs'
            'min vs stock | avgFps'
            'min vs stock | low1PctMs'
            'epp vs stock | avgFps'
            'epp vs stock | low1PctMs'
            'min-epp vs stock | avgFps'
            'min-epp vs stock | low1PctMs'
            'gm-off-stock vs stock | avgFps'
            'gm-off-stock vs stock | low1PctMs'
            'gm-off-epp vs gm-off-stock | avgFps'
            'gm-off-epp vs gm-off-stock | low1PctMs'
            '(epp - stock) - (gm-off-epp - gm-off-stock) | avgFps'
            '(epp - stock) - (gm-off-epp - gm-off-stock) | low1PctMs'
            'cap-min vs cap-stock | low01PctMs'
            'cap-min vs cap-stock | low1PctMs'
            'cap-min-epp vs cap-min | low01PctMs'
            'cap-min-epp vs cap-min | low1PctMs'
            'cap-min-epp vs cap-stock | low01PctMs'
            'cap-min-epp vs cap-stock | low1PctMs'
        )
        @($main.tests | Where-Object { $_.mixed } | ForEach-Object { $_.comparison } | Select-Object -Unique) | Should -Be @('min-epp vs stock', 'cap-min-epp vs cap-stock')
        $ceiling = Invoke-TestAnalysis -Labels $ceilingLabels -Boots 2
        @($ceiling.family.Keys) | Should -Be @('ceiling')
        $ceiling.family['ceiling'] | Should -Be 1
        @($ceiling.tests | ForEach-Object { '{0} | {1}' -f $_.comparison, $_.metric }) | Should -Be @('maxcores25-min vs maxcores25 | lastWorkerWakeMs')
    }
    It 'reads cannot show from the parked count of the reference state, not of the changed one' {
        $zeroStock = Invoke-TestAnalysis -Labels $mainLabels -Boots 2 -Set { param($ctx) if ($ctx.Label -eq 'stock') { $ctx.Value.parked = 0 } }
        foreach ($comparison in 'min vs stock', 'min-epp vs stock') {
            foreach ($metric in 'lastWorkerWakeMs', 'avgFps', 'low1PctMs') {
                $row = Get-Row $zeroStock $comparison $metric
                $row.cannotShow | Should -BeTrue -Because "$comparison $metric"
                $row.verdict | Should -Be 'cannot show' -Because "$comparison $metric"
            }
        }
        (Get-Row $zeroStock 'epp vs stock' 'lastWorkerWakeMs').cannotShow | Should -BeFalse
        (Get-Row $zeroStock 'cap-min vs cap-stock' 'low01PctMs').cannotShow | Should -BeFalse
        $zeroMin = Invoke-TestAnalysis -Labels $mainLabels -Boots 2 -Set { param($ctx) if ($ctx.Label -eq 'min') { $ctx.Value.parked = 0 } }
        (Get-Row $zeroMin 'min vs stock' 'lastWorkerWakeMs').cannotShow | Should -BeFalse
        (Get-Row $zeroMin 'min vs stock' 'lastWorkerWakeMs').verdict | Should -Be 'cannot tell'
    }
    It 'takes the margin as a share of the reference median and needs the interval strictly inside it' {
        $edge = @(1, 1, 1, -1, 0.5, -0.5)
        $analysis = Invoke-TestAnalysis -Labels $ceilingLabels -Boots 6 -Set { param($ctx) if ($ctx.Label -eq 'maxcores25-min') { $ctx.Value.lastWorkerWakeMs = 10 + $edge[$ctx.Boot] } }.GetNewClosure()
        $row = Get-Row $analysis 'maxcores25-min vs maxcores25' 'lastWorkerWakeMs'
        $row.margin | Should -Be 1
        $row.ciLow | Should -Be -0.5
        $row.ciHigh | Should -Be 1
        $row.verdict | Should -Be 'cannot tell'
        $inside = @(0.99, 0.99, 0.99, -1, 0.5, -0.5)
        $analysis = Invoke-TestAnalysis -Labels $ceilingLabels -Boots 6 -Set { param($ctx) if ($ctx.Label -eq 'maxcores25-min') { $ctx.Value.lastWorkerWakeMs = 10 + $inside[$ctx.Boot] } }.GetNewClosure()
        (Get-Row $analysis 'maxcores25-min vs maxcores25' 'lastWorkerWakeMs').verdict | Should -Be 'no difference'
    }
    It 'reads cannot tell when every boot that differs lies on one side, even with the interval inside the margin' {
        $analysis = Invoke-TestAnalysis -Labels $ceilingLabels -Boots 6 -Set { param($ctx) if ($ctx.Label -eq 'maxcores25-min' -and $ctx.Boot -eq 5) { $ctx.Value.lastWorkerWakeMs = 10.01 } }
        $row = Get-Row $analysis 'maxcores25-min vs maxcores25' 'lastWorkerWakeMs'
        $row.lower | Should -Be 0
        $row.level | Should -Be 5
        $row.higher | Should -Be 1
        $row.ciLow | Should -Be 0
        $row.ciHigh | Should -Be 0.005
        $row.margin | Should -Be 1
        $row.verdict | Should -Be 'cannot tell'
        $below = Invoke-TestAnalysis -Labels $ceilingLabels -Boots 6 -Set { param($ctx) if ($ctx.Label -eq 'maxcores25-min' -and $ctx.Boot -eq 5) { $ctx.Value.lastWorkerWakeMs = 9.99 } }
        $lowerRow = Get-Row $below 'maxcores25-min vs maxcores25' 'lastWorkerWakeMs'
        $lowerRow.lower | Should -Be 1
        $lowerRow.higher | Should -Be 0
        $lowerRow.ciLow | Should -Be -0.005
        $lowerRow.ciHigh | Should -Be 0
        $lowerRow.verdict | Should -Be 'cannot tell'
    }
    It 'keeps a tested row whose every boot is left out in its family, with p 1 and cannot tell' {
        $analysis = Invoke-TestAnalysis -Labels $mainLabels -Boots 3 -Set { param($ctx) if ($ctx.Label -eq 'stock' -and $ctx.Step -eq 'burst') { $ctx.Excluded = 'the power scheme changed' } }
        $analysis.family['main'] | Should -Be 21
        $row = Get-Row $analysis 'min vs stock' 'lastWorkerWakeMs'
        @($row.boots).Count | Should -Be 0
        $row.referenceMedian | Should -BeNullOrEmpty
        $row.stateMedian | Should -BeNullOrEmpty
        $row.shift | Should -BeNullOrEmpty
        $row.ciLow | Should -BeNullOrEmpty
        $row.margin | Should -BeNullOrEmpty
        $row.extreme | Should -Be 1
        $row.permutations | Should -Be 1
        $row.p | Should -Be 1
        $row.pHolm | Should -Be 1
        $row.verdict | Should -Be 'cannot tell'
        (Get-Row $analysis 'min vs stock' 'avgFps').boots | Should -Be @(0, 1, 2)
    }
    It 'leaves a step out only of the rows that use it and keeps all 18 boots in the game rows' {
        $analysis = Invoke-TestAnalysis -Labels $mainLabels -Boots 18 -Set { param($ctx) if ($ctx.Label -eq 'stock' -and $ctx.Step -eq 'burst' -and $ctx.Boot -eq 3) { $ctx.Excluded = 'the power scheme changed' } }
        $burst = Get-Row $analysis 'min vs stock' 'lastWorkerWakeMs'
        @($burst.boots).Count | Should -Be 17
        $burst.boots | Should -Not -Contain 3
        @((Get-Row $analysis 'min vs stock' 'avgFps').boots).Count | Should -Be 18
        @((Get-Row $analysis 'gm-off-stock vs stock' 'low1PctMs').boots).Count | Should -Be 18
    }
    It 'keeps the described rows out of the family and gives them no p and no verdict' {
        $analysis = Invoke-TestAnalysis -Labels $ceilingLabels -Boots 6 -Set { param($ctx) if ($ctx.Label -eq 'maxcores25-min' -and $ctx.Step -eq 'burst') { $ctx.Value.lastWorkerWakeMs = 11 } }
        $analysis.family['ceiling'] | Should -Be 1
        $tested = Get-Row $analysis 'maxcores25-min vs maxcores25' 'lastWorkerWakeMs'
        $tested.p | Should -Be 0.03125
        $tested.pHolm | Should -Be 0.03125
        $tested.verdict | Should -Be 'hurt'
        @($analysis.described | ForEach-Object { '{0} | {1}' -f $_.comparison, $_.metric }) | Should -Be @(
            'maxcores25-min vs maxcores25 | avgFps'
            'maxcores25-min vs maxcores25 | low1PctMs'
            'maxcores25-epp vs maxcores25 | lastWorkerWakeMs'
            'maxcores25-epp vs maxcores25 | avgFps'
            'maxcores25-epp vs maxcores25 | low1PctMs'
        )
        foreach ($row in $analysis.described) {
            $row.PSObject.Properties['p'] | Should -BeNullOrEmpty
            $row.PSObject.Properties['verdict'] | Should -BeNullOrEmpty
        }
    }
}
