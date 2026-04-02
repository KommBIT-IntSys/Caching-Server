#!/bin/zsh
# =============================================================================
# AssetCache Logger – MDM Deployment Script (KommunalBIT) v2
# Deploys AssetCache Monitoring 1.6 via Relution MDM.
#
# What this script does:
#   1. Creates required log directories
#   2. Downloads assetcache_logger.sh from GitHub
#   3. Sets correct ownership and permissions
#   4. Writes the LaunchDaemon plist
#   5. Bootstraps and starts the daemon
#
# Requirements: Runs as root (standard for Relution MDM scripts)
# Debug log:    /var/tmp/assetcache_deploy.log
# =============================================================================

# --- Logging setup (all output goes to log file since Relution is silent) ----
DEPLOY_LOG="/var/tmp/assetcache_deploy.log"
exec > >(tee -a "${DEPLOY_LOG}") 2>&1
echo ""
echo "========================================================"
echo "AssetCache Logger Deployment v3 – $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================================"

# --- Configuration -----------------------------------------------------------
# Build URL in parts – Relution mangles "raw.githubusercontent.com" to "raw_githubusercontent.com"
_GH_RAW="raw$(printf '\x2e')githubusercontent$(printf '\x2e')com"
SCRIPT_URL="https://${_GH_RAW}/Jens-Siegfried/Caching-Server/main/AssetCache_Monitoring_1.6.0.sh"
INSTALL_PATH="/usr/local/bin/assetcache_logger.sh"
PLIST_PATH="/Library/LaunchDaemons/de.kommunalbit.assetcachelogger.plist"
DAEMON_LABEL="de.kommunalbit.assetcachelogger"
LOG_DIR="/Library/Logs/KommunalBIT"
ARCHIVE_DIR="${LOG_DIR}/Archiv"
TMP_SCRIPT="/var/tmp/assetcache_logger_download.sh"

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

# --- 3. Download monitoring script to temp file ------------------------------
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

# --- 4. Install monitoring script --------------------------------------------
log "Installing to ${INSTALL_PATH}..."
cp "${TMP_SCRIPT}" "${INSTALL_PATH}" || fail "Could not copy script to ${INSTALL_PATH}."
rm -f "${TMP_SCRIPT}"
chown root:wheel "${INSTALL_PATH}"
chmod 755 "${INSTALL_PATH}"
log "Script installed."

# --- 5. Write LaunchDaemon plist ---------------------------------------------
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

# --- 6. Load / restart the LaunchDaemon -------------------------------------
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
