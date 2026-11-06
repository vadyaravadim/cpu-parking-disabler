BeforeAll {
    . (Join-Path $PSScriptRoot '..\parking-bench.ps1') -Phase 'import-test'
    $script:loadFiles = @(Get-ChildItem -Path (Join-Path $PSScriptRoot '..\loads') -Filter '*.json' -File)
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

Describe 'Find-LogMarker' {
    It 'finds the marker only after the offset' {
        $text = "a`n[VProf] VProfLite started.`nb"
        Find-LogMarker -Text $text -Pattern '[VProf] VProfLite started.' | Should -Be 2
        Find-LogMarker -Text $text -Pattern '[VProf] VProfLite started.' -From 5 | Should -Be -1
    }
    It 'treats the pattern as plain text, not a regex' {
        Find-LogMarker -Text 'VProf VProfLite started' -Pattern '[VProf] VProfLite started.' | Should -Be -1
    }
    It 'returns -1 when the log is shorter than the offset' {
        Find-LogMarker -Text 'short' -Pattern 'x' -From 100 | Should -Be -1
    }
}

Describe 'Get-ExtraLaunchFlag' {
    It 'names flags outside the recipe and drops the exe and every value' {
        $cmd = '"D:\Games\cs2.exe" -steam -novid +con_enable 1 -vulkan -console -name "secret"'
        Get-ExtraLaunchFlag -CommandLine $cmd -Expected @('-novid', '+con_enable', '1', '-console') | Should -Be @('-steam', '-vulkan', '-name')
    }
    It 'returns nothing when the command line matches the recipe' {
        Get-ExtraLaunchFlag -CommandLine 'cs2.exe -novid' -Expected @('-novid') | Should -BeNullOrEmpty
    }
}

Describe 'load recipes for -Test game' {
    It 'loads <_.BaseName> and fits the capture inside a workshop route' -ForEach $loadFiles {
        { Get-LoadRecipe -Name $_.BaseName } | Should -Not -Throw
    }
    It 'gives <_.BaseName> a process name and a PresentMon process name' -ForEach $loadFiles {
        $r = Get-LoadRecipe -Name $_.BaseName
        $r.process | Should -Not -BeNullOrEmpty
        $r.presentMonProcess | Should -Be "$($r.process).exe"
    }
    It 'refuses an unknown load and lists the known ones' {
        { Get-LoadRecipe -Name 'nope' } | Should -Throw '*cs2*'
    }
    It 'drops the Steam -applaunch pair from the args the game process sees' {
        $r = Get-LoadRecipe -Name 'cs2'
        $procArgs = Get-RecipeProcessArg -Recipe $r
        $procArgs | Should -Not -Contain '-applaunch'
        $procArgs | Should -Contain '-condebug'
    }
    It 'keeps every arg for a program started directly' {
        $r = Get-LoadRecipe -Name 'superposition'
        (Get-RecipeProcessArg -Recipe $r).Count | Should -Be @($r.launchArgs).Count
    }
}

Describe 'Get-VideoConfigMismatch' {
    BeforeAll {
        $script:shipped = Join-Path $TestDrive 'shipped.txt'
        Set-Content -Path $shipped -Value @('"video.cfg"', '{', "`t`"Version`"`t`t`"16`"", "`t`"VendorID`"`t`t`"4098`"", "`t`"setting.defaultres`"`t`t`"1280`"", "`t`"setting.mat_vsync`"`t`t`"0`"", '}')
    }
    It 'ignores machine keys outside the prefix and accepts equal settings' {
        $mine = Join-Path $TestDrive 'mine-ok.txt'
        Set-Content -Path $mine -Value @('"video.cfg"', '{', "`t`"VendorID`"`t`t`"4318`"", "`t`"setting.defaultres`"`t`t`"1280`"", "`t`"setting.mat_vsync`"`t`t`"0`"", "`t`"setting.extra`"`t`t`"1`"", '}')
        Get-VideoConfigMismatch -Expected $shipped -Installed $mine -KeyPrefix 'setting.' | Should -BeNullOrEmpty
    }
    It 'names each setting that differs or is missing' {
        $mine = Join-Path $TestDrive 'mine-bad.txt'
        Set-Content -Path $mine -Value @('"video.cfg"', '{', "`t`"setting.defaultres`"`t`t`"640`"", '}')
        Get-VideoConfigMismatch -Expected $shipped -Installed $mine -KeyPrefix 'setting.' | Should -Be @('setting.defaultres', 'setting.mat_vsync')
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

Describe 'Get-GameRejection' {
    BeforeAll {
        $script:recipe = [pscustomobject]@{ videoConfig = [pscustomobject]@{ file = 'video.txt' } }
        $script:okStats = [pscustomobject]@{ capped = $false; cappedReason = '' }
    }
    It 'accepts a run with no capped frames and no lost frames' {
        Get-GameRejection -Stats $okStats -Capture ([pscustomobject]@{ overflowedPresents = 0 }) -Video $null -Recipe $recipe | Should -BeNullOrEmpty
    }
    It 'rejects a run that lost frames to a present event buffer overflow' {
        $reason = Get-GameRejection -Stats $okStats -Capture ([pscustomobject]@{ overflowedPresents = 130 }) -Video $null -Recipe $recipe
        $reason | Should -Be 'PresentMon lost 130 frames (present event buffer overflow)'
    }
    It 'still rejects a capped run and joins several reasons' {
        $capped = [pscustomobject]@{ capped = $true; cappedReason = 'vsync' }
        $reason = Get-GameRejection -Stats $capped -Capture ([pscustomobject]@{ overflowedPresents = 2 }) -Video $null -Recipe $recipe
        $reason | Should -Match 'vsync'
        $reason | Should -Match 'lost 2 frames'
    }
}
