# CPU Parking Disabler

**Keywords:** Windows 11 stuttering, Intel 12th 13th 14th gen performance, CPU parking fix, gaming microstutters, frame drops

Disable CPU parking on Windows 11 for better performance and responsiveness.

## What it does

- **Disables CPU parking** - all cores stay active instead of going to sleep
- **Sets CPU to 100% minimum state** - no more waiting for cores to wake up
- **Unlocks hidden power options** - shows CPU parking settings in Control Panel
- **Creates backup** - saves your current settings for easy restore

## Why use this?

CPU parking causes **micro-stutters** and delays when cores need to "wake up" from sleep state. This is especially problematic with:

### Modern CPU Issues
- **Intel 12th-14th gen** (Alder Lake, Raptor Lake) - hybrid architecture with P-cores and E-cores
- **E-core parking delays** - efficiency cores take time to activate
- **Scheduler conflicts** - Windows doesn't always wake the right cores fast enough
- **Frame time spikes** - irregular CPU boost behavior causes stuttering

### Common Symptoms
- **Microstutters in games** - brief freezes every few seconds
- **Input lag spikes** - mouse/keyboard delays during CPU transitions  
- **Inconsistent frame times** - smooth FPS but jerky motion
- **Audio crackling** - real-time audio processing affected
- **Browser lag** - scrolling and video playback stutters

### Affected Hardware
- Intel Core i5/i7/i9 12th, 13th, 14th generation
- AMD Ryzen with Precision Boost
- Any multi-core CPU with parking enabled
- High refresh rate monitors (120Hz+)
- VR headsets requiring consistent frame timing

## Technical Background

**CPU Parking** is Windows' aggressive power-saving feature that puts unused cores to sleep. While good for battery life, it causes problems with modern CPUs:

### Intel Hybrid Architecture (12th-14th gen)
- **P-cores** (Performance) - 4-8 high-speed cores
- **E-cores** (Efficiency) - 8-16 slower cores  
- **Parking delays** - E-cores take 1-15ms to wake up
- **Scheduler confusion** - Windows often parks the wrong cores

### The Problem
1. Game needs more CPU power
2. Windows tries to wake parked cores
3. **1-15ms delay** while cores activate
4. **Microstutter** or frame drop occurs
5. By the time cores wake up, the moment has passed

### Why This Script Works
- **Forces 100% cores active** - no wake-up delays
- **Aggressive thresholds** - instant boost on any load
- **Bypasses Windows scheduler** - manual control over power states

## How to use

1. **Download** `cpu-parking-disabler.ps1`

2. **Right-click** on PowerShell → **Run as Administrator**

3. **Allow script execution** (one-time setup):
   ```powershell
   Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
   ```

4. **Run the script**:
   ```powershell
   .\cpu-parking-disabler.ps1
   ```

5. **Restart** when prompted (recommended)

## What changes

| Setting | Before | After |
|---------|--------|-------|
| CPU Parking | Enabled | **Disabled** |
| Minimum CPU State | 5-10% | **100%** |
| Maximum CPU State | 100% | **100%** |
| Performance Thresholds | 30%/10% | **10%/80%** |

## How to undo

The script creates a backup file on your desktop. To restore:

```powershell
powercfg -import "C:\Users\YourName\Desktop\cpu_performance_backup.pow"
```

Or reset to Windows defaults:
```powershell
powercfg -restoredefaultschemes
```

## Important notes

⚠️ **This will increase power consumption and heat**

✅ **Good for**: Desktop PCs, gaming, performance work  
❌ **Consider avoiding**: Laptops on battery, systems with cooling issues

## ⚠️ Important Warnings

**This script modifies system power settings. Use at your own risk.**

- ❌ **NOT recommended for laptops on battery** - will drain battery faster
- ❌ **Check your cooling** - higher temperatures possible  
- ✅ **Desktop PCs** - generally safe with proper cooling
- 💾 **Backup created automatically** - stored on your desktop
- ⚠️ **Check your voltage** - higher temperatures and cpu degradation possible  

## Compatibility

✅ **Tested on:**
- Intel 12th, 13th, 14th generation CPUs
- Windows 11 (all versions)
- AMD Ryzen 5000+ series

❓ **May work on:**
- Older Intel generations
- Windows 10 (not extensively tested)

## Requirements

- Windows 11
- Administrator privileges
- PowerShell

## Troubleshooting

**"Execution Policy" error?**
```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
```

**"Access Denied" error?**  
Make sure PowerShell is running as Administrator

**Settings not visible in Control Panel?**  
Restart required for registry changes

## License

MIT License - Use at your own risk