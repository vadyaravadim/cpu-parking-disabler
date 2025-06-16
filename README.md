# CPU Parking Disabler

Disable CPU parking on Windows 11 for better performance and responsiveness.

## What it does

- **Disables CPU parking** - all cores stay active instead of going to sleep
- **Sets CPU to 100% minimum state** - no more waiting for cores to wake up
- **Unlocks hidden power options** - shows CPU parking settings in Control Panel
- **Creates backup** - saves your current settings for easy restore

## Why use this?

CPU parking causes micro-stutters and delays when cores need to "wake up". This is especially noticeable in:
- Gaming (input lag, frame drops)
- Real-time applications (audio/video editing)
- Any task requiring instant CPU response

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