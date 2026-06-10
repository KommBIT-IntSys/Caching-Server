#!/bin/zsh
# AssetCache Rebuild Views
# Version: 1.9.1-rebuild2
#
# Zweck:
# - stoppt den LaunchDaemon vor dem Umbau (sicheres Backup der sichtbaren Dateien)
# - rekonstruiert HU-/CO-Dateien aus dem dauerhaften RAW-Journal
# - erzeugt fehlende Archiv-Abschnitte unter:
#   /Library/Application Support/KommunalBIT/AssetCacheLogger/archive/
# - erzeugt die aktuellen sichtbaren HU-/CO-Dateien unter:
#   /Library/Logs/KommunalBIT/
# - lässt das RAW-Journal unangetastet
# - startet den LaunchDaemon absichtlich NICHT neu
#
# Relution-Härtung:
# - keine hart codierten Dateiendungen mit Punkt in ausführungsrelevanten Variablen
# - DOT wird zur Laufzeit erzeugt
# - Status wird dauerhaft lokal geschrieben, nicht nur nach stdout
#
# Annahme:
# - RAW-Journal entspricht schema1 / v1.9.1 mit den bekannten 23 RAW-Spalten
# - Periodengrenzen werden anhand von iOSUpdates-Wechseln im RAW-Journal erkannt
# - abgeschlossene Perioden werden als Archiv-HU/CO erzeugt
# - letzte Periode wird als aktuelle sichtbare HU/CO erzeugt

emulate -L zsh
setopt NO_NOMATCH

DOT="$(printf '\x2e')"
CSV_EXT="${DOT}csv"
SH_EXT="${DOT}sh"
PLIST_EXT="${DOT}plist"

SCRIPT_VER="1${DOT}9${DOT}1-rebuild2"
LOGGER_VER="1${DOT}9${DOT}1"
RAW_SCHEMA_VER="schema1"

VISIBLE_DIR="/Library/Logs/KommunalBIT"
APP_SUPPORT_BASE="/Library/Application Support/KommunalBIT/AssetCacheLogger"
JOURNAL_DIR="${APP_SUPPORT_BASE}/journal"
ARCHIVE_DIR="${APP_SUPPORT_BASE}/archive"
BIN_DIR="${APP_SUPPORT_BASE}/bin"
STATUS_DIR="${APP_SUPPORT_BASE}/status"
RUNLOG="${STATUS_DIR}/assetcache_rebuild_views_status${DOT}log"

DAEMON_LABEL="de${DOT}kommunalbit${DOT}assetcachelogger"
PLIST_PATH="/Library/LaunchDaemons/${DAEMON_LABEL}${PLIST_EXT}"

TS_RUN="$(date +%Y%m%d_%H%M%S)"

HOST="$(/usr/sbin/scutil --get HostName 2>/dev/null \
  || /usr/sbin/scutil --get LocalHostName 2>/dev/null \
  || /bin/hostname -s 2>/dev/null \
  || echo "")"
[[ -z "${HOST:-}" ]] && HOST="unknown"

if [[ "$HOST" == *-Mac-Mini* ]]; then
  PREFIX="${HOST%%-Mac-Mini*}"
else
  PREFIX="${HOST%%-*}"
fi
[[ -z "${PREFIX:-}" ]] && PREFIX="unknown"

RAW_JOURNAL="${JOURNAL_DIR}/${PREFIX}_AssetCacheRaw_${RAW_SCHEMA_VER}${CSV_EXT}"
OUT_HU="${VISIBLE_DIR}/${PREFIX}_AssetCache_Hu_v${LOGGER_VER}${CSV_EXT}"
OUT_CO="${VISIBLE_DIR}/${PREFIX}_AssetCache_Co_v${LOGGER_VER}${CSV_EXT}"

SELF_INSTALL_PATH="${BIN_DIR}/assetcache_rebuild_views${SH_EXT}"

log_msg() {
  local msg="$*"
  local ts
  ts="$(date '+%Y-%m-%d %H:%M:%S')"
  printf "%s %s\n" "$ts" "$msg" | tee -a "$RUNLOG" 2>/dev/null || true
}

die() {
  log_msg "ERROR $*"
  exit 1
}

if [[ "$(/usr/bin/id -u)" -ne 0 ]]; then
  echo "ERROR: Dieses Skript muss als root laufen."
  exit 77
fi

mkdir -p "$APP_SUPPORT_BASE" "$JOURNAL_DIR" "$ARCHIVE_DIR" "$BIN_DIR" "$STATUS_DIR" "$VISIBLE_DIR" 2>/dev/null || true
chmod 700 "$APP_SUPPORT_BASE" "$JOURNAL_DIR" "$ARCHIVE_DIR" "$BIN_DIR" "$STATUS_DIR" 2>/dev/null || true
chmod 755 "$VISIBLE_DIR" 2>/dev/null || true

: > "$RUNLOG" 2>/dev/null || true
chmod 600 "$RUNLOG" 2>/dev/null || true

log_msg "===== AssetCache Rebuild Views ${SCRIPT_VER} gestartet ====="
log_msg "HOST=${HOST}"
log_msg "PREFIX=${PREFIX}"
log_msg "RAW_JOURNAL=${RAW_JOURNAL}"
log_msg "OUT_HU=${OUT_HU}"
log_msg "OUT_CO=${OUT_CO}"
log_msg "ARCHIVE_DIR=${ARCHIVE_DIR}"

# Sich selbst lokal ablegen, damit das Werkzeug nach Relution-Ausführung greifbar bleibt.
if [[ -n "${0:-}" && -f "$0" ]]; then
  cp "$0" "$SELF_INSTALL_PATH" 2>/dev/null && chmod 700 "$SELF_INSTALL_PATH" 2>/dev/null || true
  log_msg "SELF_INSTALL=${SELF_INSTALL_PATH}"
else
  log_msg "WARN Selbstinstallation übersprungen: Skriptpfad nicht als Datei verfügbar"
fi

# --- LaunchDaemon stoppen ----------------------------------------------------
# Verhindert, dass der Logger während des Backups der sichtbaren Dateien schreibt.
# Der Daemon wird am Ende absichtlich nicht neu gestartet.

log_msg "===== LaunchDaemon stoppen ====="
if launchctl print "system/${DAEMON_LABEL}" >/dev/null 2>&1; then
  launchctl bootout system "${PLIST_PATH}" 2>&1 | while IFS= read -r line; do
    log_msg "  launchctl: ${line}"
  done || true
  sleep 2
  if launchctl print "system/${DAEMON_LABEL}" >/dev/null 2>&1; then
    log_msg "WARN LaunchDaemon meldet sich noch – trotzdem weiter."
  else
    log_msg "LaunchDaemon gestoppt."
  fi
else
  log_msg "LaunchDaemon war nicht geladen – kein Stopp nötig."
fi

# --- RAW-Journal prüfen ------------------------------------------------------

[[ -f "$RAW_JOURNAL" ]] || die "RAW-Journal nicht gefunden: ${RAW_JOURNAL}"
[[ -s "$RAW_JOURNAL" ]] || die "RAW-Journal ist leer: ${RAW_JOURNAL}"

TMP_WORK="$(/usr/bin/mktemp -d /var/tmp/assetcache_rebuild_XXXXXX 2>/dev/null || echo "")"
[[ -n "${TMP_WORK:-}" && -d "$TMP_WORK" ]] || die "Temporäres Arbeitsverzeichnis konnte nicht erstellt werden"

cleanup() {
  rm -rf "$TMP_WORK" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

PERL_OUT="${TMP_WORK}/perl_result.txt"

IOS_BLOCK_LEN=19
TOTALSSINCE_BLOCK_LEN=19

# Perl-STDERR wird direkt ins RUNLOG geleitet, damit Fehlermeldungen (inkl. die-Meldungen)
# im Statuslog sichtbar sind und nicht nur auf stderr verschwinden.
/usr/bin/perl - "$RAW_JOURNAL" "$TMP_WORK" "$PREFIX" "$HOST" "$LOGGER_VER" "$ARCHIVE_DIR" "$VISIBLE_DIR" "$TS_RUN" "$IOS_BLOCK_LEN" "$TOTALSSINCE_BLOCK_LEN" > "$PERL_OUT" 2>> "$RUNLOG" <<'PERL_REBUILDER'
use strict;
use warnings;
use File::Path qw(make_path);
use File::Copy qw(move copy);
use File::Find qw(find);
use POSIX qw(strftime);

my ($journal, $work, $prefix, $host, $logger_ver, $archive_dir, $visible_dir, $ts_run, $ios_block_len, $tot_block_len) = @ARGV;

$ios_block_len = 19 if !defined($ios_block_len) || $ios_block_len !~ /^\d+$/;
$tot_block_len = 19 if !defined($tot_block_len) || $tot_block_len !~ /^\d+$/;

my @raw_header = qw(
  Hostname Timestamp TotalsSince Peers ClientsCnt iOSUpdates iOSBytes TotReturned
  TotOrigin ServedDelta OriginDelta CacheUsed CachePr EN0 EN1 GatewayIP DefaultIf
  DNSRes AppleReach AppleTTFB WiFiSNR WifiNoise WifiCCA
);

my @hu_header = @raw_header;

my @co_header = qw(
  SiteCode Timestamp PeerCnt ClientsCnt iOSUpdates iOSBytes ServedDelta OriginDelta
  CacheUsed CachePr DNSRes AppleReach AppleTTFB WiFiSNR
);

sub csv_escape {
  my ($s) = @_;
  $s = "" if !defined $s;
  $s =~ s/"/""/g;
  return '"' . $s . '"';
}

sub csv_line {
  return join(',', map { csv_escape($_) } @_) . "\n";
}

sub parse_csv_line {
  my ($line) = @_;
  chomp $line;
  $line =~ s/\r$//;
  my @out;

  while (length($line) > 0) {
    if ($line =~ s/^"((?:[^"]|"")*)"(?:,|$)//) {
      my $v = $1;
      $v =~ s/""/"/g;
      push @out, $v;
      next;
    }
    if ($line =~ s/^([^,]*)(?:,|$)//) {
      push @out, $1;
      next;
    }
    last;
  }

  push @out, "" while @out < 23;
  @out = @out[0..22] if @out > 23;
  return @out;
}

sub iso_to_hu_ts {
  my ($s) = @_;
  return "" if !defined($s) || $s eq "";
  $s =~ s/T/ /;
  $s =~ s/[+-]\d{2}:?\d{2}$//;
  return $s;
}

sub compact_ts {
  my ($s) = @_;
  return "unknown" if !defined($s) || $s eq "";
  my $x = $s;
  $x =~ s/[^0-9]//g;
  $x = substr($x, 0, 14) if length($x) > 14;
  return $x || "unknown";
}

sub bytes_human {
  my ($b) = @_;
  return "" if !defined($b) || $b eq "";
  return $b if $b !~ /^\d+$/;
  return "0" if $b == 0;

  my $v = $b + 0;
  my $u = "B";

  if ($v >= 1000000000000) {
    $v = $v / 1000000000000;
    $u = "TB";
  } elsif ($v >= 1000000000) {
    $v = $v / 1000000000;
    $u = "GB";
  } elsif ($v >= 1000000) {
    $v = $v / 1000000;
    $u = "MB";
  } elsif ($v >= 1000) {
    $v = $v / 1000;
    $u = "KB";
  }

  return sprintf("%.2f%s", $v, $u);
}

sub peer_count {
  my ($p) = @_;
  return "" if !defined($p) || $p eq "";
  my @x = grep { $_ ne "" } split(/;/, $p);
  return scalar(@x);
}

sub format_clientscnt_hu {
  my ($s) = @_;
  return "" if !defined($s) || $s eq "";

  if ($s =~ /^(\d+)\/(\d+)$/) {
    my ($a, $t) = ($1, $2);
    return $a if $t == 0;
    return sprintf("%.1f%%", ($a / $t) * 100.0);
  }

  return $s;
}

sub iface_state {
  my ($s) = @_;
  return "" if !defined($s) || $s eq "";
  return $s if $s eq "down" || $s eq "noip";
  return "up";
}

sub gateway_state {
  my ($s) = @_;
  return (defined($s) && $s ne "") ? "yes" : "no";
}

sub normalize_ios_version_2digit {
  my ($v) = @_;
  return "" if !defined($v) || $v eq "";
  return $v if $v !~ /^\d+(\.\d+){1,2}$/;

  my @p = split(/\./, $v);
  @p = map { /^\d$/ ? "0$_" : $_ } @p;
  return join(".", @p);
}

sub normalize_iosupdates_list_2digit {
  my ($s) = @_;
  return "" if !defined($s) || $s eq "";
  my @p = split(/\|/, $s);
  @p = map { normalize_ios_version_2digit($_) } @p;
  return join("|", @p);
}

sub hu_row_from_raw {
  my ($r, $state) = @_;

  my ($h,$ts,$totals_since,$peers,$clientscnt,$iosupdates,$iosbytes,$totret,$totorg,
      $serveddelta,$origindelta,$cacheused,$cachepr,$en0,$en1,$gatewayip,$defaultif,
      $dnsres,$applereach,$applettfb,$wifisnr,$wifinoise,$wificca) = @$r;

  my $hu_ts = iso_to_hu_ts($ts);
  $hu_ts = $ts if $hu_ts eq "";

  my $tot_hu_cur = iso_to_hu_ts($totals_since);
  my $hu_totals_since = "";

  if ($tot_hu_cur eq "") {
    $hu_totals_since = "";
  } elsif (!defined($state->{last_tot_hu}) || $state->{last_tot_hu} eq "" || $tot_hu_cur ne $state->{last_tot_hu}) {
    $state->{last_tot_hu} = $tot_hu_cur;
    $state->{tot_count} = $tot_block_len;
    $hu_totals_since = $tot_hu_cur;
  } elsif (($state->{tot_count} || 0) > 0) {
    $state->{tot_count}--;
    $hu_totals_since = $tot_hu_cur;
  }

  my $hu_ios = "";
  if (!defined($iosupdates) || $iosupdates eq "") {
    $hu_ios = "n/a";
  } elsif (!defined($state->{last_ios}) || $state->{last_ios} eq "" || $iosupdates ne $state->{last_ios}) {
    $state->{last_ios} = $iosupdates;
    $state->{ios_count} = $ios_block_len;
    $hu_ios = $iosupdates;
  } elsif (($state->{ios_count} || 0) > 0) {
    $state->{ios_count}--;
    $hu_ios = $iosupdates;
  }

  # CachePr: HU-Format ist Prozentzahl mit einer Nachkommastelle und %-Zeichen.
  # RAW enthält einen Float (z. B. "45.234"). Fehlender Wert → "n/a".
  my $hu_cachepr = (defined($cachepr) && $cachepr =~ /^[\d.]+$/)
      ? sprintf("%.1f%%", $cachepr + 0)
      : "n/a";

  my $hu_dns   = (defined($dnsres)      && $dnsres      eq "1") ? "yes" : "no";
  my $hu_reach = (defined($applereach)  && $applereach  eq "1") ? "yes" : "no";
  my $hu_ttfb  = (defined($applereach)  && $applereach  eq "1"
               && defined($applettfb)   && $applettfb   ne "")
               ? $applettfb . "ms" : "n/a";
  my $hu_snr   = (defined($wifisnr)   && $wifisnr   ne "") ? $wifisnr   . "dB"  : "n/a";
  my $hu_noise = (defined($wifinoise) && $wifinoise ne "") ? $wifinoise . "dBm" : "n/a";
  my $hu_cca   = (defined($wificca)   && $wificca   ne "") ? $wificca   . "%"   : "n/a";

  return [
    $h,
    $hu_ts,
    $hu_totals_since,
    peer_count($peers),
    format_clientscnt_hu($clientscnt),
    $hu_ios,
    bytes_human($iosbytes)    || "n/a",
    bytes_human($totret)      || "n/a",
    bytes_human($totorg)      || "n/a",
    bytes_human($serveddelta) || "n/a",
    bytes_human($origindelta) || "n/a",
    bytes_human($cacheused)   || "n/a",
    $hu_cachepr,
    iface_state($en0),
    iface_state($en1),
    gateway_state($gatewayip),
    $defaultif,
    $hu_dns,
    $hu_reach,
    $hu_ttfb,
    $hu_snr,
    $hu_noise,
    $hu_cca
  ];
}

sub co_row_from_raw {
  my ($r) = @_;

  my ($h,$ts,$totals_since,$peers,$clientscnt,$iosupdates,$iosbytes,$totret,$totorg,
      $serveddelta,$origindelta,$cacheused,$cachepr,$en0,$en1,$gatewayip,$defaultif,
      $dnsres,$applereach,$applettfb,$wifisnr,$wifinoise,$wificca) = @$r;

  return [
    $prefix,
    $ts,
    peer_count($peers),
    $clientscnt,
    normalize_iosupdates_list_2digit($iosupdates),
    $iosbytes,
    $serveddelta,
    $origindelta,
    $cacheused,
    $cachepr,
    $dnsres,
    $applereach,
    $applettfb,
    $wifisnr
  ];
}

# Prüft anhand der Manifest-Dateien im Archiv, ob eine Periode bereits rekonstruiert wurde.
# Beide Ausgabedateien (HU und CO) werden immer zusammen erzeugt; ein Manifest genügt als Nachweis.
# File::Find ersetzt das fragile glob("**/*"), das in Perls eingebautem glob() nicht portabel rekursiv ist.
sub archive_period_exists {
  my ($start_ts, $end_ts) = @_;

  my $found = 0;

  eval {
    find(sub {
      return unless -f $_ && $_ eq 'manifest.txt';

      open my $fh, "<", $File::Find::name or return;
      my %m;
      while (my $line = <$fh>) {
        chomp $line;
        $m{$1} = $2 if $line =~ /^(\w+):\s+(.+)$/;
      }
      close $fh;

      if (($m{FirstTimestamp} // "") eq $start_ts && ($m{LastTimestamp} // "") eq $end_ts) {
        $found = 1;
        die "found\n";  # vorzeitiger Abbruch des find-Laufs
      }
    }, $archive_dir);
  };

  # "found\n" ist das Abbruch-Signal; alle anderen Fehler weiterwerfen.
  die $@ if $@ && $@ ne "found\n";

  return $found;
}

sub write_view_files {
  my ($rows_ref, $hu_file, $co_file, $manifest_file, $period_name) = @_;

  my %state = (
    last_ios    => "",
    ios_count   => 0,
    last_tot_hu => "",
    tot_count   => 0
  );

  open my $hu, ">", $hu_file or die "cannot write HU $hu_file: $!";
  open my $co, ">", $co_file or die "cannot write CO $co_file: $!";

  print {$hu} csv_line(@hu_header);
  print {$co} csv_line(@co_header);

  my $count = 0;
  for my $r (@$rows_ref) {
    print {$hu} csv_line(@{ hu_row_from_raw($r, \%state) });
    print {$co} csv_line(@{ co_row_from_raw($r) });
    $count++;
  }

  close $hu;
  close $co;

  chmod 0644, $hu_file;
  chmod 0644, $co_file;

  if (defined($manifest_file) && $manifest_file ne "") {
    open my $mf, ">", $manifest_file or warn "cannot write manifest $manifest_file: $!";
    if ($mf) {
      print {$mf} "AssetCache Rebuild Manifest\n";
      print {$mf} "Period: $period_name\n";
      print {$mf} "Prefix: $prefix\n";
      print {$mf} "Host: $host\n";
      print {$mf} "Rows: $count\n";
      print {$mf} "SourceJournal: $journal\n";
      print {$mf} "GeneratedAt: " . strftime("%Y-%m-%d %H:%M:%S", localtime) . "\n";
      if (@$rows_ref) {
        print {$mf} "FirstTimestamp: " . ($rows_ref->[0]->[1]  // "") . "\n";
        print {$mf} "LastTimestamp: "  . ($rows_ref->[-1]->[1] // "") . "\n";
        print {$mf} "iOSUpdates: "     . ($rows_ref->[0]->[5]  // "") . "\n";
      }
      close $mf;
      chmod 0640, $manifest_file;
    }
  }

  return $count;
}

open my $in, "<", $journal or die "cannot open journal $journal: $!";
my $header_line = <$in>;
die "journal has no header" if !defined $header_line;

my @rows;
while (my $line = <$in>) {
  next if $line =~ /^\s*$/;
  my @f = parse_csv_line($line);
  next if !defined($f[1]) || $f[1] eq "" || $f[1] !~ /^\d{4}-\d{2}-\d{2}T/;
  push @rows, \@f;
}
close $in;

die "no data rows in journal" if !@rows;

@rows = sort { ($a->[1] // "") cmp ($b->[1] // "") } @rows;

# Perioden anhand von iOSUpdates-Wechseln.
my @periods;
my @cur;
my $cur_ios = undef;

for my $r (@rows) {
  my $ios = $r->[5] // "";

  if (!@cur) {
    @cur = ($r);
    $cur_ios = $ios;
    next;
  }

  if ($ios ne "" && defined($cur_ios) && $cur_ios ne "" && $ios ne $cur_ios) {
    push @periods, [ @cur ];
    @cur = ($r);
    $cur_ios = $ios;
    next;
  }

  if (($cur_ios // "") eq "" && $ios ne "") {
    $cur_ios = $ios;
  }

  push @cur, $r;
}

push @periods, [ @cur ] if @cur;

die "no periods derived" if !@periods;

my $archive_created = 0;
my $archive_skipped = 0;
my $visible_rows    = 0;

# Abgeschlossene Perioden ins Archiv, falls dort nicht bereits vorhanden.
# Prüfung läuft jetzt über Manifest-Dateien statt über das Einlesen ganzer CSVs.
for (my $i = 0; $i < @periods - 1; $i++) {
  my $p = $periods[$i];
  next if !@$p;

  my $start_ts = $p->[0]->[1]  // "";
  my $end_ts   = $p->[-1]->[1] // "";
  my $ios      = $p->[0]->[5]  // "unknown";

  if (archive_period_exists($start_ts, $end_ts)) {
    $archive_skipped++;
    print "SKIP_ARCHIVE period=$i start=$start_ts end=$end_ts reason=already_exists\n";
    next;
  }

  my $dir_name = "rebuild_${prefix}_" . compact_ts($start_ts) . "_" . compact_ts($end_ts);
  my $dir      = "$archive_dir/$dir_name";
  make_path($dir, { mode => 0700 });

  my $hu_file  = "$dir/${prefix}_AssetCache_Hu_v${logger_ver}.csv";
  my $co_file  = "$dir/${prefix}_AssetCache_Co_v${logger_ver}.csv";
  my $manifest = "$dir/manifest.txt";

  my $count = write_view_files($p, $hu_file, $co_file, $manifest, "archive-period-$i");
  chmod 0700, $dir;

  $archive_created++;
  print "CREATE_ARCHIVE period=$i rows=$count start=$start_ts end=$end_ts ios=$ios dir=$dir\n";
}

# Aktuelle Periode sichtbar schreiben.
my $current = $periods[-1];

die "current period empty" if !@$current;

my $tmp_hu       = "$work/current_hu.csv";
my $tmp_co       = "$work/current_co.csv";
my $tmp_manifest = "$work/current_manifest.txt";

$visible_rows = write_view_files($current, $tmp_hu, $tmp_co, $tmp_manifest, "current-visible");

my $out_hu = "$visible_dir/${prefix}_AssetCache_Hu_v${logger_ver}.csv";
my $out_co = "$visible_dir/${prefix}_AssetCache_Co_v${logger_ver}.csv";

# Bestehende sichtbare Dateien vorher sichern.
my $backup_dir  = "$archive_dir/rebuild_backup_${prefix}_${ts_run}";
my $backup_made = 0;

if ((-f $out_hu && -s $out_hu) || (-f $out_co && -s $out_co)) {
  make_path($backup_dir, { mode => 0700 });

  if (-f $out_hu && -s $out_hu) {
    copy($out_hu, "$backup_dir/${prefix}_AssetCache_Hu_v${logger_ver}.before_rebuild.csv");
    $backup_made = 1;
  }

  if (-f $out_co && -s $out_co) {
    copy($out_co, "$backup_dir/${prefix}_AssetCache_Co_v${logger_ver}.before_rebuild.csv");
    $backup_made = 1;
  }

  if ($backup_made) {
    open my $bm, ">", "$backup_dir/manifest.txt" or warn "cannot write backup manifest: $!";
    if ($bm) {
      print {$bm} "Backup before rebuild\n";
      print {$bm} "Prefix: $prefix\n";
      print {$bm} "Host: $host\n";
      print {$bm} "GeneratedAt: " . strftime("%Y-%m-%d %H:%M:%S", localtime) . "\n";
      close $bm;
      chmod 0700, $backup_dir;
    }
  }
}

move($tmp_hu, $out_hu) or die "cannot move HU to $out_hu: $!";
move($tmp_co, $out_co) or die "cannot move CO to $out_co: $!";

chmod 0644, $out_hu;
chmod 0644, $out_co;

print "VISIBLE rows=$visible_rows start=" . ($current->[0]->[1] // "") . " end=" . ($current->[-1]->[1] // "") . " hu=$out_hu co=$out_co\n";
print "SUMMARY periods=" . scalar(@periods) . " archive_created=$archive_created archive_skipped=$archive_skipped visible_rows=$visible_rows backup_made=$backup_made\n";

PERL_REBUILDER

PERL_RC=$?
if [[ "$PERL_RC" -ne 0 ]]; then
  log_msg "ERROR Perl-Rebuilder fehlgeschlagen rc=${PERL_RC}"
  exit "$PERL_RC"
fi

if [[ -f "$PERL_OUT" ]]; then
  while IFS= read -r line; do
    log_msg "$line"
  done < "$PERL_OUT"
fi

chown -R root:wheel "$APP_SUPPORT_BASE" 2>/dev/null || true
chmod 700 "$APP_SUPPORT_BASE" "$JOURNAL_DIR" "$ARCHIVE_DIR" "$BIN_DIR" "$STATUS_DIR" 2>/dev/null || true
chmod 755 "$VISIBLE_DIR" 2>/dev/null || true
chmod 644 "$OUT_HU" "$OUT_CO" 2>/dev/null || true

log_msg "===== Ergebnis sichtbare Dateien ====="
ls -lah "$OUT_HU" "$OUT_CO" 2>&1 | while IFS= read -r line; do
  log_msg "$line"
done

log_msg "===== Ergebnis Archiv-Auszug ====="
find "$ARCHIVE_DIR" -maxdepth 2 -type f \( -name "*_AssetCache_Hu_v*${CSV_EXT}" -o -name "*_AssetCache_Co_v*${CSV_EXT}" -o -name "manifest${DOT}txt" \) -print 2>/dev/null \
  | tail -n 40 \
  | while IFS= read -r line; do
      log_msg "$line"
    done

log_msg "===== AssetCache Rebuild Views Ende ====="
log_msg "HINWEIS: LaunchDaemon wurde gestoppt und absichtlich nicht neu gestartet."
log_msg "         Manueller Neustart: launchctl kickstart -k system/${DAEMON_LABEL}"
log_msg "         Oder: deploy_assetcache_logger.sh erneut ausführen."
exit 0
