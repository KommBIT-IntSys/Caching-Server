#!/bin/zsh
set -u

# Asset Cache Monitoring / Logging
# Version 1.6 (KommunalBIT)
#
# Final characteristics:
# - ClientsCnt RAW = active/total (e.g. 4/122), or just active if site unknown
# - ClientsCnt HU  = percentage only (e.g. 3.3%), or just active if site unknown
# - CSV output is fully quoted / CSV-safe, including header
# - Built-in SuS table is based on device names containing "SuS"
# - No extra columns added; existing schema preserved

SCRIPT_VER="1.6"

OUTDIR="/Library/Logs/KommunalBIT"
ARCHIVDIR="${OUTDIR}/Archiv"
STATEFILE="/var/tmp/assetcache_logger_state.tsv"

# HU visibility block state for iOSUpdates (19 lines after a change)
IOSUPD_STATEFILE="/var/tmp/assetcache_iosupdates_hu_state.tsv"
IOSUPD_BLOCK_LEN=19

# GDMF caching + debug
GDMF_STATEFILE="/var/tmp/assetcache_gdmf_state.tsv"   # SIG<TAB>VER
GDMF_DEBUGLOG="/var/tmp/assetcache_gdmf_debug.log"    # trimmed to last 1000 lines

# ---------- Static SuS table (>30 devices; source: Geräte_Global_2026-03-11_1242.csv) ----------
# Rule: only devices whose name contains "SuS" are counted as SuS base for ClientsCnt.
# Moved near the top on purpose for easier maintenance.
typeset -A SUS_TOTAL_BY_SITE
SUS_TOTAL_BY_SITE=(
  ASGS 122
  BRL 80
  BUE 114
  BUN 48
  CEG 64
  DEC 80
  EIC 133
  ELT 99
  EPS 66
  FRA 96
  FRS 62
  GSN 48
  GSW 171
  GYF 79
  HGS 44
  HHS-N 63
  HHS-W 81
  HKS 64
  LOS 81
  MJS 32
  MPS 80
  MTG 48
  OGY 36
  OPS1 64
  OPS2 32
  PES 80
  RAE 55
  SFK 49
  TEN 99
)

CSV_HEADER_FIELDS=(
  "Hostname" "Timestamp" "TotalsSince" "Peers" "ClientsCnt" "iOSUpdates" "iOSBytes"
  "TotReturned" "TotOrigin" "ServedDelta" "OriginDelta" "CacheUsed" "CachePr"
  "EN0" "EN1" "GatewayIP" "DefaultIf" "DNSRes" "AppleReach" "AppleTTFB"
  "WiFiSNR" "WifiNoise" "WifiCCA"
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

  printf "%s\n" "$current_ver" > "$ARCHIVE_STATEFILE" 2>/dev/null || true
}

# ---------- Core values ----------
TotalsSince_src="$(get_key "TotalBytesAreSince")"
TotalsSince_Raw="$(totals_since_raw "$TotalsSince_src")"
TotalsSince_Hu="$(totals_since_hu "$TotalsSince_src")"

Peers="$(peers_value)"

ClientsCnt_Active="$(clients_count_last_minutes 16)"
[[ -z "${ClientsCnt_Active:-}" ]] && ClientsCnt_Active=""

SITE_CODE="$(site_code_for_clientscnt "$PREFIX")"
ClientsCnt_Total=""
if [[ -n "${SITE_CODE:-}" && -n "${SUS_TOTAL_BY_SITE[$SITE_CODE]:-}" ]]; then
  ClientsCnt_Total="${SUS_TOTAL_BY_SITE[$SITE_CODE]}"
fi

ClientsCnt_Raw="$(format_clientscnt_raw "${ClientsCnt_Active:-}" "${ClientsCnt_Total:-}")"
ClientsCnt_Hu="$(format_clientscnt_hu "${ClientsCnt_Active:-}" "${ClientsCnt_Total:-}")"

iOSUpdates_Raw="$(gdmf_latest_ios_version)"
[[ -z "${iOSUpdates_Raw:-}" ]] && iOSUpdates_Raw=""
iOSUpdates_Hu="$(iosupdates_hu_value "${iOSUpdates_Raw:-}")"

CacheUsed_raw="$(get_key "CacheUsed")"
TotRet_raw="$(get_key "TotalBytesReturnedToClients")"
TotOrg_raw="$(get_key "TotalBytesStoredFromOrigin")"

CacheUsed_B="$(to_bytes "$CacheUsed_raw")"
TotRet_B="$(to_bytes "$TotRet_raw")"
TotOrg_B="$(to_bytes "$TotOrg_raw")"

iOSBytes_B="$(to_bytes "$(get_detail "iOS Software")")"
[[ -z "${iOSBytes_B:-}" ]] && iOSBytes_B=""

CachePr_Hu="0"
CachePr_Raw=""

pr_raw="$(get_key "MaxCachePressureLast1Hour")"
if [[ -n "${pr_raw:-}" && "$pr_raw" == *"%" ]]; then
  pr_val="${pr_raw%\%}"
  if echo "$pr_val" | /usr/bin/grep -Eq '^[0-9]{1,3}$'; then
    CachePr_Hu="$pr_val"
    CachePr_Raw="$pr_val"
  fi
fi

CacheUsed_Hu="$(bytes_human "${CacheUsed_B:-}")"
iOSBytes_Hu="$(bytes_human "${iOSBytes_B:-}")"
TotReturned_Hu="$(bytes_human "${TotRet_B:-}")"
TotOrigin_Hu="$(bytes_human "${TotOrg_B:-}")"

# ---------- Deltas ----------
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

if [[ -n "${TotalsSince_src:-}" ]]; then
  if is_uint "${TotRet_B:-}" && is_uint "${TotOrg_B:-}"; then
    printf "%s\t%s\t%s\n" "$TotalsSince_src" "${TotRet_B}" "${TotOrg_B}" > "$STATEFILE" 2>/dev/null || true
  fi
fi

ServedDelta_Hu="$(bytes_human "${ServedDelta_B:-}")"
OriginDelta_Hu="$(bytes_human "${OriginDelta_B:-}")"

# ---------- Network basics ----------
EN0="$(iface_code en0)"
EN1="$(iface_code en1)"

GatewayIP="$(/sbin/route -n get default 2>/dev/null | awk '/gateway:/{print $2; exit}')"
DefaultIf="$(/sbin/route -n get default 2>/dev/null | awk '/interface:/{print $2; exit}')"

DNSRes_Hu="no"
DNSRes_Raw="0"
if /usr/bin/dscacheutil -q host -a name swcdn.apple.com 2>/dev/null | /usr/bin/grep -q "ip_address"; then
  DNSRes_Hu="yes"
  DNSRes_Raw="1"
fi

# ---------- Apple reach + timing ----------
AppleReach_Hu="no"
AppleReach_Raw="0"
AppleTTFB_hu="n/a"
AppleTTFB_raw=""

apple_line="$(LC_ALL=C /usr/bin/curl -L --silent --show-error \
  --max-time 10 \
  -o /dev/null \
  -w "%{http_code} %{time_starttransfer}" \
  "https://swcdn.apple.com/" 2>/dev/null || true)"

apple_code="$(echo "$apple_line" | awk '{print $1}')"
apple_ttfb="$(echo "$apple_line" | awk '{print $2}')"

if echo "$apple_code" | /usr/bin/grep -Eq '^[0-9]{3}$' \
  && [[ "$apple_code" -ge 200 && "$apple_code" -lt 500 ]] \
  && echo "$apple_ttfb" | /usr/bin/grep -Eq '^[0-9.]+$'; then
  AppleTTFB_ms="$(LC_ALL=C /usr/bin/awk -v t="$apple_ttfb" 'BEGIN{printf "%.0f", t*1000.0}')"
  if [[ "${AppleTTFB_ms:-0}" -gt 0 ]]; then
    AppleReach_Hu="yes"
    AppleReach_Raw="1"
    AppleTTFB_raw="${AppleTTFB_ms}"
    AppleTTFB_hu="${AppleTTFB_ms}ms"
  fi
fi

# ---------- Wi-Fi via wdutil ----------
WiFiSNR_raw=""
WifiNoise_raw=""
WifiCCA_raw=""

WiFiSNR_hu="n/a"
WifiNoise_hu="n/a"
WifiCCA_hu="n/a"

WDUTIL="/usr/bin/wdutil"
if [[ -x "$WDUTIL" ]]; then
  _wdutil_tmp="$(/usr/bin/mktemp /var/tmp/wdutil_XXXXXX 2>/dev/null || echo "")"
  wdi=""
  if [[ -n "${_wdutil_tmp:-}" ]]; then
    _timeout_run 30 "$_wdutil_tmp" "$WDUTIL" info
    wdi="$(/bin/cat "$_wdutil_tmp" 2>/dev/null || true)"
    /bin/rm -f "$_wdutil_tmp" 2>/dev/null || true
  fi

  wifi_block="$(echo "$wdi" | awk '
    $0 ~ /^WIFI$/ {inside=1; next}
    inside && $0 ~ /^BLUETOOTH$/ {exit}
    inside {print}
  ')"

  ssid="$(echo "$wifi_block" | awk -F': ' '/^[[:space:]]*SSID[[:space:]]*:/ {print $2; exit}')"
  opm="$(echo "$wifi_block" | awk -F': ' '/^[[:space:]]*Op Mode[[:space:]]*:/ {print $2; exit}')"
  [[ "${ssid:-}" == "None" ]] && ssid=""
  [[ "${opm:-}" == "None" ]] && opm=""

  if [[ -n "${ssid:-}" && -n "${opm:-}" ]]; then
    rssi="$(echo "$wifi_block" | awk -F': ' '/^[[:space:]]*RSSI[[:space:]]*:/ {gsub(/ dBm/,"",$2); print $2; exit}')"
    noise="$(echo "$wifi_block" | awk -F': ' '/^[[:space:]]*Noise[[:space:]]*:/ {gsub(/ dBm/,"",$2); print $2; exit}')"
    cca="$(echo "$wifi_block" | awk -F': ' '/^[[:space:]]*CCA[[:space:]]*:/ {gsub(/ %/,"",$2); print $2; exit}')"

    if [[ "${rssi:-}" == "0" && "${noise:-}" == "0" && "${cca:-}" == "0" ]]; then
      :
    else
      if is_int "${rssi:-}" && is_int "${noise:-}"; then
        snr=$(( rssi - noise ))
        WiFiSNR_raw="${snr}"
        WifiNoise_raw="${noise}"
        WiFiSNR_hu="${snr}dB"
        WifiNoise_hu="${noise}dBm"
      fi
      if echo "${cca:-}" | /usr/bin/grep -Eq '^[0-9]+$'; then
        WifiCCA_raw="${cca}"
        WifiCCA_hu="${cca}%"
      fi
    fi
  fi
fi

archive_csv_on_update "${iOSUpdates_Raw:-}"

# ---------- CSV write ----------
if [[ ! -f "$OUT_RAW" ]]; then
  : > "$OUT_RAW"
  emit_csv_line "$OUT_RAW" "${CSV_HEADER_FIELDS[@]}"
  /bin/chmod 644 "$OUT_RAW"
fi

if [[ ! -f "$OUT_HU" ]]; then
  : > "$OUT_HU"
  emit_csv_line "$OUT_HU" "${CSV_HEADER_FIELDS[@]}"
  /bin/chmod 644 "$OUT_HU"
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

if [[ -n "${Peers:-}" ]]; then
  Peers_Hu="$(echo "$Peers" | awk -F';' '{print NF}')"
else
  Peers_Hu=""
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
  "$EN0" \
  "$EN1" \
  "$GatewayIP" \
  "$DefaultIf" \
  "$DNSRes_Hu" \
  "$AppleReach_Hu" \
  "$AppleTTFB_hu" \
  "$WiFiSNR_hu" \
  "$WifiNoise_hu" \
  "$WifiCCA_hu"

exit 0

