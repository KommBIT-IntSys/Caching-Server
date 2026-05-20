#!/bin/zsh
set -u

# AssetCache Logger – Relution Archivierung v1.9.1
#
# Zweck:
# Stoppt den AssetCache-Logger und verschiebt die aktuell sichtbaren
# HU-/CO-Dateien aus /Library/Logs/KommunalBIT in das sichere Archiv
# unter /Library/Application Support/KommunalBIT/AssetCacheLogger/archive/.
#
# Wichtig:
# - Der Daemon wird danach NICHT neu gestartet.
# - Das RAW-Journal unter Application Support/journal bleibt unangetastet.
# - Keine Statusdateien, kein Logging, kein Rebuild, kein Neustart.
# - /Library/Logs/KommunalBIT/Archiv wird nicht mehr verwendet.

if [[ "$(/usr/bin/id -u)" -ne 0 ]]; then
  exit 77
fi

LABEL="de.kommunalbit.assetcachelogger"
PLIST="/Library/LaunchDaemons/${LABEL}.plist"
VISIBLE_DIR="/Library/Logs/KommunalBIT"
APP_SUPPORT_BASE="/Library/Application Support/KommunalBIT/AssetCacheLogger"
ARCHIVE_DIR="${APP_SUPPORT_BASE}/archive"
TS="$(/bin/date +%Y%m%d_%H%M%S)"

# 1. LaunchDaemon stoppen/entladen/deaktivieren.
# bootout kann fehlschlagen, wenn der Dienst bereits nicht geladen ist.
# disable sorgt dafür, dass er nicht versehentlich wieder losläuft.
if [[ -f "$PLIST" ]]; then
  /bin/launchctl bootout system "$PLIST" 2>/dev/null || true
fi
/bin/launchctl disable "system/${LABEL}" 2>/dev/null || true

# 2. Falls gerade noch ein Loggerprozess läuft: beenden.
# Danach kurz warten, damit kein Schreibvorgang mehr offen ist.
/usr/bin/pkill -f "/usr/local/bin/assetcache_logger.sh" 2>/dev/null || true
/bin/sleep 2

# 3. Sicheres Archiv unter Application Support anlegen.
/bin/mkdir -p "$ARCHIVE_DIR" 2>/dev/null || exit 10
/bin/chown root:wheel "$APP_SUPPORT_BASE" "$ARCHIVE_DIR" 2>/dev/null || true
/bin/chmod 700 "$APP_SUPPORT_BASE" "$ARCHIVE_DIR" 2>/dev/null || true

# 4. Nur sichtbare HU-/CO-Dateien archivieren.
# RAW-Journal bleibt unangetastet.
if [[ -d "$VISIBLE_DIR" ]]; then
  for f in "$VISIBLE_DIR"/*_AssetCache_Hu_v*.csv "$VISIBLE_DIR"/*_AssetCache_Co_v*.csv; do
    [[ -e "$f" ]] || continue
    base="$(/usr/bin/basename "$f")"
    name="${base%.csv}"
    /bin/mv "$f" "${ARCHIVE_DIR}/${name}_${TS}.csv" 2>/dev/null || true
  done
fi

# 5. Absichtlich kein Neustart.
exit 0/bin/launchctl disable "system/${LABEL}" 2>/dev/null || true

# 2. Falls gerade noch ein Loggerprozess läuft: beenden.
# Danach kurz warten, damit kein Schreibvorgang mehr offen ist.
/usr/bin/pkill -f "/usr/local/bin/assetcache_logger.sh" 2>/dev/null || true
/bin/sleep 2

# 3. Sicheres Archiv unter Application Support anlegen.
/bin/mkdir -p "$ARCHIVE_DIR" 2>/dev/null || exit 10
/bin/chown root:wheel "$APP_SUPPORT_BASE" "$ARCHIVE_DIR" 2>/dev/null || true
/bin/chmod 700 "$APP_SUPPORT_BASE" "$ARCHIVE_DIR" 2>/dev/null || true

# 4. Nur sichtbare HU-/CO-Dateien archivieren.
# RAW-Journal bleibt unangetastet.
if [[ -d "$VISIBLE_DIR" ]]; then
  for f in "$VISIBLE_DIR"/*_AssetCache_Hu_v*.csv "$VISIBLE_DIR"/*_AssetCache_Co_v*.csv; do
    [[ -e "$f" ]] || continue
    base="$(/usr/bin/basename "$f")"
    name="${base%.csv}"
    /bin/mv "$f" "${ARCHIVE_DIR}/${name}_${TS}.csv" 2>/dev/null || true
  done
fi

# 5. Absichtlich kein Neustart.
exit 0
