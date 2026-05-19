# CLAUDE.md – AI Assistant Guide for AssetCache Monitoring

## Project Overview

**AssetCache Monitoring – KommunalBIT** is a macOS-based monitoring and logging system for Apple Content Caching on Mac Minis deployed in schools. It collects cache performance metrics every 15 minutes via a LaunchDaemon, writing three CSV files (machine-readable RAW, human-readable HU, and data-minimized CO) to `/Library/Logs/KommunalBIT/`. The primary goal is to distinguish between technical infrastructure issues and organizational/local factors when iOS/iPadOS update delivery is delayed.

**Current version: 1.9.0**  
**Primary language of documentation and comments: German**  
**Primary shell: zsh** (ShellCheck uses bash as closest approximation)

---

## Analytical Goal

The CSV files are not an end in themselves. The monitoring exists to answer one question per school: is a delay in iOS update adoption caused by infrastructure issues (KommunalBIT's responsibility) or organizational factors (local handling of iPads — charge level, Wi-Fi availability)?

**Analysis workflow:**

- Cache logger CO-CSV + Relution/MDM iPad export, evaluated one to two weeks after an iOS update event
- Relution export fields: Organisation | OS Version | OS Update Status | Letzte Verbindung | Batteriestand
- Device names are intentionally excluded from the analysis (data minimization); analysis is on site level, not individual device level
- Analysis tool: **Microsoft Copilot** (only AI permitted in the work environment)


**Implications for CO field design:**  
CO fields must be Copilot/Excel-friendly: flat structure, numeric fields as actual numbers (not formatted strings), no nested values, no IP addresses, no full hostnames.

Do not propose Python/HTML as the operational analysis layer. The production analysis workflow is Copilot + CSV. Small local validation helpers are acceptable only if explicitly requested and must not replace the documented Copilot pipeline.

**Analysis pipeline (Windows side):** The analyst works on a Windows admin workstation. Three PowerShell helpers prepare the data for Copilot: `Merge_Co_CSV.ps1` joins per-site CO-CSVs into one file, `AssetCache_Verdichten_Co.ps1` aggregates 15-minute rows into hourly rows (~75% fewer rows, time-series preserved), and `Relution-Export-Cleaner_Co_Batch.ps1` strips device names and reduces the organization name to the site code. macOS counterparts exist for admins working from a Mac.

Pre-aggregation is methodologically required, not an optimization. Copilot Basic in the browser silently truncates large input files and fabricates aggregates without flagging it. The hourly variant exists to keep input small enough for reliable processing.

**Deployment scale:** ~40 schools (growing).

---

## Repository Structure

    scripts/
      assetcache_logger.sh           # Main monitoring script – runs every 15 min
      deploy_assetcache_logger.sh    # MDM (Relution) deployment script
      uninstall_assetcache_logger.sh # Full removal and cleanup script
      archive_assetcache_logs.sh     # Archives existing CSV files before updates
      merge_co_csv.sh                # macOS: merge per-site CO-CSVs into one
      relution_cleaner_co.sh         # macOS: strip device names from Relution export
      LSI-Apple-Auswertung-v5.2.sh   # macOS: WID/Apple Security Advisory Auswertung für iOS-relevante LSIs
      Merge_Co_CSV.ps1               # Windows: same as merge_co_csv.sh
      AssetCache_Verdichten_Co.ps1   # Windows: aggregate 15-min rows to hourly rows
      LSI-Apple-Auswertung-v5.2.ps1  # Windows: WID/Apple Security Advisory Auswertung für iOS-relevante LSIs
      Relution-Export-Cleaner_Co_Batch.ps1 # Windows: Batch-Version, verarbeitet alle passenden Exporte im Skriptordner
    launchd/
      de.kommunalbit.assetcachelogger.plist  # LaunchDaemon config (900s interval)
    config/
      schulen.conf.example           # Template for school/site lookup table
    docs/
      AssetCache_Monitoring.md       # Full technical documentation (all 23 CSV fields)
      versioning-policy.md           # Versioning rules and project history
      Befehle_zum_Installieren.txt   # Manual installation reference
      Prompt-Entwicklung.md          # Methodology behind HOW_TO_COPILOT.md
    CHANGELOG.md                     # Version history
    README.md                        # Project overview and deployment guide
    HOW_TO_COPILOT.md                # End-user guide for the Copilot analysis workflow
    .github/workflows/shellcheck.yml # CI: ShellCheck linting on push/PR to scripts/**

---

## Tech Stack

- **Language**: Bash/zsh shell scripts — no external dependencies, no package manager
- **macOS-native tools**: `AssetCacheManagerUtil`, `launchctl`, `ifconfig`, `ipconfig`, `route`, `curl`, `awk`, `log show`
- **Deployment**: Relution MDM
- **CI**: GitHub Actions with ShellCheck v2.0.0
- **No build system**: scripts are deployed directly
- **Analysis layer**: Microsoft Copilot Basic (browser); the only AI permitted in the work environment. Helper scripts produce Copilot-compatible inputs
- **Licensing**: EUPL-1.2 (SPDX header in all shell scripts)

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

    docs: <description>
    ci: <description>
    feat: <description>
    fix: <description>

Examples from history: `docs: extend CSV Einordnung with AI-assisted analysis use case`, `ci: add workflow_dispatch trigger for manual ShellCheck runs`

---

## Versioning Policy (MAJOR.MINOR.PATCH)

| Type | When to use |
| --- | --- |
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
  

    timeout 30 /usr/bin/some_command || fallback_value

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

### RAW-first pipeline architecture

The main script processes data in a strict one-way pipeline — do not break this order:

1. **Collect**: all system measurements run once, results stored in `_`-prefixed intermediate variables
2. **Build RAW**: canonical RAW field variables are derived from the collected snapshot
3. **Validate/normalize RAW**: state file is written (delta baseline for next run)
4. **Build HU from RAW**: all HU fields are derived from RAW variables — no new system calls
5. **Build CO from RAW**: all CO fields are derived from RAW variables — no new system calls
6. **Write CSV**: RAW first, then HU, then CO


HU and CO must never trigger additional system measurements. If you add a new field, collect it in step 1 and derive views in steps 4 and 5.

### Triple CSV output model

The logger always writes three outputs. Keep them consistent:

- **RAW**: machine-readable, ISO 8601 timestamps, full precision, empty string for missing values
- **HU**: human-readable, local timestamps, percentages, `n/a` for missing values, visibility windows for change events
- **CO**: machine-readable, data-minimized, ISO 8601 timestamps, empty string for missing values; `SiteCode` field contains the hostname prefix only (not the full hostname); no IP addresses, no cumulative totals (`TotReturned`, `TotOrigin`), no `TotalsSince`, no pure troubleshooting fields (`DefaultIf`, `EN0`, `EN1`, `GatewayIP`, `WifiNoise`, `WifiCCA`); intended for AI-assisted and external analysis. CO is not a cosmetic variant of HU — it uses machine-readable formats throughout (ISO 8601, binary 0/1 flags, raw byte counts) but deliberately reduces the field set to omit identifying and internal-only data. CO is also the input format for the Copilot analysis pipeline, optionally pre-aggregated to hourly rows via `AssetCache_Verdichten_Co.ps1`


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

    shellcheck --shell=bash --severity=warning \
      --exclude=SC1090,SC1091,SC2034 \
      scripts/*.sh

There is no automated test suite beyond ShellCheck. Changes must be validated by deploying to a test Mac Mini with Apple Content Caching enabled.

---

## Deployment Reference

### Install (via MDM)

    scripts/deploy_assetcache_logger.sh
    # Verify:
    cat /var/tmp/assetcache_deploy.log  # should end with "Deployment complete."
    ls /Library/Logs/KommunalBIT/
    launchctl list de.kommunalbit.assetcachelogger

### Manual install

See `docs/Befehle_zum_Installieren.txt` for exact commands.

### Archive before updating

    scripts/archive_assetcache_logs.sh   # stops daemon, moves CSVs to Archiv/
    scripts/deploy_assetcache_logger.sh  # deploy new version

### Uninstall

    scripts/uninstall_assetcache_logger.sh

### Verify school config (schulen.conf)

    cat -A /etc/kommunalbit/schulen.conf | head -5
    # ^I = Tab (correct); spaces = Relution ate the tabs (broken)

---

## Installed Artifacts on Mac Mini

| Path | Description |
| --- | --- |
| `/usr/local/bin/assetcache_logger.sh` | Monitoring script |
| `/Library/LaunchDaemons/de.kommunalbit.assetcachelogger.plist` | LaunchDaemon (900s) |
| `/Library/Logs/KommunalBIT/` | CSV output directory |
| `/Library/Logs/KommunalBIT/<PREFIX>_AssetCache_Co_v<VERSION>.csv` | CO output per host (data-minimized, for AI-assisted/external analysis) |
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

## Constraints for AI Assistance

When working on this codebase, do not:

- Introduce external dependencies or package managers — everything uses macOS-native tools only
- Propose CSV schema changes without explicit discussion — RAW field stability is critical; the analysis layer depends on schema consistency across all schools
- Add fields to CO that are explicitly excluded by design (full hostname, IP addresses, cumulative totals, `TotalsSince`, `DefaultIf`, `WifiNoise`, `WifiCCA`) — their absence is an intentional data minimization decision, not an oversight
- Merge responsibilities across scripts — logger / deployer / uninstaller / archiver are intentionally separate
- Suggest zsh → bash migration; zsh is intentional on macOS targets
- "Fix" Relution workarounds (dot → underscore mangling) — these exist for a documented MDM bug, not by accident
- Suggest Python/HTML tooling for the analysis layer — Microsoft Copilot is the analysis environment; the CO-CSV is designed specifically for that tool
- Break the RAW-first pipeline order — HU and CO are always derived from RAW, never from independent system calls
- "Fix" the Copilot prompt by adding more rules when the next evaluation round shows errors — the prompt's effectiveness comes from order ("compute first, interpret second"), not from rule count. New rules accumulate, weigh down the prompt, and eventually compete with the order-first principle. Before adding a rule, ask whether the problem is a data problem or a prompt problem, and whether order can solve it. See `docs/Prompt-Entwicklung.md` for the reasoning behind this discipline


**Note on operator input:** The operator may use speech-to-text dictation. Known transcription artifacts: "Cash" → "Cache", "Revolution" → "Relution". Interpret by technical context.

---

## LSI-Apple-Auswertung

`scripts/LSI-Apple-Auswertung-v5.2.ps1` ist ein eigenständiges Windows-
Hilfsskript zur Auswertung von WID-Sicherheitsmeldungen (BSI/LSI-Bayern)
mit Bezug auf iOS/iPadOS/Safari. Es steht außerhalb des Hauptversionierungs-
schemas des Monitoring-Projekts und hat eine eigene Versionsnummer.

**Zweck:** Identifikation von iOS-/iPadOS-Schwachstellen im Feld anhand
der WID-API (Bayerisches Landesamt für Sicherheit in der Informationstechnik).
Ergebnis ist eine Gesamtauswertung als CSV mit Risikobewertung und
deutscher Kurzbeschreibung je Schwachstelleneintrag.

**Betriebsmodell:** Inkrementell — erkennt vorhandene Ausgabedatei und
fragt nur Neues nach. Erstlauf legt vollständig an.

**Kein Teil der AssetCache-Messpipeline.** Nicht in deploy/uninstall/archive
einbinden. Läuft manuell auf dem Windows-Adminarbeitsplatz bzw. dem Mac-Adminrechner.

**macOS-Pendant:** `scripts/LSI-Apple-Auswertung-v5.2.sh` — funktional identisch,
Abhängigkeiten: `curl` (macOS-nativ), `jq` (Homebrew), `python3` (macOS-nativ).
Nutzung: `./LSI-Apple-Auswertung-v5.2.sh [-d TAGE] [-m MAX] [-j] [-c] [-f]`

**Konfiguration:** `$ScriptWidApiKey` und `$RELEVANT_VERSIONS`-Array im
Skript-Header manuell pflegen.

---

## CSV Fields Reference (RAW/HU: 23 fields · CO: 14 fields)

| Field | RAW format | HU format | CO format |
| --- | --- | --- | --- |
| Hostname | string | string | SiteCode (prefix only) |
| Timestamp | ISO 8601 | local datetime | ISO 8601 |
| TotalsSince | ISO 8601 | visibility window (20 lines after change) | – |
| Peers | IPs (semikolon-getrennt) | count | PeerCnt (count) |
| ClientsCnt | N/Total | percentage | N/Total |
| iOSUpdates | string | visibility window (20 lines after change) | string |
| iOSBytes | bytes | human-readable | bytes |
| TotReturned | bytes | human-readable | – |
| TotOrigin | bytes | human-readable | – |
| ServedDelta | bytes | human-readable | bytes |
| OriginDelta | bytes | human-readable | bytes |
| CacheUsed | bytes | human-readable | bytes |
| CachePr | float | percentage | float |
| EN0 | IP / noip / down | up / noip / down | – |
| EN1 | IP / noip / down | up / noip / down | – |
| GatewayIP | IP | yes / no | – |
| DefaultIf | string | string | – |
| DNSRes | 1 / 0 | yes / no | 1 / 0 |
| AppleReach | 1 / 0 | yes / no | 1 / 0 |
| AppleTTFB | ms | ms | ms |
| WiFiSNR | dB | dB | dB |
| WifiNoise | dBm | dBm | – |
| WifiCCA | float | percentage | – |


Full field descriptions: `docs/AssetCache_Monitoring.md`

---

## Key Design Principles

1. **Separation of concerns**: logger, deployer, uninstaller, and archiver are distinct scripts — do not merge their responsibilities
2. **RAW is authoritative**: HU and CO are derived views; never compromise RAW fidelity for cosmetic reasons
3. **Fault tolerance over completeness**: prefer empty fields to crashes; use timeouts, fallbacks, and graceful degradation
4. **No external dependencies**: everything uses macOS-native tools; do not introduce package managers or third-party binaries
5. **Sensitive data stays out**: school configuration is always MDM-deployed, never hardcoded or committed
6. **Measure, don't speculate**: the goal is distinguishing technical from organizational causes — precision matters more than polish
7. **Data minimization for external outputs**: CO deliberately omits identifying fields (full hostname, IP addresses) and internal-only fields to enable external and AI-assisted analysis while limiting data exposure
8. **Order before rules** (analysis layer): When the AI analysis layer misbehaves, prefer enforcing a processing order over adding new rules. The Copilot prompt computes aggregates before interpreting them — this single discipline outperforms any number of threshold rules. The principle generalizes: structural constraints are followed reliably; threshold rules are not. Detailed reasoning in `docs/Prompt-Entwicklung.md`.
