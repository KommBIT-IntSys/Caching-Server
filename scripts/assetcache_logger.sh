#!/bin/zsh

set -u

# Asset Cache Monitoring / Logging
# Version 1.8.0 (KommunalBIT)
# SPDX-License-Identifier: EUPL-1.2
# Licensed under the EUPL, Version 1.2
# https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
# Copyright (C) 2026 Jens Luithle@KommunalBIT AöR
#
# Drei CSV-Ausgaben pro Host:
#   RAW – vollständige Rohdaten, maschinenlesbar, ISO-8601-Zeitstempel
#   HU  – menschenlesbar, Einheiten, n/a für fehlende Werte
#   CO  – datensparsam, KI-/Analysegeeignet, kein voller Hostname, keine IPs
#
# - ClientsCnt RAW = active/total (e.g. 4/122), or just active if site unknown
# - ClientsCnt HU  = percentage only (e.g. 3.3%), or just active if site unknown
# - ClientsCnt CO  = active/total (wie RAW); Hostname-Feld = SiteCode (PREFIX)
# - CSV output is fully quoted / CSV-safe, including header
# - SuS table is loaded from /etc/kommunalbit/schulen.conf (external config)

SCRIPT_VER="1.8.0"

OUTDIR="/Library/Logs/KommunalBIT"
ARCHIVDIR="${OUTDIR}/Archiv"
STATEFILE="/var/tmp/assetcache_logger_state.tsv"

# HU visibility block state for iOSUpdates (19 lines after a change = 20 total)
IOSUPD_STATEFILE="/var/tmp/assetcache_iosupdates_hu_state.tsv"
IOSUPD_BLOCK_LEN=19

# HU visibility block state for TotalsSince (19 lines after a change = 20 total)
TOTALSSINCE_HU_STATEFILE="/var/tmp/assetcache_totalssince_hu_state.tsv"
TOTALSSINCE_BLOCK_LEN=19

# GDMF caching + debug
GDMF_STATEFILE="/var/tmp/assetcache_gdmf_state.tsv"   # SIG<TAB>VER
GDMF_DEBUGLOG="/var/tmp/assetcache_gdmf_debug.log"    # trimmed to last 1000 lines

# ---------- SuS table – loaded from external config file ----------
# Rule: only devices whose name contains "SuS" are counted as SuS base for ClientsCnt.
# Format: one entry per line:  KÜRZEL<TAB>ANZAHL  (lines starting with # are ignored)
# The file is managed via MDM and is not part of this script.
typeset -A SUS_TOTAL_BY_SITE
SCHULEN_CONF="/etc/kommunalbit/schulen.conf"
if [[ -f "${SCHULEN_CONF}" ]]; then
  while IFS=$'\t' read -r _site _count; do
    [[ "${_site}" == \#* || -z "${_site}" ]] && continue
    [[ -n "${_count}" ]] && SUS_TOTAL_BY_SITE[${_site}]=${_count}
  done < "${SCHULEN_CONF}"
fi

CSV_HEADER_FIELDS=(
  "Hostname" "Timestamp" "TotalsSince" "Peers" "ClientsCnt" "iOSUpdates" "iOSBytes"
  "TotReturned" "TotOrigin" "ServedDelta" "OriginDelta" "CacheUsed" "CachePr"
  "EN0" "EN1" "GatewayIP" "DefaultIf" "DNSRes" "AppleReach" "AppleTTFB"
  "WiFiSNR" "WifiNoise" "WifiCCA"
)

# CO: datensparsam, ohne IPs und volle Hostnamen – für KI-gestützte externe Auswertung
CSV_HEADER_FIELDS_CO=(
  "SiteCode" "Timestamp" "PeerCnt" "ClientsCnt" "iOSUpdates" "iOSBytes"
  "ServedDelta" "OriginDelta" "CacheUsed" "CachePr"
  "DNSRes" "AppleReach" "AppleTTFB" "WiFiSNR"
)

# RAW: ISO 8601 local time with offset
TS_RAW="$(date +"%Y-%m-%dT%H:%M:%S%z" | sed -E 's/([+-][0-9]{2})([0-9]{2})$/\1:\2/')"

# HU: pretty local time without offset
TS_HU="$(date +"%Y-%m-%d %H:%M:%S")"

# Hostname: prefer HostName/LocalHostName to avoid DNS-inventory weirdness
HOST="$( /usr/sbin/scutil --get HostName 2>/dev/null || /usr/sbin/scutil --get LocalHostName 2>/dev/null || /bin/hostname -s 2>/dev/null || echo "" )"
[[ -z "${HOST:-}" ]] && HOST="unknown"

PREFIX="$(echo "$HOST" | awk -F'-' '{print $1}')"

OUT_RAW="${OUTDIR}/${PREFIX}_AssetCacheRaw_v${SCRIPT_VER}.csv"
OUT_HU="${OUTDIR}/${PREFIX}_AssetCache_Hu_v${SCRIPT_VER}.csv"
OUT_CO="${OUTDIR}/${PREFIX}_AssetCache_Co_v${SCRIPT_VER}.csv"

# Archive state per prefix
ARCHIVE_STATEFILE="/var/tmp/assetcache_archive_state_${PREFIX}.tsv"

# Ensure dirs exist early
/bin/mkdir -p "$OUTDIR" "$ARCHIVDIR" 2>/dev/null || true

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

  # Unknown site: just return active client count, no percentage
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

# ---------- Timeout helper ----------
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

# ---------- Gather AssetCacheManagerUtil status ----------
_acmu_tmp="$(/usr/bin/mktemp /var/tmp/acmu_XXXXXX 2>/dev/null || echo "")"
STATUS_TXT=""
if [[ -n "${_acmu_tmp:-}" ]]; then
  _timeout_run 30 "$_acmu_tmp" /usr/bin/AssetCacheManagerUtil status
  STATUS_TXT="$(/bin/cat "$_acmu_tmp" 2>/dev/null || true)"
  /bin/rm -f "$_acmu_tmp" 2>/dev/null || true
fi

# ---------- Helpers ----------
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
    if (v>=1000000000000){v=v/1000000000000; unit="TB"}
    else if (v>=1000000000) {v=v/1000000000; unit="GB"}
    else if (v>=1000000)    {v=v/1000000; unit="MB"}
    else if (v>=1000)       {v=v/1000; unit="KB"}
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

# ---------- ClientsCnt: unique client IPv4s in last N minutes ----------
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

  if [[ -f "$OUT_RAW" ]]; then
    /bin/mv "$OUT_RAW" "${ARCHIVDIR}/${PREFIX}_AssetCacheRaw_v${SCRIPT_VER}_${ts_arch}.csv" 2>/dev/null || true
  fi
  if [[ -f "$OUT_HU" ]]; then
    /bin/mv "$OUT_HU" "${ARCHIVDIR}/${PREFIX}_AssetCache_Hu_v${SCRIPT_VER}_${ts_arch}.csv" 2>/dev/null || true
  fi
  if [[ -f "$OUT_CO" ]]; then
    /bin/mv "$OUT_CO" "${ARCHIVDIR}/${PREFIX}_AssetCache_Co_v${SCRIPT_VER}_${ts_arch}.csv" 2>/dev/null || true
  fi

  printf "%s\n" "$current_ver" > "$ARCHIVE_STATEFILE" 2>/dev/null || true
}

# =============================================================================
# 1. Collect snapshot
# =============================================================================
# Einmalige Erfassung aller Systemwerte. Keine Ableitung, keine Formatierung.

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
# 2. Build RAW fields
# =============================================================================
# RAW ist die technische Wahrheit und primäre Datenquelle.

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
# 3. Validate / normalize RAW
# =============================================================================
# Konsistenz- und Ableitungslogik auf Basis der RAW-Felder. Keine neue Messung.

if [[ -n "${TotalsSince_src:-}" ]]; then
  if is_uint "${TotRet_B:-}" && is_uint "${TotOrg_B:-}"; then
    printf "%s\t%s\t%s\n" "$TotalsSince_src" "${TotRet_B}" "${TotOrg_B}" > "$STATEFILE" 2>/dev/null || true
  fi
fi

# =============================================================================
# 4. Build HU fields from RAW
# =============================================================================
# HU ist eine menschenlesbare View. Keine eigene Messung.

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
# 5. Build CO fields from RAW
# =============================================================================
# CO ist eine datensparsame Analyse-/Weitergabe-View. Keine eigene Messung.

SiteCode_Co="${PREFIX}"
PeerCnt_Co="${Peers_Hu:-}"

# =============================================================================
# 6. Write CSV files
# =============================================================================
# RAW zuerst schreiben, danach HU und CO.

archive_csv_on_update "${iOSUpdates_Raw:-}"

if [[ ! -f "$OUT_RAW" ]]; then
  : > "$OUT_RAW"
  emit_csv_line "$OUT_RAW" "${CSV_HEADER_FIELDS[@]}"
  /bin/chmod 644 "$OUT_RAW"
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

if [[ ! -f "$OUT_HU" ]]; then
  : > "$OUT_HU"
  emit_csv_line "$OUT_HU" "${CSV_HEADER_FIELDS[@]}"
  /bin/chmod 644 "$OUT_HU"
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

if [[ ! -f "$OUT_CO" ]]; then
  : > "$OUT_CO"
  emit_csv_line "$OUT_CO" "${CSV_HEADER_FIELDS_CO[@]}"
  /bin/chmod 644 "$OUT_CO"
fi

emit_csv_line "$OUT_CO" \
  "$SiteCode_Co" \
  "$TS_RAW" \
  "$PeerCnt_Co" \
  "$ClientsCnt_Raw" \
  "$iOSUpdates_Raw" \
  "${iOSBytes_B:-}" \
  "${ServedDelta_B:-}" \
  "${OriginDelta_B:-}" \
  "${CacheUsed_B:-}" \
  "$CachePr_Raw" \
  "$DNSRes_Raw" \
  "$AppleReach_Raw" \
  "$AppleTTFB_raw" \
  "$WiFiSNR_raw"

exit 0

