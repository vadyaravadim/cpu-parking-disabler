# CPU Parking Disabler

Eliminate micro-stutters and input lag by disabling CPU core parking on Windows 10/11.

---

## ⚡ What It Does

1. **Backs up** your current power scheme to Desktop (`.pow` file)
2. **Disables CPU core parking** — all cores stay active, no wake-up latency
3. **Sets EPP to max performance** — tells the CPU to favor performance over power saving

That's it. No other settings are touched. Your current power scheme is modified in-place.

## 📊 Settings Changed

| powercfg Name | Description | Before | After |
|---------------|-------------|--------|-------|
| `CPMINCORES` | Core Parking Min Cores (E-cores / all cores) | 10-50% | **100%** |
| `CPMINCORES1` | Core Parking Min Cores (P-cores, hybrid CPUs) | 10-50% | **100%** |
| `PERFEPP` | Energy Performance Preference (E-cores / all cores) | 50 | **0** |
| `PERFEPP1` | Energy Performance Preference (P-cores, hybrid CPUs) | 50 | **0** |

> `CPMINCORES1` and `PERFEPP1` are Class 1 (P-core) settings — they only exist on Intel 12th gen+ hybrid CPUs. The script unhides them via registry before applying values.

## 🎯 Problem Solved

CPU core parking puts idle cores to sleep. When load spikes, waking cores takes 1-15ms — causing micro-stutters, frame drops, and input lag. This script keeps all cores active so they respond instantly.

**Symptoms this fixes:**
- Stuttering in games despite high FPS
- Input lag spikes
- Frame time inconsistency

## 🚀 Installation

**1. Run PowerShell as Administrator**

**2. Enable script execution (one-time):**
```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
```

**3. Run the script:**
```powershell
.\cpu-parking-disabler.ps1
```

No parameters, no configuration. Run and done.

## ✅ How to Verify

**Check with powercfg:**
```powershell
powercfg -query SCHEME_CURRENT SUB_PROCESSOR CPMINCORES
powercfg -query SCHEME_CURRENT SUB_PROCESSOR PERFEPP
```

Both should show `Current AC Power Setting Index: 0x00000064` (100) for CPMINCORES and `0x00000000` (0) for PERFEPP.

**Check with Resource Monitor:**
1. Open Resource Monitor → CPU tab
2. All cores should show as "Running" (not "Parked")

## 🔄 Rollback

**From backup** (saved on your Desktop):
```powershell
powercfg -import "$env:USERPROFILE\Desktop\power_scheme_backup.pow"
powercfg -setactive SCHEME_CURRENT
```

**Full reset to Windows defaults:**
```powershell
powercfg -restoredefaultschemes
```

## ⚠️ Side Effects

- **Higher idle power consumption** (+10-30W)
- **Higher temperatures** (+5-10°C)
- **More fan noise**

Not recommended for laptops on battery or systems with poor cooling. Monitor temps with HWiNFO64 — keep under 85°C.

## 💻 Compatibility

| | Supported |
|---|-----------|
| **Intel** | 10th gen and newer (12th+ for hybrid P/E-core support) |
| **AMD** | Ryzen 5000/7000/9000 series |
| **Windows** | 10, 11 (23H2, 24H2) |

## 📝 License

MIT License — use at your own risk.

---

[Report Issues](https://github.com/vadyaravadim/cpu-parking-disabler/issues) · ⭐ If this helped, consider starring the project!
