#!/bin/sh
# Im Verzeichnis mit allen CO-CSV-Dateien ausführen:
first=1
for f in *_AssetCache_Co_v*.csv; do
  if [ "$first" -eq 1 ]; then
    cat "$f"
    first=0
  else
    tail -n +2 "$f"
  fi
done > AssetCache_Co_alle_Standorte.csv
