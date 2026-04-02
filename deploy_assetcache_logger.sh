#!/bin/zsh
# =============================================================================
# AssetCache Logger – MDM Deployment Script (KommunalBIT)
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
# =============================================================================

set -euo pipefail

# --- Configuration -----------------------------------------------------------
SCRIPT_URL="https://raw.githubusercontent.com/jens-siegfried/caching-server/main/AssetCache%20Monitoring%201.6.0.sh"
INSTALL_PATH="/usr/local/bin/assetcache_logger.sh"
PLIST_PATH="/Library/LaunchDaemons/de.kommunalbit.assetcachelogger.plist"
DAEMON_LABEL="de.kommunalbit.assetcachelogger"
LOG_DIR="/Library/Logs/KommunalBIT"
ARCHIVE_DIR="${LOG_DIR}/Archiv"

# --- Helpers -----------------------------------------------------------------
log() { echo "[deploy] $*"; }
die() { echo "[deploy] ERROR: $*" >&2; exit 1; }

# --- 1. Verify running as root -----------------------------------------------
[[ $EUID -eq 0 ]] || die "This script must run as root."

# --- 2. Create log directories -----------------------------------------------
log "Creating log directories..."
mkdir -p "${LOG_DIR}" "${ARCHIVE_DIR}"
chown root:wheel "${LOG_DIR}" "${ARCHIVE_DIR}"
chmod 755 "${LOG_DIR}" "${ARCHIVE_DIR}"

# --- 3. Download monitoring script -------------------------------------------
log "Downloading assetcache_logger.sh from GitHub..."
curl --silent --show-error --fail --location \
     --max-time 30 \
     --output "${INSTALL_PATH}" \
     "${SCRIPT_URL}" \
  || die "Download failed. Check network connectivity and the URL:\n  ${SCRIPT_URL}"

# --- 4. Set permissions on monitoring script ---------------------------------
log "Setting permissions on ${INSTALL_PATH}..."
chown root:wheel "${INSTALL_PATH}"
chmod 755 "${INSTALL_PATH}"

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

# --- 6. Load / restart the LaunchDaemon -------------------------------------
log "Loading LaunchDaemon..."

# Unload gracefully if already loaded (ignore errors if not loaded)
if launchctl list "${DAEMON_LABEL}" &>/dev/null; then
  log "Daemon already loaded – unloading first..."
  launchctl bootout system "${PLIST_PATH}" 2>/dev/null || true
  sleep 1
fi

launchctl bootstrap system "${PLIST_PATH}" \
  || die "launchctl bootstrap failed."

# Verify it loaded
if launchctl list "${DAEMON_LABEL}" &>/dev/null; then
  log "Daemon '${DAEMON_LABEL}' is running. Deployment complete."
else
  die "Daemon did not appear in launchctl list after bootstrap."
fi
