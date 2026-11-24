BeforeAll {
    . (Join-Path $PSScriptRoot '..\tools\Get-ParkingSeriesTable.ps1') -SeriesPath 'unit-test'
    $script:rulesFile = (Get-Content -Path (Join-Path $PSScriptRoot '..\results\parking-retest-2.rules.md') -Raw) -replace "`r`n", "`n"
    $script:amendments = '## Amendments'
}

Describe 'bench/results/parking-retest-2.rules.md' {
    It 'holds the rules block of the table script without a change, between blank lines' {
        $block = (Format-RulesBlock) -join "`n"
        $rulesFile.Contains("`n`n$block`n`n") | Should -BeTrue -Because 'the rules file quotes Format-RulesBlock verbatim: change the script and this file together, and after the series only under Amendments'
    }
    It 'keeps Amendments as its last heading' {
        $headings = @([regex]::Matches($rulesFile, '(?m)^## .+$') | ForEach-Object { $_.Value })
        $headings[-1] | Should -Be $amendments
        @($headings | Where-Object { $_ -eq $amendments }).Count | Should -Be 1
    }
    It 'names both pre-registered series with their boot counts' {
        foreach ($name in $seriesDesigns.Keys) {
            $rulesFile.Contains(('| {0} | {1} | {2} |' -f $name, $seriesDesigns[$name].block, $seriesDesigns[$name].boots)) | Should -BeTrue
        }
    }
}
