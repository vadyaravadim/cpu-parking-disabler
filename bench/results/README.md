# Raw results behind the core parking numbers

Every core parking number we publish comes from the files in [`parking-retest/`](parking-retest/). They are the
unedited output of [`../parking-bench.ps1`](../parking-bench.ps1), 100 runs recorded across 14 boots between
2026-11-05 21:35 and 2026-11-06 03:38. The per-frame PresentMon logs (842 MB) are too large for git. They are in the
release [`bench-data-parking-retest`](https://github.com/vadyaravadim/cpu-parking-disabler/releases/tag/bench-data-parking-retest)
as `parking-retest-presentmon.zip`, SHA256 `e874b8fd44a93e353ed954a544818fb4d46fcc02116a2bb33b793add10c1185b`.
## Testbed

- Intel Core i9-14900F (8 P-cores, 16 E-cores, 32 logical CPUs), MSI MAG B760M MORTAR II (BIOS 1.C0), AMD Radeon
  RX 7800 XT (driver 32.0.32015.7029), 180 Hz monitor.
- Windows 11 Pro 26H2, build 26300.9818, Memory Integrity on. Every result file records the full environment.
- Power plan: Balanced. On this CPU, Windows ships Balanced with a 4% core parking minimum (`CPMINCORES`) and
  energy performance preference 33 (`PERFEPP`) on AC power. That is the `stock` state below.

## Procedure

- Every boot started from a reboot, then waited 300 s for startup activity to settle. Background services, scheduled
  tasks and startup apps that could interfere were switched off for the whole series, and a preflight refused to
  measure if a known offender (hardware monitors, overlays, capture tools, updaters) was running.
- Inside a boot, each state was applied with `powercfg`, then measured twice: a `burst` test, then a `game` test.
- Main block: 8 boots, 4 states each, ordered by a Williams Latin square, so every state ran in every position
  equally often. Ceiling block: 6 boots, 3 states each, all 6 orders.
- `game`: Counter-Strike 2 build 1.41.9.6, DirectX 11, 1280x720, low settings, no vsync, workshop map
  3240880604 (CS2 FPS BENCHMARK). The route starts by itself; the bench waits 15 s after it starts, then
  PresentMon 2.6.0 records 100 s with a 16,384-event buffer: at this frame rate the default buffer drops frames
  and lowers the average by about 1%. A run that loses any frame is rejected; this series lost none. The load is CPU-bound: at 640x360 the frame rate barely moves. Steam ran in
  offline mode so the game could not update during the series, and the runner checked the build of every run.
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
| min | 8 | 769.2 [762.1-773.9] | 1.125 | 3.89 | 4.31 | 0 |
| epp | 8 | 771.4 [765.0-775.9] | 1.122 | 3.90 | 4.33 | 8 |
| min+epp | 8 | 769.0 [756.9-773.1] | 1.125 | 3.90 | 4.34 | 0 |
| ceil | 6 | 783.5 [776.0-792.1] | 1.096 | 3.95 | 4.41 | 24 |
| ceil+min | 6 | 769.0 [763.8-774.6] | 1.124 | 3.88 | 4.33 | 0 |
| ceil+epp | 6 | 778.0 [775.1-787.0] | 1.099 | 3.89 | 4.39 | 24 |

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

- **Boot 11 was run twice.** In the first attempt the bench crashed 34 s after CS2 started, before the capture
  window, so it recorded no frames. The runner discarded the boot and ran it again in full; `journal.jsonl` has both.
- One machine, one CPU, one game build. Treat it as one careful data point, and run the bench on your own PC.
