<#
.SYNOPSIS
    Core-parking bench: a multi-thread burst after idle, a frame simulator and a
    PresentMon capture of a running game, each with the parked-core count.

.DESCRIPTION
    Run it once per power state (stock, CPMINCORES only, PERFEPP only, both)
    and compare the states inside one series of runs on one machine.

      -Test burst (default)
         One worker thread per logical CPU waits on an event. After
         -IdleSeconds of idle the bench samples the parked-core count, releases
         every worker at once and records the work done in each -WindowMs
         window for -BurstMs. Parked cores show up as less work in the first
         windows. A single-thread test cannot see parking: one core always
         stays unparked.
      -Test framesim
         -Workers threads burn a fixed slice of integer math per frame at a
         -BudgetMs cadence. Writes every frame time and the parked count
         sampled every 250 ms.
      -Test game -Load cs2 -PresentMon <path>
         Waits for the load's process and, for CS2, for the route start in the
         game's console log, then captures frame times with PresentMon and
         samples the parked count every 250 ms. The recipe is loads\<load>.json.

    The parked count reads '\Processor Information(<n>)\Parking Status' through
    PdhAddEnglishCounter, so it works on every Windows display language.

    The math slice is calibrated once and cached in parking-bench-config.json
    next to this script, so every later run executes the same work. Delete it
    to recalibrate on a different machine.

    These are the tools behind the numbers in the RigPolice article:
    https://rigpolice.com/system/articles/disable-cpu-core-parking/

.EXAMPLE
    .\parking-bench.ps1 -Phase stock
    .\parking-bench.ps1 -Phase stock -Test framesim
    .\parking-bench.ps1 -Phase stock -Test game -Load cs2 -PresentMon .\PresentMon-2.6.0-x64.exe
#>
param(
    [Parameter(Mandatory)][string]$Phase,
    [ValidateSet('burst', 'framesim', 'game')][string]$Test = 'burst',
    [string]$OutDir = $PSScriptRoot,
    [int]$Bursts = 50,
    [double]$IdleSeconds = 2,
    [int]$BurstMs = 200,
    [double]$WindowMs = 1,
    [int]$Threads = 0,
    [int]$Workers = 8,
    [double]$BudgetMs = 6.944,
    [int]$Frames = 4300,
    [string]$Load,
    [string]$PresentMon
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'bench-env.ps1')

$parkBenchSource = @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading;

public static class ParkBench {
    [StructLayout(LayoutKind.Sequential)]
    struct PowerThrottlingState { public uint Version; public uint ControlMask; public uint StateMask; }

    [StructLayout(LayoutKind.Sequential)]
    struct ProcessorNumber { public ushort Group; public byte Number; public byte Reserved; }

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool SetProcessInformation(IntPtr process, int infoClass, ref PowerThrottlingState info, int size);

    [DllImport("kernel32.dll")]
    static extern IntPtr GetCurrentProcess();

    [DllImport("kernel32.dll")]
    static extern void GetCurrentProcessorNumberEx(out ProcessorNumber number);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool GetSystemCpuSetInformation(IntPtr information, int bufferLength, out int returnedLength, IntPtr process, int flags);

    static int[] cpuGroup = new int[0];
    static int[] cpuNumber = new int[0];

    public static int[] CpuEfficiencyClass = new int[0];

    public static bool SetHighQos() {
        var state = new PowerThrottlingState { Version = 1, ControlMask = 1, StateMask = 0 };
        return SetProcessInformation(GetCurrentProcess(), 4, ref state, Marshal.SizeOf(typeof(PowerThrottlingState)));
    }

    public static int LoadCpuSets() {
        int length;
        GetSystemCpuSetInformation(IntPtr.Zero, 0, out length, IntPtr.Zero, 0);
        if (length <= 0) return 0;
        IntPtr buffer = Marshal.AllocHGlobal(length);
        try {
            if (!GetSystemCpuSetInformation(buffer, length, out length, IntPtr.Zero, 0)) return 0;
            var groups = new List<int>(); var numbers = new List<int>(); var classes = new List<int>();
            for (int offset = 0; offset < length; ) {
                int size = Marshal.ReadInt32(buffer, offset);
                if (size <= 0) break;
                if (Marshal.ReadInt32(buffer, offset + 4) == 0) {
                    groups.Add(Marshal.ReadInt16(buffer, offset + 12));
                    numbers.Add(Marshal.ReadByte(buffer, offset + 14));
                    classes.Add(Marshal.ReadByte(buffer, offset + 18));
                }
                offset += size;
            }
            cpuGroup = groups.ToArray(); cpuNumber = numbers.ToArray(); CpuEfficiencyClass = classes.ToArray();
            return CpuEfficiencyClass.Length;
        } finally { Marshal.FreeHGlobal(buffer); }
    }

    public static int CurrentCpu() {
        ProcessorNumber n;
        GetCurrentProcessorNumberEx(out n);
        for (int i = 0; i < cpuGroup.Length; i++) { if (cpuGroup[i] == n.Group && cpuNumber[i] == n.Number) return i; }
        return -1;
    }

    public static long Work(long iters) {
        unchecked {
            ulong x = 88172645463325252UL; long s = 0;
            for (long i = 0; i < iters; i++) { x ^= x << 13; x ^= x >> 7; x ^= x << 17; s += (long)(x & 0xFF); }
            return s;
        }
    }

    public static double CalibrateItersPerMs(int ms) {
        Work(2000000);
        var sw = Stopwatch.StartNew(); long it = 0;
        while (sw.ElapsedMilliseconds < ms) { Work(200000); it += 200000; }
        return it / sw.Elapsed.TotalMilliseconds;
    }

    public static double[] FrameSim(int workers, double budgetMs, long workIters, int frames) {
        var results = new double[frames];
        var barrier = new Barrier(workers + 1);
        var threads = new Thread[workers];
        for (int i = 0; i < workers; i++) {
            threads[i] = new Thread(() => {
                for (int f = 0; f < frames; f++) {
                    barrier.SignalAndWait();
                    Work(workIters);
                    barrier.SignalAndWait();
                }
            });
            threads[i].IsBackground = true; threads[i].Start();
        }
        var sw = Stopwatch.StartNew();
        for (int f = 0; f < frames; f++) {
            double target = f * budgetMs;
            while (sw.Elapsed.TotalMilliseconds < target) { Thread.SpinWait(200); }
            double t0 = sw.Elapsed.TotalMilliseconds;
            barrier.SignalAndWait();
            barrier.SignalAndWait();
            results[f] = sw.Elapsed.TotalMilliseconds - t0;
        }
        foreach (var t in threads) t.Join();
        return results;
    }

    public sealed class BurstResult {
        public long[,] Work;
        public double[,] WakeMs;
        public int[] ParkedBefore;
        public int[,] CpuAtWake;
        public int[,] CpuAtEnd;
    }

    public static BurstResult Burst(int threads, long chunkIters, int windows, double windowMs, int bursts, int idleMs, ParkCounter counter) {
        var result = new BurstResult { Work = new long[bursts, windows], WakeMs = new double[bursts, threads], ParkedBefore = new int[bursts], CpuAtWake = new int[bursts, threads], CpuAtEnd = new int[bursts, threads] };
        var start = new ManualResetEvent[bursts];
        for (int b = 0; b < bursts; b++) start[b] = new ManualResetEvent(false);
        var done = new CountdownEvent(threads);
        var sw = Stopwatch.StartNew();
        double msPerTick = 1000.0 / Stopwatch.Frequency;
        long[] t0 = new long[bursts];
        var workers = new Thread[threads];
        for (int i = 0; i < threads; i++) {
            int id = i;
            workers[i] = new Thread(() => {
                Work(chunkIters * 10);
                var local = new long[windows];
                for (int b = 0; b < bursts; b++) {
                    start[b].WaitOne();
                    long origin = Volatile.Read(ref t0[b]);
                    result.WakeMs[b, id] = (sw.ElapsedTicks - origin) * msPerTick;
                    result.CpuAtWake[b, id] = CurrentCpu();
                    Array.Clear(local, 0, windows);
                    while (true) {
                        Work(chunkIters);
                        int w = (int)(((sw.ElapsedTicks - origin) * msPerTick) / windowMs);
                        if (w >= windows) break;
                        local[w] += chunkIters;
                    }
                    result.CpuAtEnd[b, id] = CurrentCpu();
                    for (int w = 0; w < windows; w++) Interlocked.Add(ref result.Work[b, w], local[w]);
                    done.Signal();
                }
            });
            workers[i].IsBackground = true; workers[i].Start();
        }
        for (int b = 0; b < bursts; b++) {
            Thread.Sleep(idleMs);
            result.ParkedBefore[b] = counter == null ? -1 : counter.Sample();
            done.Reset(threads);
            Volatile.Write(ref t0[b], sw.ElapsedTicks);
            start[b].Set();
            done.Wait();
        }
        foreach (var t in workers) t.Join();
        return result;
    }
}

public sealed class ParkCounter : IDisposable {
    [StructLayout(LayoutKind.Sequential)]
    struct FmtValue { public uint CStatus; public long LargeValue; }

    [DllImport("pdh.dll", CharSet = CharSet.Unicode)]
    static extern uint PdhOpenQueryW(string source, IntPtr userData, out IntPtr query);
    [DllImport("pdh.dll", CharSet = CharSet.Unicode)]
    static extern uint PdhAddEnglishCounterW(IntPtr query, string path, IntPtr userData, out IntPtr counter);
    [DllImport("pdh.dll")]
    static extern uint PdhCollectQueryData(IntPtr query);
    [DllImport("pdh.dll")]
    static extern uint PdhGetFormattedCounterValue(IntPtr counter, uint format, IntPtr type, out FmtValue value);
    [DllImport("pdh.dll")]
    static extern uint PdhCloseQuery(IntPtr query);

    const uint FormatLarge = 0x00000400;
    readonly object gate = new object();
    IntPtr query;
    readonly IntPtr[] counters;
    Thread sampler;
    volatile bool stopping;
    readonly List<double> times = new List<double>();
    readonly List<int> values = new List<int>();

    public ParkCounter(string[] instances) {
        uint status = PdhOpenQueryW(null, IntPtr.Zero, out query);
        if (status != 0) throw new InvalidOperationException("PdhOpenQuery failed: 0x" + status.ToString("X8"));
        counters = new IntPtr[instances.Length];
        for (int i = 0; i < instances.Length; i++) {
            string path = "\\Processor Information(" + instances[i] + ")\\Parking Status";
            status = PdhAddEnglishCounterW(query, path, IntPtr.Zero, out counters[i]);
            if (status != 0) throw new InvalidOperationException("PdhAddEnglishCounter " + path + " failed: 0x" + status.ToString("X8"));
        }
    }

    public int Sample() {
        lock (gate) {
            if (PdhCollectQueryData(query) != 0) return -1;
            int parked = 0;
            foreach (var c in counters) {
                FmtValue v;
                if (PdhGetFormattedCounterValue(c, FormatLarge, IntPtr.Zero, out v) != 0 || v.CStatus > 1) return -1;
                if (v.LargeValue == 1) parked++;
            }
            return parked;
        }
    }

    public void StartSampling(int intervalMs) {
        var sw = Stopwatch.StartNew();
        stopping = false;
        sampler = new Thread(() => {
            while (!stopping) {
                int parked = Sample();
                lock (times) { times.Add(sw.Elapsed.TotalMilliseconds); values.Add(parked); }
                Thread.Sleep(intervalMs);
            }
        });
        sampler.IsBackground = true;
        sampler.Start();
    }

    public void StopSampling() {
        stopping = true;
        if (sampler != null) { sampler.Join(); sampler = null; }
    }

    public double[] SampleTimes { get { lock (times) { return times.ToArray(); } } }
    public int[] SampleValues { get { lock (times) { return values.ToArray(); } } }

    public void Dispose() {
        StopSampling();
        if (query != IntPtr.Zero) { PdhCloseQuery(query); query = IntPtr.Zero; }
    }
}
'@

function Get-ProcessorInstanceName {
    @(Get-CimInstance -ClassName Win32_PerfRawData_Counters_ProcessorInformation -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^\d+,\d+$' } | ForEach-Object { $_.Name })
}

function Get-SpreadSummary {
    param([double[]]$Values)
    $sorted = [double[]]@($Values | Sort-Object)
    if (-not $sorted.Count) { return $null }
    [pscustomobject]@{
        median = Get-Percentile $sorted 0.50
        min = [math]::Round($sorted[0], 3)
        max = [math]::Round($sorted[-1], 3)
    }
}

function Get-CoreClassSummary {
    param([Parameter(Mandatory)][int[,]]$Cpu, [Parameter(Mandatory)][int[]]$EfficiencyClass)
    $classes = @($EfficiencyClass | Sort-Object -Unique)
    $counts = @{}
    foreach ($c in $classes) { $counts[$c] = 0 }
    $unknown = 0
    $total = 0
    for ($b = 0; $b -lt $Cpu.GetLength(0); $b++) {
        for ($t = 0; $t -lt $Cpu.GetLength(1); $t++) {
            $index = $Cpu[$b, $t]
            $total++
            if ($index -lt 0 -or $index -ge $EfficiencyClass.Count) { $unknown++ } else { $counts[$EfficiencyClass[$index]]++ }
        }
    }
    [pscustomobject]@{
        logicalCpusPerClass = @($classes | ForEach-Object { $cls = $_; [pscustomobject]@{ efficiencyClass = $cls; cpus = @($EfficiencyClass | Where-Object { $_ -eq $cls }).Count } })
        threadShareAtEndPerClass = @($classes | ForEach-Object { [pscustomobject]@{ efficiencyClass = $_; share = $(if ($total) { [math]::Round($counts[$_] / $total, 4) } else { $null }) } })
        unknown = $unknown
    }
}

function Get-ParkedSummary {
    param([int[]]$Values, [int]$Total)
    $valid = [double[]]@($Values | Where-Object { $_ -ge 0 })
    [pscustomobject]@{
        logicalCpus = $Total
        samples = $Values.Count
        unavailable = $Values.Count - $valid.Count
        parked = Get-SpreadSummary -Values $valid
    }
}

function Get-BurstSummary {
    param(
        [Parameter(Mandatory)][long[,]]$Work,
        [Parameter(Mandatory)][double[,]]$WakeMs,
        [Parameter(Mandatory)][double]$ItersPerMs,
        [Parameter(Mandatory)][double]$WindowMs,
        [double]$EarlyMs = 5
    )
    $bursts = $Work.GetLength(0)
    $windows = $Work.GetLength(1)
    $threads = $WakeMs.GetLength(1)
    $early = [math]::Min($windows, [int][math]::Ceiling($EarlyMs / $WindowMs))
    $earlyCoreMs = New-Object System.Collections.Generic.List[double]
    $totalCoreMs = New-Object System.Collections.Generic.List[double]
    $wakeMax = New-Object System.Collections.Generic.List[double]
    for ($b = 0; $b -lt $bursts; $b++) {
        $sumEarly = 0.0
        $sumAll = 0.0
        for ($w = 0; $w -lt $windows; $w++) {
            if ($w -lt $early) { $sumEarly += $Work[$b, $w] }
            $sumAll += $Work[$b, $w]
        }
        $earlyCoreMs.Add($sumEarly / $ItersPerMs)
        $totalCoreMs.Add($sumAll / $ItersPerMs)
        $max = 0.0
        for ($t = 0; $t -lt $threads; $t++) { $max = [math]::Max($max, ($WakeMs[$b, $t])) }
        $wakeMax.Add($max)
    }
    $curve = New-Object System.Collections.Generic.List[double]
    for ($w = 0; $w -lt $windows; $w++) {
        $column = New-Object System.Collections.Generic.List[double]
        for ($b = 0; $b -lt $bursts; $b++) { $column.Add(($Work[$b, $w]) / $ItersPerMs / $WindowMs) }
        $curve.Add((Get-Percentile ([double[]]@($column | Sort-Object)) 0.50))
    }
    [pscustomobject]@{
        earlyWindowMs = $early * $WindowMs
        earlyCoreMs = Get-SpreadSummary -Values $earlyCoreMs.ToArray()
        totalCoreMs = Get-SpreadSummary -Values $totalCoreMs.ToArray()
        lastWorkerWakeMs = Get-SpreadSummary -Values $wakeMax.ToArray()
        busyCoresPerWindowMedian = $curve.ToArray()
    }
}

function Write-ParkedSampleCsv {
    param([Parameter(Mandatory)]$Counter, [Parameter(Mandatory)][string]$Path)
    $times = $Counter.SampleTimes
    $values = $Counter.SampleValues
    $lines = for ($i = 0; $i -lt $times.Count; $i++) { (Format-Invariant $times[$i]) + ',' + $values[$i] }
    Write-CsvFile -Path $Path -Header 'ms,parked' -Lines @($lines)
    , [int[]]$values
}

function New-ParkCounter {
    $instances = Get-ProcessorInstanceName
    if (-not $instances.Count) { return $null }
    New-Object ParkCounter -ArgumentList (, [string[]]$instances)
}

if ($MyInvocation.InvocationName -ne '.') {
    Add-Type -TypeDefinition $parkBenchSource
    $highQos = [ParkBench]::SetHighQos()
    if (-not $highQos) { Write-Warning 'Could not opt this process out of power throttling: Windows may run it as EcoQoS on efficient cores.' }
    $cpuSets = [ParkBench]::LoadCpuSets()

    if (-not (Test-Path -Path $OutDir)) { throw "OutDir $OutDir does not exist." }
    $cfgPath = Join-Path $PSScriptRoot 'parking-bench-config.json'
    if (-not (Test-Path $cfgPath)) {
        Write-Host 'Calibrating work slice (first run only)...'
        $ipms = [ParkBench]::CalibrateItersPerMs(800)
        Write-BenchResult -Object ([pscustomobject]@{ itersPerMs = $ipms; workIters = [long]($ipms * 2.5) }) -Path $cfgPath
    }
    $cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json

    $base = Join-Path $OutDir "parking-bench-$Phase-$Test"
    $logical = [Environment]::ProcessorCount
    $counter = New-ParkCounter
    if (-not $counter) { Write-Warning 'Performance counters are unavailable: the parked count is not recorded.' }
    $result = [ordered]@{ test = $Test; phase = $Phase; highQos = $highQos }
    $files = New-Object System.Collections.Generic.List[string]

    try {
        switch ($Test) {
            'burst' {
                $threadCount = if ($Threads -gt 0) { $Threads } else { $logical }
                $windows = [int][math]::Ceiling($BurstMs / $WindowMs)
                $chunk = [long][math]::Max(1000, $cfg.itersPerMs * $WindowMs / 50)
                $metadata = Get-BenchMetadata -BenchScript $PSCommandPath
                Write-Host "Burst: $threadCount threads, $Bursts bursts of $BurstMs ms after $IdleSeconds s idle. Do not touch the PC."
                $r = [ParkBench]::Burst($threadCount, $chunk, $windows, $WindowMs, $Bursts, [int]($IdleSeconds * 1000), $counter)
                $workLines = for ($b = 0; $b -lt $Bursts; $b++) {
                    for ($w = 0; $w -lt $windows; $w++) { "$b,$(Format-Invariant ($w * $WindowMs)),$($r.Work[$b, $w]),$($r.ParkedBefore[$b])" }
                }
                Write-CsvFile -Path "$base-work.csv" -Header 'burst,windowStartMs,iterations,parkedBefore' -Lines @($workLines)
                $wakeLines = for ($b = 0; $b -lt $Bursts; $b++) {
                    for ($t = 0; $t -lt $threadCount; $t++) { "$b,$t,$(Format-Invariant ($r.WakeMs[$b, $t])),$($r.CpuAtWake[$b, $t]),$($r.CpuAtEnd[$b, $t])" }
                }
                Write-CsvFile -Path "$base-wake.csv" -Header 'burst,thread,wakeMs,cpuAtWake,cpuAtEnd' -Lines @($wakeLines)
                $files.Add("$base-work.csv")
                $files.Add("$base-wake.csv")
                $result.threads = $threadCount
                $result.bursts = $Bursts
                $result.idleSeconds = $IdleSeconds
                $result.burstMs = $BurstMs
                $result.windowMs = $WindowMs
                $result.chunkIterations = $chunk
                $result.itersPerMs = [math]::Round($cfg.itersPerMs, 1)
                $result.parkedBeforeBurst = Get-ParkedSummary -Values $r.ParkedBefore -Total $logical
                $result.burst = Get-BurstSummary -Work $r.Work -WakeMs $r.WakeMs -ItersPerMs $cfg.itersPerMs -WindowMs $WindowMs
                $result.cpuEfficiencyClass = @([ParkBench]::CpuEfficiencyClass)
                $result.coreClass = if ($cpuSets) { Get-CoreClassSummary -Cpu $r.CpuAtEnd -EfficiencyClass ([ParkBench]::CpuEfficiencyClass) } else { $null }
            }
            'framesim' {
                $metadata = Get-BenchMetadata -BenchScript $PSCommandPath
                if ($counter) { $counter.StartSampling(250) }
                $ft = [ParkBench]::FrameSim($Workers, $BudgetMs, [long]$cfg.workIters, $Frames)
                $parked = @()
                if ($counter) {
                    $counter.StopSampling()
                    $parked = Write-ParkedSampleCsv -Counter $counter -Path "$base-parked.csv"
                    $files.Add("$base-parked.csv")
                }
                $frameLines = for ($f = 0; $f -lt $ft.Count; $f++) { "$f,$(Format-Invariant $ft[$f])" }
                Write-CsvFile -Path "$base-frames.csv" -Header 'frame,ms' -Lines @($frameLines)
                $files.Add("$base-frames.csv")
                $sorted = [double[]]@($ft | Sort-Object)
                $result.workers = $Workers
                $result.budgetMs = $BudgetMs
                $result.frames = $ft.Count
                $result.frameAvgMs = [math]::Round(($ft | Measure-Object -Average).Average, 3)
                $result.frameP50Ms = Get-Percentile $sorted 0.50
                $result.frameP99Ms = Get-Percentile $sorted 0.99
                $result.frameP999Ms = Get-Percentile $sorted 0.999
                $result.frameMaxMs = [math]::Round($sorted[-1], 3)
                $result.overBudgetPct = [math]::Round(100.0 * (@($ft | Where-Object { $_ -gt $BudgetMs }).Count) / $ft.Count, 2)
                $result.parkedDuringRun = Get-ParkedSummary -Values $parked -Total $logical
            }
            'game' {
                if (-not $Load) { throw '-Test game needs -Load <name> (a file in bench\loads).' }
                if (-not $PresentMon) { throw '-Test game needs -PresentMon <path to the pinned PresentMon exe>.' }
                $recipe = Get-LoadRecipe -Name $Load
                Write-Host "Load: $($recipe.title). Start it as bench\README.md says; this window waits."
                if ($recipe.consoleLine) { Write-Host "Console line: $($recipe.consoleLine)" }
                $proc = Wait-LoadReady -Recipe $recipe
                $metadata = Get-BenchMetadata -BenchScript $PSCommandPath -Load $Load -PresentMonVersion $recipe.presentMon.version
                $loadRecord = Get-LoadRecord -Recipe $recipe -Name $Load -Process $proc
                if ($counter) { $counter.StartSampling(250) }
                $capture = Invoke-PresentMonCapture -PresentMonPath $PresentMon -ProcessName $recipe.presentMonProcess -OutputFile "$base-presentmon.csv" -Seconds $recipe.timings.captureSeconds -ExpectedSha256 $recipe.presentMon.sha256
                $files.Add("$base-presentmon.csv")
                $parked = @()
                if ($counter) {
                    $counter.StopSampling()
                    $parked = Write-ParkedSampleCsv -Counter $counter -Path "$base-parked.csv"
                    $files.Add("$base-parked.csv")
                }
                $stats = Import-Csv -Path $capture.csv | Get-FrameStats
                $result.load = $loadRecord
                $result.presentMon = [pscustomobject]@{ sha256 = $capture.presentMonSha256; overflowedPresents = $capture.overflowedPresents }
                $result.frames = $stats
                $result.rejected = Get-GameRejection -Stats $stats -Capture $capture -Video $loadRecord.videoConfig -Recipe $recipe
                $result.parkedDuringRun = Get-ParkedSummary -Values $parked -Total $logical
            }
        }
    } finally {
        if ($counter) { $counter.Dispose() }
    }

    $powerEnd = Get-PowerState
    $result.powerStateChanged = (($metadata.power | ConvertTo-Json -Depth 6 -Compress) -ne ($powerEnd | ConvertTo-Json -Depth 6 -Compress))
    $result.files = @($files | ForEach-Object { Split-Path -Leaf $_ })
    $result.powerEnd = $powerEnd
    $result.metadata = $metadata
    $out = [pscustomobject]$result
    Write-BenchResult -Object $out -Path "$base.json"
    $out | Select-Object -Property * -ExcludeProperty metadata, powerEnd | Format-List
    if ($result.powerStateChanged) { Write-Warning 'The power scheme or a processor setting changed during the run: compare this run with nothing.' }
    if ($result.rejected) { throw "Run rejected: $($result.rejected). The result file is kept." }
}
