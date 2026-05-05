#!/bin/bash
# relution_cleaner_co.sh
# Bereinigt den Relution-Export:
# - entfernt Spalte "name" (Gerätename / Schülername)
# - kürzt organizationName auf Standortkürzel (Inhalt der ersten Klammer)

input=$(ls Geraete_Global_*.csv 2>/dev/null | sort -r | head -1)

if [ -z "$input" ]; then
  echo "Keine passende Datei gefunden (Muster: Geraete_Global_*.csv)"
  exit 1
fi

output="Geraete_Global_Co_$(date +%Y-%m-%d).csv"

echo "Verarbeite: $input"

awk -F',' -v OFS=',' '
NR==1 {
  for (i=1; i<=NF; i++) {
    gsub(/"/, "", $i)
    col[$i] = i
  }
  print "model","osVersion","applePendingVersion","lastConnectionDate",\
        "deviceConnectionState","status","batteryLevel","organizationName"
  next
}
{
  org = $col["organizationName"]
  gsub(/"/, "", org)
  if (match(org, /^\(([^)]+)\)/, m)) org = m[1]
  printf "\"%s\",\"%s\",\"%s\",\"%s\",\"%s\",\"%s\",\"%s\",\"%s\"\n",
    $col["model"], $col["osVersion"], $col["applePendingVersion"],
    $col["lastConnectionDate"], $col["deviceConnectionState"],
    $col["status"], $col["batteryLevel"], org
}
' "$input" > "$output"

count=$(tail -n +2 "$output" | wc -l | tr -d ' ')
echo "Fertig: $output ($count Geräte)"
