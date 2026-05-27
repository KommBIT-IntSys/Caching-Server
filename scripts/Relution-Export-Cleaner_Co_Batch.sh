#!/bin/zsh
# Relution-Export-Cleaner_Co_Batch.sh
# Bereinigt Relution-Exporte unter macOS:
# - verarbeitet alle Dateien im Skriptordner, die mit Geraete_Global_20 oder Geräte_Global_20 beginnen
# - ignoriert bereits erzeugte _Co_-Dateien
# - entfernt personenbezogene Spalten durch feste CO-Ausgabespalten
# - extrahiert Standortkuerzel aus organizationName (Inhalt der ersten Klammer)
# - bringt Spalten in definierte Reihenfolge
# - sortiert Zeilen alphabetisch nach Standort
# - uebernimmt den Zeitstempel der Quelldatei in den Ausgabedateinamen
# - toleriert abweichende Spaltennamen und zusaetzliche Spalten
# - normalisiert iOS-/iPadOS-Versionen auf drei zweistellige Segmente:
#     26.5      -> 26.05.00
#     26.05     -> 26.05.00
#     18.7.8    -> 18.07.08
#     18.07.08  -> 18.07.08
# - normalisiert batteryLevel auf ganze Prozent:
#     54.000004 -> 54
#     52.999996 -> 53
# - bricht pro Datei bei fehlenden harten Pflichtspalten ab, verarbeitet aber weitere passende Dateien weiter
# - warnt bei fehlenden optionalen / weichen Pflichtspalten und laeuft weiter
# - prueft die Quellspalte name vor dem Entfernen auf LDG und unerwartete Namensmuster
# - entfernt lastIpAddress vor der Ausgabe, falls vorhanden
# - schreibt die CO-Datei explizit mit Semikolon als Trennzeichen
#
# Nutzung:
#   chmod +x scripts/Relution-Export-Cleaner_Co_Batch.sh
#   ./scripts/Relution-Export-Cleaner_Co_Batch.sh
#
# Erwartung:
#   Die zu bereinigenden Relution-CSV-Dateien liegen im selben Ordner wie dieses Skript.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

PYTHON_BIN=""

if command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN="$(command -v python3)"
elif [[ -x /usr/bin/python3 ]]; then
    PYTHON_BIN="/usr/bin/python3"
else
    echo ""
    echo "FEHLER: python3 wurde nicht gefunden."
    echo "Dieses Skript nutzt Python 3 fuer robuste CSV-Verarbeitung."
    echo "Auf macOS ist python3 normalerweise ueber Command Line Tools verfuegbar."
    echo ""
    exit 1
fi

"$PYTHON_BIN" - "$SCRIPT_DIR" <<'PYCODE'
import csv
import datetime
import glob
import math
import os
import re
import sys
from collections import OrderedDict

script_dir = sys.argv[1]

input_patterns = [
    "Geraete_Global_20*.csv",
    "Geräte_Global_20*.csv",
]

critical_columns = [
    "Standort",
    "model",
    "osVersion",
    "batteryLevel",
]

optional_warn_columns = [
    "lastConnectionDate",
    "applePendingVersion",
    "deviceConnectionState",
    "status",
]

expected_name_markers = [
    "SuS",
    "Sport",
    "Koga",
    "Lehrer",
]

column_map = {
    "Standort": [
        "organizationName",
        "Organisation",
        "Standort",
        "SiteCode",
        "Org",
    ],
    "model": [
        "model",
        "Modell",
        "Device Model",
        "Geraetemodell",
    ],
    "lastConnectionDate": [
        "lastConnectionDate",
        "Letzte Verbindung",
        "Last Connection",
        "Zuletzt verbunden",
    ],
    "osVersion": [
        "osVersion",
        "OS Version",
        "Betriebssystemversion",
        "iOS Version",
        "iPadOS Version",
    ],
    "applePendingVersion": [
        "applePendingVersion",
        "OS Update Status",
        "Ausstehendes Update",
        "Pending Version",
    ],
    "deviceConnectionState": [
        "deviceConnectionState",
        "Connection State",
        "Verbindungsstatus",
    ],
    "status": [
        "status",
        "Status",
        "Compliance",
        "complianceStatus",
        "MDM Status",
    ],
    "batteryLevel": [
        "batteryLevel",
        "Batteriestand",
        "Battery Level",
        "Akku",
    ],
}

output_columns = [
    "Standort",
    "model",
    "lastConnectionDate",
    "osVersion",
    "applePendingVersion",
    "deviceConnectionState",
    "status",
    "batteryLevel",
]


def warn(message):
    print(f"WARNUNG: {message}")


def get_site_code(org_name):
    if org_name is None:
        return ""

    value = str(org_name).strip()

    if not value:
        return ""

    match = re.search(r"\(([^)]+)\)", value)

    if match:
        return match.group(1).strip()

    return value


def normalize_ios_version_text(text):
    if text is None:
        return ""

    value = str(text).strip()

    if not value:
        return ""

    value = value.replace(",", ".")

    def repl(match):
        major = int(match.group(1))
        minor = int(match.group(2))
        patch = int(match.group(3)) if match.group(3) is not None else 0
        return f"{major:02d}.{minor:02d}.{patch:02d}"

    # Greift auch in einfachem Text:
    # "iPadOS < 18.7.8" -> "iPadOS < 18.07.08"
    return re.sub(r"(?<!\d)(\d+)\.(\d+)(?:\.(\d+))?(?!\d)", repl, value)


def normalize_battery_level(value):
    if value is None:
        return ""

    raw = str(value).strip()

    if not raw:
        return ""

    raw = raw.replace(",", ".")

    number = None

    try:
        number = float(raw)
    except ValueError:
        # Schutz gegen bereits durch Excel/Import verhunzte Werte wie 54.000.004.
        # In diesem Spezialfall wird der erste Block als Prozentwert interpretiert.
        # Das ist absichtlich konservativ und greift nur bei rein numerischen Punktgruppen.
        if re.fullmatch(r"\d+(?:\.\d+){2,}", raw):
            first_part = raw.split(".", 1)[0]
            try:
                number = float(first_part)
            except ValueError:
                return ""
        else:
            return ""

    if number is None or math.isnan(number) or math.isinf(number):
        return ""

    rounded = int(math.floor(number + 0.5))

    if rounded < 0 or rounded > 100:
        return ""

    return str(rounded)


def get_relution_timestamp_from_name(filename):
    basename = os.path.basename(filename)

    match = re.search(r"(\d{4}-\d{2}-\d{2}_\d{4})\.csv$", basename)

    if match:
        return match.group(1)

    match = re.search(r"(\d{4}-\d{2}-\d{2})\.csv$", basename)

    if match:
        return match.group(1)

    return datetime.datetime.now().strftime("%Y-%m-%d_%H%M")


def detect_delimiter(path):
    with open(path, "r", encoding="utf-8-sig", newline="") as handle:
        first_line = handle.readline()

    semicolon_count = first_line.count(";")
    comma_count = first_line.count(",")

    if semicolon_count > comma_count:
        return ";"

    return ","


def read_csv_smart(path):
    delimiter = detect_delimiter(path)

    with open(path, "r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle, delimiter=delimiter)
        rows = list(reader)
        fieldnames = reader.fieldnames or []

    return rows, fieldnames, delimiter


def resolve_column_map(fieldnames):
    resolved = {}

    fieldname_lookup = {name.lower(): name for name in fieldnames}

    for target_column, candidates in column_map.items():
        source_column = None

        for candidate in candidates:
            if candidate.lower() in fieldname_lookup:
                source_column = fieldname_lookup[candidate.lower()]
                break

        resolved[target_column] = source_column

    return resolved


def find_field_case_insensitive(fieldnames, name):
    needle = name.lower()

    for field in fieldnames:
        if field.lower() == needle:
            return field

    return None


def convert_relution_export_file(source_path):
    source_name = os.path.basename(source_path)

    print("")
    print(f"Verarbeite: {source_name}")

    timestamp = get_relution_timestamp_from_name(source_name)
    output_file = os.path.join(os.path.dirname(source_path), f"Geraete_Global_Co_{timestamp}.csv")

    try:
        rows, fieldnames, detected_delimiter = read_csv_smart(source_path)
    except Exception as exc:
        print(f"FEHLER: Datei konnte nicht gelesen werden: {source_path}")
        print(str(exc))
        return False

    if not rows:
        print(f"FEHLER: Die Datei enthaelt keine Daten: {source_name}")
        return False

    resolved = resolve_column_map(fieldnames)

    missing_critical = [
        column for column in critical_columns
        if not resolved.get(column)
    ]

    if missing_critical:
        print("FEHLER: Folgende wichtige Pflichtspalten wurden im Relution-Export nicht gefunden:")
        print("  " + ", ".join(missing_critical))
        print("Diese Datei wird uebersprungen, weil die erzeugte Auswertung sonst fachlich unzuverlaessig waere.")
        return False

    missing_optional = [
        column for column in optional_warn_columns
        if not resolved.get(column)
    ]

    if missing_optional:
        print("")
        warn("Folgende optionale Statusspalten wurden nicht gefunden: " + ", ".join(missing_optional))
        print("Die Datei wird trotzdem erzeugt; die fehlenden Felder werden leer ausgegeben.")

    last_ip_column = find_field_case_insensitive(fieldnames, "lastIpAddress")

    if last_ip_column:
        print("")
        warn("Die Eingabedatei enthaelt die Spalte 'lastIpAddress'.")
        print("Diese Spalte ist datenschutzsensibel und wird vor der CO-Ausgabe entfernt.")

    name_column = find_field_case_insensitive(fieldnames, "name")

    if name_column:
        ldg_rows = [
            row for row in rows
            if re.search(r"LDG", str(row.get(name_column, "")), re.IGNORECASE)
        ]

        if ldg_rows:
            print("")
            warn(f"In der Quellspalte 'name' taucht das Kuerzel 'LDG' auf ({len(ldg_rows)} Zeile(n)).")
            print("Lehrerdienstgeraete sind eine eigene, datenschutzsensiblere Auswertungsebene und sollten nicht unbemerkt in SuS-/Fachgeraete-CO-Dateien geraten.")

        unexpected_name_rows = []

        for row in rows:
            device_name = str(row.get(name_column, "") or "")

            if not device_name.strip():
                unexpected_name_rows.append(row)
                continue

            has_expected_marker = any(marker in device_name for marker in expected_name_markers)

            if not has_expected_marker:
                unexpected_name_rows.append(row)

        if unexpected_name_rows:
            print("")
            warn(
                "In der Quellspalte 'name' fehlen bei "
                f"{len(unexpected_name_rows)} Zeile(n) die erwarteten Kuerzel: "
                + ", ".join(expected_name_markers)
                + "."
            )
            print("Die Datei wird trotzdem erzeugt. Bitte pruefen, ob der Relution-Export korrekt gefiltert wurde oder ob neue Namensmuster dokumentiert werden muessen.")

            examples = []

            for row in unexpected_name_rows:
                value = str(row.get(name_column, "") or "").strip()

                if value:
                    examples.append(value)

                if len(examples) >= 5:
                    break

            if examples:
                print("Beispiele:")

                for example in examples:
                    print(f"  - {example}")

    else:
        print("")
        warn("Die Quellspalte 'name' wurde nicht gefunden. LDG- und Namensmuster-Pruefung kann nicht durchgefuehrt werden.")
        print("Die Datei wird trotzdem erzeugt; personenbezogene Namen werden weiterhin nicht in die CO-Ausgabe uebernommen.")

    cleaned = []

    for row in rows:
        output_row = OrderedDict()

        for target_column in output_columns:
            source_column = resolved.get(target_column)

            if source_column:
                value = row.get(source_column, "")

                if target_column == "Standort":
                    value = get_site_code(value)
                elif target_column in ("osVersion", "applePendingVersion"):
                    value = normalize_ios_version_text(value)
                elif target_column == "batteryLevel":
                    value = normalize_battery_level(value)
                else:
                    value = str(value).strip() if value is not None else ""

                output_row[target_column] = value
            else:
                output_row[target_column] = ""

        cleaned.append(output_row)

    cleaned.sort(
        key=lambda item: (
            item.get("Standort", ""),
            item.get("model", ""),
            item.get("osVersion", ""),
        )
    )

    try:
        with open(output_file, "w", encoding="utf-8", newline="") as handle:
            writer = csv.DictWriter(
                handle,
                fieldnames=output_columns,
                delimiter=";",
                quotechar='"',
                quoting=csv.QUOTE_MINIMAL,
                lineterminator="\n",
            )
            writer.writeheader()
            writer.writerows(cleaned)
    except Exception as exc:
        print(f"FEHLER: Ausgabedatei konnte nicht geschrieben werden: {output_file}")
        print(str(exc))
        return False

    print(f"Fertig: {os.path.basename(output_file)}")
    print(f"  Eingabe:  {len(rows)} Geraete")
    print(f"  Ausgabe:  {len(cleaned)} Geraete, alphabetisch nach Standort")
    print("  Format:   Semikolon-CSV, UTF-8")
    print("  Version:  osVersion/applePendingVersion dreistellig normalisiert, batteryLevel gerundet")

    if missing_optional:
        print("  Hinweis:  Fehlende optionale Statusfelder: " + ", ".join(missing_optional))

    if last_ip_column:
        print("  Hinweis:  lastIpAddress wurde nicht in die CO-Ausgabe uebernommen")

    return True


sources = []

for pattern in input_patterns:
    sources.extend(glob.glob(os.path.join(script_dir, pattern)))

sources = [
    path for path in sources
    if "_Co_" not in os.path.basename(path)
    and os.path.isfile(path)
]

sources = sorted(set(sources), key=lambda path: os.path.basename(path))

if not sources:
    print("")
    print("FEHLER: Keine passende Eingabedatei gefunden.")
    print("Erwartet werden Dateien im Skriptordner nach dem Muster:")
    print("  Geraete_Global_20*.csv")
    print("  Geräte_Global_20*.csv")
    print("")
    sys.exit(1)

print("")
print(f"Gefundene Eingabedateien: {len(sources)}")

ok = 0
failed = 0

for source in sources:
    if convert_relution_export_file(source):
        ok += 1
    else:
        failed += 1

print("")
print("Batch abgeschlossen.")
print(f"  Erfolgreich: {ok}")
print(f"  Uebersprungen/Fehler: {failed}")

if failed > 0:
    sys.exit(1)

sys.exit(0)
PYCODE
