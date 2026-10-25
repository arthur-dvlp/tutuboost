<div align="center">

# `TUTUBOOST`

**Windows optimizer for CS2 — simple, direct and 100% reversible.**

![Windows 10/11](https://img.shields.io/badge/Windows-10%20%7C%2011-00ff41?style=flat-square&labelColor=020a04)
![PowerShell](https://img.shields.io/badge/PowerShell-5.1-00ff41?style=flat-square&labelColor=020a04)
![MIT License](https://img.shields.io/badge/license-MIT-00ff41?style=flat-square&labelColor=020a04)
![Free](https://img.shields.io/badge/price-free-00ff41?style=flat-square&labelColor=020a04)

No installation · Open and readable code · Made in Brazil

</div>

---

## What it is

TutuBoost applies, with one click, the Windows tweaks that help CS2 the most: power, CPU, timer, GPU, mouse, network, privacy and appearance. Every change is recorded before it is made, so you can **undo everything** and go back to exactly what you had.

It is a single PowerShell script. No installer, no server, no account, no internet.

## Features

| Tab | What it does |
|---|---|
| **Dashboard** | PC summary (CPU, GPU, RAM, disk, Windows) and optimization status. |
| **Optimizations** | Cards with an on/off toggle per module, search and category filter. |
| **Experimental** | Tweaks with unproven effect. They start turned off and you test them one at a time. |
| **Cleanup** | Temporary files, caches and system junk, with a choice of what to delete. |
| **Restore** | Windows restore point and **REVERT ALL**. |
| **Apps** | Removal of the pre-installed apps you choose. |
| **Diagnostics** | PC check with BIOS reminders (XMP/DOCP/EXPO, Above 4G, Resizable BAR). |

### Optimization modules

- **Power:** Maximum power plan
- **CPU and game priority**
- **Boot and kernel (timer)**
- **GPU and display:** maximum monitor refresh rate
- **Mouse and menus**
- **Network**
- **Privacy**
- **Notifications and suggestions**
- **System** and **Windows appearance**
- **Advanced, with risk warning:** disable Core Isolation and disable Defender real-time protection (off by default)

## How to use

1. Download the latest release and **extract the .zip** into a folder.
2. Double-click **`Open_TutuBoost.bat`**.
3. Accept the administrator prompt. The program needs it to change system settings.
4. In the **Restore** tab, create a **restore point** (recommended).
5. In the **Optimizations** tab, click **SELECT RECOMMENDED** and then **OPTIMIZE ALL**.
6. **Restart the PC** so everything takes effect.

> To go back to the original state: **Restore → REVERT ALL**.

## Safety

- **Backup before changing anything:** the original value of each key, service and setting is saved in `backups\tutuboost_baseline.json`.
- **Full reversal:** REVERT ALL restores those values.
- **No network:** the program does not connect to the internet or send any data.
- **Readable code:** it is an open `.ps1`. Read it before running, if you like.
- **Risky items** are kept separate and turned off by default.

## Windows SmartScreen / antivirus warning

Because it is a new, independent program, Windows may show *"Windows protected your PC"* or your antivirus may be suspicious, since TutuBoost changes system settings. This is expected.

To open it anyway: **More info → Run anyway**.

If you prefer to verify the file, compare the hash:

```powershell
Get-FileHash .\TutuBoost.ps1 -Algorithm SHA256
```

The official SHA256 of each version is on the release page.

## Requirements

- Windows 10 or 11 (64-bit)
- PowerShell 5.1 (already included in Windows)
- An account with administrator permission

## Quick questions

**Will it break my Windows?** All changes are recorded and reversible. Still, create the restore point first.

**Do I need to restart?** Yes, some tweaks (boot and kernel) only take effect after a restart.

**Can I get VAC banned?** TutuBoost only changes Windows settings. It does not touch the game's process, memory or files.

**Can I use it with CSBoost or another program?** You can, but applying duplicate tweaks brings no extra gain.

## Disclaimer

This program changes Windows settings. Use at your own risk. It is provided "as is", without warranty, under the MIT license. Performance gains vary from PC to PC.

## License

[MIT](LICENSE) © 2026 — free to use, modify and redistribute.

---

<div align="center">

Like it? Leave a ⭐ on the repository.

</div>
