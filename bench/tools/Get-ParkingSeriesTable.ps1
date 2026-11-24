[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SeriesPath,
    [string]$MarkdownPath,
    [string]$SummaryPath,
    [switch]$ChecksOnly
)

$ErrorActionPreference = 'Stop'
$confidence = 0.9d
$planScheme = '381b4222-f694-41f0-9685-ff5bb260df2e'
$stockSettings = [ordered]@{ CPMAXCORES = 100; CPMINCORES = 4; CPMINCORES1 = 0; PERFEPP = 33; PERFEPP1 = 33 }
$changeSettings = [ordered]@{
    min     = [ordered]@{ CPMINCORES = 100; CPMINCORES1 = 100 }
    epp     = [ordered]@{ PERFEPP = 0; PERFEPP1 = 0 }
    ceiling = [ordered]@{ CPMAXCORES = 25 }
}
$scriptChanges = @('min', 'epp')
$ceilingChange = 'ceiling'
$gameModeChange = 'gameMode'
$cannotShowSetting = 'CPMINCORES'
$burstStep = 'burst'
$gameStep = 'game'
$burstAndGame = @($burstStep, $gameStep)
$gameOnly = @($gameStep)
$capFpsMax = 144
$gameModeOn = 1
$units = [ordered]@{
    'stock'          = [ordered]@{ changes = @(); gameMode = 1; fpsMax = 0; steps = $burstAndGame }
    'min'            = [ordered]@{ changes = @('min'); gameMode = 1; fpsMax = 0; steps = $burstAndGame }
    'epp'            = [ordered]@{ changes = @('epp'); gameMode = 1; fpsMax = 0; steps = $burstAndGame }
    'min-epp'        = [ordered]@{ changes = @('min', 'epp'); gameMode = 1; fpsMax = 0; steps = $burstAndGame }
    'cap-stock'      = [ordered]@{ changes = @(); gameMode = 1; fpsMax = $capFpsMax; steps = $gameOnly }
    'cap-min'        = [ordered]@{ changes = @('min'); gameMode = 1; fpsMax = $capFpsMax; steps = $gameOnly }
    'cap-min-epp'    = [ordered]@{ changes = @('min', 'epp'); gameMode = 1; fpsMax = $capFpsMax; steps = $gameOnly }
    'gm-off-stock'   = [ordered]@{ changes = @(); gameMode = 0; fpsMax = 0; steps = $gameOnly }
    'gm-off-epp'     = [ordered]@{ changes = @('epp'); gameMode = 0; fpsMax = 0; steps = $gameOnly }
    'maxcores25'     = [ordered]@{ changes = @('ceiling'); gameMode = 1; fpsMax = 0; steps = $burstAndGame }
    'maxcores25-min' = [ordered]@{ changes = @('ceiling', 'min'); gameMode = 1; fpsMax = 0; steps = $burstAndGame }
    'maxcores25-epp' = [ordered]@{ changes = @('ceiling', 'epp'); gameMode = 1; fpsMax = 0; steps = $burstAndGame }
}
$seriesDesigns = [ordered]@{
    'parking-retest-2'         = [ordered]@{ block = 'main'; boots = 18; units = @('stock', 'min', 'epp', 'min-epp', 'cap-stock', 'cap-min', 'cap-min-epp', 'gm-off-stock', 'gm-off-epp') }
    'parking-retest-2-ceiling' = [ordered]@{ block = 'ceiling'; boots = 6; units = @('maxcores25', 'maxcores25-min', 'maxcores25-epp') }
}
$metrics = [ordered]@{
    lastWorkerWakeMs = [ordered]@{ step = $burstStep; field = 'burst.lastWorkerWakeMs.median'; better = 'lower'; label = 'Burst wake, median of the run (ms)' }
    avgFps           = [ordered]@{ step = $gameStep; field = 'frames.avgFps'; better = 'higher'; label = 'Average FPS' }
    low1PctMs        = [ordered]@{ step = $gameStep; field = 'frames.low1PctMs'; better = 'lower'; label = '1% low (ms)' }
    low01PctMs       = [ordered]@{ step = $gameStep; field = 'frames.low01PctMs'; better = 'lower'; label = '0.1% low (ms)' }
}
$directionSign = @{ lower = 1; higher = -1 }
$marginShare = [ordered]@{ lastWorkerWakeMs = 0.1d; avgFps = 0.01d; low1PctMs = 0.033d; low01PctMs = 0.033d }
$comparisons = @(
    [ordered]@{ block = 'main'; state = 'min'; reference = 'stock'; metrics = @('lastWorkerWakeMs'); tested = $true }
    [ordered]@{ block = 'main'; state = 'epp'; reference = 'stock'; metrics = @('lastWorkerWakeMs'); tested = $true }
    [ordered]@{ block = 'main'; state = 'min-epp'; reference = 'stock'; metrics = @('lastWorkerWakeMs'); tested = $true }
    [ordered]@{ block = 'main'; state = 'min'; reference = 'stock'; metrics = @('avgFps', 'low1PctMs'); tested = $true }
    [ordered]@{ block = 'main'; state = 'epp'; reference = 'stock'; metrics = @('avgFps', 'low1PctMs'); tested = $true }
    [ordered]@{ block = 'main'; state = 'min-epp'; reference = 'stock'; metrics = @('avgFps', 'low1PctMs'); tested = $true }
    [ordered]@{ block = 'main'; state = 'gm-off-stock'; reference = 'stock'; metrics = @('avgFps', 'low1PctMs'); tested = $true }
    [ordered]@{ block = 'main'; state = 'gm-off-epp'; reference = 'gm-off-stock'; metrics = @('avgFps', 'low1PctMs'); tested = $true }
    [ordered]@{ block = 'main'; state = 'epp'; reference = 'stock'; minusState = 'gm-off-epp'; minusReference = 'gm-off-stock'; metrics = @('avgFps', 'low1PctMs'); tested = $true }
    [ordered]@{ block = 'main'; state = 'cap-min'; reference = 'cap-stock'; metrics = @('low01PctMs', 'low1PctMs'); tested = $true }
    [ordered]@{ block = 'main'; state = 'cap-min-epp'; reference = 'cap-min'; metrics = @('low01PctMs', 'low1PctMs'); tested = $true }
    [ordered]@{ block = 'main'; state = 'cap-min-epp'; reference = 'cap-stock'; metrics = @('low01PctMs', 'low1PctMs'); tested = $true }
    [ordered]@{ block = 'ceiling'; state = 'maxcores25-min'; reference = 'maxcores25'; metrics = @('lastWorkerWakeMs'); tested = $true }
    [ordered]@{ block = 'ceiling'; state = 'maxcores25-min'; reference = 'maxcores25'; metrics = @('avgFps', 'low1PctMs'); tested = $false }
    [ordered]@{ block = 'ceiling'; state = 'maxcores25-epp'; reference = 'maxcores25'; metrics = @('lastWorkerWakeMs', 'avgFps', 'low1PctMs'); tested = $false }
)
$stepParked = [ordered]@{ burst = 'parkedBeforeBurst'; game = 'parkedDuringRun' }
$parkedMedianFormat = '{0}.parked.median'
$burstStateFields = [ordered]@{ lastWorkerWakeMs = 'burst.lastWorkerWakeMs.median'; earlyCoreMs = 'burst.earlyCoreMs.median'; totalCoreMs = 'burst.totalCoreMs.median' }
$uncappedStateFields = [ordered]@{ avgFps = 'frames.avgFps'; p50Ms = 'frames.p50Ms'; low1PctMs = 'frames.low1PctMs'; low01PctMs = 'frames.low01PctMs'; gpuBusyP50Ms = 'frames.gpuBusyP50Ms'; cpuBusyP50Ms = 'frames.cpuBusyP50Ms' }
$cappedStateFields = [ordered]@{ avgFps = 'frames.avgFps'; p50Ms = 'frames.p50Ms'; low01PctMs = 'frames.low01PctMs'; low1PctMs = 'frames.low1PctMs'; slowFrames = 'cap.slowFrames' }
$capPeriodField = 'cap.periodMs'
$overPeriodSuffix = 'OverPeriod'
$overPeriodKeys = @('low01PctMs', 'low1PctMs')
$requiredFingerprintFields = @('metadata.os.build', 'metadata.os.ubr', 'metadata.qpcFrequency', 'metadata.benchScript.sha256')
$optionalFingerprintFields = @('metadata.power.overlayAc', 'metadata.power.overlayDc')
$optionalEnvironmentFields = @('environment.hvciEnabled', 'environment.bios.version', 'environment.microcodeRaw', 'environment.clockFlags')
$driverFingerprintFields = @('environment.drivers.gpu', 'environment.drivers.audio')
$processorSettingsField = 'metadata.power.processorSettings'
$powerExplicitField = 'environment.powerExplicit'
$logicalCpusField = 'logicalCpus'
$burstFingerprintFields = @('threads', 'bursts', 'idleSeconds', 'burstMs', 'windowMs', 'chunkIterations', 'itersPerMs', 'burst.earlyWindowMs')
$gameFingerprintFields = @('metadata.presentMonVersion', 'presentMon.sha256', 'load.name', 'load.build', 'load.videoConfig', 'frames.refreshHz')
$presentModesField = 'frames.presentModes'
$gateFields = [ordered]@{
    series         = 'series'
    boot           = 'boot'
    stateIndex     = 'stateIndex'
    state          = 'state'
    resultFile     = 'bench.resultFile'
    capturedAt     = 'capturedAt'
    test           = 'test'
    phase          = 'phase'
    scheme         = 'metadata.power.schemeGuid'
    highQos        = 'highQos'
    adapters       = 'environment.enabledNetworkAdapters'
    autoGameMode   = 'autoGameModeEnabled'
    ppm            = 'ppm'
    cap            = 'cap'
    capFpsMax      = 'cap.fpsMax'
    rejected       = 'rejected'
    overflow       = 'presentMon.overflowedPresents'
}
$exclusionFields = [ordered]@{ powerStateChanged = 'powerStateChanged'; buffersLost = 'ppm.buffersLost'; captureChanges = 'ppm.captureChanges'; captureProfile = 'ppm.captureProfile' }
$wakeSuffix = '-wake.csv'
$wakeBurstColumn = 'burst'
$wakeColumn = 'wakeMs'
$wakeQuantile = 0.9
$phaseFormat = 'boot{0:00}-state{1:00}'
$benchFileFormat = 'parking-bench-{0}-{1}.json'
$timestampFormat = 's'
$noPublicReason = 'no public reason'
$noParkedReason = 'no parked-core reading'
$everyRowScope = 'every row and state table'
$noBootNote = 'no boot holds every step this row pairs'
$rowNameFormat = '{0}: {1}'
$ceilingLabel = '(forced: the ceiling)'
$mixedLabel = 'mixed effect: the script''s two changes'
$notPreRegistered = 'not a pre-registered series'
$percent = 100

. (Join-Path (Split-Path -Parent $PSScriptRoot) 'bench-env.ps1')
. (Join-Path $PSScriptRoot 'series-lib.ps1')

function ConvertTo-JournalTime {
    param([Parameter(Mandatory)]$Value)
    if ($Value -is [datetime]) { return $Value }
    [datetime]::ParseExact([string]$Value, $timestampFormat, $invariant)
}

function Get-UnitSetting {
    param([Parameter(Mandatory)][string]$Label)
    $settings = [ordered]@{}
    foreach ($name in $stockSettings.Keys) { $settings[$name] = $stockSettings[$name] }
    foreach ($change in $units[$Label].changes) { foreach ($name in $changeSettings[$change].Keys) { $settings[$name] = $changeSettings[$change][$name] } }
    $settings
}

function Format-StateLabel {
    param([Parameter(Mandatory)][string]$Label)
    if ($units[$Label].changes -contains $ceilingChange) { return "$Label $ceilingLabel" }
    $Label
}

function Get-ComparisonName {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Comparison, [switch]$Labelled)
    $names = @('state', 'reference', 'minusState', 'minusReference' | Where-Object { $Comparison.Contains($_) } | ForEach-Object { if ($Labelled) { Format-StateLabel $Comparison[$_] } else { $Comparison[$_] } })
    if ($names.Count -gt 2) { return '({0} - {1}) - ({2} - {3})' -f $names }
    '{0} vs {1}' -f $names
}

function Read-StepData {
    param([Parameter(Mandatory)][string]$SeriesPath, [Parameter(Mandatory)]$Accepted, [Parameter(Mandatory)][object[]]$Events)
    $where = 'boot {0} state {1}' -f $Accepted.Boot, $Accepted.StateIndex
    $wrapper = Read-Json -Path (Join-Path $SeriesPath $Accepted.WrapperFile) -Where "$where wrapper $($Accepted.WrapperFile)"
    $benchName = [string](Get-Field $wrapper $gateFields.resultFile $where)
    $bench = Read-Json -Path (Join-Path $SeriesPath $benchName) -Where "$where bench result $benchName"
    $step = [string](Get-Field $Accepted.PlanState 'step' "plan.json $where")
    $bootEvent = @($Events | Where-Object { [int]$_.index -eq $Accepted.Boot -and @(@($_.states) | Where-Object { [int]$_.index -eq $Accepted.StateIndex -and $_.result -eq $Accepted.WrapperFile }).Count })[0]
    $wakeName = $null
    $wakeMax = $null
    if ($step -eq $burstStep) {
        $wakeName = @(@(Get-Field $wrapper 'bench.files' $where) | Where-Object { ([string]$_).EndsWith($wakeSuffix) })[0]
        if (-not $wakeName) { throw "$where wrapper field bench.files lists no $wakeSuffix file" }
        $wakePath = Join-Path $SeriesPath $wakeName
        if (-not (Test-Path -LiteralPath $wakePath -PathType Leaf)) { throw "$where wake file is missing: $wakeName" }
        $lines = [System.IO.File]::ReadAllLines($wakePath)
        $header = ([string]($lines | Select-Object -First 1)).Split(',')
        $burstAt = [Array]::IndexOf($header, $wakeBurstColumn)
        $wakeAt = [Array]::IndexOf($header, $wakeColumn)
        if ($burstAt -lt 0) { throw "$where wake file $wakeName has no column $wakeBurstColumn" }
        if ($wakeAt -lt 0) { throw "$where wake file $wakeName has no column $wakeColumn" }
        $perBurst = New-Object 'System.Collections.Generic.SortedDictionary[int,decimal]'
        foreach ($line in @($lines | Select-Object -Skip 1 | Where-Object { $_ })) {
            $cells = $line.Split(',')
            $burst = [int]$cells[$burstAt]
            $value = [decimal]::Parse($cells[$wakeAt], [System.Globalization.NumberStyles]::Float, $invariant)
            if (-not $perBurst.ContainsKey($burst) -or $value -gt $perBurst[$burst]) { $perBurst[$burst] = $value }
        }
        if ($perBurst.Count -eq 0) { throw "$where wake file $wakeName has no burst row" }
        $wakeMax = [decimal[]]@($perBurst.Values)
    }
    [pscustomobject]@{
        Boot        = $Accepted.Boot
        StateIndex  = $Accepted.StateIndex
        Label       = [string](Get-Field $Accepted.PlanState 'label' "plan.json $where")
        Step        = $step
        PlanState   = $Accepted.PlanState
        Wrapper     = $wrapper
        WrapperFile = $Accepted.WrapperFile
        Bench       = $bench
        BenchFile   = $benchName
        WakeFile    = $wakeName
        WakeMax     = $wakeMax
        Event       = $bootEvent
        Excluded    = $null
    }
}

function Get-GameModeError {
    param([Parameter(Mandatory)][int]$GameMode, [AllowNull()]$Ppm, [Parameter(Mandatory)][int]$ProfileId)
    $prefix = "Game Mode $GameMode check failed:"
    if ($null -eq $Ppm) { return "$prefix the bench result has no ppm record" }
    if ($null -eq $Ppm.buffersLost -or $Ppm.buffersLost -ne 0) { return "$prefix ppm buffersLost is '$($Ppm.buffersLost)', expected 0" }
    if ($Ppm.captureChanges -ne 0) { return "$prefix the power profile changed $($Ppm.captureChanges) time(s) inside the capture window (ppm captureChanges)" }
    if ($GameMode -eq 1) {
        if ($null -eq $Ppm.captureProfile -or $Ppm.captureProfile -ne $ProfileId) { return "$prefix ppm captureProfile is '$($Ppm.captureProfile)', expected $ProfileId" }
        return
    }
    if ($Ppm.startedBeforeLoad -ne $true) { return "$prefix the trace did not start before the load (ppm startedBeforeLoad is '$($Ppm.startedBeforeLoad)')" }
    if (@(@($Ppm.profileChanges) | Where-Object { $_ -and $_.to -eq $ProfileId }).Count) { return "$prefix the power profile changed to $ProfileId (ppm profileChanges)" }
    if (@(@($Ppm.profileChanges) | Where-Object { $_ -and $_.from -eq $ProfileId -and $_.offsetSeconds -gt 0 }).Count) { return "$prefix the power profile left $ProfileId after the capture window started (ppm profileChanges)" }
}

function Assert-StepState {
    param([Parameter(Mandatory)]$Step, [Parameter(Mandatory)]$Plan)
    $where = 'boot {0} state {1} ({2} {3})' -f $Step.Boot, $Step.StateIndex, $Step.Label, $Step.Step
    $wrapper = $Step.Wrapper
    $bench = $Step.Bench
    $series = [string](Get-Field $wrapper $gateFields.series $where)
    if ($series -cne [string]$Plan.series) { throw "$where wrapper field $($gateFields.series) is '$series', plan.json says '$($Plan.series)'" }
    $boot = [int](Get-Field $wrapper $gateFields.boot $where)
    if ($boot -ne $Step.Boot) { throw "$where wrapper field $($gateFields.boot) is $boot, the journal says $($Step.Boot)" }
    $stateIndex = [int](Get-Field $wrapper $gateFields.stateIndex $where)
    if ($stateIndex -ne $Step.StateIndex) { throw "$where wrapper field $($gateFields.stateIndex) is $stateIndex, the journal says $($Step.StateIndex)" }
    $wrapperState = ConvertTo-FingerprintValue (Get-Field $wrapper $gateFields.state $where)
    $planState = ConvertTo-FingerprintValue $Step.PlanState
    if ($wrapperState -cne $planState) { throw "$where wrapper field $($gateFields.state) is '$wrapperState', plan.json says '$planState'" }
    $phase = $phaseFormat -f $Step.Boot, $Step.StateIndex
    $expectedFile = $benchFileFormat -f $phase, $Step.Step
    if ($Step.BenchFile -cne $expectedFile) { throw "$where wrapper field $($gateFields.resultFile) is '$($Step.BenchFile)', expected '$expectedFile'" }
    $test = [string](Get-Field $bench $gateFields.test $where)
    if ($test -cne $Step.Step) { throw "$where bench field $($gateFields.test) is '$test', the plan step is '$($Step.Step)'" }
    $benchPhase = [string](Get-Field $bench $gateFields.phase $where)
    if ($benchPhase -cne $phase) { throw "$where bench field $($gateFields.phase) is '$benchPhase', expected '$phase'" }

    if (-not $units.Contains($Step.Label)) { throw "$where plan state label '$($Step.Label)' is not a pre-registered unit: $(@($units.Keys) -join ', ')" }
    $unit = $units[$Step.Label]
    $settings = Get-UnitSetting -Label $Step.Label
    foreach ($name in $settings.Keys) {
        $planned = [int](Get-Field $Step.PlanState "settings.$name" "plan.json $where")
        if ($planned -ne $settings[$name]) { throw "$where plan state $name is $planned, the pre-registered unit $($Step.Label) sets $($settings[$name])" }
    }
    $gameMode = [int](Get-Field $Step.PlanState 'gameMode' "plan.json $where")
    if ($gameMode -ne $unit.gameMode) { throw "$where plan state gameMode is $gameMode, the pre-registered unit $($Step.Label) has $($unit.gameMode)" }
    $planFpsMax = Get-OptionalField $Step.PlanState 'fpsMax'
    $fpsMax = if ($null -eq $planFpsMax) { 0 } else { [int]$planFpsMax }
    if ($fpsMax -ne $unit.fpsMax) { throw "$where plan state fpsMax is $fpsMax, the pre-registered unit $($Step.Label) has $($unit.fpsMax)" }
    if ($unit.steps -notcontains $Step.Step) { throw "$where plan step '$($Step.Step)' is not a step of the pre-registered unit $($Step.Label): $($unit.steps -join ', ')" }
    $scheme = [string](Get-Field $Step.PlanState 'scheme' "plan.json $where")
    if ($scheme -cne $planScheme) { throw "$where plan state scheme is '$scheme', the pre-registered units run on '$planScheme'" }

    $captured = ConvertTo-JournalTime (Get-Field $wrapper $gateFields.capturedAt $where)
    $started = ConvertTo-JournalTime (Get-Field $Step.Event 'startedAt' "$where journal boot event")
    $ended = ConvertTo-JournalTime (Get-Field $Step.Event 'endedAt' "$where journal boot event")
    if ($captured -lt $started -or $captured -gt $ended) {
        throw ("$where wrapper field $($gateFields.capturedAt) {0} is outside its boot: the journal says {1} to {2}" -f $captured.ToString($timestampFormat, $invariant), $started.ToString($timestampFormat, $invariant), $ended.ToString($timestampFormat, $invariant))
    }

    $benchScheme = [string](Get-Field $bench $gateFields.scheme $where)
    if ($benchScheme -ne $scheme) { throw "$where bench field $($gateFields.scheme) is '$benchScheme', the state sets '$scheme'" }
    $processor = @(Get-Field $bench $processorSettingsField $where)
    foreach ($name in $settings.Keys) {
        $rows = @($processor | Where-Object { $_.alias -eq $name })
        if ($rows.Count -ne 1) { throw "$where bench field $processorSettingsField has $($rows.Count) rows with alias $name, expected 1" }
        if ([int]$rows[0].ac -ne $settings[$name] -or [int]$rows[0].dc -ne $settings[$name]) { throw "$where bench field $processorSettingsField $name is AC $($rows[0].ac) DC $($rows[0].dc), the state sets $($settings[$name])" }
    }
    $highQos = Get-Field $bench $gateFields.highQos $where
    if ($highQos -ne $true) { throw "$where bench field $($gateFields.highQos) is '$highQos': the bench did not opt out of power throttling" }
    $adapters = [int](Get-Field $wrapper $gateFields.adapters $where)
    if ($adapters -ne 0) { throw "$where wrapper field $($gateFields.adapters) is $adapters, the series runs with every physical adapter disabled" }

    if ($Step.Step -ne $gameStep) { return }
    $autoGameMode = [int](Get-Field $bench $gateFields.autoGameMode $where)
    if ($autoGameMode -ne $gameMode) { throw "$where bench field $($gateFields.autoGameMode) is $autoGameMode, the state sets Game Mode $gameMode" }
    $gameModeError = Get-GameModeError -GameMode $gameMode -Ppm (Get-OptionalField $bench $gateFields.ppm) -ProfileId ([int](Get-Field $Plan 'gameModeProfileId' 'plan.json'))
    if ($gameModeError) { throw "$where $gameModeError" }
    $cap = Get-OptionalField $bench $gateFields.cap
    if ($fpsMax -gt 0 -and $null -eq $cap) { throw "$where bench field $($gateFields.cap) is missing, the state caps at $fpsMax fps" }
    if ($fpsMax -gt 0 -and [int](Get-Field $bench $gateFields.capFpsMax $where) -ne $fpsMax) { throw "$where bench field $($gateFields.capFpsMax) is $($cap.fpsMax), the state caps at $fpsMax fps" }
    if ($fpsMax -eq 0 -and $null -ne $cap) { throw "$where bench field $($gateFields.cap) is set (fpsMax $($cap.fpsMax)), the state runs uncapped" }
    $rejected = Get-OptionalField $bench $gateFields.rejected
    if ($rejected) { throw "$where bench field $($gateFields.rejected) is not empty: $rejected" }
    $overflow = [int](Get-Field $bench $gateFields.overflow $where)
    if ($overflow -ne 0) { throw "$where bench field $($gateFields.overflow) is $overflow, expected 0" }
}

function Get-StepStateField {
    param([Parameter(Mandatory)]$Step)
    if ($Step.Step -eq $burstStep) { return $burstStateFields }
    if ($units[$Step.Label].fpsMax -gt 0) { return $cappedStateFields }
    $uncappedStateFields
}

function Assert-StepField {
    param([Parameter(Mandatory)]$Step)
    $where = 'boot {0} state {1} ({2} {3})' -f $Step.Boot, $Step.StateIndex, $Step.Label, $Step.Step
    $fields = @($metrics.Values | Where-Object { $_.step -eq $Step.Step } | ForEach-Object { $_.field }) + @((Get-StepStateField -Step $Step).Values)
    if ($units[$Step.Label].fpsMax -gt 0) { $fields += $capPeriodField }
    foreach ($field in @($fields | Select-Object -Unique)) { $null = ConvertTo-WrittenDecimal (Get-Field $Step.Bench $field $where) }
}

function Get-StepFingerprint {
    param([Parameter(Mandatory)]$Step)
    $where = 'boot {0} state {1}' -f $Step.Boot, $Step.StateIndex
    $bench = $Step.Bench
    $processor = @(Get-Field $bench $processorSettingsField $where)
    $planned = @($processor | Where-Object { $stockSettings.Contains([string]$_.alias) } | ForEach-Object { [string]$_.guid })
    $explicit = @(@(Get-Field $Step.Wrapper $powerExplicitField $where) | Where-Object { $planned -notcontains ([string]$_).Split(':')[0].Split('\')[-1] })
    $fingerprint = [ordered]@{}
    foreach ($field in $requiredFingerprintFields) { $fingerprint[$field] = [string](Get-Field $bench $field $where) }
    $fingerprint[$processorSettingsField] = (@($processor | Where-Object { -not $stockSettings.Contains([string]$_.alias) } | ForEach-Object { '{0}:{1}:{2}' -f $_.guid, $_.ac, $_.dc } | Sort-Object) -join ';')
    $fingerprint[$powerExplicitField] = (@($explicit | ForEach-Object { [string]$_ } | Sort-Object) -join ';')
    foreach ($field in $driverFingerprintFields) { $fingerprint[$field] = Get-DriverFingerprint (Get-Field $Step.Wrapper $field $where) }
    $fingerprint[$logicalCpusField] = [string](Get-Field $bench "$($stepParked[$Step.Step]).$logicalCpusField" $where)
    foreach ($field in $optionalFingerprintFields) { $fingerprint[$field] = ConvertTo-FingerprintValue (Get-OptionalField $bench $field) }
    foreach ($field in $optionalEnvironmentFields) { $fingerprint[$field] = ConvertTo-FingerprintValue (Get-OptionalField $Step.Wrapper $field) }
    if ($Step.Step -eq $burstStep) {
        foreach ($field in $burstFingerprintFields) { $fingerprint[$field] = [string](Get-Field $bench $field $where) }
        return $fingerprint
    }
    foreach ($field in $gameFingerprintFields) { $fingerprint[$field] = ConvertTo-FingerprintValue (Get-Field $bench $field $where) }
    $fingerprint[$presentModesField] = (@(Get-Field $bench $presentModesField $where) | Sort-Object) -join ';'
    $fingerprint
}

function Get-StepExclusion {
    param([Parameter(Mandatory)]$Step, [Parameter(Mandatory)][int]$ProfileId)
    $where = 'boot {0} state {1}' -f $Step.Boot, $Step.StateIndex
    $reasons = New-Object System.Collections.Generic.List[string]
    if ((Get-Field $Step.Bench $exclusionFields.powerStateChanged $where) -eq $true) { $reasons.Add('the power scheme or a processor setting changed during the run (powerStateChanged)') }
    if ($Step.Step -eq $burstStep) {
        $null = Get-Field $Step.Bench $gateFields.ppm $where
        $buffersLost = Get-OptionalField $Step.Bench $exclusionFields.buffersLost
        $captureChanges = Get-OptionalField $Step.Bench $exclusionFields.captureChanges
        $captureProfile = Get-OptionalField $Step.Bench $exclusionFields.captureProfile
        if ($null -eq $buffersLost -or $buffersLost -ne 0) { $reasons.Add("ppm buffersLost is '$buffersLost', expected 0") }
        if ($captureChanges -ne 0) { $reasons.Add("the power profile changed $captureChanges time(s) inside the burst window (ppm captureChanges)") }
        if ($captureProfile -eq $ProfileId) { $reasons.Add("the Game Mode power profile $ProfileId was active in the burst window (ppm captureProfile)") }
    }
    if ($reasons.Count) { return $reasons -join '; ' }
    $null
}

function Get-FailedAttempt {
    param([Parameter(Mandatory)][string]$SeriesPath, [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Journal)
    foreach ($attempt in @($Journal | Where-Object { $_.event -eq 'boot' -and $_.outcome -ne 'success' })) {
        $failing = @(@($attempt.states) | Where-Object { $_ -and $_.status -ne 'ok' }) | Select-Object -First 1
        $folder = Get-OptionalField $attempt 'failedDir'
        if ($failing -and $failing.result) { $folder = Split-Path -Parent ([string]$failing.result) }
        if (-not $folder) { $folder = $null }
        $reason = $noPublicReason
        if ($failing -and $folder) {
            $name = $benchFileFormat -f ($phaseFormat -f [int]$attempt.index, [int]$failing.index), $failing.step
            $found = @(Get-ChildItem -LiteralPath (Join-Path $SeriesPath $folder) -Recurse -File -Filter $name | Sort-Object -Property FullName)
            if ($found.Count) {
                $rejected = Get-OptionalField (Read-Json -Path $found[0].FullName -Where "failed attempt $name") $gateFields.rejected
                if ($rejected) { $reason = [string]$rejected }
            }
        }
        [pscustomobject][ordered]@{
            boot        = [int]$attempt.index
            startedAt   = (ConvertTo-JournalTime (Get-Field $attempt 'startedAt' "journal boot $($attempt.index) $($attempt.outcome)")).ToString($timestampFormat, $invariant)
            endedAt     = (ConvertTo-JournalTime (Get-Field $attempt 'endedAt' "journal boot $($attempt.index) $($attempt.outcome)")).ToString($timestampFormat, $invariant)
            outcome     = [string]$attempt.outcome
            failingStep = $(if ($failing) { 'state {0} {1}' -f $failing.index, $failing.step } else { $null })
            failedDir   = $folder
            reason      = $reason
        }
    }
}

function Get-SignedRankCount {
    param([Parameter(Mandatory)][AllowEmptyCollection()][int[]]$Ranks)
    $total = 0
    foreach ($rank in $Ranks) { $total += $rank }
    $count = New-Object 'decimal[]' ($total + 1)
    $count[0] = 1d
    $reach = 0
    foreach ($rank in $Ranks) {
        $reach += $rank
        for ($sum = $reach; $sum -ge $rank; $sum--) { $count[$sum] += $count[$sum - $rank] }
    }
    , $count
}

function Get-SignedRankTest {
    param([Parameter(Mandatory)][AllowEmptyCollection()][decimal[]]$Differences)
    $nonzero = [decimal[]]@($Differences | Where-Object { $_ -ne 0 })
    $ranks = [int[]]@()
    if ($nonzero.Count) { $ranks = [int[]]@(Get-DoubledMidRank -Values ([decimal[]]@($nonzero | ForEach-Object { [math]::Abs($_) }))) }
    $total = 0
    $rankSum = 0
    for ($i = 0; $i -lt $ranks.Count; $i++) {
        $total += $ranks[$i]
        if ($nonzero[$i] -gt 0) { $rankSum += $ranks[$i] }
    }
    $observed = [math]::Abs(2 * $rankSum - $total)
    $count = Get-SignedRankCount -Ranks $ranks
    $extreme = 0d
    $permutations = 0d
    for ($sum = 0; $sum -lt $count.Count; $sum++) {
        if ($count[$sum] -eq 0) { continue }
        $permutations += $count[$sum]
        if ([math]::Abs(2 * $sum - $total) -ge $observed) { $extreme += $count[$sum] }
    }
    [pscustomobject]@{
        n            = $nonzero.Count
        level        = $Differences.Count - $nonzero.Count
        rankSum      = $rankSum
        total        = $total
        extreme      = $extreme
        permutations = $permutations
        direction    = [math]::Sign(2 * $rankSum - $total)
    }
}

function Get-PairedShiftEstimate {
    param([Parameter(Mandatory)][decimal[]]$Differences)
    $size = $Differences.Count
    $walsh = New-Object System.Collections.Generic.List[decimal]
    for ($i = 0; $i -lt $size; $i++) { for ($j = $i; $j -lt $size; $j++) { $walsh.Add(($Differences[$i] + $Differences[$j]) / 2) } }
    $sorted = $walsh.ToArray()
    [Array]::Sort($sorted)
    $result = [ordered]@{ shift = Get-Median -Values $sorted; ciLow = $null; ciHigh = $null; ciConfidence = $null }
    $noTies = Get-SignedRankCount -Ranks ([int[]]@(1..$size))
    $permutations = 0d
    foreach ($value in $noTies) { $permutations += $value }
    $tail = (1d - $confidence) / 2 * $permutations
    $cumulative = 0d
    $below = 0d
    $k = 0
    foreach ($value in $noTies) {
        $cumulative += $value
        if ($cumulative -gt $tail) { break }
        $below = $cumulative
        $k++
    }
    if ($k -ge 1) {
        $result.ciLow = $sorted[$k - 1]
        $result.ciHigh = $sorted[$sorted.Count - $k]
        $result.ciConfidence = 1d - 2 * $below / $permutations
    }
    [pscustomobject]$result
}

function Get-ComparisonRow {
    param([Parameter(Mandatory)][string[]]$Labels, [Parameter(Mandatory)][object[]]$Steps)
    $lookup = @{}
    foreach ($step in $Steps) { $lookup["$($step.Boot)|$($step.Label)|$($step.Step)"] = $step }
    $boots = [int[]]@($Steps | ForEach-Object { $_.Boot } | Sort-Object -Unique)
    foreach ($comparison in $comparisons) {
        $sides = @('reference', 'state', 'minusReference', 'minusState' | Where-Object { $comparison.Contains($_) })
        if (@($sides | Where-Object { $Labels -notcontains $comparison[$_] }).Count) { continue }
        $referenceUnit = $units[$comparison.reference]
        $stateUnit = $units[$comparison.state]
        $changed = @($changeSettings.Keys | Where-Object { ($referenceUnit.changes -contains $_) -ne ($stateUnit.changes -contains $_) })
        $change = @($changed | ForEach-Object { $changeSettings[$_].Keys })
        if ($referenceUnit.gameMode -ne $stateUnit.gameMode) { $change += $gameModeChange }
        if ($comparison.Contains('minusReference') -and $units[$comparison.minusReference].gameMode -ne $referenceUnit.gameMode) { $change += $gameModeChange }
        $readsParked = $comparison.tested -and $change -contains $cannotShowSetting
        foreach ($metric in $comparison.metrics) {
            $step = $metrics[$metric].step
            $pairs = New-Object System.Collections.Generic.List[object]
            $noParked = New-Object System.Collections.Generic.List[object]
            foreach ($boot in $boots) {
                $found = [ordered]@{}
                foreach ($side in $sides) { $found[$side] = $lookup["$boot|$($comparison[$side])|$step"] }
                if (@($found.Values | Where-Object { $null -eq $_ -or $_.Excluded }).Count) { continue }
                if ($readsParked -and $null -eq (Get-OptionalField $found['reference'].Bench ($parkedMedianFormat -f $stepParked[$step]))) {
                    $noParked.Add($found['reference'])
                    continue
                }
                $pairs.Add([pscustomobject]@{ Boot = $boot; Found = $found })
            }
            [pscustomobject]@{
                Comparison  = $comparison
                Name        = Get-ComparisonName -Comparison $comparison
                Metric      = $metric
                Change      = @($change)
                Mixed       = @($changed | Where-Object { $scriptChanges -contains $_ }).Count -gt 1
                ReadsParked = $readsParked
                Pairs       = $pairs.ToArray()
                NoParked    = $noParked.ToArray()
            }
        }
    }
}

function Get-PairedDifference {
    param([Parameter(Mandatory)]$Row)
    $definition = $metrics[$Row.Metric]
    $sides = @('reference', 'state', 'minusReference', 'minusState' | Where-Object { $Row.Comparison.Contains($_) })
    $values = [ordered]@{}
    foreach ($side in $sides) { $values[$side] = New-Object System.Collections.Generic.List[decimal] }
    $parked = New-Object System.Collections.Generic.List[decimal]
    foreach ($pair in $Row.Pairs) {
        foreach ($side in $sides) { $values[$side].Add((ConvertTo-WrittenDecimal (Get-Field $pair.Found[$side].Bench $definition.field "boot $($pair.Boot) $($Row.Comparison[$side]) $($definition.step)"))) }
        if ($Row.ReadsParked) { $parked.Add((ConvertTo-WrittenDecimal (Get-OptionalField $pair.Found['reference'].Bench ($parkedMedianFormat -f $stepParked[$definition.step])))) }
    }
    $differences = for ($i = 0; $i -lt $Row.Pairs.Count; $i++) {
        $difference = $values['state'][$i] - $values['reference'][$i]
        if ($values.Contains('minusState')) { $difference -= $values['minusState'][$i] - $values['minusReference'][$i] }
        $difference
    }
    [pscustomobject]@{
        Boots       = [int[]]@($Row.Pairs | ForEach-Object { $_.Boot })
        Values      = $values
        Differences = [decimal[]]@($differences)
        Parked      = $parked.ToArray()
    }
}

function Get-PairedAnalysis {
    param([Parameter(Mandatory)][string[]]$Labels, [Parameter(Mandatory)][object[]]$Steps)
    $tested = New-Object System.Collections.Generic.List[object]
    $described = New-Object System.Collections.Generic.List[object]
    foreach ($entry in @(Get-ComparisonRow -Labels $Labels -Steps $Steps)) {
        $comparison = $entry.Comparison
        $metric = $entry.Metric
        $pairs = Get-PairedDifference -Row $entry
        $differences = $pairs.Differences
        $empty = $pairs.Boots.Count -eq 0
        $test = Get-SignedRankTest -Differences $differences
        $shift = [pscustomobject]@{ shift = $null; ciLow = $null; ciHigh = $null; ciConfidence = $null }
        $referenceMedian = $null
        $stateMedian = $null
        if (-not $empty) {
            $shift = Get-PairedShiftEstimate -Differences $differences
            $referenceMedian = Get-Median -Values $pairs.Values['reference'].ToArray()
            $stateMedian = Get-Median -Values $pairs.Values['state'].ToArray()
        }
        $lower = @($differences | Where-Object { $_ -lt 0 }).Count
        $higher = @($differences | Where-Object { $_ -gt 0 }).Count
        $row = [ordered]@{
            comparison      = $entry.Name
            block           = $comparison.block
            reference       = $comparison.reference
            state           = $comparison.state
            step            = $metrics[$metric].step
            metric          = $metric
            change          = $entry.Change
            mixed           = $entry.Mixed
            boots           = @($pairs.Boots)
            differences     = @($differences | ForEach-Object { ConvertTo-OutputNumber $_ })
            referenceValues = @($pairs.Values['reference'] | ForEach-Object { ConvertTo-OutputNumber $_ })
            stateValues     = @($pairs.Values['state'] | ForEach-Object { ConvertTo-OutputNumber $_ })
        }
        if ($comparison.Contains('minusState')) {
            $row.minusReference = $comparison.minusReference
            $row.minusState = $comparison.minusState
            $row.minusReferenceValues = @($pairs.Values['minusReference'] | ForEach-Object { ConvertTo-OutputNumber $_ })
            $row.minusStateValues = @($pairs.Values['minusState'] | ForEach-Object { ConvertTo-OutputNumber $_ })
        }
        $row.referenceMedian = ConvertTo-OutputNumber $referenceMedian
        $row.stateMedian = ConvertTo-OutputNumber $stateMedian
        $row.shift = ConvertTo-OutputNumber $shift.shift
        $row.shiftPctOfReference = $(if (-not $empty) { ConvertTo-OutputNumber (Get-PercentOf -Value $shift.shift -Reference $referenceMedian) })
        $row.ciLow = ConvertTo-OutputNumber $shift.ciLow
        $row.ciHigh = ConvertTo-OutputNumber $shift.ciHigh
        $row.ciConfidence = ConvertTo-OutputNumber $shift.ciConfidence
        $row.lower = $lower
        $row.level = $test.level
        $row.higher = $higher
        if (-not $comparison.tested) {
            $described.Add([pscustomobject]$row)
            continue
        }
        $margin = $(if (-not $empty) { $marginShare[$metric] * $referenceMedian })
        $row.margin = ConvertTo-OutputNumber $margin
        $row.extreme = [long]$test.extreme
        $row.permutations = [long]$test.permutations
        $row.p = ConvertTo-OutputNumber ($test.extreme / $test.permutations) $pValueDigits
        $row.pHolm = $null
        $row.verdict = $null
        $row.cannotShow = $entry.ReadsParked -and -not $empty -and (Get-Median -Values $pairs.Parked) -eq 0
        $tested.Add([pscustomobject]@{
                Test      = $test
                Shift     = $shift
                Margin    = $margin
                Direction = $test.direction * $directionSign[$metrics[$metric].better]
                SameSide  = ($lower -eq 0 -or $higher -eq 0) -and ($lower + $higher) -gt 0
                Row       = $row
            })
    }
    $family = [ordered]@{}
    $holmExact = New-Object 'object[]' $tested.Count
    foreach ($block in @($tested | ForEach-Object { $_.Row.block } | Select-Object -Unique)) {
        $at = @(for ($i = 0; $i -lt $tested.Count; $i++) { if ($tested[$i].Row.block -eq $block) { $i } })
        $family[$block] = $at.Count
        $holm = @(Get-HolmAdjusted -Extreme @($at | ForEach-Object { $tested[$_].Test.extreme }) -Permutations @($at | ForEach-Object { $tested[$_].Test.permutations }))
        for ($j = 0; $j -lt $at.Count; $j++) {
            $entry = $tested[$at[$j]]
            $entry.Row.pHolm = $holm[$j].pHolm
            $entry.Row.verdict = Get-Verdict -Significant $holm[$j].significant -Direction $entry.Direction -CiLow $entry.Shift.ciLow -CiHigh $entry.Shift.ciHigh -Margin $entry.Margin -CannotShow:$entry.Row.cannotShow -SameSide:$entry.SameSide
            $holmExact[$at[$j]] = $holm[$j].numerator / $holm[$j].denominator
        }
    }
    [pscustomobject]@{
        family     = $family
        tests      = @($tested | ForEach-Object { [pscustomobject]$_.Row })
        described  = $described.ToArray()
        pHolmExact = $holmExact
    }
}

function Get-FieldSpread {
    param([Parameter(Mandatory)][object[]]$Steps, [Parameter(Mandatory)][string]$Field)
    Get-Spread -Values @($Steps | ForEach-Object { ConvertTo-WrittenDecimal (Get-Field $_.Bench $Field "boot $($_.Boot) $($_.Label) $($_.Step)") })
}

function Get-StateSummary {
    param([Parameter(Mandatory)][string]$Label, [Parameter(Mandatory)][string]$Step, [Parameter(Mandatory)][object[]]$Steps, [Parameter(Mandatory)][int]$ProfileId)
    $unit = $units[$Label]
    $fields = Get-StepStateField -Step $Steps[0]
    $parkedField = $parkedMedianFormat -f $stepParked[$Step]
    $withParked = @($Steps | Where-Object { $null -ne (Get-OptionalField $_.Bench $parkedField) })
    $parked = $null
    if ($withParked.Count) { $parked = Get-FieldSpread -Steps $withParked -Field $parkedField }
    $state = [ordered]@{
        label      = $Label
        step       = $Step
        ceiling    = $unit.changes -contains $ceilingChange
        boots      = @($Steps | ForEach-Object { $_.Boot })
        benchFiles = @($Steps | ForEach-Object { $_.BenchFile })
    }
    if ($unit.fpsMax -gt 0 -and $Step -eq $gameStep) { $state.fpsMax = $unit.fpsMax }
    foreach ($key in $fields.Keys) { $state[$key] = Get-FieldSpread -Steps $Steps -Field $fields[$key] }
    if ($Step -eq $burstStep) {
        $state.wakeP90Ms = Get-Spread -Values @($Steps | ForEach-Object { ConvertTo-WrittenDecimal (Get-Percentile ([double[]]@($_.WakeMax | Sort-Object)) $wakeQuantile) })
        $state.slowestWakeMs = Get-Spread -Values @($Steps | ForEach-Object { @($_.WakeMax | Sort-Object)[-1] })
        $state[$stepParked[$Step]] = $parked
        return [pscustomobject]$state
    }
    if ($unit.fpsMax -gt 0) {
        foreach ($key in $overPeriodKeys) {
            $state[$key + $overPeriodSuffix] = Get-Spread -Values @($Steps | ForEach-Object { (ConvertTo-WrittenDecimal (Get-Field $_.Bench $fields[$key] "boot $($_.Boot)")) - (ConvertTo-WrittenDecimal (Get-Field $_.Bench $capPeriodField "boot $($_.Boot)")) })
        }
        $state[$stepParked[$Step]] = $parked
        return [pscustomobject]$state
    }
    $state.gpuBusySharePct = Get-Spread -Values @($Steps | ForEach-Object { [math]::Round((ConvertTo-WrittenDecimal (Get-Field $_.Bench $fields.gpuBusyP50Ms "boot $($_.Boot)")) / (ConvertTo-WrittenDecimal (Get-Field $_.Bench $fields.p50Ms "boot $($_.Boot)")) * $percent, $summaryDigits) })
    $state[$stepParked[$Step]] = $parked
    $state.gameModeProfileSteps = [ordered]@{ steps = @($Steps | Where-Object { (Get-OptionalField $_.Bench $exclusionFields.captureProfile) -eq $ProfileId }).Count; of = $Steps.Count }
    [pscustomobject]$state
}

function Format-RulesBlock {
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('## Pre-registered comparisons')
    $lines.Add('')
    $lines.Add('These rules were fixed in this script before any outcome of the series was read.')
    $lines.Add('')
    $unitRows = @(foreach ($label in $units.Keys) {
            $unit = $units[$label]
            $settings = Get-UnitSetting -Label $label
            , @(@(Format-StateLabel $label) + @($settings.Keys | ForEach-Object { $settings[$_] }) + @($(if ($unit.gameMode -eq $gameModeOn) { 'on' } else { 'off' }), $(if ($unit.fpsMax -gt 0) { $unit.fpsMax } else { 'off' }), ($unit.steps -join ', ')))
        })
    $lines.AddRange([string[]]@(Format-MarkdownTable -Header (@('Unit') + @($stockSettings.Keys) + @('Game Mode', 'fps_max', 'Steps')) -Rows $unitRows))
    $lines.Add('')
    $lines.AddRange([string[]]@(Format-MarkdownTable -Header 'Series', 'Block', 'Boots', 'Units, every step once in every boot' -Rows @($seriesDesigns.Keys | ForEach-Object { , @($_, $seriesDesigns[$_].block, $seriesDesigns[$_].boots, ($seriesDesigns[$_].units -join ', ')) })))
    $lines.Add('')
    $number = @{}
    $comparisonRows = @(foreach ($comparison in $comparisons) {
            foreach ($metric in $comparison.metrics) {
                $index = '-'
                if ($comparison.tested) {
                    $number[$comparison.block] = 1 + $(if ($number.ContainsKey($comparison.block)) { $number[$comparison.block] } else { 0 })
                    $index = $number[$comparison.block]
                }
                $changed = @($changeSettings.Keys | Where-Object { ($units[$comparison.reference].changes -contains $_) -ne ($units[$comparison.state].changes -contains $_) })
                , @(
                    $comparison.block
                    $index
                    (Get-ComparisonName -Comparison $comparison -Labelled)
                    $metrics[$metric].label
                    $metrics[$metric].better
                    $(if ($comparison.tested) { ($marginShare[$metric] * $percent).ToString($displayFormat, $invariant) + '%' } else { '-' })
                    $(if ($comparison.tested) { 'tested' } else { 'described' })
                    $(if (@($changed | Where-Object { $scriptChanges -contains $_ }).Count -gt 1) { $mixedLabel } else { '-' })
                )
            }
        })
    $lines.AddRange([string[]]@(Format-MarkdownTable -Header 'Block', '#', 'Comparison', 'Metric', 'Better', 'Margin (share of the reference median)', 'Row', 'Label' -Rows $comparisonRows))
    $lines.Add('')
    $alphaText = $alpha.ToString($invariant)
    $confidenceText = ($confidence * $percent).ToString($displayFormat, $invariant)
    $lines.Add('- Pairs: each comparison takes d = state minus reference within each boot; the interaction row takes d = (epp - stock) - (gm-off-epp - gm-off-stock) within each boot.')
    $lines.Add('- Test: the exact two-sided Wilcoxon signed-rank test. A boot with d = 0 leaves the test and counts as level; tied |d| take their mid-rank; p is the share of the 2^n sign patterns of the n boots left whose rank sum lies at least as far from its mean as the observed one.')
    $lines.Add("- Family: Holm over the tested rows of one block at alpha $alphaText; the main block and the ceiling block are separate families.")
    $lines.Add("- Shift: the Hodges-Lehmann estimate, the median of the n(n+1)/2 Walsh averages of d over all boots of the row, with the interval [W(k), W(N+1-k)] at no less than $confidenceText% confidence, k from the signed-rank distribution without ties; no interval for 4 boots or fewer.")
    $lines.Add('- Margin: the share above of the reference median over the boots of the row; the interaction row takes the stock median.')
    $lines.Add("- Verdict, first match: (1) helped or hurt when the Holm-adjusted p is under $alphaText, by the direction and the better side of the metric; (2) cannot show when the comparison changes $cannotShowSetting and the median parked count of the reference state over the boots of the row is 0 (parked before the burst, or during the game); (3) cannot tell when at least one boot differs and every boot that differs lies on one side; (4) no difference when the whole interval lies strictly inside the margin; (5) cannot tell.")
    $lines.Add("- A comparison that moves both changes of the script (CPMINCORES and PERFEPP) carries the label ""$mixedLabel"" with its verdict; the single-change rows are separate.")
    $lines.Add("- The ceiling block pairs its states with maxcores25 inside each boot; no test and no number is taken across the two blocks. Its states are forced and carry ""$ceilingLabel"".")
    $lines.Add('- Described rows get the shift and the interval only: no p and no verdict.')
    $parkedFields = @($stepParked.Values | ForEach-Object { $parkedMedianFormat -f $_ }) -join ' or '
    $logicalFields = @($stepParked.Values | ForEach-Object { "$_.$logicalCpusField" }) -join ' or '
    $common = @($requiredFingerprintFields) + @($optionalFingerprintFields) + @($optionalEnvironmentFields) + @($driverFingerprintFields) + @($logicalFields)
    $lines.Add(('- The series is refused, and needs an amendment dated before any outcome is read, on: a planned step without exactly one accepted result in journal.jsonl; a wrapper whose {0}, {1}, {2} or {3} differs from plan.json and the journal; a wrapper {4} other than {5}; a bench JSON whose {6} or {7} is not its own step''s; a plan state that is not one of the units above; a pre-registered series with another boot count or without every step of its units in every boot; a wrapper {8} outside its boot in the journal; a bench {9}, or one of the five values above in {10}, AC or DC, other than the state''s; a bench {11} other than true; a wrapper {12} other than 0; a game whose {13} differs from its Game Mode or whose {14} record fails the Game Mode check; a game {15} or {16} other than the state''s; a game with a non-empty {17} or a non-zero {18}; a missing or non-numeric field that a table reads, or a wake file without its {19} and {20} columns or without a burst row; any difference between steps in {21}; between bursts in {22}; between games in {23}; or in {24} and {25} once the five planned values are left out.' -f $gateFields.series, $gateFields.boot, $gateFields.stateIndex, $gateFields.state, $gateFields.resultFile, ($benchFileFormat -f '<phase>', '<step>'), $gateFields.phase, $gateFields.test, $gateFields.capturedAt, $gateFields.scheme, $processorSettingsField, $gateFields.highQos, $gateFields.adapters, $gateFields.autoGameMode, $gateFields.ppm, $gateFields.cap, $gateFields.capFpsMax, $gateFields.rejected, $gateFields.overflow, $wakeBurstColumn, $wakeColumn, ($common -join ', '), ($burstFingerprintFields -join ', '), ((@($gameFingerprintFields) + @($presentModesField)) -join ', '), $processorSettingsField, $powerExplicitField))
    $lines.Add(('- A step leaves every row and state table that uses it, and its boot stays in the others, when it is a burst whose {0} is not 0, whose {1} is not 0 or whose {2} is the Game Mode profile, or any step whose {3} is true. In a tested row that changes {4}, a boot whose reference step has no {5} is left out of that row only and listed with the reason "{6}"; no other row reads the parked count.' -f $exclusionFields.buffersLost, $exclusionFields.captureChanges, $exclusionFields.captureProfile, $exclusionFields.powerStateChanged, $cannotShowSetting, $parkedFields, $noParkedReason))
    $lines.Add('- A tested row with no boot that holds every step it pairs stays in its family with p = 1 and reads cannot tell; a described row with no boot prints dashes.')
    $lines.Add('- Listed only: failed attempts and power profile changes before the capture window. A failed attempt''s rejection text is printed as recorded; failed attempts are never read for outcomes.')
    $lines.ToArray()
}

function New-SeriesReport {
    param([Parameter(Mandatory)][string]$SeriesPath, [switch]$ChecksOnly)
    $plan = Read-Json -Path (Join-Path $SeriesPath 'plan.json') -Where 'plan.json'
    $journal = Read-Journal -Path (Join-Path $SeriesPath 'journal.jsonl')
    $series = [string](Get-Field $plan 'series' 'plan.json')
    $profileId = [int](Get-Field $plan 'gameModeProfileId' 'plan.json')
    $accepted = @(Get-AcceptedResult -Plan $plan -Journal $journal)
    $events = @($journal | Where-Object { $_.event -eq 'boot' -and $_.outcome -eq 'success' })
    $steps = @($accepted | ForEach-Object { Read-StepData -SeriesPath $SeriesPath -Accepted $_ -Events $events })
    foreach ($step in $steps) { Assert-StepState -Step $step -Plan $plan }
    foreach ($group in @($steps | Group-Object -Property { "$($_.Boot)|$($_.Label)|$($_.Step)" } | Where-Object { $_.Count -gt 1 })) {
        $first = $group.Group[0]
        throw "boot $($first.Boot) holds the $($first.Label) $($first.Step) step $($group.Count) times"
    }
    $bootCount = @($plan.boots).Count
    $preRegistered = $seriesDesigns.Contains($series)
    if ($preRegistered) {
        $design = $seriesDesigns[$series]
        if ($bootCount -ne $design.boots) { throw "plan.json lists $bootCount boots, the pre-registered series $series has $($design.boots)" }
        $expected = [string[]]@(foreach ($label in $design.units) { foreach ($step in $units[$label].steps) { "$label $step" } })
        [Array]::Sort($expected, [System.StringComparer]::Ordinal)
        $expected = $expected -join ', '
        for ($boot = 0; $boot -lt $bootCount; $boot++) {
            $held = [string[]]@($steps | Where-Object { $_.Boot -eq $boot } | ForEach-Object { "$($_.Label) $($_.Step)" })
            [Array]::Sort($held, [System.StringComparer]::Ordinal)
            $held = $held -join ', '
            if ($held -cne $expected) { throw "boot $boot holds $held; the pre-registered series $series holds every step of $($design.units -join ', ') once in every boot" }
        }
    }
    $firstSeen = @{}
    foreach ($step in $steps) {
        $fingerprint = Get-StepFingerprint -Step $step
        foreach ($field in $fingerprint.Keys) {
            if (-not $firstSeen.ContainsKey($field)) {
                $firstSeen[$field] = [pscustomobject]@{ Step = $step; Value = $fingerprint[$field] }
                continue
            }
            $seen = $firstSeen[$field]
            if ($fingerprint[$field] -cne $seen.Value) {
                throw ("boot {0} state {1} field {2} differs from boot {3} state {4}: '{5}' against '{6}'" -f $step.Boot, $step.StateIndex, $field, $seen.Step.Boot, $seen.Step.StateIndex, $fingerprint[$field], $seen.Value)
            }
        }
    }
    foreach ($step in $steps) { $step.Excluded = Get-StepExclusion -Step $step -ProfileId $profileId }
    foreach ($step in @($steps | Where-Object { -not $_.Excluded })) { Assert-StepField -Step $step }
    $labels = @($units.Keys | Where-Object { @($steps | ForEach-Object { $_.Label }) -contains $_ })
    $rows = @(Get-ComparisonRow -Labels $labels -Steps $steps)
    $leftOut = @($steps | Where-Object { $_.Excluded } | ForEach-Object { [pscustomobject][ordered]@{ boot = $_.Boot; stateIndex = $_.StateIndex; state = $_.Label; step = $_.Step; reason = $_.Excluded; leftOutOf = @($everyRowScope) } })
    $noParked = @(foreach ($row in $rows) { foreach ($step in $row.NoParked) { [pscustomobject]@{ Step = $step; Row = $rowNameFormat -f $row.Name, $row.Metric } } })
    foreach ($group in @($noParked | Group-Object -Property { "$($_.Step.Boot)|$($_.Step.StateIndex)" })) {
        $step = $group.Group[0].Step
        $leftOut += [pscustomobject][ordered]@{ boot = $step.Boot; stateIndex = $step.StateIndex; state = $step.Label; step = $step.Step; reason = $noParkedReason; leftOutOf = @($group.Group | ForEach-Object { $_.Row }) }
    }
    $excluded = @($leftOut | Sort-Object -Property boot, stateIndex)
    $rowBoots = @($rows | Where-Object { $_.Comparison.tested } | ForEach-Object { [pscustomobject][ordered]@{ comparison = $_.Name; metric = $_.Metric; boots = $_.Pairs.Count } })
    $failedAttempts = @(Get-FailedAttempt -SeriesPath $SeriesPath -Journal $journal)
    $profileChanges = @(foreach ($step in $steps) {
            $changes = @(@(Get-OptionalField $step.Bench 'ppm.profileChanges') | Where-Object { $_ })
            $expectedPath = $step.Step -eq $gameStep -and [int]$step.PlanState.gameMode -eq $gameModeOn -and $changes.Count -eq 1 -and $changes[0].to -eq $profileId
            if ($changes.Count -and -not $expectedPath) {
                [pscustomobject][ordered]@{
                    boot       = $step.Boot
                    stateIndex = $step.StateIndex
                    state      = $step.Label
                    step       = $step.Step
                    changes    = @($changes | ForEach-Object { [pscustomobject][ordered]@{ offsetSeconds = ConvertTo-OutputNumber (ConvertTo-WrittenDecimal $_.offsetSeconds); from = [int]$_.from; to = [int]$_.to } })
                }
            }
        })

    $firstBurst = @($steps | Where-Object { $_.Step -eq $burstStep })[0]
    $firstGame = @($steps | Where-Object { $_.Step -eq $gameStep })[0]
    $environment = $steps[0].Wrapper.environment
    $os = Get-Field $steps[0].Bench 'metadata.os' 'boot 0'
    $testbed = [ordered]@{}
    $testbed['Windows'] = "$($os.displayVersion) build $($os.build).$($os.ubr)"
    $testbed['CPU'] = [string](Get-Field $environment 'cpu.name' 'boot 0 wrapper environment')
    $testbed['Board and BIOS'] = "$(Get-Field $environment 'bios.board' 'boot 0 wrapper environment'), BIOS $(Get-Field $environment 'bios.version' 'boot 0 wrapper environment')"
    $testbed['GPU driver'] = (@(Get-Field $environment 'drivers.gpu' 'boot 0 wrapper environment') | ForEach-Object { "$($_.device) $($_.version)" }) -join '; '
    $testbed['Audio drivers'] = (@(Get-Field $environment 'drivers.audio' 'boot 0 wrapper environment') | ForEach-Object { "$($_.device) $($_.version)" }) -join '; '
    $testbed['Power scheme'] = [string](Get-Field $steps[0].Bench 'metadata.power.schemeGuid' 'boot 0')
    $testbed['Logical CPUs'] = [string](Get-Field $firstBurst.Bench 'parkedBeforeBurst.logicalCpus' 'boot 0')
    $testbed['Burst'] = "$($firstBurst.Bench.threads) threads, $($firstBurst.Bench.bursts) bursts of $($firstBurst.Bench.burstMs) ms after $($firstBurst.Bench.idleSeconds) s idle"
    $testbed['Present mode'] = (@(Get-Field $firstGame.Bench 'frames.presentModes' 'boot 0')) -join '; '
    $testbed['Refresh rate'] = "$(Get-Field $firstGame.Bench 'frames.refreshHz' 'boot 0') Hz"
    $testbed['Load'] = "$(Get-Field $firstGame.Bench 'load.name' 'boot 0') $(Get-Field $firstGame.Bench 'load.build' 'boot 0')"
    $testbed['PresentMon'] = [string](Get-Field $firstGame.Bench 'metadata.presentMonVersion' 'boot 0')
    $testbed['Game Mode power profile'] = [string]$profileId
    $testbed['Settle before the first step'] = "$(Get-Field $plan 'settleSeconds' 'plan.json') s"
    $testbed['Game capture'] = "$(Get-Field $plan 'captureSeconds' 'plan.json') s"
    $testbed['Enabled physical network adapters'] = [string]$environment.enabledNetworkAdapters
    $testbed['Boots'] = [string]$bootCount
    $testbed['Steps per boot'] = [string]@($plan.boots[0].states).Count
    $start = @($journal | Where-Object { $_.event -eq 'start' }) | Select-Object -First 1
    foreach ($key in 'services', 'tasks', 'startup', 'network') {
        $counts = $start.PSObject.Properties[$key]
        if ($counts) { $testbed["Disabled $key"] = [string][int]$counts.Value }
    }

    $checks = @(
        [ordered]@{ name = 'one accepted result per planned step'; source = 'private runner journal.jsonl and plan.json'; benchJson = $false; status = 'passed' }
        [ordered]@{ name = 'wrapper series, boot, step and state equal plan.json'; source = 'private runner wrapper and plan.json'; benchJson = $false; status = 'passed' }
        [ordered]@{ name = 'every wrapper names the bench JSON of its own step, whose phase and test are that step'; source = 'private runner wrapper bench.resultFile, bench JSON phase and test'; benchJson = $false; status = 'passed' }
        [ordered]@{ name = 'every planned state is a pre-registered unit of this script'; source = 'private runner plan.json'; benchJson = $false; status = 'passed' }
        [ordered]@{ name = 'pre-registered boot count, every step of every unit once in every boot'; source = 'private runner plan.json'; benchJson = $false; status = $(if ($preRegistered) { 'passed' } else { $notPreRegistered }) }
        [ordered]@{ name = 'every capture inside its boot'; source = 'private runner wrapper capturedAt, journal.jsonl startedAt and endedAt'; benchJson = $false; status = 'passed' }
        [ordered]@{ name = 'power scheme and the five planned values, AC and DC, equal the state'; source = 'bench JSON metadata.power'; benchJson = $true; status = 'passed' }
        [ordered]@{ name = 'Game Mode registry value and power profile equal the state'; source = 'bench JSON autoGameModeEnabled, ppm'; benchJson = $true; status = 'passed' }
        [ordered]@{ name = 'fps cap equals the state'; source = 'bench JSON cap.fpsMax'; benchJson = $true; status = 'passed' }
        [ordered]@{ name = 'no rejected run, no PresentMon overflow, every run at high QoS'; source = 'bench JSON rejected, presentMon.overflowedPresents, highQos'; benchJson = $true; status = 'passed' }
        [ordered]@{ name = 'OS build, UBR, QPC frequency and bench script identical'; source = 'bench JSON metadata.os, metadata.qpcFrequency, metadata.benchScript'; benchJson = $true; status = 'passed' }
        [ordered]@{ name = 'PresentMon, load build, video config, refresh rate and present mode identical'; source = 'bench JSON metadata.presentMonVersion, presentMon.sha256, load, frames.refreshHz, frames.presentModes'; benchJson = $true; status = 'passed' }
        [ordered]@{ name = 'burst parameters and logical CPU count identical'; source = 'bench JSON threads, bursts, idleSeconds, burstMs, windowMs, chunkIterations, itersPerMs, burst.earlyWindowMs, logicalCpus'; benchJson = $true; status = 'passed' }
        [ordered]@{ name = 'power settings other than the five planned identical'; source = 'bench JSON metadata.power, private runner wrapper environment.powerExplicit'; benchJson = $false; status = 'passed' }
        [ordered]@{ name = 'GPU and audio driver versions identical'; source = 'private runner wrapper environment.drivers'; benchJson = $false; status = 'passed' }
        [ordered]@{ name = 'HVCI, BIOS version, microcode and clock flags identical, no enabled physical network adapter'; source = 'private runner wrapper environment'; benchJson = $false; status = 'passed' }
        [ordered]@{ name = 'every field a table reads is present and numeric in every step not left out, every wake file has its columns and a burst row'; source = 'bench JSON, wake.csv'; benchJson = $true; status = 'passed' }
    ) | ForEach-Object { [pscustomobject]$_ }

    $constants = [ordered]@{
        alpha          = $alpha
        confidence     = $confidence
        scheme         = $planScheme
        units          = [ordered]@{}
        seriesDesigns  = $seriesDesigns
        metrics        = $metrics
        margins        = [ordered]@{ shareOfReferenceMedian = $marginShare }
        comparisons    = @($comparisons | ForEach-Object { $entry = [ordered]@{ comparison = Get-ComparisonName -Comparison $_ }; foreach ($key in $_.Keys) { $entry[$key] = $_[$key] }; [pscustomobject]$entry })
        cannotShowWhenReferenceParkedIsZero = $cannotShowSetting
    }
    foreach ($label in $units.Keys) { $constants.units[$label] = [ordered]@{ settings = Get-UnitSetting -Label $label; gameMode = $units[$label].gameMode; fpsMax = $units[$label].fpsMax; steps = $units[$label].steps; ceiling = $units[$label].changes -contains $ceilingChange } }

    $md = New-Object System.Collections.Generic.List[string]
    $md.Add('## Testbed')
    $md.Add('')
    $md.AddRange([string[]]@(Format-MarkdownTable -Header 'Item', 'Value' -Rows @($testbed.Keys | ForEach-Object { , @($_, $testbed[$_]) })))
    $md.Add('')
    $md.Add('## Checks that passed before these tables were written')
    $md.Add('')
    $md.AddRange([string[]]@(Format-MarkdownTable -Header 'Check', 'Source', 'Repeatable from the bench JSON', 'Status' -Rows @($checks | ForEach-Object { , @($_.name, $_.source, $(if ($_.benchJson) { 'yes' } else { 'no, needs the private runner' }), $_.status) })))
    $md.Add('')
    if (-not $preRegistered) {
        $md.Add("$series is $notPreRegistered`: its boot count and units were not checked against a design, and no row below is a result.")
        $md.Add('')
    }
    $md.Add('Power profile changes before the capture window, other than the single change into the Game Mode profile of a Game Mode game (listed only):')
    $md.Add('')
    if ($profileChanges.Count) {
        $md.AddRange([string[]]@(Format-MarkdownTable -Header 'Boot', 'State', 'Step', 'Changes (from -> to at seconds from the window start)' -Rows @($profileChanges | ForEach-Object { , @($_.boot, (Format-StateLabel $_.state), $_.step, (($_.changes | ForEach-Object { '{0} -> {1} at {2} s' -f $_.from, $_.to, (Format-Rounded $_.offsetSeconds) }) -join ', ')) })))
    }
    else { $md.Add('None.') }
    $md.Add('')
    $md.Add('## Failed attempts')
    $md.Add('')
    if ($failedAttempts.Count) {
        $md.AddRange([string[]]@(Format-MarkdownTable -Header 'Boot', 'Started', 'Ended', 'Outcome', 'Failing step', 'Folder', 'Public reason' -Rows @($failedAttempts | ForEach-Object { , @($_.boot, $_.startedAt, $_.endedAt, $_.outcome, $(if ($_.failingStep) { $_.failingStep } else { '-' }), $(if ($_.failedDir) { $_.failedDir } else { '-' }), $_.reason) })))
    }
    else { $md.Add('No failed attempt.') }
    $md.Add('')
    $md.Add('## Steps left out')
    $md.Add('')
    if ($excluded.Count) {
        $md.AddRange([string[]]@(Format-MarkdownTable -Header 'Boot', 'State', 'Step', 'Reason', 'Left out of' -Rows @($excluded | ForEach-Object { , @($_.boot, (Format-StateLabel $_.state), $_.step, $_.reason, ($_.leftOutOf -join '; ')) })))
    }
    else { $md.Add('No step was left out.') }

    $summary = [ordered]@{ series = $series; constants = $constants; checks = $checks; testbed = $testbed; analysis = [ordered]@{} }
    if ($ChecksOnly) {
        $md.Add('')
        $md.Add('## Boots per tested row')
        $md.Add('')
        $md.Add('How many boots each pre-registered test will pair, counted before any outcome is read.')
        $md.Add('')
        $md.AddRange([string[]]@(Format-MarkdownTable -Header 'Comparison', 'Metric', 'Boots' -Rows @($rows | Where-Object { $_.Comparison.tested } | ForEach-Object { , @((Get-ComparisonName -Comparison $_.Comparison -Labelled), $metrics[$_.Metric].label, $_.Pairs.Count) })))
        $summary.analysis = [ordered]@{ excluded = $excluded; failedAttempts = $failedAttempts; profileChanges = $profileChanges; rowBoots = $rowBoots }
        return [pscustomobject]@{ Markdown = ($md -join "`n") + "`n"; Summary = [pscustomobject]$summary }
    }

    $analysis = Get-PairedAnalysis -Labels $labels -Steps $steps
    $kept = @($steps | Where-Object { -not $_.Excluded })
    $states = @(foreach ($label in $labels) {
            foreach ($stepName in $units[$label].steps) {
                $group = @($kept | Where-Object { $_.Label -eq $label -and $_.Step -eq $stepName } | Sort-Object -Property Boot)
                if ($group.Count) { Get-StateSummary -Label $label -Step $stepName -Steps $group -ProfileId $profileId }
            }
        })
    $allBoots = @($steps | ForEach-Object { $_.Boot } | Sort-Object -Unique)
    $fileMap = @(
        [ordered]@{ table = 'Pre-registered tests and Described comparisons'; files = 'parking-bench-bootNN-stateNN-<step>.json'; fields = 'burst.lastWorkerWakeMs.median, frames.avgFps, frames.low1PctMs, frames.low01PctMs, parkedBeforeBurst.parked.median, parkedDuringRun.parked.median'; runner = $false }
        [ordered]@{ table = 'Burst'; files = 'parking-bench-bootNN-stateNN-burst.json, parking-bench-bootNN-stateNN-burst-wake.csv'; fields = 'burst.lastWorkerWakeMs, burst.earlyCoreMs, burst.totalCoreMs, parkedBeforeBurst.parked; wake.csv burst, wakeMs'; runner = $false }
        [ordered]@{ table = 'Uncapped game'; files = 'parking-bench-bootNN-stateNN-game.json'; fields = 'frames.*, parkedDuringRun.parked, ppm.captureProfile'; runner = $false }
        [ordered]@{ table = 'Capped game'; files = 'parking-bench-bootNN-stateNN-game.json'; fields = 'frames.avgFps, frames.p50Ms, frames.low01PctMs, frames.low1PctMs, cap.periodMs, cap.slowFrames, parkedDuringRun.parked'; runner = $false }
        [ordered]@{ table = 'Steps left out'; files = 'parking-bench-bootNN-stateNN-<step>.json'; fields = 'powerStateChanged, ppm.buffersLost, ppm.captureChanges, ppm.captureProfile'; runner = $false }
        [ordered]@{ table = 'Power profile changes before the capture window'; files = 'parking-bench-bootNN-stateNN-<step>.json'; fields = 'ppm.profileChanges'; runner = $false }
        [ordered]@{ table = 'Failed attempts'; files = 'journal.jsonl, failed\<folder>\...\parking-bench-bootNN-stateNN-<step>.json'; fields = 'boot events startedAt, endedAt, outcome, states, failedDir; rejected'; runner = $true }
        [ordered]@{ table = 'Testbed: OS, power, load, PresentMon, burst'; files = 'parking-bench-bootNN-stateNN-<step>.json'; fields = 'metadata.*, frames.presentModes, frames.refreshHz, load, threads, bursts, burstMs, idleSeconds, parkedBeforeBurst.logicalCpus'; runner = $false }
        [ordered]@{ table = 'Testbed: CPU, BIOS, drivers, network adapters'; files = 'bootNN-stateNN-<step>.json'; fields = 'environment.*'; runner = $true }
        [ordered]@{ table = 'Testbed: counts of disabled services, tasks, startup items and network adapters'; files = 'journal.jsonl'; fields = 'start event services, tasks, startup, network'; runner = $true }
        [ordered]@{ table = 'State labels, power values, Game Mode and cap'; files = 'plan.json'; fields = 'boots[].states[]'; runner = $true }
    ) | ForEach-Object { [pscustomobject]$_ }
    $summary.analysis = [ordered]@{ family = $analysis.family; tests = $analysis.tests; described = $analysis.described; excluded = $excluded; failedAttempts = $failedAttempts; profileChanges = $profileChanges }
    $summary.states = $states
    $summary.fileMap = $fileMap

    $md.Add('')
    $md.AddRange([string[]]@(Format-RulesBlock))
    $md.Add('')
    $md.Add('## Pre-registered tests')
    $md.Add('')
    $md.Add(('Holm-corrected within each block at alpha {0}: {1}. Shift and interval are state minus reference, in the unit of the metric; lower, level and higher count the boots by the sign of d.' -f $alpha.ToString($invariant), ((@($analysis.family.Keys) | ForEach-Object { '{0} {1} tests' -f $_, $analysis.family[$_] }) -join ', ')))
    $md.Add('')
    $rowNote = {
        param($Row)
        if (@($Row.boots).Count -eq 0) { return $noBootNote }
        $notes = @()
        if ($Row.mixed) { $notes += $mixedLabel }
        $out = @($allBoots | Where-Object { @($Row.boots) -notcontains $_ })
        if ($out.Count) { $notes += 'boots left out: ' + ($out -join ', ') }
        if ($notes.Count) { $notes -join '; ' } else { '-' }
    }
    $rowCells = {
        param($Row)
        if (@($Row.boots).Count -eq 0) { return @('-', '-', '-', '-', '-') }
        @(
            (Format-Rounded $Row.referenceMedian)
            (Format-Rounded $Row.stateMedian)
            (Format-Rounded $Row.shift)
            $(if ($null -eq $Row.shiftPctOfReference) { 'n/a' } else { Format-Rounded $Row.shiftPctOfReference })
            $(if ($null -eq $Row.ciLow) { 'none' } else { '[{0}, {1}]' -f (Format-Rounded $Row.ciLow), (Format-Rounded $Row.ciHigh) })
        )
    }
    $rowName = {
        param($Row)
        $entry = [ordered]@{ state = $Row.state; reference = $Row.reference }
        if ($Row.PSObject.Properties['minusState']) { $entry.minusState = $Row.minusState; $entry.minusReference = $Row.minusReference }
        Get-ComparisonName -Comparison $entry -Labelled
    }
    $testRows = @(for ($i = 0; $i -lt $analysis.tests.Count; $i++) {
            $test = $analysis.tests[$i]
            , @(
                (& $rowName $test)
                $metrics[$test.metric].label
                @($test.boots).Count
                (& $rowCells $test)
                $(if ($null -eq $test.margin) { '-' } else { '+/-{0}' -f (Format-Rounded $test.margin) })
                ('{0} / {1} / {2}' -f $test.lower, $test.level, $test.higher)
                (Format-PValue -Value $analysis.pHolmExact[$i])
                $test.verdict
                (& $rowNote $test)
            )
        })
    $md.AddRange([string[]]@(Format-MarkdownTable -Header 'Comparison', 'Metric', 'Boots', 'Reference median', 'State median', 'Shift', 'Shift (% of reference)', 'Interval', 'Margin', 'Lower / level / higher', 'p (Holm)', 'Verdict', 'Note' -Rows $testRows))
    $md.Add('')
    $md.Add('## Described comparisons')
    $md.Add('')
    if ($analysis.described.Count) {
        $md.Add('No test and no verdict: the shift and its interval only.')
        $md.Add('')
        $describedRows = @(foreach ($row in $analysis.described) {
                , @(
                    (& $rowName $row)
                    $metrics[$row.metric].label
                    @($row.boots).Count
                    (& $rowCells $row)
                    ('{0} / {1} / {2}' -f $row.lower, $row.level, $row.higher)
                    (& $rowNote $row)
                )
            })
        $md.AddRange([string[]]@(Format-MarkdownTable -Header 'Comparison', 'Metric', 'Boots', 'Reference median', 'State median', 'Shift', 'Shift (% of reference)', 'Interval', 'Lower / level / higher', 'Note' -Rows $describedRows))
    }
    else { $md.Add('No described comparison in this series.') }
    $md.Add('')
    $md.Add('## Burst')
    $md.Add('')
    $md.Add(('Median [min-max] over the runs of each state. The wake of a burst is its slowest thread; each run gives the median, the p{0} and the slowest of its bursts.' -f ($wakeQuantile * $percent)))
    $md.Add('')
    $md.AddRange([string[]]@(Format-MarkdownTable -Header 'State', 'Runs', 'Wake, median of the run (ms)', ('Wake, p{0} of the run (ms)' -f ($wakeQuantile * $percent)), 'Wake, slowest of the run (ms)', 'Parked before the burst', 'Core-ms in the early window', 'Core-ms in the burst' -Rows @($states | Where-Object { $_.step -eq $burstStep } | ForEach-Object { , @((Format-StateLabel $_.label), $_.boots.Count, (Format-Spread $_.lastWorkerWakeMs), (Format-Spread $_.wakeP90Ms), (Format-Spread $_.slowestWakeMs), (Format-Spread $_.parkedBeforeBurst), (Format-Spread $_.earlyCoreMs), (Format-Spread $_.totalCoreMs)) })))
    $md.Add('')
    $md.Add('## Uncapped game')
    $md.Add('')
    $md.Add('Median [min-max] over the runs of each state. 1% low and 0.1% low are the 99th and 99.9th percentile frame time.')
    $md.Add('')
    $md.AddRange([string[]]@(Format-MarkdownTable -Header 'State', 'Runs', 'Avg FPS', 'p50 (ms)', '1% low (ms)', '0.1% low (ms)', 'GPU busy p50 (ms)', 'CPU busy p50 (ms)', 'GPU busy (% of the p50 frame)', 'Parked during the run', 'Game Mode profile in the window' -Rows @($states | Where-Object { $_.step -eq $gameStep -and -not $_.PSObject.Properties['fpsMax'] } | ForEach-Object { , @((Format-StateLabel $_.label), $_.boots.Count, (Format-Spread $_.avgFps), (Format-Spread $_.p50Ms), (Format-Spread $_.low1PctMs), (Format-Spread $_.low01PctMs), (Format-Spread $_.gpuBusyP50Ms), (Format-Spread $_.cpuBusyP50Ms), (Format-Spread $_.gpuBusySharePct), (Format-Spread $_.parkedDuringRun), ('{0} of {1}' -f $_.gameModeProfileSteps.steps, $_.gameModeProfileSteps.of)) })))
    $md.Add('')
    $md.Add('## Capped game')
    $md.Add('')
    $md.Add('Median [min-max] over the runs of each state. Average FPS and p50 are load checks; the cap period is 1000 / fps_max ms; a slow frame is longer than the cap period times the bench factor.')
    $md.Add('')
    $md.AddRange([string[]]@(Format-MarkdownTable -Header 'State', 'Runs', 'fps_max', 'Avg FPS', 'p50 (ms)', '0.1% low (ms)', '1% low (ms)', '0.1% low over the cap period (ms)', '1% low over the cap period (ms)', 'Slow frames', 'Parked during the run' -Rows @($states | Where-Object { $_.PSObject.Properties['fpsMax'] } | ForEach-Object { , @((Format-StateLabel $_.label), $_.boots.Count, $_.fpsMax, (Format-Spread $_.avgFps), (Format-Spread $_.p50Ms), (Format-Spread $_.low01PctMs), (Format-Spread $_.low1PctMs), (Format-Spread $_.low01PctMsOverPeriod), (Format-Spread $_.low1PctMsOverPeriod), (Format-Spread $_.slowFrames), (Format-Spread $_.parkedDuringRun)) })))
    $md.Add('')
    $md.Add('## Table to file map')
    $md.Add('')
    $md.AddRange([string[]]@(Format-MarkdownTable -Header 'Table', 'File', 'Fields', 'Needs the private runner' -Rows @($fileMap | ForEach-Object { , @($_.table, $_.files, $_.fields, $(if ($_.runner) { 'yes' } else { 'no' })) })))
    $md.Add('')
    $md.Add('## Boots and files')
    $md.Add('')
    $md.AddRange([string[]]@(Format-MarkdownTable -Header 'State', 'Step', 'Boots', 'Bench JSON files' -Rows @($states | ForEach-Object { , @((Format-StateLabel $_.label), $_.step, ($_.boots -join ', '), ($_.benchFiles -join ', ')) })))

    [pscustomobject]@{ Markdown = ($md -join "`n") + "`n"; Summary = [pscustomobject]$summary }
}

if ($MyInvocation.InvocationName -ne '.') {
    $report = New-SeriesReport -SeriesPath $SeriesPath -ChecksOnly:$ChecksOnly
    if ($MarkdownPath) { Write-TextFile -Path $MarkdownPath -Text $report.Markdown } else { $report.Markdown }
    if ($SummaryPath) { Write-TextFile -Path $SummaryPath -Text ((ConvertTo-Json -InputObject $report.Summary -Depth 12) + "`n") }
}
