# win-cleanup

Windows disk & cache cleanup script with package manager maintenance.

## Features

- **Windows system cleanup**: Temp files, crash dumps, prefetch, thumbnail cache, Windows Update cache
- **Browser cache**: Chrome, Edge
- **Application cache**: Claude (safe parts only), NVIDIA, Docker, Cursor, VS Code
- **Package manager cache**: conda, pip, uv, npm, pnpm, yarn, bun, cargo, go, scoop, docker
- **Package updates** (optional): conda, pip, npm, scoop, winget
- **Recycle Bin**: Auto-empty
- **Protected paths**: Claude Code memory/config is never touched

## Usage

```powershell
# Preview what would be cleaned (no changes)
.\cleanup.ps1 -DryRun

# Run cleanup (with confirmation prompt)
.\cleanup.ps1

# Run cleanup without prompt
.\cleanup.ps1 -Force

# Clean + update all package managers
.\cleanup.ps1 -UpdatePackages

# Clean + update, no prompt
.\cleanup.ps1 -UpdatePackages -Force
```

## Scheduled Task

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
| Package Cache | conda/pip/npm/yarn/pnpm/cargo/go/scoop/docker | Packages re-download if needed |
| Recycle Bin | Deleted files | Permanent deletion |

## What is NEVER cleaned

- Claude Code config & memory (`%APPDATA%\Claude\claude-code`)
- Claude VM runtime (`%APPDATA%\Claude\vm_bundles`)
- Application data & settings
- Docker images & volumes (only dangling/unused via `docker system prune`)
- Any user documents or project files

## Requirements

- Windows 10/11
- PowerShell 5.1+
- Administrator rights (for scheduled task registration and system cache cleanup)

## License

MIT
