# Windows 11 CPU Parking Disabler

Eliminate micro-stutters and input lag by disabling CPU parking and configuring aggressive processor power settings for Windows 11.

**Keywords:** Windows 11 CPU parking disable, Intel Alder Lake Raptor Lake stuttering fix, frame drops micro-stutters, gaming performance optimization, E-core P-core scheduling

---

## ⚡ What It Does

- Disables CPU core parking (all cores stay active)
- Sets min/max processor state to 100%
- Enables aggressive Processor Performance Boost Mode
- Optimizes performance increase/decrease thresholds (10%/60%)
- Unlocks 8 hidden power settings in Windows UI
- Creates automatic backup

## 🎯 Problem Solved

Modern Intel CPUs (12th-14th gen) and AMD Ryzen processors experience **micro-stutters** due to CPU parking - cores take 1-15ms to wake up, causing frame drops and input lag spikes.

**Symptoms:**
- Stuttering in games despite high FPS
- Input lag spikes
- Frame time inconsistency
- Audio crackling

## 📊 Changes Applied

| Setting | Before | After |
|---------|--------|-------|
| CPU Parking | Enabled | **Disabled (100)** |
| Min/Max Processor State | 5% / 100% | **100% / 100%** |
| Boost Mode | Default | **Aggressive (2)** |
| Performance Thresholds | 30% / 40% | **10% / 60%** |
| Core Wake Delay | 1-15ms | **0ms** |

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

**4. Restart when prompted**

## ✅ Recommended For

- Desktop PCs with proper cooling
- Gaming systems (especially 120Hz+ monitors)
- Intel 12th/13th/14th gen CPUs
- AMD Ryzen 5000/7000 series
- VR gaming
- Workstations requiring consistent performance

## ⚠️ Not Recommended For

- Laptops on battery (significant battery drain)
- Systems with inadequate cooling
- Small form factor / fanless PCs

## 🔄 Rollback

**Using backup:**
```powershell
powercfg -import "$env:USERPROFILE\Desktop\cpu_performance_backup.pow"
powercfg -setactive SCHEME_CURRENT
```

**Reset to defaults:**
```powershell
powercfg -restoredefaultschemes
```

## 🔥 Side Effects

- **+10-30W idle power consumption**
- **+5-10°C temperatures**
- **Increased fan noise**
- Monitor temps with HWiNFO64, keep under 85°C

## 🛠️ Troubleshooting

**Execution policy error:**
```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
```

**Access denied:** Run PowerShell as Administrator

**Settings not visible:** Restart required for registry changes

## 💻 Compatibility

**Tested:**
- Intel 12th/13th/14th gen (Alder Lake, Raptor Lake)
- AMD Ryzen 5000/7000 series
- Windows 11 (23H2, 24H2)

**May work:** Intel 10th/11th gen, Windows 10

## 📝 License

MIT License - Use at your own risk. Monitor temperatures after applying changes.

---

**Version 2.0** | [Report Issues](https://github.com/vadyaravadim/cpu-parking-disabler/issues)
