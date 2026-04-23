# CLAUDE.md – AI Assistant Guide for AssetCache Monitoring

## Project Overview

**AssetCache Monitoring – KommunalBIT** is a macOS-based monitoring and logging system for Apple Content Caching on Mac Minis deployed in schools. It collects cache performance metrics every 15 minutes via a LaunchDaemon, writing two CSV files (machine-readable RAW and human-readable HU) to `/Library/Logs/KommunalBIT/`. The primary goal is to distinguish between technical infrastructure issues and organizational/local factors when iOS/iPadOS update delivery is delayed.

**Current version: 1.7.0**  
**Primary language of documentation and comments: German**  
**Primary shell: zsh** (ShellCheck uses bash as closest approximation)

---

## Repository Structure

```
scripts/
  assetcache_logger.sh           # Main monitoring script – runs every 15 min
  deploy_assetcache_logger.sh    # MDM (Relution) deployment script
  uninstall_assetcache_logger.sh # Full removal and cleanup script
  archive_assetcache_logs.sh     # Archives existing CSV files before updates
launchd/
  de.kommunalbit.assetcachelogger.plist  # LaunchDaemon config (900s interval)
config/
  schulen.conf.example           # Template for school/site lookup table
docs/
  AssetCache_Monitoring.md       # Full technical documentation (all 23 CSV fields)
  versioning-policy.md           # Versioning rules and project history
  Befehle_zum_Installieren.txt   # Manual installation reference
CHANGELOG.md                     # Version history
README.md                        # Project overview and deployment guide
.github/workflows/shellcheck.yml # CI: ShellCheck linting on push/PR to scripts/**
```

---

## Tech Stack

- **Language**: Bash/zsh shell scripts — no external dependencies, no package manager
- **macOS-native tools**: `AssetCacheManagerUtil`, `launchctl`, `ifconfig`, `ipconfig`, `route`, `curl`, `awk`, `log show`
- **Deployment**: Relution MDM
- **CI**: GitHub Actions with ShellCheck v2.0.0
- **No build system**: scripts are deployed directly

---

## Development Workflow

### Branching

Develop on feature branches, merge to `main` via pull request. The `main` branch is the stable, releasable baseline. ShellCheck runs automatically on push/PR when `scripts/**` changes.

### Making Changes

1. Read the existing script thoroughly before editing — patterns and conventions matter
2. Update `CHANGELOG.md` for every functional change
3. Update `README.md` if structure, deployment steps, or artifacts change
4. Update `docs/AssetCache_Monitoring.md` if CSV fields or behavior change
5. Bump `SCRIPT_VER` inside `assetcache_logger.sh` when releasing a new version
6. Update version in `CHANGELOG.md` and `README.md` to match

### Commit Message Convention

Use short prefixes:
```
docs: <description>
ci: <description>
feat: <description>
fix: <description>
```

Examples from history: `docs: extend CSV Einordnung with AI-assisted analysis use case`, `ci: add workflow_dispatch trigger for manual ShellCheck runs`

---

## Versioning Policy (MAJOR.MINOR.PATCH)

| Type  | When to use |
|-------|-------------|
| PATCH | Quoting fixes, path corrections, error handling, minor deploy/cleanup fixes, doc corrections without functional change |
| MINOR | New CSV field, new GDMF logic, new checks, new/changed deploy logic, new analysis dimension |
| MAJOR | New data model, structural CSV change, fundamental configuration or architecture overhaul |

**Release criteria** — all must be true before bumping a version:
1. Code is consistently committed
2. README and CHANGELOG match the functional state
3. The rollout purpose is clear
4. It is documented whether this is a test or production state

A version covers: `assetcache_logger.sh`, `deploy_assetcache_logger.sh`, `uninstall_assetcache_logger.sh`, the LaunchDaemon plist, `README.md`, and `CHANGELOG.md`.

---

## Script Conventions

### Safety requirements (follow in all scripts)
- `set -u` is required in `assetcache_logger.sh` — error on undefined variables. The operational scripts (`deploy`, `archive`, `uninstall`) do not use it; `uninstall_assetcache_logger.sh` uses `#!/bin/sh` and is intentionally kept minimal.
- Quote all variable expansions: `"${VAR}"` not `$VAR`
- Wrap external commands in timeout guards (30–60 seconds):
  ```zsh
  timeout 30 /usr/bin/some_command || fallback_value
  ```
- Use `csv_escape` / `emit_csv_line` helpers for CSV output — never construct CSV by hand
- Validate numeric values before arithmetic with `is_uint` / `is_int` guards

### Shell target
`assetcache_logger.sh`, `deploy_assetcache_logger.sh`, and `archive_assetcache_logs.sh` use `#!/bin/zsh`. `uninstall_assetcache_logger.sh` uses `#!/bin/sh` (intentionally POSIX-minimal). ShellCheck runs all scripts as `--shell=bash` (zsh not natively supported). Excluded rules: `SC1090`, `SC1091`, `SC2034`.

### State files
Delta calculations rely on TSV state files under `/var/tmp/`:
- `assetcache_logger_state.tsv` — main delta state
- `assetcache_iosupdates_hu_state.tsv` — iOS update visibility window
- `assetcache_totalssince_hu_state.tsv` — TotalsSince visibility window
- `assetcache_gdmf_state.tsv` — GDMF cache/signature tracking
- `assetcache_archive_state_<PREFIX>.tsv` — per-host archive tracking (one file per hostname prefix)

When adding a new state file, always add cleanup for it in `uninstall_assetcache_logger.sh`.

### Dual CSV output model
The logger always writes two outputs. Keep them consistent:
- **RAW**: machine-readable, ISO 8601 timestamps, full precision, empty string for missing values
- **HU**: human-readable, local timestamps, percentages, `n/a` for missing values, visibility windows for change events

Never mix cosmetic formatting into RAW. RAW is the authoritative data source.

### Visibility windows (HU only)
When a value changes (e.g. iOS version, TotalsSince), show it for the next 20 lines in HU output, then suppress until next change. Track this via the corresponding `_hu_state.tsv` file.

### GDMF integration
- Cache Apple GDMF API responses locally
- Detect changes via response signature
- Fall back to cached version if the API request fails
- Debug log trimmed to 1000 lines maximum

---

## Relution MDM Workarounds

Relution 26.1.1 mangles scripts by replacing dots with underscores in specific patterns:
- `raw.githubusercontent.com` → `raw_githubusercontent.com`
- `.csv` → `_csv`
- `.plist` → `_plist`

**Workarounds in place:**
- Construct the GitHub raw URL dynamically using `printf '\x2e'` (hex dot) in the deploy script
- The uninstall script removes both `.plist` and `_plist` variants of artifacts
- After editing scripts in Relution, always verify the deploy log for correct URLs and filenames

---

## CI / Linting

ShellCheck runs automatically on push or PR when any file in `scripts/**` changes. It can also be triggered manually via `workflow_dispatch`.

To lint locally (requires ShellCheck installed):
```bash
shellcheck --shell=bash --severity=warning \
  --exclude=SC1090,SC1091,SC2034 \
  scripts/*.sh
```

There is no automated test suite beyond ShellCheck. Changes must be validated by deploying to a test Mac Mini with Apple Content Caching enabled.

---

## Deployment Reference

### Install (via MDM)
```sh
scripts/deploy_assetcache_logger.sh
# Verify:
cat /var/tmp/assetcache_deploy.log  # should end with "Deployment complete."
ls /Library/Logs/KommunalBIT/
launchctl list de.kommunalbit.assetcachelogger
```

### Manual install
See `docs/Befehle_zum_Installieren.txt` for exact commands.

### Archive before updating
```sh
scripts/archive_assetcache_logs.sh   # stops daemon, moves CSVs to Archiv/
scripts/deploy_assetcache_logger.sh  # deploy new version
```

### Uninstall
```sh
scripts/uninstall_assetcache_logger.sh
```

### Verify school config (schulen.conf)
```sh
cat -A /etc/kommunalbit/schulen.conf | head -5
# ^I = Tab (correct); spaces = Relution ate the tabs (broken)
```

---

## Installed Artifacts on Mac Mini

| Path | Description |
|------|-------------|
| `/usr/local/bin/assetcache_logger.sh` | Monitoring script |
| `/Library/LaunchDaemons/de.kommunalbit.assetcachelogger.plist` | LaunchDaemon (900s) |
| `/Library/Logs/KommunalBIT/` | CSV output directory |
| `/Library/Logs/KommunalBIT/Archiv/` | Archive for old CSV versions |
| `/etc/kommunalbit/schulen.conf` | School lookup table (MDM-deployed, not in repo) |
| `/var/tmp/assetcache_*.tsv` | State files for delta calculations |

---

## What Does NOT Belong in This Repository

- Production `schulen.conf` with real school codes and iPad counts
- Relution deployment templates containing real site data
- Any per-school monitoring results or CSV exports
- Credentials or API keys
- Internal site-specific logic that hasn't been abstracted

Only include: example configurations, anonymized examples, publishable technical documentation.

---

## CSV Fields Reference (23 total)

| Field | RAW format | HU format |
|-------|-----------|-----------|
| Hostname | string | string |
| Timestamp | ISO 8601 | local datetime |
| TotalsSince | ISO 8601 | visibility window (20 lines after change) |
| Peers | int | int |
| ClientsCnt | N/Total | percentage |
| iOSUpdates | string | visibility window (20 lines after change) |
| iOSBytes | bytes | human-readable |
| TotReturned | bytes | human-readable |
| TotOrigin | bytes | human-readable |
| ServedDelta | bytes | human-readable |
| OriginDelta | bytes | human-readable |
| CacheUsed | bytes | human-readable |
| CachePr | float | percentage |
| EN0 | status | status |
| EN1 | status | status |
| GatewayIP | IP | IP |
| DefaultIf | string | string |
| DNSRes | ok/fail | ok/fail |
| AppleReach | ok/fail | ok/fail |
| AppleTTFB | ms | ms |
| WiFiSNR | dB | dB |
| WifiNoise | dBm | dBm |
| WifiCCA | float | percentage |

Full field descriptions: `docs/AssetCache_Monitoring.md`

---

## Key Design Principles

1. **Separation of concerns**: logger, deployer, uninstaller, and archiver are distinct scripts — do not merge their responsibilities
2. **RAW is authoritative**: HU is a derived, human-friendly view; never compromise RAW fidelity for cosmetic reasons
3. **Fault tolerance over completeness**: prefer empty fields to crashes; use timeouts, fallbacks, and graceful degradation
4. **No external dependencies**: everything uses macOS-native tools; do not introduce package managers or third-party binaries
5. **Sensitive data stays out**: school configuration is always MDM-deployed, never hardcoded or committed
6. **Measure, don't speculate**: the goal is distinguishing technical from organizational causes — precision matters more than polish
