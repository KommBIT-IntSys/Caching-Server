#!/bin/sh
# merge_co_csv.sh
# Führt alle CO-CSV-Dateien der Caching-Server im aktuellen Verzeichnis
# zu einer gemeinsamen Datei zusammen.
# Header wird einmalig übernommen, Datenzeilen akkumuliert.
#
# Ergebnis: AssetCache_Co_alle_Standorte.csv
# Nutzung: ./merge_co_csv.sh
# Im Verzeichnis mit allen CO-CSV-Dateien ausführen.
first=1
for f in *_AssetCache_Co_v*.csv; do
  if [ "$first" -eq 1 ]; then
    cat "$f"
    first=0
  else
    tail -n +2 "$f"
  fi
done > AssetCache_Co_alle_Standorte.csv
