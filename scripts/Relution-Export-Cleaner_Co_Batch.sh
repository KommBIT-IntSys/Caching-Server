#!/bin/bash
# Relution-Export-Cleaner_Co_Batch.sh
# Bereinigt Relution-Exporte im Skriptordner:
# - verarbeitet mehrere Dateien nach Geraete_Global_202*.csv und Geräte_Global_202*.csv
# - erzeugt pro Quelldatei eine datensparsame CO-Datei Geraete_Global_Co_<Zeitstempel>.csv
# - entfernt Gerätenamen/personenbezogene Spalten durch feste CO-Ausgabespalten
# - reduziert Organisation/organizationName auf Standortkürzel
# - normalisiert iOS-/iPadOS-Versionen zweistellig für KI-/Copilot-Auswertungen
# - warnt bei LDG und unerwarteten Namensmustern in der entfernten name-Spalte
# - warnt bei lastIpAddress und übernimmt diese datenschutzsensible Spalte nicht
# - schreibt UTF-8-CSV mit Semikolon als Trennzeichen

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

shopt -s nullglob
SOURCES=()
for candidate in "$SCRIPT_DIR"/Geraete_Global_202*.csv "$SCRIPT_DIR"/Geräte_Global_202*.csv; do
    [ -f "$candidate" ] || continue
    base="$(basename "$candidate")"
    case "$base" in
        *_Co_*) continue ;;
    esac
    SOURCES+=("$candidate")
done

/usr/bin/perl - "$SCRIPT_DIR" "${SOURCES[@]}" <<'PERL'
use strict;
use warnings;
use utf8;
use Encode qw(decode);
use File::Basename qw(basename);
use POSIX qw(strftime);
use Unicode::Normalize qw(NFC);

binmode(STDOUT, ':encoding(UTF-8)');
binmode(STDERR, ':encoding(UTF-8)');

my $script_dir = shift @ARGV;
my @source_paths = @ARGV;

my @output_columns = (
    'Standort',
    'model',
    'lastConnectionDate',
    'osVersion',
    'applePendingVersion',
    'deviceConnectionState',
    'status',
    'batteryLevel',
);

my %column_map = (
    Standort              => [ 'organizationName', 'Organisation', 'Standort', 'SiteCode', 'Org' ],
    model                 => [ 'model', 'Modell', 'Device Model', 'Geraetemodell' ],
    lastConnectionDate    => [ 'lastConnectionDate', 'Letzte Verbindung', 'Last Connection', 'Zuletzt verbunden' ],
    osVersion             => [ 'osVersion', 'OS Version', 'Betriebssystemversion', 'iOS Version', 'iPadOS Version' ],
    applePendingVersion   => [ 'applePendingVersion', 'OS Update Status', 'Ausstehendes Update', 'Pending Version' ],
    deviceConnectionState => [ 'deviceConnectionState', 'Connection State', 'Verbindungsstatus' ],
    status                => [ 'status', 'Status', 'Compliance', 'complianceStatus', 'MDM Status' ],
    batteryLevel          => [ 'batteryLevel', 'Batteriestand', 'Battery Level', 'Akku' ],
);

my @critical_columns = ( 'Standort', 'model', 'osVersion', 'batteryLevel' );
my @optional_warn_columns = ( 'lastConnectionDate', 'applePendingVersion', 'deviceConnectionState', 'status' );
my @expected_name_markers = ( 'SuS', 'Sport', 'Koga', 'Lehrer' );

sub warn_msg {
    my ($message) = @_;
    print "WARNUNG: $message\n";
}

sub display_name {
    my ($name) = @_;
    my $decoded = eval { decode('UTF-8', $name, 1) };
    $decoded = $name if $@ || !defined $decoded;
    return NFC($decoded);
}

sub normalize_header {
    my ($header) = @_;
    $header = '' unless defined $header;
    $header =~ s/^\x{FEFF}//;
    $header =~ s/^\s+|\s+$//g;
    return lc $header;
}

sub csv_records {
    my ($text) = @_;
    my @records;
    my @row;
    my $field = '';
    my $in_quotes = 0;
    my $field_started = 0;
    my $len = length($text);

    for (my $i = 0; $i < $len; $i++) {
        my $ch = substr($text, $i, 1);

        if ($in_quotes) {
            if ($ch eq '"') {
                my $next = ($i + 1 < $len) ? substr($text, $i + 1, 1) : '';
                if ($next eq '"') {
                    $field .= '"';
                    $i++;
                } else {
                    $in_quotes = 0;
                }
            } else {
                $field .= $ch;
            }
            next;
        }

        if ($ch eq '"') {
            if (!$field_started || $field eq '') {
                $in_quotes = 1;
                $field_started = 1;
            } else {
                $field .= $ch;
            }
        } elsif ($ch eq ',') {
            push @row, $field;
            $field = '';
            $field_started = 0;
        } elsif ($ch eq "\r" || $ch eq "\n") {
            if ($ch eq "\r" && $i + 1 < $len && substr($text, $i + 1, 1) eq "\n") {
                $i++;
            }
            push @row, $field;
            push @records, [ @row ] unless @row == 1 && $row[0] eq '' && $field_started == 0;
            @row = ();
            $field = '';
            $field_started = 0;
        } else {
            $field .= $ch;
            $field_started = 1 unless $ch =~ /\s/ && $field eq '';
        }
    }

    die "CSV endet innerhalb eines gequoteten Feldes\n" if $in_quotes;

    if (@row || $field ne '' || $field_started) {
        push @row, $field;
        push @records, [ @row ];
    }

    return @records;
}

sub csv_quote {
    my ($value) = @_;
    $value = '' unless defined $value;
    $value =~ s/\r\n/\n/g;
    $value =~ s/\r/\n/g;
    $value =~ s/"/""/g;
    return '"' . $value . '"';
}

sub write_csv {
    my ($path, $rows) = @_;
    open my $out, '>:encoding(UTF-8)', $path or die "Ausgabedatei konnte nicht geschrieben werden: $!\n";
    print {$out} join(';', map { csv_quote($_) } @output_columns), "\n";
    for my $row (@{$rows}) {
        print {$out} join(';', map { csv_quote($row->{$_}) } @output_columns), "\n";
    }
    close $out or die "Ausgabedatei konnte nicht geschlossen werden: $!\n";
}

sub get_site_code {
    my ($value) = @_;
    return '' unless defined $value && $value ne '';
    return $1 if $value =~ /\(([^)]*)\)/;
    return $value;
}

sub normalize_version_text {
    my ($value) = @_;
    return $value unless defined $value && $value ne '';
    $value =~ s{(?<!\d)(\d+)\.(\d+)(?:\.(\d+))?(?!\d)}{
        defined $3
            ? sprintf('%s.%02d.%02d', $1, $2, $3)
            : sprintf('%s.%02d', $1, $2)
    }gex;
    return $value;
}

sub timestamp_from_name {
    my ($file_name) = @_;
    return $1 if $file_name =~ /(\d{4}-\d{2}-\d{2}_\d{4})\.csv\z/;
    return $1 if $file_name =~ /(\d{4}-\d{2}-\d{2})\.csv\z/;
    return strftime('%Y-%m-%d_%H%M', localtime);
}

sub resolve_columns {
    my ($headers) = @_;
    my %available;
    for my $idx (0 .. $#{$headers}) {
        my $normalized = normalize_header($headers->[$idx]);
        $available{$normalized} = $idx unless exists $available{$normalized};
    }

    my %resolved;
    for my $target (keys %column_map) {
        $resolved{$target} = undef;
        for my $candidate (@{ $column_map{$target} }) {
            my $normalized = normalize_header($candidate);
            if (exists $available{$normalized}) {
                $resolved{$target} = $available{$normalized};
                last;
            }
        }
    }

    my $name_idx = exists $available{name} ? $available{name} : undef;
    my $last_ip_idx = exists $available{lastipaddress} ? $available{lastipaddress} : undef;

    return (\%resolved, $name_idx, $last_ip_idx);
}

sub row_value {
    my ($row, $idx) = @_;
    return '' unless defined $idx;
    return defined $row->[$idx] ? $row->[$idx] : '';
}

sub process_file {
    my ($source_path, $source_name) = @_;

    print "\nVerarbeite: $source_name\n";

    my $timestamp = timestamp_from_name($source_name);
    my $output_path = "$script_dir/Geraete_Global_Co_$timestamp.csv";
    my $output_name = basename($output_path);

    my $text;
    eval {
        open my $in, '<:encoding(UTF-8)', $source_path or die "$!\n";
        local $/;
        $text = <$in>;
        close $in;
    };
    if ($@) {
        print "FEHLER: Datei konnte nicht gelesen werden: $source_name\n$@";
        return 0;
    }

    if (!defined $text || $text eq '') {
        print "FEHLER: Die Datei ist leer: $source_name\n";
        return 0;
    }

    my @records;
    eval { @records = csv_records($text); 1 } or do {
        my $err = $@ || 'unbekannter CSV-Fehler';
        print "FEHLER: CSV konnte nicht geparst werden: $source_name\n$err";
        return 0;
    };

    if (!@records) {
        print "FEHLER: Die Datei enthaelt keinen Header: $source_name\n";
        return 0;
    }

    my $headers = shift @records;
    if (!@records) {
        print "FEHLER: Die Datei enthaelt keine Daten: $source_name\n";
        return 0;
    }

    my ($resolved, $name_idx, $last_ip_idx) = resolve_columns($headers);

    my @missing_critical = grep { !defined $resolved->{$_} } @critical_columns;
    if (@missing_critical) {
        print "FEHLER: Folgende wichtige Pflichtspalten wurden im Relution-Export nicht gefunden:\n";
        print "  " . join(', ', @missing_critical) . "\n";
        print "Diese Datei wird uebersprungen, weil die erzeugte Auswertung sonst fachlich unzuverlaessig waere.\n";
        return 0;
    }

    my @missing_optional = grep { !defined $resolved->{$_} } @optional_warn_columns;
    if (@missing_optional) {
        print "\n";
        warn_msg("Folgende optionale Statusspalten wurden nicht gefunden: " . join(', ', @missing_optional));
        print "Die Datei wird trotzdem erzeugt; die fehlenden Felder werden leer ausgegeben.\n";
    }

    if (defined $last_ip_idx) {
        print "\n";
        warn_msg("Die Eingabedatei enthaelt die Spalte 'lastIpAddress'.");
        print "Diese Spalte ist datenschutzsensibel und wird vor der CO-Ausgabe entfernt.\n";
    }

    if (defined $name_idx) {
        my $ldg_count = 0;
        my $unexpected_count = 0;
        my @examples;

        for my $row (@records) {
            my $device_name = row_value($row, $name_idx);
            $ldg_count++ if $device_name =~ /LDG/i;

            my $expected = 0;
            for my $marker (@expected_name_markers) {
                if ($device_name =~ /\Q$marker\E/i) {
                    $expected = 1;
                    last;
                }
            }
            if (!$expected) {
                $unexpected_count++;
                push @examples, $device_name if $device_name =~ /\S/ && @examples < 5;
            }
        }

        if ($ldg_count > 0) {
            print "\n";
            warn_msg("In der Quellspalte 'name' taucht das Kuerzel 'LDG' auf ($ldg_count Zeile(n)).");
            print "Lehrerdienstgeraete sind eine eigene, datenschutzsensiblere Auswertungsebene und sollten nicht unbemerkt in SuS-/Fachgeraete-CO-Dateien geraten.\n";
        }

        if ($unexpected_count > 0) {
            print "\n";
            warn_msg("In der Quellspalte 'name' fehlen bei $unexpected_count Zeile(n) die erwarteten Kuerzel: " . join(', ', @expected_name_markers) . ".");
            print "Die Datei wird trotzdem erzeugt. Bitte pruefen, ob der Relution-Export korrekt gefiltert wurde oder ob neue Namensmuster dokumentiert werden muessen.\n";
            if (@examples) {
                print "Beispiele:\n";
                print "  - $_\n" for @examples;
            }
        }
    } else {
        print "\n";
        warn_msg("Die Quellspalte 'name' wurde nicht gefunden. LDG- und Namensmuster-Pruefung kann nicht durchgefuehrt werden.");
        print "Die Datei wird trotzdem erzeugt; personenbezogene Namen werden weiterhin nicht in die CO-Ausgabe uebernommen.\n";
    }

    my @cleaned;
    for my $row (@records) {
        my %out;
        for my $target (@output_columns) {
            my $value = row_value($row, $resolved->{$target});
            $value = get_site_code($value) if $target eq 'Standort';
            $value = normalize_version_text($value) if $target eq 'osVersion' || $target eq 'applePendingVersion';
            $out{$target} = $value;
        }
        push @cleaned, \%out;
    }

    @cleaned = sort {
        lc($a->{Standort} // '') cmp lc($b->{Standort} // '')
            || ($a->{model} // '') cmp ($b->{model} // '')
    } @cleaned;

    eval { write_csv($output_path, \@cleaned); 1 } or do {
        my $err = $@ || 'unbekannter Schreibfehler';
        print "FEHLER: Ausgabedatei konnte nicht geschrieben werden: $output_name\n$err";
        return 0;
    };

    print "Fertig: $output_name\n";
    print "  Eingabe:  " . scalar(@records) . " Geraete\n";
    print "  Ausgabe:  " . scalar(@cleaned) . " Geraete, alphabetisch nach Standort\n";
    print "  Hinweis:  Fehlende optionale Statusfelder: " . join(', ', @missing_optional) . "\n" if @missing_optional;
    print "  Hinweis:  lastIpAddress wurde nicht in die CO-Ausgabe uebernommen\n" if defined $last_ip_idx;

    return 1;
}

my @sources = sort { $a->{display} cmp $b->{display} } map {
    {
        path    => $_,
        display => display_name(basename($_)),
    }
} @source_paths;

if (!@sources) {
    print "FEHLER: Keine passende Eingabedatei gefunden.\n";
    print "Erwartet werden Dateien im Skriptordner nach dem Muster:\n";
    print "  Geraete_Global_202*.csv\n";
    print "  Geräte_Global_202*.csv\n";
    print "\nBatch abgeschlossen.\n";
    print "  Gefunden: 0\n";
    print "  Erfolgreich: 0\n";
    print "  Uebersprungen/Fehler: 0\n";
    exit 1;
}

print "\nGefundene Eingabedateien: " . scalar(@sources) . "\n";

my $ok = 0;
my $failed = 0;
for my $source (@sources) {
    if (process_file($source->{path}, $source->{display})) {
        $ok++;
    } else {
        $failed++;
    }
}

print "\nBatch abgeschlossen.\n";
print "  Gefunden: " . scalar(@sources) . "\n";
print "  Erfolgreich: $ok\n";
print "  Uebersprungen/Fehler: $failed\n";

exit($ok > 0 ? 0 : 1);
PERL
' "$input" > "$output"

count=$(tail -n +2 "$output" | wc -l | tr -d ' ')
echo "Fertig: $output ($count Geräte)"
