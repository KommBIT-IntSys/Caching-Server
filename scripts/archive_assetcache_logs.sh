#!/bin/zsh
# =============================================================================
# AssetCache Logger – Archivierungsskript v1.9.0 (KommunalBIT)
# SPDX-License-Identifier: EUPL-1.2
#
# Archiviert sichtbare HU/CO nach Application Support (dauerhafter Archivort)
# und setzt visible_epoch_<PREFIX>.tsv, damit der Logger beim nächsten Rebuild
# ausschließlich den neuen Abschnitt aufbaut.
#
# Das RAW-Journal wird niemals verschoben oder gelöscht.
# /Library/Logs/KommunalBIT/Archiv erhält nur Komfortkopien (nicht maßgeblich).
#
# Einsatz:    Manuell als root oder via Relution MDM (läuft als root)
# Debug-Log:  /var/tmp/assetcache_archive.log
#
# Aufruf im Update-Workflow (Relution):
#   1. archive_assetcache_logs.sh  ← dieser Schritt; stoppt + startet Daemon
#   2. deploy_assetcache_logger.sh ← deployt neue Skriptversion (startet Daemon erneut)
# =============================================================================

ARCHIVE_LOG="/var/tmp/assetcache_archive.log"
exec > >(tee -a "${ARCHIVE_LOG}") 2>&1
echo ""
echo "========================================================"
echo "AssetCache Archivieren v1.9.0 – $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================================"

# --- Relution-Workaround: Punkte in bestimmten Mustern werden zu Unterstrichen
DOT="$(printf '\x2e')"
DOT_CSV="${DOT}csv"

PLIST_PATH="/Library/LaunchDaemons/de${DOT}kommunalbit${DOT}assetcachelogger${DOT}plist"
DAEMON_LABEL="de${DOT}kommunalbit${DOT}assetcachelogger"

# --- Pfade (identisch mit assetcache_logger.sh v1.9.0) ----------------------
VISIBLE_DIR="/Library/Logs/KommunalBIT"
VISIBLE_ARCHIVDIR="${VISIBLE_DIR}/Archiv"
APP_SUPPORT_BASE="/Library/Application Support/KommunalBIT/AssetCacheLogger"
JOURNAL_DIR="${APP_SUPPORT_BASE}/journal"
STATE_DIR="${APP_SUPPORT_BASE}/state"
ARCHIVE_BASE_DIR="${APP_SUPPORT_BASE}/archive"
RAW_SCHEMA_VER="schema1"
SCRIPT_VER="1.9.0"

# --- Host / Prefix (identische Logik wie Logger) ----------------------------
HOST="$( /usr/sbin/scutil --get HostName 2>/dev/null \
  || /usr/sbin/scutil --get LocalHostName 2>/dev/null \
  || /bin/hostname -s 2>/dev/null \
  || echo "" )"
[[ -z "${HOST:-}" ]] && HOST="unknown"
if [[ "$HOST" == *-Mac-Mini* ]]; then
  PREFIX="${HOST%%-Mac-Mini*}"
else
  PREFIX="${HOST%%-*}"
fi

RAW_JOURNAL="${JOURNAL_DIR}/${PREFIX}_AssetCacheRaw_${RAW_SCHEMA_VER}.csv"
VISIBLE_EPOCH_FILE="${STATE_DIR}/visible_epoch_${PREFIX}.tsv"
OUT_HU="${VISIBLE_DIR}/${PREFIX}_AssetCache_Hu_v${SCRIPT_VER}.csv"
OUT_CO="${VISIBLE_DIR}/${PREFIX}_AssetCache_Co_v${SCRIPT_VER}.csv"

# --- Hilfsfunktionen ---------------------------------------------------------
log()  { echo "[$(date '+%H:%M:%S')] $*"; }
fail() { echo "[$(date '+%H:%M:%S')] FEHLER: $*"; exit 1; }

# --- 1. Root-Check -----------------------------------------------------------
[[ "$(/usr/bin/id -u)" -eq 0 ]] || fail "Muss als root ausgefuehrt werden."
log "Root – OK"
log "Host: ${HOST}  Prefix: ${PREFIX}"

# --- 2. Verzeichnisse sicherstellen ------------------------------------------
for _dir in "$VISIBLE_ARCHIVDIR" "$ARCHIVE_BASE_DIR"; do
  if [[ ! -d "$_dir" ]]; then
    /bin/mkdir -p "$_dir" 2>/dev/null || fail "Verzeichnis konnte nicht angelegt werden: $_dir"
    /bin/chown root:wheel "$_dir" 2>/dev/null || true
    /bin/chmod 755 "$_dir" 2>/dev/null || true
    log "Verzeichnis angelegt: $_dir"
  fi
done

# --- 3. Daemon stoppen -------------------------------------------------------
DAEMON_WAS_RUNNING=0
if launchctl list "${DAEMON_LABEL}" &>/dev/null; then
  DAEMON_WAS_RUNNING=1
  log "Daemon '${DAEMON_LABEL}' laeuft – wird gestoppt..."
  launchctl bootout system "${PLIST_PATH}" 2>&1 || true
  sleep 2
  log "Daemon gestoppt."
else
  log "Daemon '${DAEMON_LABEL}' laeuft nicht."
fi

# --- 4. Durables Archivverzeichnis anlegen -----------------------------------
TS_ARCH="$(date +%Y%m%d_%H%M%S)"
ARCH_DIR="${ARCHIVE_BASE_DIR}/${TS_ARCH}_${PREFIX}"
/bin/mkdir -p "$ARCH_DIR" 2>/dev/null || fail "Archiv-Verzeichnis konnte nicht angelegt werden: $ARCH_DIR"
/bin/chown root:wheel "$ARCH_DIR" 2>/dev/null || true
/bin/chmod 700 "$ARCH_DIR" 2>/dev/null || true
log "Durable Archivverzeichnis: $ARCH_DIR"

# --- 5. Letzten Journal-Timestamp für visible_epoch ermitteln ---------------
LAST_JOURNAL_TS=""
if [[ -f "$RAW_JOURNAL" ]]; then
  LAST_JOURNAL_TS="$(/usr/bin/tail -n 1 "$RAW_JOURNAL" 2>/dev/null \
    | /usr/bin/perl -e '
      my $line = <STDIN>; chomp $line;
      if ($line =~ /^"[^"]*","([^"]*)"/) { print $1; }
    ' 2>/dev/null)"
  log "Letzter Journal-Timestamp: ${LAST_JOURNAL_TS:-nicht ermittelbar}"
else
  log "WARN: Kein RAW-Journal gefunden: $RAW_JOURNAL"
fi

# --- 6. HU archivieren -------------------------------------------------------
HU_LINES=0
HU_ARCHIVED=0
if [[ -f "$OUT_HU" ]]; then
  DST_HU="${ARCH_DIR}/$(basename "$OUT_HU")"
  if /bin/cp "$OUT_HU" "$DST_HU" 2>/dev/null; then
    HU_LINES="$(/usr/bin/wc -l < "$OUT_HU" 2>/dev/null | /usr/bin/tr -d ' ')"
    /bin/chown root:wheel "$DST_HU" 2>/dev/null || true
    /bin/chmod 640 "$DST_HU" 2>/dev/null || true
    # Komfortkopie nach Library/Logs/Archiv (nicht maßgeblich)
    /bin/cp "$DST_HU" \
      "${VISIBLE_ARCHIVDIR}/${PREFIX}_AssetCache_Hu_v${SCRIPT_VER}_${TS_ARCH}${DOT_CSV}" \
      2>/dev/null || true
    log "HU archiviert: $(basename "$OUT_HU") (${HU_LINES} Zeilen)"
    HU_ARCHIVED=1
  else
    log "WARN: HU konnte nicht archiviert werden."
  fi
else
  log "HU-Datei nicht vorhanden: $OUT_HU"
fi

# --- 7. CO archivieren -------------------------------------------------------
CO_LINES=0
CO_ARCHIVED=0
if [[ -f "$OUT_CO" ]]; then
  DST_CO="${ARCH_DIR}/$(basename "$OUT_CO")"
  if /bin/cp "$OUT_CO" "$DST_CO" 2>/dev/null; then
    CO_LINES="$(/usr/bin/wc -l < "$OUT_CO" 2>/dev/null | /usr/bin/tr -d ' ')"
    /bin/chown root:wheel "$DST_CO" 2>/dev/null || true
    /bin/chmod 640 "$DST_CO" 2>/dev/null || true
    /bin/cp "$DST_CO" \
      "${VISIBLE_ARCHIVDIR}/${PREFIX}_AssetCache_Co_v${SCRIPT_VER}_${TS_ARCH}${DOT_CSV}" \
      2>/dev/null || true
    log "CO archiviert: $(basename "$OUT_CO") (${CO_LINES} Zeilen)"
    CO_ARCHIVED=1
  else
    log "WARN: CO konnte nicht archiviert werden."
  fi
else
  log "CO-Datei nicht vorhanden: $OUT_CO"
fi

# --- 8. Optionaler RAW-Auszug (Snapshot des Journals) -----------------------
# Das Journal selbst bleibt unberührt; hier entsteht nur eine Read-only-Kopie.
if [[ -f "$RAW_JOURNAL" ]]; then
  RAW_EXPORT="${ARCH_DIR}/${PREFIX}_AssetCacheRaw_export_${RAW_SCHEMA_VER}${DOT_CSV}"
  if /bin/cp "$RAW_JOURNAL" "$RAW_EXPORT" 2>/dev/null; then
    /bin/chown root:wheel "$RAW_EXPORT" 2>/dev/null || true
    /bin/chmod 640 "$RAW_EXPORT" 2>/dev/null || true
    RAW_LINES="$(/usr/bin/wc -l < "$RAW_EXPORT" 2>/dev/null | /usr/bin/tr -d ' ')"
    log "RAW-Journal-Snapshot: $(basename "$RAW_EXPORT") (${RAW_LINES} Zeilen)"
  else
    log "WARN: RAW-Auszug konnte nicht erstellt werden."
  fi
fi

# --- 9. Manifest schreiben ---------------------------------------------------
{
  printf "Host:           %s\n" "$HOST"
  printf "Prefix:         %s\n" "$PREFIX"
  printf "Archiviert:     %s\n" "$(date '+%Y-%m-%d %H:%M:%S')"
  printf "Script-Version: %s\n" "$SCRIPT_VER"
  printf "Journal:        %s\n" "$RAW_JOURNAL"
  printf "HU-Zeilen:      %s\n" "$HU_LINES"
  printf "CO-Zeilen:      %s\n" "$CO_LINES"
  [[ -n "${LAST_JOURNAL_TS:-}" ]] && printf "visible_epoch:  %s\n" "$LAST_JOURNAL_TS"
} > "${ARCH_DIR}/manifest.txt" 2>/dev/null || true
log "Manifest geschrieben."

# --- 10. visible_epoch setzen ------------------------------------------------
# Signalisiert dem Logger: HU/CO absichtlich archiviert, nicht verloren.
# Rebuild baut nur Zeilen nach diesem Timestamp auf.
if [[ -n "${LAST_JOURNAL_TS:-}" ]]; then
  printf "%s\n" "$LAST_JOURNAL_TS" > "$VISIBLE_EPOCH_FILE" 2>/dev/null \
    && log "visible_epoch gesetzt: $LAST_JOURNAL_TS" \
    || log "WARN: visible_epoch konnte nicht geschrieben werden."
else
  log "WARN: visible_epoch nicht gesetzt (kein Journal-Timestamp ermittelbar)."
fi

# --- 11. Sichtbare HU/CO entfernen ------------------------------------------
[[ "$HU_ARCHIVED" -eq 1 ]] && /bin/rm -f "$OUT_HU" 2>/dev/null && log "HU-Sichtdatei entfernt."
[[ "$CO_ARCHIVED" -eq 1 ]] && /bin/rm -f "$OUT_CO" 2>/dev/null && log "CO-Sichtdatei entfernt."

# Legacy-Dateien (*_csv, entstanden durch Relution-Schreibfehler) bereinigen
for _f in "${VISIBLE_DIR}"/*_csv; do
  [[ -f "$_f" ]] || continue
  /bin/rm -f "$_f" 2>/dev/null && log "Legacy-Datei entfernt: $(basename "$_f")"
done

# --- 12. Daemon neu starten --------------------------------------------------
if [[ "$DAEMON_WAS_RUNNING" -eq 1 ]]; then
  if [[ -f "$PLIST_PATH" ]]; then
    launchctl bootstrap system "$PLIST_PATH" 2>&1 || true
    sleep 1
    if launchctl list "${DAEMON_LABEL}" &>/dev/null; then
      log "Daemon neu gestartet."
    else
      log "WARN: Daemon konnte nicht neu gestartet werden – bitte manuell pruefen."
    fi
  else
    log "WARN: Plist nicht gefunden – Daemon nicht neu gestartet: $PLIST_PATH"
  fi
else
  log "Daemon bleibt gestoppt (war nicht aktiv)."
fi

echo ""
echo "========================================================"
log "Archivierung abgeschlossen."
log "Durables Archiv: $ARCH_DIR"
echo "========================================================"
