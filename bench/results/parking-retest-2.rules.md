# Pre-registered rules: parking-retest-2 and parking-retest-2-ceiling

This file fixes how the two series are measured and read. It was committed before either series ran. After that
commit only the `## Amendments` section at the end may change, and every amendment is dated and written before
any outcome it affects is read.

The tables of both series are the output of [`bench/tools/Get-ParkingSeriesTable.ps1`](../tools/Get-ParkingSeriesTable.ps1).
No outcome is read any other way, and the section "Pre-registered comparisons" below is that script's own
rules block, copied without a change.

## What is measured

- `parking-retest-2`: nine units in every boot, 18 boots. The order of the units is a 9 by 9 Williams square
  followed by the same square with every row reversed, so each unit sits in each position twice and follows
  each other unit twice.
- `parking-retest-2-ceiling`: three units in every boot, 6 boots, one for each of the six orders. These states
  cap the unparked cores with `CPMAXCORES` 25. They are forced, they show the ceiling of the effect, and they
  are not what a PC does by itself.
- A unit with two steps runs `parking-bench.ps1` (the burst test) and then
  `parking-bench.ps1 -Test game -Load cs2`. A unit with one step runs the game test only. The capped units add
  `-FpsMax 144`. [`bench/README.md`](../README.md) has the procedure and what the bench rejects.
- Every boot waits 300 s after sign-in before its first step. Every game step captures 100 s of the CS2
  workshop benchmark map.
- Each state sets the five power values of the table below on the Balanced plan, for AC and DC, and Game Mode
  through `AutoGameModeEnabled`. Nothing else differs between the states of a series.

## Failed boots

- When a step of a boot fails, the runner moves every file of that boot to `failed\` and measures the boot
  again in the same order. The published series keeps the `failed\` folder.
- Only boots that the journal marks as a success are read. A failed attempt is listed with its public reason
  and is never read for an outcome.
- A series that stops before its last boot is not read. How it is resumed is an amendment, written before any
  outcome is read.

## What is never done

- No number of the one-boot rehearsal of 2026-11-24 is published or used by a rule.
- No test and no number is taken across the two series: they ran as separate chains.
- No boot or step is measured again because of what its outcome was.
- No outcome is read before the checks of the script passed (`-ChecksOnly` prints the checks alone).

## Pre-registered comparisons

These rules were fixed in this script before any outcome of the series was read.

| Unit | CPMAXCORES | CPMINCORES | CPMINCORES1 | PERFEPP | PERFEPP1 | Game Mode | fps_max | Steps |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| stock | 100 | 4 | 0 | 33 | 33 | on | off | burst, game |
| min | 100 | 100 | 100 | 33 | 33 | on | off | burst, game |
| epp | 100 | 4 | 0 | 0 | 0 | on | off | burst, game |
| min-epp | 100 | 100 | 100 | 0 | 0 | on | off | burst, game |
| cap-stock | 100 | 4 | 0 | 33 | 33 | on | 144 | game |
| cap-min | 100 | 100 | 100 | 33 | 33 | on | 144 | game |
| cap-min-epp | 100 | 100 | 100 | 0 | 0 | on | 144 | game |
| gm-off-stock | 100 | 4 | 0 | 33 | 33 | off | off | game |
| gm-off-epp | 100 | 4 | 0 | 0 | 0 | off | off | game |
| maxcores25 (forced: the ceiling) | 25 | 4 | 0 | 33 | 33 | on | off | burst, game |
| maxcores25-min (forced: the ceiling) | 25 | 100 | 100 | 33 | 33 | on | off | burst, game |
| maxcores25-epp (forced: the ceiling) | 25 | 4 | 0 | 0 | 0 | on | off | burst, game |

| Series | Block | Boots | Units, every step once in every boot |
| --- | --- | --- | --- |
| parking-retest-2 | main | 18 | stock, min, epp, min-epp, cap-stock, cap-min, cap-min-epp, gm-off-stock, gm-off-epp |
| parking-retest-2-ceiling | ceiling | 6 | maxcores25, maxcores25-min, maxcores25-epp |

| Block | # | Comparison | Metric | Better | Margin (share of the reference median) | Row | Label |
| --- | --- | --- | --- | --- | --- | --- | --- |
| main | 1 | min vs stock | Burst wake, median of the run (ms) | lower | 10% | tested | - |
| main | 2 | epp vs stock | Burst wake, median of the run (ms) | lower | 10% | tested | - |
| main | 3 | min-epp vs stock | Burst wake, median of the run (ms) | lower | 10% | tested | mixed effect: the script's two changes |
| main | 4 | min vs stock | Average FPS | higher | 1% | tested | - |
| main | 5 | min vs stock | 1% low (ms) | lower | 3.3% | tested | - |
| main | 6 | epp vs stock | Average FPS | higher | 1% | tested | - |
| main | 7 | epp vs stock | 1% low (ms) | lower | 3.3% | tested | - |
| main | 8 | min-epp vs stock | Average FPS | higher | 1% | tested | mixed effect: the script's two changes |
| main | 9 | min-epp vs stock | 1% low (ms) | lower | 3.3% | tested | mixed effect: the script's two changes |
| main | 10 | gm-off-stock vs stock | Average FPS | higher | 1% | tested | - |
| main | 11 | gm-off-stock vs stock | 1% low (ms) | lower | 3.3% | tested | - |
| main | 12 | gm-off-epp vs gm-off-stock | Average FPS | higher | 1% | tested | - |
| main | 13 | gm-off-epp vs gm-off-stock | 1% low (ms) | lower | 3.3% | tested | - |
| main | 14 | (epp - stock) - (gm-off-epp - gm-off-stock) | Average FPS | higher | 1% | tested | - |
| main | 15 | (epp - stock) - (gm-off-epp - gm-off-stock) | 1% low (ms) | lower | 3.3% | tested | - |
| main | 16 | cap-min vs cap-stock | 0.1% low (ms) | lower | 3.3% | tested | - |
| main | 17 | cap-min vs cap-stock | 1% low (ms) | lower | 3.3% | tested | - |
| main | 18 | cap-min-epp vs cap-min | 0.1% low (ms) | lower | 3.3% | tested | - |
| main | 19 | cap-min-epp vs cap-min | 1% low (ms) | lower | 3.3% | tested | - |
| main | 20 | cap-min-epp vs cap-stock | 0.1% low (ms) | lower | 3.3% | tested | mixed effect: the script's two changes |
| main | 21 | cap-min-epp vs cap-stock | 1% low (ms) | lower | 3.3% | tested | mixed effect: the script's two changes |
| ceiling | 1 | maxcores25-min (forced: the ceiling) vs maxcores25 (forced: the ceiling) | Burst wake, median of the run (ms) | lower | 10% | tested | - |
| ceiling | - | maxcores25-min (forced: the ceiling) vs maxcores25 (forced: the ceiling) | Average FPS | higher | - | described | - |
| ceiling | - | maxcores25-min (forced: the ceiling) vs maxcores25 (forced: the ceiling) | 1% low (ms) | lower | - | described | - |
| ceiling | - | maxcores25-epp (forced: the ceiling) vs maxcores25 (forced: the ceiling) | Burst wake, median of the run (ms) | lower | - | described | - |
| ceiling | - | maxcores25-epp (forced: the ceiling) vs maxcores25 (forced: the ceiling) | Average FPS | higher | - | described | - |
| ceiling | - | maxcores25-epp (forced: the ceiling) vs maxcores25 (forced: the ceiling) | 1% low (ms) | lower | - | described | - |

- Pairs: each comparison takes d = state minus reference within each boot; the interaction row takes d = (epp - stock) - (gm-off-epp - gm-off-stock) within each boot.
- Test: the exact two-sided Wilcoxon signed-rank test. A boot with d = 0 leaves the test and counts as level; tied |d| take their mid-rank; p is the share of the 2^n sign patterns of the n boots left whose rank sum lies at least as far from its mean as the observed one.
- Family: Holm over the tested rows of one block at alpha 0.05; the main block and the ceiling block are separate families.
- Shift: the Hodges-Lehmann estimate, the median of the n(n+1)/2 Walsh averages of d over all boots of the row, with the interval [W(k), W(N+1-k)] at no less than 90% confidence, k from the signed-rank distribution without ties; no interval for 4 boots or fewer.
- Margin: the share above of the reference median over the boots of the row; the interaction row takes the stock median.
- Verdict, first match: (1) helped or hurt when the Holm-adjusted p is under 0.05, by the direction and the better side of the metric; (2) cannot show when the comparison changes CPMINCORES and the median parked count of the reference state over the boots of the row is 0 (parked before the burst, or during the game); (3) cannot tell when at least one boot differs and every boot that differs lies on one side; (4) no difference when the whole interval lies strictly inside the margin; (5) cannot tell.
- A comparison that moves both changes of the script (CPMINCORES and PERFEPP) carries the label "mixed effect: the script's two changes" with its verdict; the single-change rows are separate.
- The ceiling block pairs its states with maxcores25 inside each boot; no test and no number is taken across the two blocks. Its states are forced and carry "(forced: the ceiling)".
- Described rows get the shift and the interval only: no p and no verdict.
- The series is refused, and needs an amendment dated before any outcome is read, on: a planned step without exactly one accepted result in journal.jsonl; a wrapper whose series, boot, stateIndex or state differs from plan.json and the journal; a wrapper bench.resultFile other than parking-bench-<phase>-<step>.json; a bench JSON whose phase or test is not its own step's; a plan state that is not one of the units above; a pre-registered series with another boot count or without every step of its units in every boot; a wrapper capturedAt outside its boot in the journal; a bench metadata.power.schemeGuid, or one of the five values above in metadata.power.processorSettings, AC or DC, other than the state's; a bench highQos other than true; a wrapper environment.enabledNetworkAdapters other than 0; a game whose autoGameModeEnabled differs from its Game Mode or whose ppm record fails the Game Mode check; a game cap or cap.fpsMax other than the state's; a game with a non-empty rejected or a non-zero presentMon.overflowedPresents; a missing or non-numeric field that a table reads, or a wake file without its burst and wakeMs columns or without a burst row; any difference between steps in metadata.os.build, metadata.os.ubr, metadata.qpcFrequency, metadata.benchScript.sha256, metadata.power.overlayAc, metadata.power.overlayDc, environment.hvciEnabled, environment.bios.version, environment.microcodeRaw, environment.clockFlags, environment.drivers.gpu, environment.drivers.audio, parkedBeforeBurst.logicalCpus or parkedDuringRun.logicalCpus; between bursts in threads, bursts, idleSeconds, burstMs, windowMs, chunkIterations, itersPerMs, burst.earlyWindowMs; between games in metadata.presentMonVersion, presentMon.sha256, load.name, load.build, load.videoConfig, frames.refreshHz, frames.presentModes; or in metadata.power.processorSettings and environment.powerExplicit once the five planned values are left out.
- A step leaves every row and state table that uses it, and its boot stays in the others, when it is a burst whose ppm.buffersLost is not 0, whose ppm.captureChanges is not 0 or whose ppm.captureProfile is the Game Mode profile, or any step whose powerStateChanged is true. In a tested row that changes CPMINCORES, a boot whose reference step has no parkedBeforeBurst.parked.median or parkedDuringRun.parked.median is left out of that row only and listed with the reason "no parked-core reading"; no other row reads the parked count.
- A tested row with no boot that holds every step it pairs stays in its family with p = 1 and reads cannot tell; a described row with no boot prints dashes.
- Listed only: failed attempts and power profile changes before the capture window. A failed attempt's rejection text is printed as recorded; failed attempts are never read for outcomes.

## Amendments

- 2026-11-25, recorded before any outcome was read: the first `parking-retest-2` start stopped in boot 0 after the
  Office ClickToRun Service Monitor re-enabled `ClickToRunSvc` and two consecutive attempts failed the preflight. The
  runner restored the system. No boot was accepted and no outcome was read. The attempt was set aside as
  `parking-retest-2-aborted-20261125`, the nine `\Microsoft\Office\` tasks joined the runner's disabled set, and the same
  plan and bench script were restarted from boot 0. The comparisons and statistical rules did not change.
- 2026-11-27, before the top-up was measured and before any outcome was read: original ceiling boot 0 lost the
  `maxcores25-min` versus `maxcores25` burst pair under the already registered `ppm.captureChanges` exclusion, leaving
  five pairs. Exactly one one-boot series named `parking-retest-2-ceiling-topup` repeats the six states of original
  ceiling boot 0 in the same order and settings. The original and top-up raw series stay separate and immutable. Every
  existing validity, homogeneity and exclusion gate applies across both series, including the four top-up steps whose
  outcomes are not reported. Only the within-top-up `maxcores25-min` versus `maxcores25` burst pair joins the sole
  pre-registered ceiling tested row, as analysis-only boot 6. No top-up outcome joins a described comparison, state
  table, testbed summary, file map or another test. If that pair is excluded, the row reports five pairs and no further
  top-up is permitted. The ceiling family still contains one tested row; Holm and every statistical rule stay unchanged.
  An ordinary runner retry of a failed boot follows the existing failed-boot rules, but another accepted or substitute
  top-up series is prohibited after its validity or exclusion status is known.
