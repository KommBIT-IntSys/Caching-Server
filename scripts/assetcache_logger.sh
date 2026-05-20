#!/bin/zsh

set -u

if [[ "$(id -u)" -ne 0 ]]; then
  echo "ERROR: assetcache_logger.sh must run as root. Use sudo or run via LaunchDaemon/Relution." >&2
  exit 77
fi

# Asset Cache Monitoring / Logging
# Version 1.9.0 (KommunalBIT)
# SPDX-License-Identifier: EUPL-1.2
# Licensed under the EUPL, Version 1.2
# https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
# Copyright (C) 2026 Jens Luithle@KommunalBIT AöR
#
# v1.9.0 Architektur:
#   RAW  – dauerhaftes Journal unter /Library/Application Support/KommunalBIT/AssetCacheLogger/journal/
#          (kanonische Wahrheit; überlebt macOS-Update-Neustarts)
#   HU   – menschenlesbare View, sichtbar unter /Library/Logs/KommunalBIT/
#   CO   – datensparsame Analyse-View, sichtbar unter /Library/Logs/KommunalBIT/
#
# /Library/Logs/KommunalBIT ist nur noch sichtbarer Ausgabeort.
# HU und CO können jederzeit deterministisch aus dem RAW-Journal wiederhergestellt werden.
# RAW wird standardmäßig nicht sichtbar geschrieben (nur im Application-Support-Journal).
#
# Key deltas vs 1.8.2:
# - RAW-Journal dauerhaft unter Application Support/journal/ (überdauert Neustarts)
# - Statefiles von /var/tmp nach Application Support/state/ verlagert (mit Migrations-Logik)
# - Boot-Erkennung via kern.boottime; nach Neustart Rebuild sichtbarer HU-/CO-Dateien
# - Rebuild von HU und CO aus RAW-Journal (deterministisch, ohne Live-Statefiles)
# - Archivierung via cp statt mv (sichtbare Dateien); RAW-Journal wird nie verschoben
# - Statuslog unter Application Support (dauerhaft)
# - EXPORT_VISIBLE_RAW=0: kein sichtbares RAW per Default
# - RAW_SCHEMA_VER entkoppelt das Journal von SCRIPT_VER (kein Neubeginn bei Patch/Minor)

SCRIPT_VER="1.9.0"
RAW_SCHEMA_VER="schema1"

# Auf 1 setzen, um zusätzlich eine sichtbare RAW-Datei unter /Library/Logs/KommunalBIT zu schreiben
EXPORT_VISIBLE_RAW=0

# =============================================================================
# Verzeichnis-Konstanten (PREFIX-unabhängig)
# =============================================================================

VISIBLE_DIR="/Library/Logs/KommunalBIT"
VISIBLE_ARCHIVDIR="${VISIBLE_DIR}/Archiv"

APP_SUPPORT_BASE="/Library/Application Support/KommunalBIT/AssetCacheLogger"
JOURNAL_DIR="${APP_SUPPORT_BASE}/journal"
STATE_DIR="${APP_SUPPORT_BASE}/state"
BOOT_DIR="${APP_SUPPORT_BASE}/boot"
STATUS_LOG="${APP_SUPPORT_BASE}/status.log"

# =============================================================================
# Statefiles (PREFIX-unabhängig, jetzt unter STATE_DIR)
# =============================================================================

STATEFILE="${STATE_DIR}/assetcache_logger_state.tsv"
IOSUPD_STATEFILE="${STATE_DIR}/assetcache_iosupdates_hu_state.tsv"
IOSUPD_BLOCK_LEN=19
TOTALSSINCE_HU_STATEFILE="${STATE_DIR}/assetcache_totalssince_hu_state.tsv"
TOTALSSINCE_BLOCK_LEN=19
GDMF_STATEFILE="${STATE_DIR}/assetcache_gdmf_state.tsv"
GDMF_DEBUGLOG="${STATE_DIR}/assetcache_gdmf_debug.log"

# =============================================================================
# Zeitstempel
# =============================================================================

TS_RAW="$(date +"%Y-%m-%dT%H:%M:%S%z" | sed -E 's/([+-][0-9]{2})([0-9]{2})$/\1:\2/')"
TS_HU="$(date +"%Y-%m-%d %H:%M:%S")"

# =============================================================================
# Hostname und Prefix
# =============================================================================

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

# =============================================================================
# PREFIX-abhängige Pfade
# =============================================================================

OUT_HU="${VISIBLE_DIR}/${PREFIX}_AssetCache_Hu_v${SCRIPT_VER}.csv"
OUT_CO="${VISIBLE_DIR}/${PREFIX}_AssetCache_Co_v${SCRIPT_VER}.csv"
OUT_RAW=""  # nur gesetzt wenn EXPORT_VISIBLE_RAW=1
if [[ "${EXPORT_VISIBLE_RAW}" -eq 1 ]]; then
  OUT_RAW="${VISIBLE_DIR}/${PREFIX}_AssetCacheRaw_v${SCRIPT_VER}.csv"
fi

ARCHIVE_STATEFILE="${STATE_DIR}/assetcache_archive_state_${PREFIX}.tsv"
RAW_JOURNAL="${JOURNAL_DIR}/${PREFIX}_AssetCacheRaw_${RAW_SCHEMA_VER}.csv"

# =============================================================================
# SuS-Tabelle – externe Konfigurationsdatei
# =============================================================================
# Format: KÜRZEL<TAB>ANZAHL  (Zeilen mit # werden ignoriert)
typeset -A SUS_TOTAL_BY_SITE
SCHULEN_CONF="/etc/kommunalbit/schulen.conf"
if [[ -f "${SCHULEN_CONF}" ]]; then
  while IFS=$'\t' read -r _site _count; do
    [[ "${_site}" == \#* || -z "${_site}" ]] && continue
    [[ -n "${_count}" ]] && SUS_TOTAL_BY_SITE[${_site}]=${_count}
  done < "${SCHULEN_CONF}"
fi

# =============================================================================
# CSV-Header
# =============================================================================

CSV_HEADER_FIELDS=(
  "Hostname" "Timestamp" "TotalsSince" "Peers" "ClientsCnt" "iOSUpdates" "iOSBytes"
  "TotReturned" "TotOrigin" "ServedDelta" "OriginDelta" "CacheUsed" "CachePr"
  "EN0" "EN1" "GatewayIP" "DefaultIf" "DNSRes" "AppleReach" "AppleTTFB"
  "WiFiSNR" "WifiNoise" "WifiCCA"
)

CSV_HEADER_FIELDS_CO=(
  "SiteCode" "Timestamp" "PeerCnt" "ClientsCnt" "iOSUpdates" "iOSBytes"
  "ServedDelta" "OriginDelta" "CacheUsed" "CachePr"
  "DNSRes" "AppleReach" "AppleTTFB" "WiFiSNR"
)

# =============================================================================
# Statuslog
# =============================================================================

status_log() {
  local ts
  ts="$(date '+%Y-%m-%d %H:%M:%S')"
  printf "%s %s\n" "$ts" "$*" >> "${STATUS_LOG}" 2>/dev/null || true
  # Auf 2000 Zeilen kürzen
  if [[ -f "$STATUS_LOG" ]]; then
    local lc
    lc="$(/usr/bin/wc -l < "$STATUS_LOG" 2>/dev/null | tr -d ' ')"
    if [[ -n "${lc:-}" && "$lc" -gt 2000 ]]; then
      /usr/bin/tail -n 2000 "$STATUS_LOG" > "${STATUS_LOG}.tmp" 2>/dev/null \
        && /bin/mv "${STATUS_LOG}.tmp" "$STATUS_LOG" 2>/dev/null || true
    fi
  fi
}

# =============================================================================
# Verzeichnisstruktur sicherstellen
# =============================================================================

ensure_app_support_dirs() {
  local dir created_any=0
  for dir in "$APP_SUPPORT_BASE" "$JOURNAL_DIR" "$STATE_DIR" "$BOOT_DIR"; do
    if [[ ! -d "$dir" ]]; then
      if /bin/mkdir -p "$dir" 2>/dev/null; then
        /bin/chown root:wheel "$dir" 2>/dev/null || true
        /bin/chmod 700 "$dir" 2>/dev/null || true
        created_any=1
      else
        # Statuslog kann hier noch nicht sicher schreiben; stderr als Fallback
        printf "%s ERROR failed to create dir %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$dir" >&2
      fi
    fi
  done
  for dir in "$VISIBLE_DIR" "$VISIBLE_ARCHIVDIR"; do
    if [[ ! -d "$dir" ]]; then
      /bin/mkdir -p "$dir" 2>/dev/null || true
      /bin/chown root:wheel "$dir" 2>/dev/null || true
      /bin/chmod 755 "$dir" 2>/dev/null || true
    fi
  done
  [[ "$created_any" -eq 1 ]] && status_log "INFO Application-Support-Verzeichnisse angelegt"
}

# =============================================================================
# Migration: /var/tmp → STATE_DIR (einmalig)
# =============================================================================

migrate_statefiles_from_var_tmp() {
  local -a migrations=(
    "/var/tmp/assetcache_logger_state.tsv:${STATEFILE}"
    "/var/tmp/assetcache_iosupdates_hu_state.tsv:${IOSUPD_STATEFILE}"
    "/var/tmp/assetcache_totalssince_hu_state.tsv:${TOTALSSINCE_HU_STATEFILE}"
    "/var/tmp/assetcache_gdmf_state.tsv:${GDMF_STATEFILE}"
    "/var/tmp/assetcache_gdmf_debug.log:${GDMF_DEBUGLOG}"
    "/var/tmp/assetcache_archive_state_${PREFIX}.tsv:${ARCHIVE_STATEFILE}"
  )

  local entry src dst
  for entry in "${migrations[@]}"; do
    src="${entry%%:*}"
    dst="${entry#*:}"
    if [[ -f "$src" && ! -f "$dst" ]]; then
      if /bin/cp "$src" "$dst" 2>/dev/null; then
        /bin/chown root:wheel "$dst" 2>/dev/null || true
        /bin/chmod 600 "$dst" 2>/dev/null || true
        status_log "INFO migriert: $src → $dst"
      else
        status_log "WARN Migration fehlgeschlagen: $src → $dst"
      fi
    fi
  done
}

# =============================================================================
# Boot-Erkennung
# =============================================================================
# Gibt 1 zurück wenn sich die Boot-Zeit geändert hat, sonst 0.

detect_boot_change() {
  local cur_boot_sec
  cur_boot_sec="$(/usr/sbin/sysctl kern.boottime 2>/dev/null \
    | /usr/bin/sed -E 's/.*sec = ([0-9]+), usec = [0-9]+.*/\1/')"
  if ! echo "${cur_boot_sec:-}" | /usr/bin/grep -Eq '^[0-9]+$'; then
    status_log "WARN Boot-Time konnte nicht sauber gelesen werden"
    return 0
  fi

  local boot_file="${BOOT_DIR}/last_boot_time"
  local prev_boot_sec=""
  if [[ -f "$boot_file" ]]; then
    prev_boot_sec="$(/bin/cat "$boot_file" 2>/dev/null | tr -d '\r\n')"
  fi

  if [[ "${cur_boot_sec:-}" != "${prev_boot_sec:-}" ]]; then
    status_log "INFO Boot-Wechsel erkannt old=${prev_boot_sec:-none} new=${cur_boot_sec}"
    printf "%s\n" "$cur_boot_sec" > "$boot_file" 2>/dev/null || true
    return 1
  fi
  return 0
}

# =============================================================================
# Hilfsfunktionen (unveränderter Kern aus v1.8.2)
# =============================================================================

site_code_for_clientscnt() {
  local pfx="${1:-}"
  local alt=""

  [[ -z "${pfx:-}" ]] && { echo ""; return; }

  if [[ -n "${SUS_TOTAL_BY_SITE[$pfx]:-}" ]]; then
    echo "$pfx"
    return
  fi

  alt="${pfx%[0-9]}"
  if [[ -n "${alt:-}" && -n "${SUS_TOTAL_BY_SITE[$alt]:-}" ]]; then
    echo "$alt"
    return
  fi

  echo ""
}

format_clientscnt_raw() {
  local active="${1:-}"
  local total="${2:-}"

  if [[ -z "${active:-}" ]]; then
    echo ""
    return
  fi

  if [[ -n "${total:-}" ]] && echo "$total" | /usr/bin/grep -Eq '^[0-9]+$'; then
    echo "${active}/${total}"
  else
    echo "$active"
  fi
}

format_clientscnt_hu() {
  local active="${1:-}"
  local total="${2:-}"
  local pct=""

  if [[ -z "${active:-}" ]]; then
    echo ""
    return
  fi

  if ! echo "$active" | /usr/bin/grep -Eq '^[0-9]+$'; then
    echo ""
    return
  fi

  if [[ -z "${total:-}" ]] || ! echo "$total" | /usr/bin/grep -Eq '^[0-9]+$'; then
    echo "$active"
    return
  fi

  [[ "$total" -gt 0 ]] || { echo "$active"; return; }

  pct="$(LC_ALL=C /usr/bin/awk -v a="$active" -v t="$total" 'BEGIN{printf "%.1f", (a/t)*100.0}')"
  echo "${pct}%"
}

csv_escape() {
  local s="${1-}"
  s="${s//\"/\"\"}"
  printf '"%s"' "$s"
}

normalize_ios_version_2digit() {
  local v="${1:-}"
  [[ -z "${v:-}" ]] && { echo ""; return; }

  if ! echo "$v" | /usr/bin/grep -Eq '^[0-9]+(\.[0-9]+){1,2}$'; then
    echo "$v"
    return
  fi

  local IFS='.'
  local -a parts out
  local p
  parts=(${=v})
  out=()

  for p in "${parts[@]}"; do
    if echo "$p" | /usr/bin/grep -Eq '^[0-9]$'; then
      out+=("0$p")
    else
      out+=("$p")
    fi
  done

  echo "${(j:.:)out}"
}

normalize_iosupdates_list_2digit() {
  local s="${1:-}"
  [[ -z "${s:-}" ]] && { echo ""; return; }

  local IFS='|'
  local -a parts out
  local p
  parts=(${=s})
  out=()

  for p in "${parts[@]}"; do
    out+=("$(normalize_ios_version_2digit "$p")")
  done

  echo "${(j:|:)out}"
}

emit_csv_line() {
  local out="$1"
  shift
  local first=1
  local field

  for field in "$@"; do
    if [[ $first -eq 1 ]]; then
      first=0
    else
      printf ',' >> "$out"
    fi
    csv_escape "$field" >> "$out"
  done
  printf '\n' >> "$out"
}

# ---------- Timeout-Helfer ----------
_timeout_run() {
  local secs="$1" outfile="$2"
  shift 2

  ( "$@" > "$outfile" 2>/dev/null ) &
  local cmd_pid=$!
  ( sleep "$secs" && kill "$cmd_pid" 2>/dev/null ) &
  local wdog_pid=$!

  wait "$cmd_pid" 2>/dev/null
  kill "$wdog_pid" 2>/dev/null
  wait "$wdog_pid" 2>/dev/null 2>&1
}

# ---------- AssetCacheManagerUtil-Status einlesen ----------
_acmu_tmp="$(/usr/bin/mktemp /var/tmp/acmu_XXXXXX 2>/dev/null || echo "")"
STATUS_TXT=""
if [[ -n "${_acmu_tmp:-}" ]]; then
  _timeout_run 30 "$_acmu_tmp" /usr/bin/AssetCacheManagerUtil status
  STATUS_TXT="$(/bin/cat "$_acmu_tmp" 2>/dev/null || true)"
  /bin/rm -f "$_acmu_tmp" 2>/dev/null || true
fi

get_key() {
  local key="$1"
  echo "$STATUS_TXT" | awk -F': ' -v k="$key" '
    $0 ~ "^[[:space:]]*" k ":" { print $2; exit }
  ' | sed 's/[;[:space:]]*$//'
}

get_detail() {
  local key="$1"
  echo "$STATUS_TXT" | awk -v k="$key" '
    BEGIN{inside=0}
    /^[[:space:]]*CacheDetails:/ {inside=1; next}
    inside && /^[[:space:]]*CacheFree:/ {exit}
    inside {
      pat="^[[:space:]]*" k ":[[:space:]]*"
      if ($0 ~ pat) {
        sub(pat, "", $0)
        sub(/[;[:space:]]*$/, "", $0)
        print $0
        exit
      }
    }'
}

to_bytes() {
  local s="${1:-}"
  s="${s//;/}"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"

  [[ -z "${s:-}" ]] && echo "" && return
  [[ "$s" == Zero* ]] && echo 0 && return
  echo "$s" | /usr/bin/grep -Eq '^[0-9]+$' && echo "$s" && return

  local num unit mult
  num="$(echo "$s" | awk '{print $1}')"
  unit="$(echo "$s" | awk '{print $2}')"
  num="${num/,/.}"

  case "$unit" in
    B)   mult=1 ;;
    KB)  mult=1000 ;;
    KiB) mult=1024 ;;
    MB)  mult=1000000 ;;
    MiB) mult=1048576 ;;
    GB)  mult=1000000000 ;;
    GiB) mult=1073741824 ;;
    TB)  mult=1000000000000 ;;
    TiB) mult=1099511627776 ;;
    *) echo "" ; return ;;
  esac

  LC_ALL=C /usr/bin/awk -v n="$num" -v m="$mult" 'BEGIN{printf "%.0f\n", n*m}'
}

bytes_human() {
  local b="${1:-}"
  [[ -z "${b:-}" ]] && echo "" && return

  if ! echo "$b" | /usr/bin/grep -Eq '^[0-9]+$'; then
    echo "$b"
    return
  fi
  if [[ "$b" -eq 0 ]]; then
    echo "0"
    return
  fi

  LC_ALL=C /usr/bin/awk -v x="$b" 'BEGIN{
    v=x+0; unit="B";
    if      (v>=1000000000000){v=v/1000000000000; unit="TB"}
    else if (v>=1000000000)   {v=v/1000000000;    unit="GB"}
    else if (v>=1000000)      {v=v/1000000;       unit="MB"}
    else if (v>=1000)         {v=v/1000;          unit="KB"}
    printf "%.2f%s", v, unit
  }'
}

iface_code() {
  local ifn="$1"

  if ! /sbin/ifconfig "$ifn" >/dev/null 2>&1; then
    echo "down"
    return
  fi

  local ip=""
  ip="$(/usr/sbin/ipconfig getifaddr "$ifn" 2>/dev/null || true)"
  if [[ -n "${ip:-}" ]]; then
    echo "$ip"
    return
  fi

  if /sbin/ifconfig "$ifn" 2>/dev/null | /usr/bin/grep -q "status: active"; then
    echo "noip"
  else
    echo "down"
  fi
}

hu_iface_state() {
  local raw="$1"
  case "$raw" in
    down|noip) echo "$raw" ;;
    *) echo "up" ;;
  esac
}

hu_gateway_state() {
  local raw="$1"
  if [[ -n "${raw:-}" ]]; then
    echo "yes"
  else
    echo "no"
  fi
}

is_uint() { echo "${1:-}" | /usr/bin/grep -Eq '^[0-9]+$'; }
is_int()  { echo "${1:-}" | /usr/bin/grep -Eq '^-?[0-9]+$'; }

offset_colon() { sed -E 's/([+-][0-9]{2})([0-9]{2})$/\1:\2/'; }

totals_since_raw() {
  local s="${1:-}"
  [[ -z "${s:-}" ]] && echo "" && return

  if echo "$s" | /usr/bin/grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2} [+-][0-9]{4}$'; then
    /bin/date -j -f "%Y-%m-%d %H:%M:%S %z" "$s" +"%Y-%m-%dT%H:%M:%S%z" 2>/dev/null | offset_colon
  elif echo "$s" | /usr/bin/grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$'; then
    /bin/date -j -f "%Y-%m-%d %H:%M:%S" "$s" +"%Y-%m-%dT%H:%M:%S%z" 2>/dev/null | offset_colon
  else
    echo ""
  fi
}

totals_since_hu() {
  local s="${1:-}"
  [[ -z "${s:-}" ]] && echo "" && return

  if echo "$s" | /usr/bin/grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2} [+-][0-9]{4}$'; then
    /bin/date -j -f "%Y-%m-%d %H:%M:%S %z" "$s" +"%Y-%m-%d %H:%M:%S" 2>/dev/null
  elif echo "$s" | /usr/bin/grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$'; then
    /bin/date -j -f "%Y-%m-%d %H:%M:%S" "$s" +"%Y-%m-%d %H:%M:%S" 2>/dev/null
  else
    echo ""
  fi
}

peers_value() {
  local self0 self1 gw
  self0="$(/usr/sbin/ipconfig getifaddr en0 2>/dev/null || true)"
  self1="$(/usr/sbin/ipconfig getifaddr en1 2>/dev/null || true)"
  gw="$(/sbin/route -n get default 2>/dev/null | awk '/gateway:/{print $2; exit}')"

  local ips
  ips="$(echo "$STATUS_TXT" | awk '
    BEGIN{inside=0}
    /^[[:space:]]*Peers:/ {inside=1; next}
    inside && /^[A-Za-z0-9].*:[[:space:]].*$/ {exit}
    inside {print}
  ' | /usr/bin/grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | awk '
    $0 ~ /^10\./ || $0 ~ /^192\.168\./ || $0 ~ /^172\.(1[6-9]|2[0-9]|3[0-1])\./
  ' | awk -v s0="$self0" -v s1="$self1" -v g="$gw" '
    $0 != s0 && $0 != s1 && $0 != g
  ' | /usr/bin/sort -u | paste -sd";" -)"

  echo "${ips:-}"
}

trim_gdmf_debuglog() {
  if [[ -f "$GDMF_DEBUGLOG" ]]; then
    local linecount
    linecount="$(/usr/bin/wc -l < "$GDMF_DEBUGLOG" 2>/dev/null | tr -d ' ')"
    if [[ -n "${linecount:-}" && "$linecount" -gt 1000 ]]; then
      /usr/bin/tail -n 1000 "$GDMF_DEBUGLOG" > "${GDMF_DEBUGLOG}.tmp" 2>/dev/null \
        && /bin/mv "${GDMF_DEBUGLOG}.tmp" "$GDMF_DEBUGLOG"
    fi
  fi
}

# ---------- ClientsCnt ----------
clients_count_last_minutes() {
  local mins="${1:-16}"

  local self0 self1
  self0="$(/usr/sbin/ipconfig getifaddr en0 2>/dev/null || true)"
  self1="$(/usr/sbin/ipconfig getifaddr en1 2>/dev/null || true)"

  local tmp=""
  tmp="$(/usr/bin/mktemp /var/tmp/assetcache_clients_XXXXXX 2>/dev/null || echo "")"
  [[ -z "${tmp:-}" ]] && { echo ""; return; }

  _timeout_run 60 "$tmp" /usr/bin/log show --last "${mins}m" --style syslog \
    --predicate '(subsystem == "com.apple.AssetCache") && (eventMessage CONTAINS[c] "Received GET request from ")'

  local cnt
  cnt="$(
    /bin/cat "$tmp" 2>/dev/null \
    | /usr/bin/grep -Eo 'Received GET request from ([0-9]{1,3}\.){3}[0-9]{1,3}:[0-9]+' \
    | /usr/bin/grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' \
    | awk '$0 ~ /^10\./ || $0 ~ /^192\.168\./ || $0 ~ /^172\.(1[6-9]|2[0-9]|3[0-1])\./' \
    | awk -v s0="$self0" -v s1="$self1" '$0 != s0 && $0 != s1' \
    | /usr/bin/sort -u \
    | /usr/bin/wc -l \
    | tr -d " "
  )"

  /bin/rm -f "$tmp" 2>/dev/null || true
  echo "${cnt:-}"
}

# ---------- GDMF ----------
gdmf_latest_ios_version() {
  local url="https://gdmf.apple.com/v2/pmv"
  local body http ver size sig prev_sig cached_ver changed

  body="$(/usr/bin/mktemp /var/tmp/gdmf_body.XXXXXX 2>/dev/null || echo "")"
  [[ -n "${body:-}" ]] || { echo ""; return; }

  prev_sig=""
  cached_ver=""
  if [[ -f "$GDMF_STATEFILE" ]]; then
    IFS=$'\t' read -r prev_sig cached_ver < "$GDMF_STATEFILE" 2>/dev/null || true
  fi

  http="$(/usr/bin/curl -L -sS --max-time 12 --fail -o "$body" -w "%{http_code}" "$url" 2>/dev/null || echo "")"
  http="$(echo "${http:-}" | tr -d '\r\n')"
  [[ -n "${http:-}" ]] || http="na"

  size="$(/usr/bin/wc -c < "$body" 2>/dev/null | tr -d ' ')"
  [[ -n "${size:-}" ]] || size="0"

  if [[ "$http" != "200" ]]; then
    printf "%s http=%s size=%s sig=na changed=na ver=na\n" "$(date '+%F %T')" "$http" "$size" >> "$GDMF_DEBUGLOG" 2>/dev/null || true
    trim_gdmf_debuglog
    /bin/rm -f "$body" 2>/dev/null || true
    echo "${cached_ver:-}"
    return
  fi

  sig="$(/usr/bin/shasum -a 256 "$body" 2>/dev/null | awk '{print $1}')"
  [[ -n "${sig:-}" ]] || sig=""

  ver="$(/usr/bin/perl -MJSON::PP -e '
    use strict; use warnings;
    my $file = shift;
    open my $fh, "<", $file or exit 0;
    local $/; my $txt = <$fh>;
    my $o = eval { decode_json($txt) }; exit 0 if !$o;
    my $list = $o->{PublicAssetSets}{iOS} || [];
    exit 0 if ref($list) ne "ARRAY" || !@$list;

    my %best;
    for my $it (@$list) {
      next unless ref($it) eq "HASH";
      my $pv = $it->{ProductVersion} || next;
      my $pd = $it->{PostingDate} || next;
      my ($major) = ($pv =~ /^(\d+)\./);
      next unless defined $major;

      if (!exists $best{$major}) { $best{$major} = $it; next; }
      my $b = $best{$major};

      if ($pd gt ($b->{PostingDate}||"")) { $best{$major} = $it; next; }
      if ($pd eq ($b->{PostingDate}||"")) {
        if ($pv gt ($b->{ProductVersion}||"")) { $best{$major} = $it; next; }
        if (($it->{Build}||"") gt ($b->{Build}||"")) { $best{$major} = $it; }
      }
    }

    my @maj = sort { $b <=> $a } keys %best;
    @maj = @maj[0..1] if @maj > 2;

    my @out;
    for my $m (@maj) {
      push @out, $best{$m}->{ProductVersion} if $best{$m}->{ProductVersion};
    }
    print join("|", @out);
  ' "$body" 2>/dev/null)"
  ver="$(echo "${ver:-}" | tr -d '\r\n')"

  changed="0"
  if [[ -n "${sig:-}" && "${sig:-}" != "${prev_sig:-}" ]]; then
    changed="1"
  fi

  printf "%s http=%s size=%s sig=%s changed=%s ver=%s\n" "$(date '+%F %T')" "$http" "$size" "${sig:-na}" "$changed" "${ver:-na}" >> "$GDMF_DEBUGLOG" 2>/dev/null || true
  trim_gdmf_debuglog

  if [[ -n "${ver:-}" ]]; then
    printf "%s\t%s\n" "${sig:-}" "$ver" > "$GDMF_STATEFILE" 2>/dev/null || true
    /bin/rm -f "$body" 2>/dev/null || true
    echo "$ver"
    return
  fi

  /bin/rm -f "$body" 2>/dev/null || true
  echo "${cached_ver:-}"
}

iosupdates_hu_value() {
  local cur="${1:-}"
  [[ -z "${cur:-}" ]] && { echo "n/a"; return; }

  local last="" count="0"
  if [[ -f "$IOSUPD_STATEFILE" ]]; then
    IFS=$'\t' read -r last count < "$IOSUPD_STATEFILE" 2>/dev/null || true
  fi
  echo "${count:-0}" | /usr/bin/grep -Eq '^[0-9]+$' || count="0"

  if [[ -z "${last:-}" || "$cur" != "$last" ]]; then
    printf "%s\t%s\n" "$cur" "$IOSUPD_BLOCK_LEN" > "$IOSUPD_STATEFILE" 2>/dev/null || true
    echo "$cur"
    return
  fi

  if [[ "$count" -gt 0 ]]; then
    local newc=$((count - 1))
    printf "%s\t%s\n" "$last" "$newc" > "$IOSUPD_STATEFILE" 2>/dev/null || true
    echo "$cur"
  else
    echo ""
  fi
}

totalssince_hu_value() {
  local cur="${1:-}"
  [[ -z "${cur:-}" ]] && { echo ""; return; }

  local last="" count="0"
  if [[ -f "$TOTALSSINCE_HU_STATEFILE" ]]; then
    IFS=$'\t' read -r last count < "$TOTALSSINCE_HU_STATEFILE" 2>/dev/null || true
  fi
  echo "${count:-0}" | /usr/bin/grep -Eq '^[0-9]+$' || count="0"

  if [[ -z "${last:-}" || "$cur" != "$last" ]]; then
    printf "%s\t%s\n" "$cur" "$TOTALSSINCE_BLOCK_LEN" > "$TOTALSSINCE_HU_STATEFILE" 2>/dev/null || true
    echo "$cur"
    return
  fi

  if [[ "$count" -gt 0 ]]; then
    local newc=$((count - 1))
    printf "%s\t%s\n" "$last" "$newc" > "$TOTALSSINCE_HU_STATEFILE" 2>/dev/null || true
    echo "$cur"
  else
    echo ""
  fi
}

# ---------- Archivierung bei iOS-Update-Wechsel ----------
# Kopiert sichtbare HU-/CO-Dateien ins Archiv (cp statt mv).
# Das RAW-Journal wird nie verschoben oder archiviert.
archive_csv_on_update() {
  local current_ver="${1:-}"
  [[ -z "${current_ver:-}" ]] && return

  local last_archived=""
  if [[ -f "$ARCHIVE_STATEFILE" ]]; then
    last_archived="$(/bin/cat "$ARCHIVE_STATEFILE" 2>/dev/null | tr -d '\r\n')"
  fi

  [[ "${current_ver:-}" == "${last_archived:-}" ]] && return

  if [[ -z "${last_archived:-}" ]]; then
    printf "%s\n" "$current_ver" > "$ARCHIVE_STATEFILE" 2>/dev/null || true
    return
  fi

  local ts_arch
  ts_arch="$(date +%Y%m%d_%H%M%S)"

  # HU kopieren, danach zurücksetzen (neuer iOS-Abschnitt beginnt frisch)
  if [[ -f "$OUT_HU" ]]; then
    local dst_hu="${VISIBLE_ARCHIVDIR}/${PREFIX}_AssetCache_Hu_v${SCRIPT_VER}_${ts_arch}.csv"
    if /bin/cp "$OUT_HU" "$dst_hu" 2>/dev/null; then
      : > "$OUT_HU"
      emit_csv_line "$OUT_HU" "${CSV_HEADER_FIELDS[@]}"
      /bin/chmod 644 "$OUT_HU" 2>/dev/null || true
    fi
  fi

  # CO kopieren und zurücksetzen
  if [[ -f "$OUT_CO" ]]; then
    local dst_co="${VISIBLE_ARCHIVDIR}/${PREFIX}_AssetCache_Co_v${SCRIPT_VER}_${ts_arch}.csv"
    if /bin/cp "$OUT_CO" "$dst_co" 2>/dev/null; then
      : > "$OUT_CO"
      emit_csv_line "$OUT_CO" "${CSV_HEADER_FIELDS_CO[@]}"
      /bin/chmod 644 "$OUT_CO" 2>/dev/null || true
    fi
  fi

  # Optionale sichtbare RAW-Datei ebenfalls kopieren und zurücksetzen
  if [[ "${EXPORT_VISIBLE_RAW}" -eq 1 && -n "${OUT_RAW:-}" && -f "$OUT_RAW" ]]; then
    local dst_raw="${VISIBLE_ARCHIVDIR}/${PREFIX}_AssetCacheRaw_v${SCRIPT_VER}_${ts_arch}.csv"
    if /bin/cp "$OUT_RAW" "$dst_raw" 2>/dev/null; then
      : > "$OUT_RAW"
      emit_csv_line "$OUT_RAW" "${CSV_HEADER_FIELDS[@]}"
      /bin/chmod 644 "$OUT_RAW" 2>/dev/null || true
    fi
  fi

  printf "%s\n" "$current_ver" > "$ARCHIVE_STATEFILE" 2>/dev/null || true
  status_log "INFO Archiv erstellt ts=${ts_arch} ver=${current_ver}"
}

# =============================================================================
# ISO-8601-Zeitstempel → HU-lesbares Format (für Rebuild aus Journal)
# =============================================================================
# Eingabe: 2026-05-20T12:34:56+02:00
# Ausgabe: 2026-05-20 12:34:56

iso_to_hu_ts() {
  local s="${1:-}"
  [[ -z "$s" ]] && echo "" && return
  # Doppelpunkt aus Zeitzone entfernen: +02:00 → +0200
  local s_fixed
  s_fixed="$(echo "$s" | sed -E 's/([+-][0-9]{2}):([0-9]{2})$/\1\2/')"
  /bin/date -j -f "%Y-%m-%dT%H:%M:%S%z" "$s_fixed" +"%Y-%m-%d %H:%M:%S" 2>/dev/null || echo ""
}

# =============================================================================
# Rebuild: HU und CO aus RAW-Journal neu erzeugen
# =============================================================================
# Deterministisch – ohne Live-Statefiles.
# Schreibt über temporäre Dateien, dann atomares mv.

rebuild_visible_from_journal() {
  if [[ ! -f "$RAW_JOURNAL" ]]; then
    status_log "INFO kein RAW-Journal vorhanden, kein Rebuild möglich"
    return 1
  fi
  if [[ ! -s "$RAW_JOURNAL" ]]; then
    status_log "INFO RAW-Journal ist leer, kein Rebuild"
    return 1
  fi

  status_log "INFO Rebuild HU/CO aus RAW-Journal gestartet: ${RAW_JOURNAL}"

  local tmp_hu tmp_co
  tmp_hu="$(/usr/bin/mktemp /var/tmp/rebuild_hu_XXXXXX 2>/dev/null || echo "")"
  tmp_co="$(/usr/bin/mktemp /var/tmp/rebuild_co_XXXXXX 2>/dev/null || echo "")"

  if [[ -z "${tmp_hu:-}" || -z "${tmp_co:-}" ]]; then
    status_log "ERROR Rebuild: temporäre Dateien konnten nicht erstellt werden"
    return 1
  fi

  : > "$tmp_hu"
  : > "$tmp_co"
  emit_csv_line "$tmp_hu" "${CSV_HEADER_FIELDS[@]}"
  emit_csv_line "$tmp_co" "${CSV_HEADER_FIELDS_CO[@]}"

  # Zustandsverfolgung für Block-Sichtbarkeit (deterministisch aus RAW)
  local last_iosupdates="" iosupdates_count=0
  local last_totalssince_hu="" totalssince_count=0

  local lineno=0
  local data_rows=0

  while IFS= read -r raw_line; do
    lineno=$((lineno + 1))
    [[ "$lineno" -eq 1 ]] && continue  # Header überspringen
    [[ -z "${raw_line:-}" ]] && continue

    # Gequotetes CSV via perl parsen → Tab-separiert
    local fields_str
    fields_str="$(echo "$raw_line" | /usr/bin/perl -e '
      use strict;
      my $line = <STDIN>; chomp $line;
      my @out;
      while (length($line) > 0) {
        if ($line =~ s/^"((?:[^"]|"")*)"(?:,|$)//) {
          my $v = $1; $v =~ s/""/"/g; push @out, $v;
        } elsif ($line =~ s/^([^,]*)(?:,|$)//) {
          push @out, $1;
        } else { last; }
      }
      print join("\t", @out) . "\n";
    ' 2>/dev/null)"

    [[ -z "${fields_str:-}" ]] && continue

    # In zsh-Array aufteilen (1-basiert)
    local -a f
    f=("${(s:\t:)${fields_str%%$'\n'}}")

    [[ "${#f}" -lt 23 ]] && continue  # unvollständige Zeile überspringen

    local r_host="${f[1]:-}"  r_ts="${f[2]:-}"       r_totalssince="${f[3]:-}"
    local r_peers="${f[4]:-}" r_clientscnt="${f[5]:-}" r_iosupdates="${f[6]:-}"
    local r_iosbytes="${f[7]:-}"    r_totret="${f[8]:-}"      r_totorg="${f[9]:-}"
    local r_serveddelta="${f[10]:-}" r_origindelta="${f[11]:-}" r_cacheused="${f[12]:-}"
    local r_cachepr="${f[13]:-}"  r_en0="${f[14]:-}"        r_en1="${f[15]:-}"
    local r_gatewayip="${f[16]:-}" r_defaultif="${f[17]:-}"   r_dnsres="${f[18]:-}"
    local r_applereach="${f[19]:-}" r_applettfb="${f[20]:-}"  r_wifisnr="${f[21]:-}"
    local r_wifinoise="${f[22]:-}"  r_wificca="${f[23]:-}"

    # ----------------------------------------------------------------
    # HU-Felder ableiten
    # ----------------------------------------------------------------

    # Timestamp
    local hu_ts
    hu_ts="$(iso_to_hu_ts "$r_ts")"
    [[ -z "${hu_ts:-}" ]] && hu_ts="$r_ts"

    # TotalsSince – Block-Sichtbarkeit
    local hu_totalssince_cur
    hu_totalssince_cur="$(iso_to_hu_ts "$r_totalssince")"
    local hu_totalssince=""
    if [[ -z "${last_totalssince_hu:-}" || "$hu_totalssince_cur" != "$last_totalssince_hu" ]]; then
      last_totalssince_hu="$hu_totalssince_cur"
      totalssince_count=$TOTALSSINCE_BLOCK_LEN
      hu_totalssince="$hu_totalssince_cur"
    elif [[ "$totalssince_count" -gt 0 ]]; then
      totalssince_count=$((totalssince_count - 1))
      hu_totalssince="$hu_totalssince_cur"
    fi

    # Peers – Anzahl
    local hu_peers=""
    if [[ -n "$r_peers" ]]; then
      hu_peers="$(echo "$r_peers" | awk -F';' '{print NF}')"
    fi

    # ClientsCnt
    local cc_active="" cc_total=""
    if [[ "$r_clientscnt" == */* ]]; then
      cc_active="${r_clientscnt%%/*}"
      cc_total="${r_clientscnt##*/}"
    elif [[ -n "$r_clientscnt" ]]; then
      cc_active="$r_clientscnt"
    fi
    local hu_clientscnt
    hu_clientscnt="$(format_clientscnt_hu "${cc_active:-}" "${cc_total:-}")"

    # iOSUpdates – Block-Sichtbarkeit
    local hu_iosupdates=""
    if [[ -z "${last_iosupdates:-}" || "$r_iosupdates" != "$last_iosupdates" ]]; then
      last_iosupdates="$r_iosupdates"
      iosupdates_count=$IOSUPD_BLOCK_LEN
      hu_iosupdates="$r_iosupdates"
    elif [[ "$iosupdates_count" -gt 0 ]]; then
      iosupdates_count=$((iosupdates_count - 1))
      hu_iosupdates="$r_iosupdates"
    fi

    # Byte-Felder
    local hu_iosbytes hu_totret hu_totorg hu_serveddelta hu_origindelta hu_cacheused
    hu_iosbytes="$(bytes_human "${r_iosbytes:-}")"
    hu_totret="$(bytes_human "${r_totret:-}")"
    hu_totorg="$(bytes_human "${r_totorg:-}")"
    hu_serveddelta="$(bytes_human "${r_serveddelta:-}")"
    hu_origindelta="$(bytes_human "${r_origindelta:-}")"
    hu_cacheused="$(bytes_human "${r_cacheused:-}")"

    # CachePr
    local hu_cachepr="0"
    [[ -n "${r_cachepr:-}" ]] && hu_cachepr="$r_cachepr"

    # Netzwerk
    local hu_en0 hu_en1 hu_gateway
    hu_en0="$(hu_iface_state "$r_en0")"
    hu_en1="$(hu_iface_state "$r_en1")"
    hu_gateway="$(hu_gateway_state "$r_gatewayip")"

    # DNS + Apple
    local hu_dnsres="no" hu_applereach="no" hu_applettfb="n/a"
    [[ "$r_dnsres" == "1" ]] && hu_dnsres="yes"
    if [[ "$r_applereach" == "1" ]]; then
      hu_applereach="yes"
      [[ -n "${r_applettfb:-}" ]] && hu_applettfb="${r_applettfb}ms" || hu_applettfb="n/a"
    fi

    # WiFi
    local hu_wifisnr="n/a" hu_wifinoise="n/a" hu_wificca="n/a"
    [[ -n "${r_wifisnr:-}" ]] && hu_wifisnr="${r_wifisnr}dB"
    [[ -n "${r_wifinoise:-}" ]] && hu_wifinoise="${r_wifinoise}dBm"
    [[ -n "${r_wificca:-}" ]] && hu_wificca="${r_wificca}%"

    emit_csv_line "$tmp_hu" \
      "$r_host" "$hu_ts" "$hu_totalssince" "$hu_peers" "$hu_clientscnt" \
      "$hu_iosupdates" "${hu_iosbytes:-n/a}" "${hu_totret:-n/a}" "${hu_totorg:-n/a}" \
      "${hu_serveddelta:-n/a}" "${hu_origindelta:-n/a}" "${hu_cacheused:-n/a}" \
      "$hu_cachepr" "$hu_en0" "$hu_en1" "$hu_gateway" "$r_defaultif" \
      "$hu_dnsres" "$hu_applereach" "$hu_applettfb" "$hu_wifisnr" "$hu_wifinoise" "$hu_wificca"

    # ----------------------------------------------------------------
    # CO-Felder ableiten
    # ----------------------------------------------------------------
    local co_iosupdates
    co_iosupdates="$(normalize_iosupdates_list_2digit "${r_iosupdates:-}")"

    emit_csv_line "$tmp_co" \
      "$PREFIX" "$r_ts" "$hu_peers" "$r_clientscnt" "$co_iosupdates" \
      "${r_iosbytes:-}" "${r_serveddelta:-}" "${r_origindelta:-}" "${r_cacheused:-}" \
      "$r_cachepr" "$r_dnsres" "$r_applereach" "${r_applettfb:-}" "${r_wifisnr:-}"

    data_rows=$((data_rows + 1))
  done < "$RAW_JOURNAL"

  # Atomar auf Zieldateien setzen
  local rebuild_ok=0
  if /bin/mv "$tmp_hu" "$OUT_HU" 2>/dev/null; then
    /bin/chmod 644 "$OUT_HU" 2>/dev/null || true
    status_log "INFO HU aus RAW-Journal wiederhergestellt (${data_rows} Datenzeilen)"
    rebuild_ok=1
  else
    status_log "ERROR Rebuild HU: mv fehlgeschlagen → $OUT_HU"
    /bin/rm -f "$tmp_hu" 2>/dev/null || true
  fi

  if /bin/mv "$tmp_co" "$OUT_CO" 2>/dev/null; then
    /bin/chmod 644 "$OUT_CO" 2>/dev/null || true
    status_log "INFO CO aus RAW-Journal wiederhergestellt (${data_rows} Datenzeilen)"
  else
    status_log "ERROR Rebuild CO: mv fehlgeschlagen → $OUT_CO"
    /bin/rm -f "$tmp_co" 2>/dev/null || true
    rebuild_ok=0
  fi

  return $((1 - rebuild_ok))
}

# =============================================================================
# Sichtbare Dateien prüfen und ggf. aus Journal wiederherstellen
# =============================================================================

check_and_rebuild_visible_files() {
  local needs_rebuild=0

  # Sichtbarer Log-Ordner vorhanden?
  if [[ ! -d "$VISIBLE_DIR" ]]; then
    /bin/mkdir -p "$VISIBLE_DIR" "$VISIBLE_ARCHIVDIR" 2>/dev/null || true
    /bin/chown root:wheel "$VISIBLE_DIR" "$VISIBLE_ARCHIVDIR" 2>/dev/null || true
    /bin/chmod 755 "$VISIBLE_DIR" "$VISIBLE_ARCHIVDIR" 2>/dev/null || true
    status_log "WARN sichtbarer Log-Ordner fehlte; neu angelegt"
    needs_rebuild=1
  fi

  if [[ ! -f "$OUT_HU" || ! -s "$OUT_HU" ]]; then
    status_log "INFO sichtbare HU-Datei fehlt oder leer"
    needs_rebuild=1
  fi

  if [[ ! -f "$OUT_CO" || ! -s "$OUT_CO" ]]; then
    status_log "INFO sichtbare CO-Datei fehlt oder leer"
    needs_rebuild=1
  fi

  if [[ "$needs_rebuild" -eq 1 ]]; then
    if [[ -f "$RAW_JOURNAL" && -s "$RAW_JOURNAL" ]]; then
      rebuild_visible_from_journal
    else
      status_log "INFO kein Journal für Rebuild vorhanden – sichtbare Dateien entstehen ab diesem Lauf neu"
    fi
  fi
}

# =============================================================================
# Startup-Sequenz
# =============================================================================

ensure_app_support_dirs
migrate_statefiles_from_var_tmp
status_log "INFO start v${SCRIPT_VER} schema=${RAW_SCHEMA_VER} host=${HOST} prefix=${PREFIX}"

_boot_changed=0
detect_boot_change || _boot_changed=1

check_and_rebuild_visible_files

# =============================================================================
# 1. Snapshot erfassen
# =============================================================================
# Einmalige Messung aller Systemwerte.

TotalsSince_src="$(get_key "TotalBytesAreSince")"

_peers_raw="$(peers_value)"

_clientscnt_active="$(clients_count_last_minutes 16)"
[[ -z "${_clientscnt_active:-}" ]] && _clientscnt_active=""

_site_code="$(site_code_for_clientscnt "$PREFIX")"
_clientscnt_total=""
if [[ -n "${_site_code:-}" && -n "${SUS_TOTAL_BY_SITE[${_site_code}]:-}" ]]; then
  _clientscnt_total="${SUS_TOTAL_BY_SITE[${_site_code}]}"
fi

_iosupdates_src="$(gdmf_latest_ios_version)"
[[ -z "${_iosupdates_src:-}" ]] && _iosupdates_src=""

_cacheused_src="$(get_key "CacheUsed")"
_totret_src="$(get_key "TotalBytesReturnedToClients")"
_totorg_src="$(get_key "TotalBytesStoredFromOrigin")"
_iosbytes_src="$(get_detail "iOS Software")"
_cachepr_src="$(get_key "MaxCachePressureLast1Hour")"

_en0_collected="$(iface_code en0)"
_en1_collected="$(iface_code en1)"
_gatewayip_collected="$(/sbin/route -n get default 2>/dev/null | awk '/gateway:/{print $2; exit}')"
_defaultif_collected="$(/sbin/route -n get default 2>/dev/null | awk '/interface:/{print $2; exit}')"

_dnsres_ok=0
if /usr/bin/dscacheutil -q host -a name swcdn.apple.com 2>/dev/null | /usr/bin/grep -q "ip_address"; then
  _dnsres_ok=1
fi

_apple_line="$(LC_ALL=C /usr/bin/curl -L --silent --show-error \
  --max-time 10 \
  -o /dev/null \
  -w "%{http_code} %{time_starttransfer}" \
  "https://swcdn.apple.com/" 2>/dev/null || true)"
_apple_code="$(echo "$_apple_line" | awk '{print $1}')"
_apple_ttfb="$(echo "$_apple_line" | awk '{print $2}')"

_wdutil_rssi=""
_wdutil_noise=""
_wdutil_cca=""
WDUTIL="/usr/bin/wdutil"
if [[ -x "$WDUTIL" ]]; then
  _wdutil_tmp="$(/usr/bin/mktemp /var/tmp/wdutil_XXXXXX 2>/dev/null || echo "")"
  _wdutil_out=""
  if [[ -n "${_wdutil_tmp:-}" ]]; then
    _timeout_run 30 "$_wdutil_tmp" "$WDUTIL" info
    _wdutil_out="$(/bin/cat "$_wdutil_tmp" 2>/dev/null || true)"
    /bin/rm -f "$_wdutil_tmp" 2>/dev/null || true
  fi

  _wifi_block="$(echo "$_wdutil_out" | awk '
    $0 ~ /^WIFI$/ {inside=1; next}
    inside && $0 ~ /^BLUETOOTH$/ {exit}
    inside {print}
  ')"

  _ssid="$(echo "$_wifi_block" | awk -F': ' '/^[[:space:]]*SSID[[:space:]]*:/ {print $2; exit}')"
  _opm="$(echo "$_wifi_block" | awk -F': ' '/^[[:space:]]*Op Mode[[:space:]]*:/ {print $2; exit}')"
  [[ "${_ssid:-}" == "None" ]] && _ssid=""
  [[ "${_opm:-}" == "None" ]] && _opm=""

  if [[ -n "${_ssid:-}" && -n "${_opm:-}" ]]; then
    _wdutil_rssi="$(echo "$_wifi_block" | awk -F': ' '/^[[:space:]]*RSSI[[:space:]]*:/ {gsub(/ dBm/,"",$2); print $2; exit}')"
    _wdutil_noise="$(echo "$_wifi_block" | awk -F': ' '/^[[:space:]]*Noise[[:space:]]*:/ {gsub(/ dBm/,"",$2); print $2; exit}')"
    _wdutil_cca="$(echo "$_wifi_block" | awk -F': ' '/^[[:space:]]*CCA[[:space:]]*:/ {gsub(/ %/,"",$2); print $2; exit}')"

    if [[ "${_wdutil_rssi:-}" == "0" && "${_wdutil_noise:-}" == "0" && "${_wdutil_cca:-}" == "0" ]]; then
      _wdutil_rssi=""
      _wdutil_noise=""
      _wdutil_cca=""
    fi
  fi
fi

# =============================================================================
# 2. RAW-Felder berechnen
# =============================================================================
# RAW ist die technische Wahrheit.

TotalsSince_Raw="$(totals_since_raw "$TotalsSince_src")"

Peers="${_peers_raw}"

ClientsCnt_Raw="$(format_clientscnt_raw "${_clientscnt_active:-}" "${_clientscnt_total:-}")"

iOSUpdates_Raw="${_iosupdates_src}"

iOSBytes_B="$(to_bytes "$_iosbytes_src")"
[[ -z "${iOSBytes_B:-}" ]] && iOSBytes_B=""

TotRet_B="$(to_bytes "$_totret_src")"
TotOrg_B="$(to_bytes "$_totorg_src")"
CacheUsed_B="$(to_bytes "$_cacheused_src")"

CachePr_Raw=""
if [[ -n "${_cachepr_src:-}" && "$_cachepr_src" == *"%" ]]; then
  _cachepr_val="${_cachepr_src%\%}"
  if echo "$_cachepr_val" | /usr/bin/grep -Eq '^[0-9]{1,3}$'; then
    CachePr_Raw="$_cachepr_val"
  fi
fi

ServedDelta_B=""
OriginDelta_B=""
if is_uint "${TotRet_B:-}"; then ServedDelta_B="0"; fi
if is_uint "${TotOrg_B:-}"; then OriginDelta_B="0"; fi

if [[ -f "$STATEFILE" ]]; then
  IFS=$'\t' read -r LAST_SINCE LAST_RET LAST_ORG < "$STATEFILE" || true
  if [[ -n "${LAST_SINCE:-}" && "$LAST_SINCE" == "$TotalsSince_src" ]]; then
    if is_uint "${LAST_RET:-}" && is_uint "${TotRet_B:-}" && [[ "${TotRet_B}" -ge "${LAST_RET}" ]]; then
      ServedDelta_B=$(( TotRet_B - LAST_RET ))
    fi
    if is_uint "${LAST_ORG:-}" && is_uint "${TotOrg_B:-}" && [[ "${TotOrg_B}" -ge "${LAST_ORG}" ]]; then
      OriginDelta_B=$(( TotOrg_B - LAST_ORG ))
    fi
  fi
fi

EN0="${_en0_collected}"
EN1="${_en1_collected}"
GatewayIP="${_gatewayip_collected}"
DefaultIf="${_defaultif_collected}"

DNSRes_Raw="0"
[[ "${_dnsres_ok}" -eq 1 ]] && DNSRes_Raw="1"

AppleReach_Raw="0"
AppleTTFB_raw=""
if echo "$_apple_code" | /usr/bin/grep -Eq '^[0-9]{3}$' \
  && [[ "$_apple_code" -ge 200 && "$_apple_code" -lt 500 ]] \
  && echo "$_apple_ttfb" | /usr/bin/grep -Eq '^[0-9.]+$'; then
  _apple_ttfb_ms="$(LC_ALL=C /usr/bin/awk -v t="$_apple_ttfb" 'BEGIN{printf "%.0f", t*1000.0}')"
  if [[ "${_apple_ttfb_ms:-0}" -gt 0 ]]; then
    AppleReach_Raw="1"
    AppleTTFB_raw="${_apple_ttfb_ms}"
  fi
fi

WiFiSNR_raw=""
WifiNoise_raw=""
WifiCCA_raw=""
if is_int "${_wdutil_rssi:-}" && is_int "${_wdutil_noise:-}"; then
  WiFiSNR_raw=$(( _wdutil_rssi - _wdutil_noise ))
  WifiNoise_raw="${_wdutil_noise}"
fi
if echo "${_wdutil_cca:-}" | /usr/bin/grep -Eq '^[0-9]+$'; then
  WifiCCA_raw="${_wdutil_cca}"
fi

# =============================================================================
# 3. RAW validieren / STATEFILE aktualisieren
# =============================================================================

if [[ -n "${TotalsSince_src:-}" ]]; then
  if is_uint "${TotRet_B:-}" && is_uint "${TotOrg_B:-}"; then
    printf "%s\t%s\t%s\n" "$TotalsSince_src" "${TotRet_B}" "${TotOrg_B}" > "$STATEFILE" 2>/dev/null || true
  fi
fi

# =============================================================================
# 4. RAW-Journal schreiben (dauerhaft, zuerst)
# =============================================================================
# Das Journal ist die kanonische Datenquelle. Wird geschrieben bevor HU/CO entstehen.

# Journal anlegen (Header) wenn nicht vorhanden oder leer
if [[ ! -f "$RAW_JOURNAL" || ! -s "$RAW_JOURNAL" ]]; then
  : > "$RAW_JOURNAL" 2>/dev/null || {
    status_log "ERROR RAW-Journal konnte nicht angelegt werden: $RAW_JOURNAL"
  }
  if [[ -f "$RAW_JOURNAL" ]]; then
    /bin/chown root:wheel "$RAW_JOURNAL" 2>/dev/null || true
    /bin/chmod 600 "$RAW_JOURNAL" 2>/dev/null || true
    emit_csv_line "$RAW_JOURNAL" "${CSV_HEADER_FIELDS[@]}"
    status_log "INFO neues RAW-Journal angelegt: $RAW_JOURNAL"
  fi
fi

# Schutz gegen Doppelzeilen: letzten Timestamp prüfen
_journal_skip=0
if [[ -f "$RAW_JOURNAL" ]]; then
  _last_journal_line="$(/usr/bin/tail -n 1 "$RAW_JOURNAL" 2>/dev/null || true)"
  if echo "${_last_journal_line:-}" | /usr/bin/grep -qF "\"${TS_RAW}\""; then
    status_log "WARN Doppelzeile erkannt (ts=${TS_RAW}), Journal-Append übersprungen"
    _journal_skip=1
  fi
fi

if [[ "$_journal_skip" -eq 0 ]]; then
  if emit_csv_line "$RAW_JOURNAL" \
    "$HOST" \
    "$TS_RAW" \
    "$TotalsSince_Raw" \
    "$Peers" \
    "$ClientsCnt_Raw" \
    "$iOSUpdates_Raw" \
    "${iOSBytes_B:-}" \
    "${TotRet_B:-}" \
    "${TotOrg_B:-}" \
    "${ServedDelta_B:-}" \
    "${OriginDelta_B:-}" \
    "${CacheUsed_B:-}" \
    "$CachePr_Raw" \
    "$EN0" \
    "$EN1" \
    "$GatewayIP" \
    "$DefaultIf" \
    "$DNSRes_Raw" \
    "$AppleReach_Raw" \
    "$AppleTTFB_raw" \
    "$WiFiSNR_raw" \
    "$WifiNoise_raw" \
    "$WifiCCA_raw" 2>/dev/null; then
    status_log "INFO RAW-Zeile ins Journal geschrieben ts=${TS_RAW}"
  else
    status_log "ERROR RAW-Zeile konnte nicht ins Journal geschrieben werden"
  fi
fi

# =============================================================================
# 5. HU-Felder aus RAW ableiten
# =============================================================================

TotalsSince_Hu="$(totalssince_hu_value "$(totals_since_hu "$TotalsSince_src")")"

if [[ -n "${Peers:-}" ]]; then
  Peers_Hu="$(echo "$Peers" | awk -F';' '{print NF}')"
else
  Peers_Hu=""
fi

ClientsCnt_Hu="$(format_clientscnt_hu "${_clientscnt_active:-}" "${_clientscnt_total:-}")"

iOSUpdates_Hu="$(iosupdates_hu_value "${iOSUpdates_Raw:-}")"

iOSBytes_Hu="$(bytes_human "${iOSBytes_B:-}")"
TotReturned_Hu="$(bytes_human "${TotRet_B:-}")"
TotOrigin_Hu="$(bytes_human "${TotOrg_B:-}")"
CacheUsed_Hu="$(bytes_human "${CacheUsed_B:-}")"

CachePr_Hu="0"
[[ -n "${CachePr_Raw:-}" ]] && CachePr_Hu="${CachePr_Raw}"

ServedDelta_Hu="$(bytes_human "${ServedDelta_B:-}")"
OriginDelta_Hu="$(bytes_human "${OriginDelta_B:-}")"

EN0_HU="$(hu_iface_state "$EN0")"
EN1_HU="$(hu_iface_state "$EN1")"
GatewayIP_HU="$(hu_gateway_state "$GatewayIP")"

DNSRes_Hu="no"
[[ "$DNSRes_Raw" == "1" ]] && DNSRes_Hu="yes"

AppleReach_Hu="no"
AppleTTFB_hu="n/a"
if [[ "$AppleReach_Raw" == "1" ]]; then
  AppleReach_Hu="yes"
  AppleTTFB_hu="${AppleTTFB_raw}ms"
fi

WiFiSNR_hu="n/a"
WifiNoise_hu="n/a"
WifiCCA_hu="n/a"
[[ -n "${WiFiSNR_raw:-}" ]] && WiFiSNR_hu="${WiFiSNR_raw}dB"
[[ -n "${WifiNoise_raw:-}" ]] && WifiNoise_hu="${WifiNoise_raw}dBm"
[[ -n "${WifiCCA_raw:-}" ]] && WifiCCA_hu="${WifiCCA_raw}%"

# =============================================================================
# 6. CO-Felder aus RAW ableiten
# =============================================================================

SiteCode_Co="${PREFIX}"
PeerCnt_Co="${Peers_Hu:-}"
iOSUpdates_Co="$(normalize_iosupdates_list_2digit "${iOSUpdates_Raw:-}")"

# =============================================================================
# 7. Archivierung bei iOS-Update-Wechsel
# =============================================================================

archive_csv_on_update "${iOSUpdates_Raw:-}"

# =============================================================================
# 8. Sichtbare Dateien schreiben (HU, CO; RAW optional)
# =============================================================================

# Verzeichnis noch einmal sicherstellen (kann nach Rebuild fehlen)
[[ ! -d "$VISIBLE_DIR" ]] && /bin/mkdir -p "$VISIBLE_DIR" "$VISIBLE_ARCHIVDIR" 2>/dev/null || true

# HU
if [[ ! -f "$OUT_HU" || ! -s "$OUT_HU" ]]; then
  : > "$OUT_HU"
  emit_csv_line "$OUT_HU" "${CSV_HEADER_FIELDS[@]}"
  /bin/chmod 644 "$OUT_HU" 2>/dev/null || true
fi

emit_csv_line "$OUT_HU" \
  "$HOST" \
  "$TS_HU" \
  "$TotalsSince_Hu" \
  "$Peers_Hu" \
  "$ClientsCnt_Hu" \
  "$iOSUpdates_Hu" \
  "${iOSBytes_Hu:-n/a}" \
  "${TotReturned_Hu:-n/a}" \
  "${TotOrigin_Hu:-n/a}" \
  "${ServedDelta_Hu:-n/a}" \
  "${OriginDelta_Hu:-n/a}" \
  "${CacheUsed_Hu:-n/a}" \
  "$CachePr_Hu" \
  "$EN0_HU" \
  "$EN1_HU" \
  "$GatewayIP_HU" \
  "$DefaultIf" \
  "$DNSRes_Hu" \
  "$AppleReach_Hu" \
  "$AppleTTFB_hu" \
  "$WiFiSNR_hu" \
  "$WifiNoise_hu" \
  "$WifiCCA_hu"

# CO
if [[ ! -f "$OUT_CO" || ! -s "$OUT_CO" ]]; then
  : > "$OUT_CO"
  emit_csv_line "$OUT_CO" "${CSV_HEADER_FIELDS_CO[@]}"
  /bin/chmod 644 "$OUT_CO" 2>/dev/null || true
fi

emit_csv_line "$OUT_CO" \
  "$SiteCode_Co" \
  "$TS_RAW" \
  "$PeerCnt_Co" \
  "$ClientsCnt_Raw" \
  "$iOSUpdates_Co" \
  "${iOSBytes_B:-}" \
  "${ServedDelta_B:-}" \
  "${OriginDelta_B:-}" \
  "${CacheUsed_B:-}" \
  "$CachePr_Raw" \
  "$DNSRes_Raw" \
  "$AppleReach_Raw" \
  "$AppleTTFB_raw" \
  "$WiFiSNR_raw"

# Optionale sichtbare RAW-Datei (nur wenn EXPORT_VISIBLE_RAW=1)
if [[ "${EXPORT_VISIBLE_RAW}" -eq 1 && -n "${OUT_RAW:-}" ]]; then
  if [[ ! -f "$OUT_RAW" || ! -s "$OUT_RAW" ]]; then
    : > "$OUT_RAW"
    emit_csv_line "$OUT_RAW" "${CSV_HEADER_FIELDS[@]}"
    /bin/chmod 644 "$OUT_RAW" 2>/dev/null || true
  fi

  emit_csv_line "$OUT_RAW" \
    "$HOST" \
    "$TS_RAW" \
    "$TotalsSince_Raw" \
    "$Peers" \
    "$ClientsCnt_Raw" \
    "$iOSUpdates_Raw" \
    "${iOSBytes_B:-}" \
    "${TotRet_B:-}" \
    "${TotOrg_B:-}" \
    "${ServedDelta_B:-}" \
    "${OriginDelta_B:-}" \
    "${CacheUsed_B:-}" \
    "$CachePr_Raw" \
    "$EN0" \
    "$EN1" \
    "$GatewayIP" \
    "$DefaultIf" \
    "$DNSRes_Raw" \
    "$AppleReach_Raw" \
    "$AppleTTFB_raw" \
    "$WiFiSNR_raw" \
    "$WifiNoise_raw" \
    "$WifiCCA_raw"
fi

exit 0
