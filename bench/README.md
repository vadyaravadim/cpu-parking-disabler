# Core parking bench

Reproduce the measurements behind the RigPolice article https://rigpolice.com/system/articles/disable-cpu-core-parking/ . `parking-bench.ps1` has three tests. `burst` (the default) releases one thread per logical CPU after an idle pause and records the work done in each 1 ms window, the test where parked cores show. `framesim` runs a synthetic frame loop. `game` captures the frame times of a running load. Every test records the parked-core count. The CS2 load below is the CPU-bound real-game check.

**Same procedure, not same numbers.** A game update, a driver update or a different CPU moves every number. Compare states only inside one series of runs on one machine, never against the published tables.

## What you need

- Windows 11, an elevated PowerShell (Windows PowerShell 5.1 or PowerShell 7).
- Run one power state per series: stock, then each state you want to compare (for example after `cpu-parking-disabler.ps1`).
- PresentMon 2.6.0: https://github.com/GameTechDev/PresentMon/releases/tag/v2.6.0. Verify the download: `(Get-FileHash .\PresentMon-2.6.0-x64.exe).Hash` must equal `b2a706bc6ad475749e3b7e3409263aa1e6906d45bdcf993f6dbc0f660188f1af`.
- A load from the section "Loads" below.
- Download the whole `bench` folder: the script dot-sources `bench-env.ps1` and the load recipes live in `loads\*.json` next to it.

## Steps

1. Make the machine quiet yourself. The bench only measures: it does not check, close or change anything. Reboot, do not open a browser, launcher, updater, VPN or monitoring tool afterwards, and wait the same fixed time after every reboot (write it down) so uptime is comparable between states.
2. If you run with `-Load`, do not start the load yet: the bench waits for it. Otherwise start your own load now, if your test needs one.
3. Run the bench from the elevated shell: `.\parking-bench.ps1 -Phase stock` (burst), `.\parking-bench.ps1 -Phase stock -Test framesim`, `.\parking-bench.ps1 -Phase stock -Test game -Load cs2 -PresentMon <path to PresentMon-2.6.0-x64.exe>`; then the same with `-Phase tweaked`. For a capped game run add `-FpsMax <N>` to the game command (for example `-FpsMax 144`; see the section below). Results go next to the script, or to `-OutDir`. With `-Load`, start the load from the section "Loads" after the bench prints `Waiting for <process> ...`.
4. Repeat at least 5 times per state in the order A-B-A-B (never all A then all B), with a reboot before every run.

For `-Test game` start the bench before the load: it waits for the load's process and, when the recipe names a start line, for that line in the game log, then waits the load pause and captures. Do not touch the PC until it prints the result.

**Capped run (`-FpsMax <N>`, CS2 only).** Before the console line, type this into the CS2 console and press Enter (the bench prints it with your N filled in):

```
bind F9 "echo rigpolice_cap_key; fps_max <N>"
```

Then type the console line as usual. The map resets `fps_max` when it loads and again after the start line, when the game log shows `Cannot set convar 'fps_max'`. After that line the bench presses F9 once, only while CS2 is the foreground window; if it is not, the run fails. The load pause is still counted from the start line, so a capped and an uncapped run capture the same part of the route. The bench refuses an N whose period, 1000 / N ms, is within 3% of the refresh period of your monitor, and rejects the run when the median frame time is not within 2% of 1000 / N ms.

**Undo.** Every game run of the CS2 map changes `fps_max`: the map sets it to 0, and a capped run then sets it to N. CS2 saves the last value when it exits, and a capped run also leaves F9 bound. Before your first CS2 game run, note what `fps_max` and `bind F9` print in the CS2 console. Afterwards type `fps_max <noted value>`, then `bind F9 "<noted command>"`, or `unbind F9` if F9 was unbound.

## What the bench touches

Nothing persistent. It reads the registry, `powercfg /qh`, WMI and performance counters, and it runs only its own worker threads, a performance counter query, an ETW session named `rigpolice-ppm` (provider `Microsoft-Windows-Kernel-Processor-Power`, keyword `0x44`) that it starts and stops itself around every test, writing a temporary ETL file that it deletes after decoding it, and, for `-Test game`, PresentMon with its own ETW session named `rigpolice-bench`. It writes a one-time calibration file `parking-bench-config.json` next to the script and reads the game log named in the recipe. With `-FpsMax` it also presses one key (F9) into CS2, only while CS2 is the foreground window. The key runs the bind you typed. CS2 keeps that bind, and on every game run of the CS2 map it saves `fps_max` in its own config files when it exits (undo: the **Undo** paragraph under Steps). It changes no power, registry, service or boot setting and stops no process. It does not check whether your machine is quiet; that is up to you. A test in `tests\` fails if a changing command is added.

## Result record

Each result stores the bench script name and its SHA256, the OS build, display version and update revision, the active power scheme GUID with every processor setting for AC and DC, the load name and the PresentMon version, and the QPC timer frequency, next to the measurements. `parking-bench.ps1` adds the parked-core count, the power state at the end of the run (a change marks the run) and, for `-Test game`, the game build, whether the installed video config matches the shipped one (mismatched key names only) and the names of launch flags outside the recipe (names only, no values), and the count of frames PresentMon lost to a present event buffer overflow (`presentMon.overflowedPresents`; a run that lost any is rejected). Every result also holds a `ppm` object for the measured part of the run (the burst, the frame loop or the capture): `session` and `keyword` of the `rigpolice-ppm` trace; `startedBeforeLoad`, whether the trace started before the load process existed (game runs; null otherwise); `buffersLost`, taken from `logman query` and null when its output has no `Buffers Lost` line (logman prints localized labels on some Windows languages); `profileChanges`, every processor power profile change the trace saw, as profile ids with the offset in seconds from the start of the measured part (zero or negative means before it); `captureProfile`, the profile id in effect when the measured part started, null when the trace saw no change before it or a change fell inside it; and `captureChanges`, the number of changes inside it. The trace logs only changes, so an empty list means no change was seen. Profile ids are recorded as numbers only. For `-Test game` the result also holds `autoGameModeEnabled`, the value of `AutoGameModeEnabled` under `HKCU\Software\Microsoft\GameBar` read before the capture (null when it does not exist), and `cap`, null on an uncapped run and otherwise `fpsMax`, `periodMs` (1000 / `fpsMax`), `tolerance`, `slowFrameFactor`, `slowFrames` (frames longer than `slowFrameFactor` times the period), `pressedAfterStartSeconds` (seconds from the start line to the key press) and `echoSeen` (whether the bind's echo text appeared in the game log after the press; it is recorded and never rejects a run). Nothing else is recorded: no process or service list, no driver inventory, no user name or computer name.

## Reading the result

One run proves nothing. Take the median of the runs of each state and look at the spread (min to max). A difference counts only when it is larger than the spread inside a state. "Cannot tell" is a valid result. A maximum from a single run is never a headline.

## Sharing a result

The result files hold only the fields above and the measurements, so they can be shared as they are.

## Loads

### Counter-Strike 2, workshop benchmark map (`cs2`)

- PresentMon 2.6.0, SHA256 `b2a706bc6ad475749e3b7e3409263aa1e6906d45bdcf993f6dbc0f660188f1af` (https://github.com/GameTechDev/PresentMon/releases/tag/v2.6.0).
- Steam app 730 (free), workshop map 3240880604 ("CS2 FPS BENCHMARK DUST2"). The map is a 131 s camera route over de_dust2 and ends with a disconnect by itself.
- Bottleneck: CPU. vsync: 0 (off).

Launch arguments:

```
steam.exe -applaunch 730 -novid -condebug +con_enable 1 -console +toggleconsole
```

Wait 25 s for the main menu, bring the game window to the front, then type this into the console (the launch arguments open it) and press Enter:

```
game_type 3; game_mode 0; sv_skirmish_id 0; sv_game_mode_flags 32; mapgroup @workshop/3240880604/de_dust2; nextlevel de_dust2; map de_dust2 customgamemode=3240880604 nomapvalidation=true; hideconsole
```

The line is fixed; do not edit it. `hideconsole` closes the console so it does not sit over the scene.

Timings: the route has started when the game log `../../csgo/console.log` (relative to the folder of cs2.exe) shows `[VProf] VProfLite started.`. From that line: load pause 15 s, then capture 100 s.

Turn these off in the GPU driver and anywhere else before the run:

- AMD Radeon Chill
- AMD Frame Rate Target Control (FRTC)
- AMD Anti-Lag
- NVIDIA Reflex / Low Latency Mode overrides
- any external frame limiter

Video settings: use the provided file `bench\loads\cs2_video.txt` as is. The mapping from its values to in-game menu labels is not confirmed against a primary source, so do not set the menu by hand.

1. Close CS2.
2. Back up your own file: `<Steam>\userdata\<your Steam id>\730\local\cfg\cs2_video.txt`.
3. Copy `bench\loads\cs2_video.txt` over it.
4. Run the load.
5. Close CS2 and put your backup back.

The file sets 1280x720 (`setting.defaultres`, `setting.defaultresheight`), `setting.mat_vsync` = 0 and `setting.msaa_samples` = 0. It also carries `VendorID`, `DeviceID`, `knowndevice`, `Autoconfig` and `Version` from the machine it was captured on. Whether CS2 accepts the file without them is not verified, so they are kept.

The bench rejects the run when:

- SyncInterval above 0
- the installed cs2_video.txt differs from the shipped cs2_video.txt in any setting.* value, or is not found
- frame times cluster at the monitor refresh period
- cs2.exe is not the captured process
- the captured frames cover less than 95 s of the 100 s capture (the load stopped presenting or exited)

### Unigine Superposition 1.1 (free), infinite scene (`superposition`)

- PresentMon 2.6.0, SHA256 `b2a706bc6ad475749e3b7e3409263aa1e6906d45bdcf993f6dbc0f660188f1af` (https://github.com/GameTechDev/PresentMon/releases/tag/v2.6.0).
- Program: Unigine Superposition 1.1, installer `Unigine_Superposition-1.1.exe`, SHA256 `DE5DBF4F7AD284B709C5DB318DBEDC1B025A41E50326595A444EE9CBD4A17182`, installed to `C:\Program Files\Unigine\Superposition Benchmark`.
- Bottleneck: GPU. vsync: 0 (off).

Launch arguments:

```
bin\superposition.exe -project_name Superposition -video_mode -1 -console_command "world_load superposition/superposition" -video_app direct3d11 -video_width 2560 -video_height 1440 -video_fullscreen 1 -preset 0 -video_vsync 0 -sound 0
```

Run it from `C:\Program Files\Unigine\Superposition Benchmark\bin`. Change `-video_width` and `-video_height` to your monitor's native resolution.

Timings: from the start of superposition.exe: load pause 20 s, then capture 60 s.

Turn these off in the GPU driver and anywhere else before the run:

- AMD Radeon Chill
- AMD Frame Rate Target Control (FRTC)
- AMD Anti-Lag
- any external frame limiter

The bench rejects the run when:

- SyncInterval above 0
- frame times cluster at the monitor refresh period
- superposition.exe is not the captured process
- the captured frames cover less than 57 s of the 60 s capture (the load stopped presenting or exited)