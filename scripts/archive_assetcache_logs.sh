#!/bin/zsh
# =============================================================================
# AssetCache Logger – Relution Archive Script (KommunalBIT) v1.9.1
#
# Zweck:
#   Stoppt den AssetCache-Logger und verschiebt die aktuell sichtbaren
#   HU-/CO-Dateien aus /Library/Logs/KommunalBIT in das sichere Archiv unter:
#
#   /Library/Application Support/KommunalBIT/AssetCacheLogger/archive/
#
# Vertrag:
#   - Der Daemon wird danach NICHT neu gestartet.
#   - Das RAW-Journal unter Application Support/journal bleibt unangetastet.
#   - Keine Statusdateien.
#   - Kein Rebuild.
#   - Kein Neustart.
#   - Kein /Library/Logs/KommunalBIT/Archiv.
#
# Visuelle Kontrolle:
#   Nach Ausführung liegen im laufenden Arbeitsordner keine HU-/CO-CSV-Dateien mehr.
#   Die verschobenen Dateien liegen unter Application Support/archive/.
# =============================================================================

set -u
setopt NULL_GLOB

if [[ "$(/usr/bin/id -u)" -ne 0 ]]; then
  exit 77
fi

DOT="$(printf '\x2e')"
SH_EXT="${DOT}sh"
PLIST_EXT="${DOT}plist"

LABEL="de${DOT}kommunalbit${DOT}assetcachelogger"
PLIST_PATH="/Library/LaunchDaemons/${LABEL}${PLIST_EXT}"
INSTALL_PATH="/usr/local/bin/assetcache_logger${SH_EXT}"

VISIBLE_DIR="/Library/Logs/KommunalBIT"
APP_SUPPORT_BASE="/Library/Application Support/KommunalBIT/AssetCacheLogger"
ARCHIVE_DIR="${APP_SUPPORT_BASE}/archive"

TS="$(/bin/date +%Y%m%d_%H%M%S)"

# 1. LaunchDaemon stoppen und deaktivieren.
# Der Daemon wird absichtlich NICHT wieder gestartet.
if [[ -f "$PLIST_PATH" ]]; then
  /bin/launchctl bootout system "$PLIST_PATH" 2>/dev/null || true
fi

/bin/launchctl disable "system/${LABEL}" 2>/dev/null || true

# 2. Falls gerade noch ein Loggerprozess läuft: beenden.
# Danach kurz warten, damit kein Schreibvorgang mehr offen ist.
/usr/bin/pkill -f "$INSTALL_PATH" 2>/dev/null || true
/usr/bin/pkill -f "/usr/local/bin/assetcache_logger_sh" 2>/dev/null || true
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
