<#
.SYNOPSIS
    Core-parking micro-benchmark: frame pacing + throughput, no installs, no admin.

.DESCRIPTION
    Measures what CPU core parking actually costs in three comparable states
    (run it once per state, e.g. stock / parking forced / after cpu-parking-disabler):

      1. Frame simulator: N worker threads each burn a fixed slice of integer math
         per "frame" at a 144 Hz cadence. Reports p50/p99/max frame time and the
         share of frames that blew the 6.944 ms budget. This is the stutter metric:
         parking hurts the tail, not the average.
      2. Parked-core count from the '\Processor Information(*)\Parking Status'
         performance counters, sampled before and after the run.

    The math slice is calibrated once and cached in bench-config.json next to this
    script, so every later run (and every power state) executes the exact same work.
    Delete bench-config.json to recalibrate on a different machine.

    For an independent throughput number, pair it with the 7-Zip benchmark:
        7zr b 3 -mmt32     (multi-thread)
        7zr b 3 -mmt1      (single-thread)

    These are the tools behind the numbers in the RigPolice article:
    https://rigpolice.com/system/articles/disable-cpu-core-parking/

.EXAMPLE
    .\bench.ps1 -Phase stock
    # ...change power settings...
    .\bench.ps1 -Phase parked
    # ...run cpu-parking-disabler...
    .\bench.ps1 -Phase tweaked
#>
param(
    [Parameter(Mandatory)][string]$Phase,
    [int]$Workers = 8,
    [double]$BudgetMs = 6.944,
    [int]$Frames = 4300
)
$ErrorActionPreference = 'Stop'
$outDir = $PSScriptRoot

Add-Type -TypeDefinition @'
using System;
using System.Diagnostics;
using System.Threading;
public static class ParkBench {
    // xorshift64 keeps the loop pure ALU work: no memory pressure, no allocations.
    public static long Work(long iters) {
        unchecked {
            ulong x = 88172645463325252UL; long s = 0;
            for (long i = 0; i < iters; i++) { x ^= x << 13; x ^= x >> 7; x ^= x << 17; s += (long)(x & 0xFF); }
            return s;
        }
    }
    public static double CalibrateItersPerMs(int ms) {
        Work(2000000); // JIT warmup
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
            barrier.SignalAndWait();  // frame start
            barrier.SignalAndWait();  // all workers done
            results[f] = sw.Elapsed.TotalMilliseconds - t0;
        }
        foreach (var t in threads) t.Join();
        return results;
    }
}
'@

function Get-ParkedCount {
    ((Get-Counter '\Processor Information(*)\Parking Status').CounterSamples |
        Where-Object { $_.InstanceName -match '^\d+,\d+$' -and $_.CookedValue -eq 1 }).Count
}

# Calibrate once, then reuse the cached work size for every phase.
$cfgPath = Join-Path $outDir 'bench-config.json'
if (Test-Path $cfgPath) {
    $cfg = Get-Content $cfgPath | ConvertFrom-Json
} else {
    Write-Host 'Calibrating work slice (first run only)...'
    $ipms = [ParkBench]::CalibrateItersPerMs(800)
    @{ itersPerMs = $ipms; workIters = [long]($ipms * 2.5) } | ConvertTo-Json | Set-Content $cfgPath
    $cfg = Get-Content $cfgPath | ConvertFrom-Json
}

$parkedBefore = Get-ParkedCount
$ft = [ParkBench]::FrameSim($Workers, $BudgetMs, [long]$cfg.workIters, $Frames)
$parkedAfter = Get-ParkedCount

$sorted = $ft | Sort-Object
$n = $sorted.Count
$result = [pscustomobject]@{
    phase         = $Phase
    parkedBefore  = $parkedBefore
    parkedAfter   = $parkedAfter
    frameAvgMs    = [math]::Round(($ft | Measure-Object -Average).Average, 3)
    frameP50Ms    = [math]::Round($sorted[[int]($n * 0.50)], 3)
    frameP99Ms    = [math]::Round($sorted[[int]($n * 0.99)], 3)
    frameMaxMs    = [math]::Round(($ft | Measure-Object -Maximum).Maximum, 3)
    overBudgetPct = [math]::Round(100.0 * (@($ft | Where-Object { $_ -gt $BudgetMs }).Count) / $n, 2)
}
$result | ConvertTo-Json | Set-Content (Join-Path $outDir "bench-$Phase.json")
$result | Format-List
