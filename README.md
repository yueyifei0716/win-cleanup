# win-cleanup

Windows disk & cache cleanup tool with desktop GUI and CLI.

## Desktop App (GUI)

A native desktop application with real-time disk visualization, one-click cleanup, and history charts.

### Features

- **Dashboard** - Disk usage overview with live bar charts for all drives
- **Scan & Clean** - Scan all cleanable caches, select items, one-click cleanup
- **Cache Distribution** - Doughnut chart showing what's consuming space
- **Package Updates** - Update conda, pip, npm, scoop, winget from the UI
- **History** - Bar chart and table of past cleanups with freed space tracking
- **Protected Paths** - Claude Code memory/config is never touched

### Run from source

```powershell
# Install dependencies (Python 3.13 recommended)
pip install pywebview psutil

# Launch
python app.py

# Or use the batch file
run.bat
```

### Build standalone exe

```powershell
pip install pyinstaller
build.bat
# Output: dist/WinCleanup.exe (13 MB, no Python needed)
```

Double-click `WinCleanup.exe` to launch.

## CLI Script

For headless / scheduled use:

```powershell
# Preview what would be cleaned (no changes)
.\cleanup.ps1 -DryRun

# Run cleanup (with confirmation prompt)
.\cleanup.ps1

# Run cleanup without prompt
.\cleanup.ps1 -Force

# Clean + update all package managers
.\cleanup.ps1 -UpdatePackages -Force
```

### Scheduled Task

Run `schedule.ps1` as Administrator to set up automatic cleanup:

```powershell
# Register weekly cleanup (Sunday 3 AM)
.\schedule.ps1 -Register

# Register daily cleanup
.\schedule.ps1 -Register -Interval Daily

# Remove scheduled task
.\schedule.ps1 -Unregister
```

## What gets cleaned

| Category | Items | Impact |
|----------|-------|--------|
| Windows Temp | `%TEMP%`, `C:\Windows\Temp` | None - auto-regenerated |
| System Cache | Thumbnails, Prefetch, Update Cache, Crash Dumps | Slight slowdown on first access |
| Browser Cache | Chrome/Edge cache, code cache, SW cache | Pages load slower on first visit |
| App Cache | Claude GPU/render cache, NVIDIA shader cache, Docker temp | Auto-rebuilt on next launch |
| IDE Cache | VS Code, Cursor cache and cached data | Auto-rebuilt on next launch |
| Package Cache | conda, pip, uv, npm, pnpm, yarn, bun, cargo, go, scoop, docker | Packages re-download if needed |
| Recycle Bin | Deleted files | Permanent deletion |

## What is NEVER cleaned

- Claude Code config & memory (`%APPDATA%\Claude\claude-code`)
- Claude VM runtime (`%APPDATA%\Claude\vm_bundles`)
- Application data & settings
- Docker images & volumes (only dangling/unused via `docker system prune`)
- Any user documents or project files

## Requirements

- Windows 10/11
- Python 3.10+ (for running from source)
- Administrator rights recommended (for system cache cleanup)

## License

MIT
