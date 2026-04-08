#!/bin/zsh
# =============================================================================
# AssetCache Logger – CSV-Archivieren (KommunalBIT) v2
# Stoppt den Daemon, verschiebt alle aktuellen CSV-Dateien ins Archiv
# und startet den Daemon danach neu.
#
# Einsatz:    Relution MDM Script (läuft als root)
# Debug-Log:  /var/tmp/assetcache_archive.log
# =============================================================================

# --- Logging setup (Relution gibt keine Rückmeldung – alles in Log-Datei) ----
ARCHIVE_LOG="/var/tmp/assetcache_archive.log"
exec > >(tee -a "${ARCHIVE_LOG}") 2>&1
echo ""
echo "========================================================"
echo "AssetCache CSV-Archivieren v2 – $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================================"

# --- Konfiguration -----------------------------------------------------------
LOG_DIR="/Library/Logs/KommunalBIT"
ARCHIVE_DIR="${LOG_DIR}/Archiv"

# Relution-Bug: Punkte in bestimmten Zeichenketten werden zu Unterstrichen.
# Workaround: Punkt zur Laufzeit konstruieren.
DOT="$(printf '\x2e')"

PLIST_PATH="/Library/LaunchDaemons/de${DOT}kommunalbit${DOT}assetcachelogger${DOT}plist"
DAEMON_LABEL="de${DOT}kommunalbit${DOT}assetcachelogger"

# --- Hilfsfunktionen ---------------------------------------------------------
log()  { echo "[$(date '+%H:%M:%S')] $*"; }
fail() { echo "[$(date '+%H:%M:%S')] FEHLER: $*"; exit 1; }

# --- 1. Root-Check -----------------------------------------------------------
[[ $EUID -eq 0 ]] || fail "Muss als root ausgeführt werden."
log "Root – OK"

# --- 2. Log-Verzeichnis prüfen -----------------------------------------------
if [[ ! -d "${LOG_DIR}" ]]; then
  fail "Log-Verzeichnis nicht gefunden: ${LOG_DIR}"
fi
log "Log-Verzeichnis gefunden: ${LOG_DIR}"

# --- 3. Archiv-Verzeichnis anlegen (falls nicht vorhanden) -------------------
if [[ ! -d "${ARCHIVE_DIR}" ]]; then
  mkdir -p "${ARCHIVE_DIR}" || fail "Archiv-Verzeichnis konnte nicht angelegt werden."
  chown root:wheel "${ARCHIVE_DIR}"
  chmod 755 "${ARCHIVE_DIR}"
  log "Archiv-Verzeichnis angelegt: ${ARCHIVE_DIR}"
else
  log "Archiv-Verzeichnis vorhanden: ${ARCHIVE_DIR}"
fi

# --- 4. Daemon stoppen -------------------------------------------------------
DAEMON_WAS_RUNNING=0

if launchctl list "${DAEMON_LABEL}" &>/dev/null; then
  DAEMON_WAS_RUNNING=1
  log "Daemon '${DAEMON_LABEL}' läuft – wird gestoppt..."
  launchctl bootout system "${PLIST_PATH}" 2>&1 || true
  sleep 2
  log "Daemon gestoppt."
else
  log "Daemon '${DAEMON_LABEL}' läuft nicht – wird nach dem Archivieren gestartet."
fi

# --- 5. CSV-Dateien verschieben ----------------------------------------------
CSV_EXT="${DOT}csv"
MOVED=0
SKIPPED=0

log "Suche CSV-Dateien in ${LOG_DIR} ..."

for f in "${LOG_DIR}"/*"${CSV_EXT}"; do
  [[ -f "$f" ]] || continue
  BASENAME="$(basename "$f")"
  DEST="${ARCHIVE_DIR}/${BASENAME}"

  # Falls Zieldatei bereits existiert: Zeitstempel anhängen
  if [[ -f "${DEST}" ]]; then
    TS="$(date '+%Y%m%d_%H%M%S')"
    NAME_BASE="${BASENAME%${CSV_EXT}}"
    DEST="${ARCHIVE_DIR}/${NAME_BASE}_${TS}${CSV_EXT}"
  fi

  if mv "$f" "${DEST}" 2>/dev/null; then
    log "Verschoben: ${BASENAME} → Archiv/"
    MOVED=$((MOVED + 1))
  else
    log "WARNUNG: Konnte '${BASENAME}' nicht verschieben."
    SKIPPED=$((SKIPPED + 1))
  fi
done

# Legacy-Varianten (*_csv ohne Punkt – entstanden durch Relution-Bug beim Schreiben)
for f in "${LOG_DIR}"/*_csv; do
  [[ -f "$f" ]] || continue
  BASENAME="$(basename "$f")"
  DEST="${ARCHIVE_DIR}/${BASENAME}"
  if [[ -f "${DEST}" ]]; then
    DEST="${ARCHIVE_DIR}/${BASENAME}_$(date '+%Y%m%d_%H%M%S')"
  fi
  if mv "$f" "${DEST}" 2>/dev/null; then
    log "Verschoben (Legacy _csv): ${BASENAME} → Archiv/"
    MOVED=$((MOVED + 1))
  else
    log "WARNUNG: Konnte Legacy-Datei '${BASENAME}' nicht verschieben."
    SKIPPED=$((SKIPPED + 1))
  fi
done

if [[ $MOVED -eq 0 && $SKIPPED -eq 0 ]]; then
  log "Keine CSV-Dateien im Log-Verzeichnis gefunden – nichts zu tun."
elif [[ $SKIPPED -eq 0 ]]; then
  log "${MOVED} Datei(en) ins Archiv verschoben."
else
  log "${MOVED} Datei(en) verschoben, ${SKIPPED} Datei(en) konnten nicht verschoben werden (siehe oben)."
fi

# --- 6. Daemon neu starten ---------------------------------------------------
if [[ -f "${PLIST_PATH}" ]]; then
  log "Starte Daemon '${DAEMON_LABEL}' neu..."
  launchctl bootstrap system "${PLIST_PATH}" 2>&1
  BOOT_EXIT=$?
  sleep 1
  if [[ ${BOOT_EXIT} -eq 0 ]] && launchctl list "${DAEMON_LABEL}" &>/dev/null; then
    log "Daemon läuft wieder."
  else
    log "WARNUNG: Daemon konnte nicht neu gestartet werden (exit ${BOOT_EXIT})."
    log "         Manuell starten: launchctl bootstrap system ${PLIST_PATH}"
  fi
else
  log "WARNUNG: Plist nicht gefunden (${PLIST_PATH}) – Daemon nicht gestartet."
  log "         'Monitoring Deploy' in Relution ausführen, um ihn einzurichten."
fi

log "Fertig."
