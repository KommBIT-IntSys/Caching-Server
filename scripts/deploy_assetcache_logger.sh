#!/bin/zsh
# =============================================================================
# AssetCache Logger – MDM Deployment Script (KommunalBIT) v1.9.0
#
# Deployt den AssetCache Logger via Relution MDM.
#
# Aufgaben:
#   1. Sichtbaren Arbeitsordner und Application-Support-Struktur anlegen
#   2. Benutzer admin Lese-/Schreibrechte auf Application-Support-Bereich geben
#   3. assetcache_logger.sh von GitHub laden
#   4. Skript nach /usr/local/bin installieren
#   5. LaunchDaemon-Plist schreiben
#   6. LaunchDaemon explizit aktivieren, laden und starten
#
# Wichtig:
#   - Dieses Skript archiviert keine bestehenden Monitoring-Dateien.
#   - Archivierung ist Aufgabe des separaten Archivierungsskripts.
#   - /Library/Logs/KommunalBIT ist nur sichtbarer Arbeitsordner.
#   - /Library/Application Support/KommunalBIT/AssetCacheLogger ist der dauerhafte Bereich.
#
# Relution-Hinweis:
#   Relution zeigt stdout/stderr nicht zuverlässig sichtbar an.
#   Dieses Deploy-Skript schreibt zusätzlich nach:
#   /var/tmp/assetcache_deploy.log
# =============================================================================

set -u

# --- Logging setup -----------------------------------------------------------

DEPLOY_LOG="/var/tmp/assetcache_deploy.log"
exec > >(tee -a "${DEPLOY_LOG}") 2>&1

DOT="$(printf '\x2e')"
SH_EXT="${DOT}sh"
PLIST_EXT="${DOT}plist"
SCRIPT_DEPLOY_VER="1${DOT}9${DOT}0"

echo ""
echo "========================================================"
echo "AssetCache Logger Deployment v${SCRIPT_DEPLOY_VER} – $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================================"

# --- Configuration -----------------------------------------------------------

# Build URL and file extensions in parts – Relution can mangle literal dots
# in raw.githubusercontent.com, .sh, .plist and similar strings.
_GH_RAW="raw${DOT}githubusercontent${DOT}com"

SCRIPT_NAME="assetcache_logger${SH_EXT}"
SCRIPT_URL="https://${_GH_RAW}/KommBIT-IntSys/Caching-Server/main/scripts/${SCRIPT_NAME}"

INSTALL_PATH="/usr/local/bin/${SCRIPT_NAME}"

DAEMON_LABEL="de${DOT}kommunalbit${DOT}assetcachelogger"
PLIST_PATH="/Library/LaunchDaemons/${DAEMON_LABEL}${PLIST_EXT}"

# Alte kaputte Relution-Variante aus früheren Tests, falls vorhanden.
BAD_PLIST_PATH="/Library/LaunchDaemons/de${DOT}kommunalbit${DOT}assetcachelogger_plist"

VISIBLE_DIR="/Library/Logs/KommunalBIT"

APP_SUPPORT_BASE="/Library/Application Support/KommunalBIT/AssetCacheLogger"
JOURNAL_DIR="${APP_SUPPORT_BASE}/journal"
STATE_DIR="${APP_SUPPORT_BASE}/state"
BOOT_DIR="${APP_SUPPORT_BASE}/boot"
APP_ARCHIVE_DIR="${APP_SUPPORT_BASE}/archive"

ADMIN_USER="admin"

TMP_SCRIPT="/var/tmp/assetcache_logger_download${SH_EXT}"

SCHULEN_CONF="/etc/kommunalbit/schulen.conf"

XML_VERSION="1${DOT}0"
PLIST_VERSION="1${DOT}0"

# --- Helpers -----------------------------------------------------------------

log() {
  echo "[$(date '+%H:%M:%S')] $*"
}

fail() {
  echo "[$(date '+%H:%M:%S')] FAILED: $*"
  exit 1
}

apply_admin_acl() {
  if ! /usr/bin/id "${ADMIN_USER}" >/dev/null 2>&1; then
    log "WARNING: User '${ADMIN_USER}' not found – ACL not applied."
    return
  fi

  log "Applying ACL for user '${ADMIN_USER}' on Application Support tree..."

  # Reset ACLs only inside our own project tree to avoid duplicate ACL entries.
  /bin/chmod -RN "${APP_SUPPORT_BASE}" 2>/dev/null || true

  /usr/sbin/chown -R root:wheel "${APP_SUPPORT_BASE}" 2>/dev/null || true

  # root remains owner; admin gets access via ACL.
  /bin/chmod 700 "${APP_SUPPORT_BASE}" "${JOURNAL_DIR}" "${STATE_DIR}" "${BOOT_DIR}" "${APP_ARCHIVE_DIR}" 2>/dev/null || true

  # Existing files: allow admin read/write/copy/delete.
  /usr/bin/find "${APP_SUPPORT_BASE}" -type f -exec /bin/chmod +a "${ADMIN_USER} allow read,write,append,delete,readattr,writeattr,readextattr,writeextattr,readsecurity" {} \; 2>/dev/null || true

  # Existing directories: allow admin to browse/write; inherit to future files/dirs.
  /usr/bin/find "${APP_SUPPORT_BASE}" -type d -exec /bin/chmod +a "${ADMIN_USER} allow list,search,add_file,add_subdirectory,delete_child,readattr,writeattr,readextattr,writeextattr,readsecurity,file_inherit,directory_inherit" {} \; 2>/dev/null || true

  log "ACL applied for user '${ADMIN_USER}'."
}

# --- 1. Verify running as root -----------------------------------------------

[[ "$(/usr/bin/id -u)" -eq 0 ]] || fail "Must run as root."

log "Running as root – OK"

# --- 2. Stop old LaunchDaemon if present -------------------------------------

log "Stopping old LaunchDaemon instance if present..."

launchctl bootout system "${PLIST_PATH}" 2>&1 || true
launchctl bootout system "${BAD_PLIST_PATH}" 2>&1 || true

pkill -f "${INSTALL_PATH}" 2>/dev/null || true
pkill -f "/usr/local/bin/assetcache_logger_sh" 2>/dev/null || true
pkill -f "/usr/local/bin/assetcache_logger.sh" 2>/dev/null || true

sleep 2

# Remove old wrongly named plist from previous Relution-mangled deployments.
if [[ -e "${BAD_PLIST_PATH}" ]]; then
  rm -f "${BAD_PLIST_PATH}" 2>/dev/null || true
  log "Removed old bad plist path: ${BAD_PLIST_PATH}"
fi

log "Old daemon/process stop attempt complete."

# --- 3. Create required directories ------------------------------------------

log "Creating visible output directory..."

mkdir -p "${VISIBLE_DIR}" || fail "Could not create visible output directory: ${VISIBLE_DIR}"
chown root:wheel "${VISIBLE_DIR}" 2>/dev/null || true
chmod 755 "${VISIBLE_DIR}" 2>/dev/null || true

log "Creating Application Support structure..."

mkdir -p "${JOURNAL_DIR}" "${STATE_DIR}" "${BOOT_DIR}" "${APP_ARCHIVE_DIR}" \
  || fail "Could not create Application Support directories."

chown root:wheel "${APP_SUPPORT_BASE}" "${JOURNAL_DIR}" "${STATE_DIR}" "${BOOT_DIR}" "${APP_ARCHIVE_DIR}" 2>/dev/null || true
chmod 700 "${APP_SUPPORT_BASE}" "${JOURNAL_DIR}" "${STATE_DIR}" "${BOOT_DIR}" "${APP_ARCHIVE_DIR}" 2>/dev/null || true

apply_admin_acl

log "Directories ready:"
log "  Visible: ${VISIBLE_DIR}"
log "  AppSupport: ${APP_SUPPORT_BASE}"
log "  Journal: ${JOURNAL_DIR}"
log "  State: ${STATE_DIR}"
log "  Boot: ${BOOT_DIR}"
log "  Archive: ${APP_ARCHIVE_DIR}"

# --- 4. Create schulen.conf if missing ---------------------------------------

log "Checking schulen.conf..."

mkdir -p /etc/kommunalbit || fail "Could not create /etc/kommunalbit"

if [[ ! -f "${SCHULEN_CONF}" ]]; then
  cat > "${SCHULEN_CONF}" << 'SCHULEN_EOF'
# SuS-Tabelle – KommunalBIT AssetCache Monitoring
# Format: KÜRZEL<TAB>ANZAHL  (eine Zeile pro Schule)
# Beispiel:
# ABC	123
# DEF	45
ASG	24
ASGS	122
BES	30
BRL	80
BUE	114
BUN	48
CEG	64
DEC	80
EIC	133
ELT	99
EPS	66
FOS/BOS	19
FRA	96
FRS	62
GSN	102
GSW	173
GYF	79
HGS	44
HHS-N	63
HHS-W	81
HKS	64
IGG	25
LOS	81
MJS	32
MPS	80
MTG	48
OGY	36
OPS1	64
OPS	232
PES	80
RAE	55
SFK	49
TEN	99
SCHULEN_EOF

  chown root:wheel "${SCHULEN_CONF}" 2>/dev/null || true
  chmod 644 "${SCHULEN_CONF}" 2>/dev/null || true
  log "schulen.conf created."
else
  log "schulen.conf already exists – not overwritten."
fi

# --- 5. Download monitoring script -------------------------------------------

log "Downloading assetcache_logger.sh from GitHub..."
log "URL: ${SCRIPT_URL}"

rm -f "${TMP_SCRIPT}"

HTTP_CODE=$(
  curl \
    --silent --show-error \
    --location \
    --max-time 30 \
    --write-out "%{http_code}" \
    --output "${TMP_SCRIPT}" \
    "${SCRIPT_URL}" 2>&1
)
CURL_EXIT=$?

log "curl exit code: ${CURL_EXIT}, HTTP status/output: ${HTTP_CODE}"

if [[ ${CURL_EXIT} -ne 0 ]]; then
  fail "curl failed with exit ${CURL_EXIT}. Check network connectivity."
fi

if [[ "${HTTP_CODE}" != "200" ]]; then
  fail "Server returned HTTP/status '${HTTP_CODE}'. URL may be wrong or repo may be private."
fi

FILESIZE="$(wc -c < "${TMP_SCRIPT}" | tr -d ' ')"
log "Downloaded ${FILESIZE} bytes."

if [[ -z "${FILESIZE}" || "${FILESIZE}" -lt 1000 ]]; then
  fail "Downloaded file is too small (${FILESIZE} bytes) – likely empty or an error page."
fi

if ! head -1 "${TMP_SCRIPT}" | grep -q '^#!/bin/zsh'; then
  fail "Downloaded file does not look like a zsh script."
fi

if ! grep -q 'SCRIPT_VER="1.9.0"' "${TMP_SCRIPT}"; then
  log "WARNING: Downloaded script does not contain SCRIPT_VER=\"1.9.0\""
fi

# --- 6. Install monitoring script --------------------------------------------

log "Installing script to ${INSTALL_PATH}..."

mkdir -p /usr/local/bin || fail "Could not create /usr/local/bin"

cp "${TMP_SCRIPT}" "${INSTALL_PATH}" || fail "Could not copy script to ${INSTALL_PATH}"
rm -f "${TMP_SCRIPT}" 2>/dev/null || true

chown root:wheel "${INSTALL_PATH}" || fail "Could not chown ${INSTALL_PATH}"
chmod 755 "${INSTALL_PATH}" || fail "Could not chmod ${INSTALL_PATH}"

log "Script installed."

# --- 7. Write LaunchDaemon plist ---------------------------------------------

log "Writing LaunchDaemon plist to ${PLIST_PATH}..."

cat > "${PLIST_PATH}" << PLIST_EOF
<?xml version="${XML_VERSION}" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST ${PLIST_VERSION}//EN"
"http://www.apple.com/DTDs/PropertyList-${PLIST_VERSION}.dtd">
<plist version="${PLIST_VERSION}">
<dict>
  <key>Label</key>
  <string>${DAEMON_LABEL}</string>

  <key>ProgramArguments</key>
  <array>
    <string>${INSTALL_PATH}</string>
  </array>

  <key>StartInterval</key>
  <integer>900</integer>

  <key>RunAtLoad</key>
  <true/>

  <key>StandardOutPath</key>
  <string>/var/tmp/assetcache_logger.out</string>

  <key>StandardErrorPath</key>
  <string>/var/tmp/assetcache_logger.err</string>
</dict>
</plist>
PLIST_EOF

chown root:wheel "${PLIST_PATH}" || fail "Could not chown plist."
chmod 644 "${PLIST_PATH}" || fail "Could not chmod plist."

if ! plutil -lint "${PLIST_PATH}" >/dev/null 2>&1; then
  fail "LaunchDaemon plist failed plutil validation."
fi

log "Plist written and validated."

# --- 8. Enable, bootstrap and start LaunchDaemon ------------------------------

log "Enabling LaunchDaemon..."

launchctl enable "system/${DAEMON_LABEL}" 2>&1 || true

log "Bootstrapping LaunchDaemon..."

launchctl bootstrap system "${PLIST_PATH}" 2>&1
BOOT_EXIT=$?

if [[ ${BOOT_EXIT} -ne 0 ]]; then
  fail "launchctl bootstrap failed with exit ${BOOT_EXIT}."
fi

log "Kickstarting LaunchDaemon..."

launchctl kickstart -k "system/${DAEMON_LABEL}" 2>&1 || true

sleep 3

if launchctl print "system/${DAEMON_LABEL}" >/dev/null 2>&1; then
  log "Daemon '${DAEMON_LABEL}' is loaded."
else
  fail "Daemon not found after bootstrap."
fi

# --- 9. Final visibility checks ----------------------------------------------

log "Checking installed files..."

if [[ -x "${INSTALL_PATH}" ]]; then
  log "Installed script executable – OK"
else
  fail "Installed script is not executable."
fi

if [[ -d "${APP_SUPPORT_BASE}" ]]; then
  log "Application Support base exists – OK"
else
  fail "Application Support base missing."
fi

if [[ -d "${VISIBLE_DIR}" ]]; then
  log "Visible output directory exists – OK"
else
  fail "Visible output directory missing."
fi

if [[ -e "${BAD_PLIST_PATH}" ]]; then
  fail "Bad plist path still exists: ${BAD_PLIST_PATH}"
fi

if [[ -f "${PLIST_PATH}" ]]; then
  log "LaunchDaemon plist exists at correct path – OK"
else
  fail "LaunchDaemon plist missing at correct path."
fi

log "Deployment complete."
exit 0
# --- Helpers -----------------------------------------------------------------
log()  { echo "[$(date '+%H:%M:%S')] $*"; }
fail() { echo "[$(date '+%H:%M:%S')] FAILED: $*"; exit 1; }

# --- 1. Verify running as root -----------------------------------------------
[[ $EUID -eq 0 ]] || fail "Must run as root."
log "Running as root – OK"

# --- 2. Create log directories -----------------------------------------------
log "Creating log directories..."
mkdir -p "${LOG_DIR}" "${ARCHIVE_DIR}" || fail "Could not create log directories."
chown root:wheel "${LOG_DIR}" "${ARCHIVE_DIR}"
chmod 755 "${LOG_DIR}" "${ARCHIVE_DIR}"
log "Directories ready: ${LOG_DIR}, ${ARCHIVE_DIR}"

# --- 3. Create schulen.conf (only if not already present) --------------------
# The actual school data is written by the Relution version of this script.
# This GitHub version only creates an empty placeholder on first install.
log "Checking schulen.conf..."
mkdir -p /etc/kommunalbit
if [[ ! -f "${SCHULEN_CONF}" ]]; then
  cat > "${SCHULEN_CONF}" << 'SCHULEN_EOF'
# SuS-Tabelle – KommunalBIT AssetCache Monitoring
# Format: KÜRZEL<TAB>ANZAHL  (eine Zeile pro Schule)
# Beispiel:
# ABC	120
# DEF	80
SCHULEN_EOF
  chown root:wheel "${SCHULEN_CONF}"
  chmod 644 "${SCHULEN_CONF}"
  log "schulen.conf Vorlage angelegt (bitte mit echten Daten befüllen)."
else
  log "schulen.conf bereits vorhanden – wird nicht überschrieben."
fi

# --- 4. Download monitoring script to temp file ------------------------------
log "Downloading assetcache_logger.sh from GitHub..."
log "URL: ${SCRIPT_URL}"

rm -f "${TMP_SCRIPT}"
HTTP_CODE=$(curl \
  --silent --show-error \
  --location \
  --max-time 30 \
  --write-out "%{http_code}" \
  --output "${TMP_SCRIPT}" \
  "${SCRIPT_URL}" 2>&1)
CURL_EXIT=$?

log "curl exit code: ${CURL_EXIT}, HTTP status: ${HTTP_CODE}"

if [[ ${CURL_EXIT} -ne 0 ]]; then
  fail "curl failed (exit ${CURL_EXIT}). Check network connectivity."
fi

if [[ "${HTTP_CODE}" != "200" ]]; then
  fail "Server returned HTTP ${HTTP_CODE}. URL may be wrong or repo may be private."
fi

FILESIZE=$(wc -c < "${TMP_SCRIPT}" | tr -d ' ')
log "Downloaded ${FILESIZE} bytes."

if [[ ${FILESIZE} -lt 100 ]]; then
  fail "Downloaded file is too small (${FILESIZE} bytes) – likely empty or an error page."
fi

# --- 5. Install monitoring script --------------------------------------------
log "Installing to ${INSTALL_PATH}..."
mkdir -p /usr/local/bin
cp "${TMP_SCRIPT}" "${INSTALL_PATH}" || fail "Could not copy script to ${INSTALL_PATH}."
rm -f "${TMP_SCRIPT}"
chown root:wheel "${INSTALL_PATH}"
chmod 755 "${INSTALL_PATH}"
log "Script installed."

# --- 6. Write LaunchDaemon plist ---------------------------------------------
log "Writing LaunchDaemon plist to ${PLIST_PATH}..."
cat > "${PLIST_PATH}" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
"http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>de.kommunalbit.assetcachelogger</string>

  <key>ProgramArguments</key>
  <array>
    <string>/usr/local/bin/assetcache_logger.sh</string>
  </array>

  <key>StartInterval</key>
  <integer>900</integer>

  <key>RunAtLoad</key>
  <true/>

  <key>StandardOutPath</key>
  <string>/var/tmp/assetcache_logger.out</string>

  <key>StandardErrorPath</key>
  <string>/var/tmp/assetcache_logger.err</string>
</dict>
</plist>
EOF

chown root:wheel "${PLIST_PATH}"
chmod 644 "${PLIST_PATH}"
log "Plist written."

# --- 7. Load / restart the LaunchDaemon -------------------------------------
log "Loading LaunchDaemon..."

if launchctl list "${DAEMON_LABEL}" &>/dev/null; then
  log "Daemon already loaded – unloading first..."
  launchctl bootout system "${PLIST_PATH}" 2>&1 || true
  sleep 2
fi

launchctl bootstrap system "${PLIST_PATH}" 2>&1
BOOT_EXIT=$?

if [[ ${BOOT_EXIT} -ne 0 ]]; then
  fail "launchctl bootstrap failed (exit ${BOOT_EXIT})."
fi

sleep 1
if launchctl list "${DAEMON_LABEL}" &>/dev/null; then
  log "Daemon '${DAEMON_LABEL}' is running."
else
  fail "Daemon not found in launchctl list after bootstrap."
fi

log "Deployment complete."
