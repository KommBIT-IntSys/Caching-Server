#!/bin/sh

# Asset Cache Monitoring – Deinstaller (KommunalBIT)
# Entfernt:
# - LaunchDaemon (korrekte .plist und historische _plist-Variante)
# - Monitoring-Script /usr/local/bin/assetcache_logger.sh
# - Konfigurationsdatei /etc/kommunalbit/schulen.conf
# - Log-/CSV-Dateien (aktuell, versioniert, historische Altlasten)
# - State-/Debug-/Temp-Dateien in /var/tmp
# Statuslog: /var/tmp/assetcache_uninstall.log

STATUS_FILE="/var/tmp/assetcache_uninstall.log"

# Sauberer Start: alte Statusdatei loeschen
/bin/rm -f "$STATUS_FILE" 2>/dev/null || true
: > "$STATUS_FILE" || exit 1

log() { printf '%s\n' "$*" >> "$STATUS_FILE"; }
fail() { log "RESULT=FAIL"; log "REASON=$*"; exit 1; }
ok()   { log "RESULT=OK";   exit 0; }

# Workaround: Relution ersetzt Punkte durch Unterstriche in Dateinamen
DOT='.'
PLIST_EXT="$(printf '%s%s' "$DOT" 'plist')"
CSV_EXT="$(printf '%s%s'   "$DOT" 'csv')"

PLIST_LABEL="de.kommunalbit.assetcachelogger"
PLIST_PATH="/Library/LaunchDaemons/${PLIST_LABEL}${PLIST_EXT}"
PLIST_PATH_BAD="/Library/LaunchDaemons/${PLIST_LABEL}_plist"
SCRIPT_PATH="/usr/local/bin/assetcache_logger.sh"
LOG_DIR="/Library/Logs/KommunalBIT"
ARCHIV_DIR="${LOG_DIR}/Archiv"
SCHULEN_CONF="/etc/kommunalbit/schulen.conf"

HOST="$(/usr/sbin/scutil --get HostName 2>/dev/null \
  || /usr/sbin/scutil --get LocalHostName 2>/dev/null \
  || /bin/hostname -s 2>/dev/null \
  || echo unknown)"
PREFIX="$(printf '%s' "$HOST" | /usr/bin/awk -F'-' '{print $1}')"

log "SCRIPT=assetcache_uninstaller"
log "TIME=$(date '+%F %T')"
log "HOST=${HOST}"
log "PREFIX=${PREFIX}"
log "RESULT=RUNNING"

# --- 1. LaunchDaemon entladen ------------------------------------------------
log "--- LaunchDaemon entladen ---"
/bin/launchctl bootout system "$PLIST_PATH"     >> "$STATUS_FILE" 2>&1 || true
/bin/launchctl bootout system "$PLIST_PATH_BAD" >> "$STATUS_FILE" 2>&1 || true
/bin/sleep 1

# --- 2. Installierte Dateien entfernen ---------------------------------------
log "--- Dateien entfernen ---"
/bin/rm -f "$PLIST_PATH"           >> "$STATUS_FILE" 2>&1 || true
/bin/rm -f "$PLIST_PATH_BAD"       >> "$STATUS_FILE" 2>&1 || true
/bin/rm -f "$SCRIPT_PATH"          >> "$STATUS_FILE" 2>&1 || true

# --- 3. Konfigurationsdatei entfernen ----------------------------------------
/bin/rm -f "$SCHULEN_CONF"         >> "$STATUS_FILE" 2>&1 || true
/bin/rmdir /etc/kommunalbit        >> "$STATUS_FILE" 2>&1 || true

# --- 4. Log-/CSV-Dateien entfernen -------------------------------------------
log "--- CSV-Dateien entfernen ---"
# Aktuelle / versionierte Dateien
/bin/rm -f "${LOG_DIR}"/*AssetCache*"${CSV_EXT}"    >> "$STATUS_FILE" 2>&1 || true
/bin/rm -f "${ARCHIV_DIR}"/*AssetCache*"${CSV_EXT}" >> "$STATUS_FILE" 2>&1 || true
# Historische Altlasten aus defekten Relution-Laeufen (_csv statt .csv)
/bin/rm -f "${LOG_DIR}"/*_csv    >> "$STATUS_FILE" 2>&1 || true
/bin/rm -f "${ARCHIV_DIR}"/*_csv >> "$STATUS_FILE" 2>&1 || true
# Ganz alte Ein-Datei-Variante
/bin/rm -f "${LOG_DIR}/assetcache${CSV_EXT}"    >> "$STATUS_FILE" 2>&1 || true
/bin/rm -f "${ARCHIV_DIR}/assetcache${CSV_EXT}" >> "$STATUS_FILE" 2>&1 || true

# Log-Verzeichnisse entfernen, wenn leer
/bin/rmdir "$ARCHIV_DIR" >> "$STATUS_FILE" 2>&1 || true
/bin/rmdir "$LOG_DIR"    >> "$STATUS_FILE" 2>&1 || true

# --- 5. State-/Temp-/Debug-Dateien in /var/tmp entfernen --------------------
log "--- Temp-Dateien entfernen ---"
/bin/rm -f /var/tmp/assetcache_logger_state.tsv          >> "$STATUS_FILE" 2>&1 || true
/bin/rm -f /var/tmp/assetcache_iosupdates_hu_state.tsv   >> "$STATUS_FILE" 2>&1 || true
/bin/rm -f /var/tmp/assetcache_gdmf_state.tsv            >> "$STATUS_FILE" 2>&1 || true
/bin/rm -f /var/tmp/assetcache_gdmf_debug.log            >> "$STATUS_FILE" 2>&1 || true
/bin/rm -f /var/tmp/assetcache_archive_state_*.tsv       >> "$STATUS_FILE" 2>&1 || true
/bin/rm -f /var/tmp/assetcache_logger.out                >> "$STATUS_FILE" 2>&1 || true
/bin/rm -f /var/tmp/assetcache_logger.err                >> "$STATUS_FILE" 2>&1 || true
/bin/rm -f /var/tmp/assetcache_logger_download.sh        >> "$STATUS_FILE" 2>&1 || true
/bin/rm -f /var/tmp/assetcache_deploy.log                >> "$STATUS_FILE" 2>&1 || true
# Alte Installer-/Cleanup-Statusdateien frueherer Laeufe
/bin/rm -f /var/tmp/assetcache_relution_installer_status.txt >> "$STATUS_FILE" 2>&1 || true
/bin/rm -f /var/tmp/assetcache_relution_cleanup_status.txt   >> "$STATUS_FILE" 2>&1 || true

# --- 6. Verifikation ---------------------------------------------------------
log "--- Verifikation ---"
if [ -e "$PLIST_PATH" ]; then
  fail "Korrekte plist noch vorhanden: $PLIST_PATH"
fi
if [ -e "$PLIST_PATH_BAD" ]; then
  fail "Historische _plist noch vorhanden: $PLIST_PATH_BAD"
fi
if [ -e "$SCRIPT_PATH" ]; then
  fail "Monitoring-Script noch vorhanden: $SCRIPT_PATH"
fi
if /bin/launchctl list 2>/dev/null | /usr/bin/grep -q "$PLIST_LABEL"; then
  fail "LaunchDaemon laut launchctl noch geladen."
fi

# Verbleibende Reste im Log-Verzeichnis protokollieren (kein Fehler, nur Info)
if [ -d "$LOG_DIR" ]; then
  REMAINS="$(/bin/ls -A "$LOG_DIR" 2>/dev/null)"
  [ -n "$REMAINS" ] && log "HINWEIS: Reste in ${LOG_DIR}: ${REMAINS}"
fi

ok
