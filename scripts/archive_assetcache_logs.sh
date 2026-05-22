#!/bin/zsh
# AssetCache Logger Archivierung
# Version: 1.9.1-archive2
#
# Zweck:
# - stoppt den AssetCache-Logger-LaunchDaemon
# - verschiebt sichtbare Altdateien aus /Library/Logs/KommunalBIT
#   in das neue Archiv unter /Library/Application Support/KommunalBIT/AssetCacheLogger/archive
# - umfasst HU, CO und Legacy-RAW-Dateien aus v1.8.x/v1.9.x
# - migriert Inhalte aus dem alten Archivordner /Library/Logs/KommunalBIT/Archiv
# - entfernt den alten Archivordner danach
# - startet den Logger absichtlich NICHT neu
#
# Zielzustand:
# - alte Bestände liegen unter Application Support archive
# - /Library/Logs/KommunalBIT enthält keine alten AssetCache-CSV-Dateien mehr
# - /Library/Logs/KommunalBIT/Archiv existiert nicht mehr
# - anschließender Schritt: Deploy-Skript v1.9.1 ausführen

emulate -L zsh
setopt NO_NOMATCH

SCRIPT_VER="1.9.1-archive2"

BASE="/Library/Application Support/KommunalBIT/AssetCacheLogger"
ARCHIVE_DIR="${BASE}/archive"
LOGDIR="/Library/Logs/KommunalBIT"
OLD_ARCHIV_DIR="${LOGDIR}/Archiv"

LOGGER_LABEL="de.kommunalbit.assetcachelogger"
LAUNCHD_LABEL="system/${LOGGER_LABEL}"
PLIST_PATH="/Library/LaunchDaemons/${LOGGER_LABEL}.plist"

TS="$(date +%Y%m%d_%H%M%S)"

echo "===== AssetCache Logger Archivierung v${SCRIPT_VER} ====="
date
echo

echo "===== Kontext ====="
hostname
scutil --get ComputerName 2>/dev/null || true
id
echo "BASE=${BASE}"
echo "ARCHIVE_DIR=${ARCHIVE_DIR}"
echo "LOGDIR=${LOGDIR}"
echo "OLD_ARCHIV_DIR=${OLD_ARCHIV_DIR}"
echo "PLIST_PATH=${PLIST_PATH}"
echo

echo "===== Root-Prüfung ====="
if [[ "$(id -u)" != "0" ]]; then
  echo "FEHLER: Dieses Archivierungsskript muss als root laufen."
  echo "In Relution sollte das Skript automatisch als root laufen."
  echo "Keine Änderungen durchgeführt."
  exit 1
fi
echo "OK: läuft als root"
echo

echo "===== Zielstruktur anlegen ====="
mkdir -p "$ARCHIVE_DIR"

# Application-Support-Basis restriktiv halten.
chmod 700 "$BASE" 2>/dev/null || true
chmod 700 "$ARCHIVE_DIR" 2>/dev/null || true

ls -lah "$ARCHIVE_DIR" 2>&1
echo

archive_file() {
  local src="$1"

  [[ -f "$src" ]] || return 0

  local base clean dst n
  base="$(basename "$src")"

  # .csv nur am Ende entfernen, damit der Zielname lesbarer wird.
  clean="${base%.csv}"
  dst="${ARCHIVE_DIR}/${clean}_${TS}.csv"

  n=1
  while [[ -e "$dst" ]]; do
    dst="${ARCHIVE_DIR}/${clean}_${TS}_${n}.csv"
    n=$((n + 1))
  done

  echo "MOVE: $src"
  echo "  -> $dst"
  mv "$src" "$dst"
  local rc=$?
  echo "  rc=$rc"

  return "$rc"
}

migrate_old_archiv_file() {
  local src="$1"

  [[ -f "$src" ]] || return 0

  local rel flat clean dst n
  rel="${src#$OLD_ARCHIV_DIR/}"

  # Unterordnerstruktur aus altem Archiv flach und kollisionsarm im Dateinamen abbilden.
  flat="$(printf '%s' "$rel" | tr '/ ' '__')"
  clean="${flat%.csv}"
  dst="${ARCHIVE_DIR}/legacyArchiv_${clean}_${TS}.csv"

  n=1
  while [[ -e "$dst" ]]; do
    dst="${ARCHIVE_DIR}/legacyArchiv_${clean}_${TS}_${n}.csv"
    n=$((n + 1))
  done

  echo "MIGRATE: $src"
  echo "  -> $dst"
  mv "$src" "$dst"
  local rc=$?
  echo "  rc=$rc"

  return "$rc"
}

echo "===== LaunchDaemon stoppen ====="
echo "--- launchctl print vorher"
launchctl print "$LAUNCHD_LABEL" 2>&1 | sed -n '1,100p' || true
echo

echo "--- launchctl bootout"
if [[ -f "$PLIST_PATH" ]]; then
  launchctl bootout system "$PLIST_PATH" 2>&1 || true
else
  echo "Hinweis: Plist nicht gefunden: $PLIST_PATH"
fi
echo

echo "--- launchctl print nach bootout"
launchctl print "$LAUNCHD_LABEL" 2>&1 | sed -n '1,100p' || true
echo

echo "===== Sichtbare AssetCache-CSV-Dateien archivieren ====="
if [[ -d "$LOGDIR" ]]; then
  echo
  echo "--- HU-Dateien"
  find "$LOGDIR" -maxdepth 1 -type f -name '*_AssetCache_Hu_v*.csv' -print0 2>/dev/null | while IFS= read -r -d '' f; do
    archive_file "$f"
  done

  echo
  echo "--- CO-Dateien"
  find "$LOGDIR" -maxdepth 1 -type f -name '*_AssetCache_Co_v*.csv' -print0 2>/dev/null | while IFS= read -r -d '' f; do
    archive_file "$f"
  done

  echo
  echo "--- Legacy-RAW-Dateien"
  find "$LOGDIR" -maxdepth 1 -type f -name '*_AssetCacheRaw_v*.csv' -print0 2>/dev/null | while IFS= read -r -d '' f; do
    archive_file "$f"
  done
else
  echo "Hinweis: sichtbarer Logordner existiert nicht: $LOGDIR"
fi
echo

echo "===== Alten Archivordner migrieren ====="
if [[ -d "$OLD_ARCHIV_DIR" ]]; then
  echo "Alter Archivordner gefunden: $OLD_ARCHIV_DIR"
  echo

  find "$OLD_ARCHIV_DIR" -type f -print0 2>/dev/null | while IFS= read -r -d '' f; do
    migrate_old_archiv_file "$f"
  done

  echo
  echo "--- alten Archivordner entfernen"
  rm -rf "$OLD_ARCHIV_DIR"
  echo "remove_old_archiv_rc=$?"
else
  echo "Kein alter Archivordner vorhanden."
fi
echo

echo "===== Ergebnis: sichtbarer Logordner ====="
ls -lah "$LOGDIR" 2>&1 || true
echo

echo "===== Ergebnis: neues Archiv ====="
ls -lah "$ARCHIVE_DIR" 2>&1 || true
echo

echo "===== Ergebnis: LaunchDaemon bleibt gestoppt ====="
launchctl print "$LAUNCHD_LABEL" 2>&1 | sed -n '1,100p' || true
echo

echo "===== Hinweis ====="
echo "Das Archivierungsskript startet den Logger absichtlich nicht neu."
echo "Nächster Schritt: Deploy-Skript v1.9.1 ausführen."
echo

echo "===== Archivierung Ende ====="
date

exit 0
