<div align="center">

# CPU Parking Disabler

**Kill micro-stutters. Unpark every core. One command.**

Disables CPU core parking (a.k.a. **unparking your CPU cores**) and sets Energy Performance Preference to maximum on Windows 10/11.
Zero install. Zero dependencies. Just download and run.

[![lint](https://img.shields.io/github/actions/workflow/status/vadyaravadim/cpu-parking-disabler/lint.yml?label=lint&logo=powershell)](https://github.com/vadyaravadim/cpu-parking-disabler/actions/workflows/lint.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Windows 10/11](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D4?logo=windows)](https://www.microsoft.com/windows)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?logo=powershell&logoColor=white)](https://docs.microsoft.com/en-us/powershell/)
[![Latest release](https://img.shields.io/github/v/release/vadyaravadim/cpu-parking-disabler)](https://github.com/vadyaravadim/cpu-parking-disabler/releases)
[![PowerShell Gallery](https://img.shields.io/powershellgallery/v/cpu-parking-disabler?logo=powershell&label=PS%20Gallery)](https://www.powershellgallery.com/packages/cpu-parking-disabler)
![GitHub Stars](https://img.shields.io/github/stars/vadyaravadim/cpu-parking-disabler?style=social)

**[Read the deep dive with measured benchmarks →](https://rigpolice.com/system/articles/disable-cpu-core-parking/)**

</div>

---

## Quick Start

**Easiest — from the PowerShell Gallery:**

```powershell
Install-Script cpu-parking-disabler
cpu-parking-disabler                 # then run it by name (open a NEW PowerShell window first, so the Scripts folder is on PATH)
```

The script self-elevates. Update later with `Update-Script cpu-parking-disabler`.

**One-liner** instead (in any PowerShell — it self-elevates):

```powershell
irm https://raw.githubusercontent.com/vadyaravadim/cpu-parking-disabler/main/cpu-parking-disabler.ps1 | iex
```

The script saves itself to `%USERPROFILE%\cpu-parking-disabler.ps1` and reruns from there; an existing copy at that path that differs is kept as `.bak`. The power-scheme backup still goes to the Desktop.

**Or clone:**

```powershell
git clone https://github.com/vadyaravadim/cpu-parking-disabler.git
cd cpu-parking-disabler
.\cpu-parking-disabler.ps1
```

**Or download the ZIP** (no PowerShell needed): click **Code ▸ Download ZIP** at the top of this page, unzip, then double-click **`Run.bat`**.

Whichever method you use, click **Yes** on the UAC prompt — the script requests admin rights on its own, no need to open an admin console manually.

No parameters, no configuration. Run and done.

## What It Does

1. **Backs up** your current power scheme to Desktop (`.pow` file)
2. **Disables CPU core parking** (unparks all cores) — all cores stay active, no wake-up latency
3. **Sets EPP to max performance** — CPU favors performance over power saving

That's it. No other settings are touched. Your current power scheme is modified in-place.

## Before & After

| Before | After |
|--------|-------|
| ![Windows Resource Monitor showing several CPU cores Parked before running the script](assets/before.png) | ![All CPU cores unparked and Running after disabling core parking](assets/after.png) |

> Cores marked **Parked** → all cores **Running**. Open Resource Monitor → CPU tab to verify on your system.

## Settings Changed

| Setting | Description | Before | After |
|---------|-------------|--------|-------|
| `CPMINCORES` | Core Parking Min Cores (E-cores / all cores) | 10–50% | **100%** |
| `CPMINCORES1` | Core Parking Min Cores (P-cores, hybrid CPUs) | 10–50% | **100%** |
| `PERFEPP` | Energy Performance Preference (E-cores / all cores) | 50 | **0** |
| `PERFEPP1` | Energy Performance Preference (P-cores, hybrid CPUs) | 50 | **0** |

> `CPMINCORES1` and `PERFEPP1` are Class 1 (P-core) settings — they only exist on Intel 12th gen+ hybrid CPUs. The script unhides them via registry before applying values.

## The Problem: Why Core Parking Causes Stutters

CPU core parking puts idle cores to sleep. When load spikes, waking cores takes **1–15 ms** — causing micro-stutters, frame drops, and input lag. This script keeps all cores active so they respond instantly.

**Symptoms this fixes:**
- Stuttering in games despite high FPS
- Input lag spikes
- Frame time inconsistency

## Measured Impact

Three states on an i9-14900F (8 P + 16 E cores, Windows 11 24H2): stock, parking forced (24 of 32 threads parked — the state aggressive-parking machines live in), and after this script:

| Metric | Stock | Parking active | After the script |
|--------|-------|----------------|------------------|
| 7-Zip rating, 32 threads | 175,111 MIPS | 71,120 MIPS (**−59%**) | 175,695 MIPS |
| Worst frame (144 Hz sim) | 6.5 ms | **17.3 ms** | 5.4 ms |
| Frames over the 6.9 ms budget | 0% | 0.14% | 0% |

Parking costs tail latency (micro-stutter), not average speed — and the script removes it even against hard parking caps. Full methodology, screenshots, and the "check your own PC in 30 seconds" guide: **[the RigPolice deep dive](https://rigpolice.com/system/articles/disable-cpu-core-parking/)**. Reproduce it yourself with [`bench/bench.ps1`](bench/bench.ps1) + `7zr b 3 -mmt32`.

## Verify: Check If Your CPU Cores Are Parked

**Resource Monitor** (`resmon`) → **CPU** tab: parked cores are labeled **Parked** next to the core graph; after running the script every core should say **Running**.

Or check the applied values directly:

```powershell
powercfg -query SCHEME_CURRENT SUB_PROCESSOR CPMINCORES
powercfg -query SCHEME_CURRENT SUB_PROCESSOR PERFEPP
```

CPMINCORES should show `0x00000064` (100), PERFEPP should show `0x00000000` (0).

## Rollback

**From your backup** (saved on Desktop) — in an Administrator PowerShell:
```powershell
$bak  = (Get-ChildItem "$env:USERPROFILE\Desktop\power_scheme_backup_*.pow" | Sort-Object LastWriteTime)[-1].FullName
$guid = [regex]::Match((powercfg -import $bak), '[0-9a-fA-F-]{36}').Value
powercfg -setactive $guid
```
`powercfg -import` restores the saved scheme as a new entry and prints its GUID; `-setactive` switches to it. It appears as a duplicate in your scheme list — drop the leftover with `powercfg -delete <GUID>` if you like. (Plain `powercfg -import file.pow` alone does **not** roll back: it neither overwrites the active scheme nor activates the copy.)

**Full reset to Windows defaults** — simplest, but resets *all* power schemes:
```powershell
powercfg -restoredefaultschemes
```

## Side Effects

- **Higher idle power** (+10–30 W) — not recommended on battery
- **Higher temps** (+5–10 °C) — monitor with [HWiNFO64](https://www.hwinfo.com/), keep under 85 °C
- **More fan noise**

## Compatibility

| | Supported |
|---|-----------|
| **Intel** | 10th gen+ (12th+ for hybrid P/E-core support) |
| **AMD** | Ryzen 5000 / 7000 / 9000 |
| **Windows** | 10, 11 (23H2, 24H2) |

## FAQ

### What is CPU core parking?
A Windows power-management feature that puts idle CPU cores into a low-power **parked** state. Waking a parked core takes ~1–15 ms, which can cause micro-stutters, frame-time spikes, and input lag under bursty load.

### What does "unpark CPU cores" mean?
Unparking means forcing Windows to keep every core active instead of parking idle ones. This script **unparks all CPU cores** by setting Core Parking Min Cores to 100%.

### Does disabling core parking increase FPS?
It mainly improves **1% lows, frame-time consistency, and input latency** — not average FPS. If your stutter comes from core wake-up latency, unparking helps; if your CPU never parks under load, you won't notice a difference.

### Is it safe to unpark CPU cores?
Yes. It only changes power settings and backs up your current scheme first, so you can always roll back. The trade-offs are higher idle power and temperatures (see [Side Effects](#side-effects)), not hardware risk — keep temps under ~85 °C.

### Do the changes survive a reboot?
Yes. The values are written into your active Windows power scheme, so they persist across reboots until you roll back (or a major Windows update resets power schemes).

### How do I check if my CPU cores are parked?
Open **Resource Monitor** (Win+R → `resmon`) → **CPU** tab: parked cores are labeled **Parked**. See [Verify](#verify-check-if-your-cpu-cores-are-parked) for the `powercfg` commands that show the underlying settings.

### How is this different from ParkControl (Bitsum)?
ParkControl is a GUI app. This is a zero-install, open-source PowerShell script that applies the same core-parking + EPP tweak directly via `powercfg`/registry, creates a backup, and leaves **no background process** behind. Use whichever you prefer — this is the lightweight, transparent, scriptable option.

### How is this different from Quick CPU?
Quick CPU (Coder Bag) is a closed-source GUI app for monitoring and tuning many CPU parameters, core parking among them. This script does one thing — unpark all cores and max out EPP — with no install, no background process, and readable source. If you only want core parking gone, this is the smaller hammer.

### Can I disable core parking through the registry (ValueMax method)?
Registry guides that tell you to search for `0cc5b647-c1df-4637-891a-dec35c318583` and edit `ValueMax`/`Attributes` are manipulating the same **Core Parking Min Cores** setting this script changes. `powercfg` is the documented interface for it — same result, no manual registry surgery, plus a backup file.

### How do I re-enable core parking?
Restore the `.pow` backup saved to your Desktop — see [Rollback](#rollback).

## Related

- [MSI Mode Utility](https://github.com/vadyaravadim/msi-mode-utility) — enable MSI mode (Message Signaled Interrupts) for GPU, USB, network & audio devices to cut DPC latency and input lag
- [Interrupt Affinity Utility](https://github.com/vadyaravadim/interrupt-affinity-utility) — pin GPU, network, USB & audio interrupts to specific CPU cores (P/E-core aware) to tame DPC latency
- [Timer Resolution Utility](https://github.com/vadyaravadim/timer-resolution-utility) — set 0.5 ms timer resolution, disable dynamic tick, un-force HPET — with a built-in Sleep(1) benchmark
- [GameDVR & FSO Disabler](https://github.com/vadyaravadim/gamedvr-fso-disabler) — disable Game DVR / Xbox Game Bar capture and Fullscreen Optimizations on Windows 10/11 to fix capture stutters and frame drops
- [Remove Hidden Devices](https://github.com/vadyaravadim/remove-hidden-devices) — remove ghost / hidden devices left behind by unplugged USB sticks, headsets & dongles cluttering Device Manager

Same idea across the series: one transparent PowerShell script, no binaries, you see exactly what changes.

## License

[MIT](LICENSE) — use at your own risk.

---

<div align="center">

If this fixed your stutters, consider giving it a ⭐

[Report Issues](https://github.com/vadyaravadim/cpu-parking-disabler/issues)

</div>
