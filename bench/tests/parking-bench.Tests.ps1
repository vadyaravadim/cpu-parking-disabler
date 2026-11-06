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
