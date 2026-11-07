# Raw results behind the core parking numbers

Every core parking benchmark number we publish comes from the files in [`parking-retest/`](parking-retest/). They are the
unedited output of [`../parking-bench.ps1`](../parking-bench.ps1), 100 runs recorded across 14 boots between
2026-11-05 21:35 and 2026-11-06 03:38. The per-frame PresentMon logs (842 MB) are too large for git. They are in the
release [`bench-data-parking-retest`](https://github.com/vadyaravadim/cpu-parking-disabler/releases/tag/bench-data-parking-retest)
as `parking-retest-presentmon.zip`, SHA256 `e874b8fd44a93e353ed954a544818fb4d46fcc02116a2bb33b793add10c1185b`.
The idle checks of Windows' default power plans are in [`testbed-checks/`](testbed-checks/), see [Testbed checks](#testbed-checks).

## Testbed

- Intel Core i9-14900F (8 P-cores, 16 E-cores, 32 logical CPUs), MSI MAG B760M MORTAR II (BIOS 1.C0), AMD Radeon
  RX 7800 XT (driver 32.0.32015.7029), 180 Hz monitor.
- Windows 11 Pro 26H2, build 26300.9818, Memory Integrity on. Every result file records the full environment.
- Power plan: Balanced at Windows' default values. On this CPU those are a 4% core parking minimum for the E-cores
  (`CPMINCORES`, set by the processor profile Windows ships for Raptor Lake desktops), 0% for the P-cores
  (`CPMINCORES1`) and energy performance preference 33 (`PERFEPP`, `PERFEPP1`) on AC power, the last two being
  Windows' generic Balanced values. That is the `stock` state below. Every state wrote its values to AC and DC alike;
  the desktop ran on AC power throughout.

## Procedure

- Every boot started from a reboot, then waited 300 s for startup activity to settle. 11 third-party services and 6
  scheduled tasks on the runner's block list were switched off for the whole series; `journal.jsonl` records the
  counts, not the names. Windows' own services kept running, Windows Update, Delivery Optimization, Search and SysMain
  included, and every result file lists the services that ran. A preflight refused to measure if a known offender
  (hardware monitors, overlays, capture tools, vendor updaters) was running.
- Inside a boot, each state was applied with `powercfg`, then measured twice: a `burst` test, then a `game` test.
- Main block: 8 boots, 4 states each, ordered by a Williams Latin square, so every state ran in every position
  equally often. Ceiling block: 6 boots, 3 states each, all 6 orders.
- `game`: Counter-Strike 2 build 1.41.9.6, 1280x720 fullscreen, no vsync, video settings from
  [`../loads/cs2_video.txt`](../loads/cs2_video.txt): every detail setting at its lowest except dynamic shadows, HDR
  and FSR, which hold the values of Valve's High and Very High presets. Workshop map 3240880604 (CS2 FPS BENCHMARK).
  The route starts by itself; the bench waits 15 s after it starts, then PresentMon 2.6.0 records 100 s with a
  16,384-event buffer. A run that loses any frame is rejected; this series lost none. The load is CPU-bound: in every
  run the CPU was busy for the whole median frame (`cpuBusyP50Ms` equals `p50Ms`), while the GPU was busy for 94 to
  96% of it (`gpuBusyP50Ms`). The runner checked the CS2 build of every run.
- `burst`: 50 bursts of 200 ms on 32 threads (one per logical CPU), with 2 s of idle before each burst, so the
  cores have time to park. It measures how much work the threads get done and how late the last one wakes up.

## States

| State | `CPMAXCORES` | `CPMINCORES` / `CPMINCORES1` | `PERFEPP` / `PERFEPP1` | Boots |
|---|---|---|---|---|
| `stock` | 100 | 4 / 0 | 33 / 33 | 8 |
| `min` | 100 | **100 / 100** | 33 / 33 | 8 |
| `epp` | 100 | 4 / 0 | **0 / 0** | 8 |
| `min+epp` | 100 | **100 / 100** | **0 / 0** | 8 |
| `ceil` | **25** | 4 / 0 | 33 / 33 | 6 |
| `ceil+min` | **25** | **100 / 100** | 33 / 33 | 6 |
| `ceil+epp` | **25** | 4 / 0 | **0 / 0** | 6 |

`min+epp` is what `cpu-parking-disabler.ps1` sets. The `ceil` states force parking with a 25% maximum, to show what
parking costs when it actually holds cores down.

## Results

CS2, one value per run (medians across runs; lower ms is better):

| State | n | Avg fps, median [min-max] | p50 ms | 1% low ms | 0.1% low ms | Parked CPUs during run |
|---|---|---|---|---|---|---|
| stock | 8 | 770.0 [764.7-774.0] | 1.124 | 3.90 | 4.34 | 8 |
| min | 8 | 769.3 [762.1-773.9] | 1.125 | 3.89 | 4.31 | 0 |
| epp | 8 | 771.4 [765.0-775.9] | 1.122 | 3.90 | 4.33 | 8 |
| min+epp | 8 | 769.0 [756.9-773.1] | 1.125 | 3.90 | 4.34 | 0 |
| ceil | 6 | 783.6 [776.0-792.1] | 1.096 | 3.95 | 4.41 | 24 |
| ceil+min | 6 | 769.1 [763.8-774.6] | 1.124 | 3.88 | 4.33 | 0 |
| ceil+epp | 6 | 778.0 [775.1-787.0] | 1.099 | 3.89 | 4.39 | 24 |

Medians of the run values, rounded half away from zero.

The ceiling block ran in boots 8 to 13, after the main block. In each of those 6 boots `ceil` beat `ceil+min` in
average fps, by 0.83% to 2.79%; against `ceil+epp` it ranged from -0.76% to +1.81%.

Burst test (medians across runs; parked counts are of 32 logical CPUs):

| State | n | Parked before burst | Core-ms per 200 ms burst, median [min-max] | Core-ms in first 5 ms | Last worker wakes, ms, median [min-max] |
|---|---|---|---|---|---|
| stock | 8 | 31 | 4807 [4787-4859] | 17.6 | 15.86 [15.43-19.21] |
| min | 8 | 0 | 4845 [4841-4887] | 22.1 | 0.31 [0.30-0.34] |
| epp | 8 | 31 | 4906 [4892-4972] | 92.9 | 16.09 [15.44-22.48] |
| min+epp | 8 | 0 | 4957 [4953-5004] | 106.7 | 0.26 [0.23-0.28] |
| ceil | 6 | 31 | 1490 [1486-1502] | 7.0 | 160.42 [149.03-161.38] |
| ceil+min | 6 | 0 | 4849 [4842-4852] | 22.1 | 0.34 [0.31-0.38] |
| ceil+epp | 6 | 31 | 1534 [1521-1540] | 35.3 | 160.68 [160.59-160.92] |

## Files

Names are `bootNN-stateNN-<test>`: the boot index (0 to 13) and the position inside that boot.

- `bootNN-stateNN-<test>.json`: the runner's record of the step: the state applied, the environment, CPU time per
  process during the run, and the list of bench files.
- `bootNN-stateNN-<test>-bench.log`: the console output of the bench.
- `parking-bench-bootNN-stateNN-burst.json` (+ `-work.csv`, `-wake.csv`): burst summary, work per 1 ms window, wake
  time of every thread.
- `parking-bench-bootNN-stateNN-game.json` (+ `-parked.csv`): frame statistics, CS2 build, PresentMon lost-frame
  count, parked CPUs sampled during the run. The matching `-presentmon.csv` is in the release archive.
- `journal.jsonl`: the runner's log of every boot, including the failed attempt below. `plan.json`: the full plan.
- User names, the machine name and account IDs are removed from every file; profile paths read `%USERPROFILE%`.

## Caveats

- **Boot 11 ran twice.** In the first attempt the `ceil+epp` burst and game runs and the `ceil+min` burst run
  finished, then the `ceil+min` game run stopped on a PowerShell error (`ConstructorInvokedThrowException`, in
  `journal.jsonl`). The runner discarded the boot and ran it again in full. The rerun wrote its results under the same
  names, so the three finished runs of the first attempt were overwritten: `boot11-state00-burst.json`,
  `boot11-state01-game.json` and `boot11-state02-burst.json` and their bench files hold the second attempt.
- Every run records one pending file operation, a delete of `gamingservicesproxy_17.dll.0` that Windows queues again
  at every boot. A reboot cannot clear it, so the preflight does not count a delete-only entry as a pending reboot; it
  refuses on a pending rename or a Windows Update or servicing reboot flag.
- Microsoft Defender (`MsMpEng`) used 8.4 to 17.9 s of CPU time during the first game run of every boot
  (`processCpuDelta`). The balanced order put every state in that slot equally often.
- One machine, one CPU, one game build. Treat it as one careful data point, and run the bench on your own PC.

## Testbed checks

[`testbed-checks/`](testbed-checks/) holds checks we ran on the same PC on 2026-11-07: what Windows' default Balanced
and High performance plans do on this CPU, and a run of the published script with its undo. The plan checks ran with
no user value for `CPMINCORES`, `CPMINCORES1`, `PERFEPP` or `PERFEPP1` in either plan, and the script run started from
Balanced in the same state. The PC ran everyday desktop apps during the checks, so they are not bench conditions: read the
parked counts as a snapshot of normal idle, not as bench data. On this CPU High performance does not turn parking off.
Windows gives it the same 4% minimum as Balanced, and at idle it parked 31 of 32 logical CPUs in our check.

- `qh-balanced.txt`, `qh-high-performance.txt`: `powercfg /qh` of every processor power setting of each plan.
- `qa-balanced.txt`, `qa-high-performance.txt`: `powercfg /qa` of the same plans, which also shows where each value
  comes from. Both plans read `CPMINCORES` 4 from `Provisioning` and `CPMINCORES1` 0 from `OS Default`. Balanced reads
  `PERFEPP` and `PERFEPP1` 33 on AC and 50 on DC; High performance reads 5 on AC and 0 on DC.
- `qa-overlay-max.txt`, `qa-overlay-min.txt`: the two power mode overlays of Windows 11 (`OVERLAY_SCHEME_MAX`,
  `OVERLAY_SCHEME_MIN`). They carry only `PERFEPP` and `PERFEPP1`, never a parking minimum: the Max Performance
  overlay sets both to 33 on AC, the Better Battery-life overlay to 50. No overlay was active during the checks.
- `parked-samples.json`: five rounds, each switching to Balanced and then to High performance. For each plan the
  check waited 60 s, then read `ParkingStatus` of every logical CPU from
  `Win32_PerfFormattedData_Counters_ProcessorInformation` once a second for 30 s. The median sample was 31 of 32
  parked on High performance in every round and 29 to 30 of 32 on Balanced. Single samples dropped lower when an app
  woke up.
- `status-balanced-<n>.txt`, `status-high-performance-<n>.txt`: the output of `cpu-parking-disabler.ps1 -Status` after
  the samples of each plan in each round, from a development build of the script.
- `sample-run.txt`: the run quoted in the main README. The published v1.3.1 one-liner, started from an admin terminal
  on Balanced after 120 s of idle. The user folder is shown as `you`.
- `sample-undo.txt`: `-Undo` of that run, from the saved copy of the script.
- `undo-check.txt`: Balanced right after that undo. No user value is left for the four settings (`reg query`),
  `CPMINCORES` reads 4 from `Provisioning` and the other three come from `OS Default` (`powercfg /qa`), and the
  effective values are back to 4, 0, 33 and 33 on AC (`powercfg /qh`). The last part is `-Status` after 30 s of idle.
