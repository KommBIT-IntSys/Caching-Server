# Copilot-Prompt: AssetCache-Monitoring – Standortanalyse iOS-Update

## Verwendung

Diesen Prompt zusammen mit zwei Dateien an Microsoft Copilot übergeben:

1. **CO-CSV** – zusammengeführte Cache-Logger-Daten aller Standorte
   (`*_AssetCache_Co_v*.csv`, siehe Skripte unter dem Prompt für Copilot)
   
2. **Relution-Export** – Geräteliste ohne Gerätenamen und ohne Schulnamen (siehe Skripte unter dem Prompt für Copilot)
   (Felder: `model | osVersion | applePendingVersion | status | deviceConnectionState | batteryLevel | organizationName`)
   Geräte mit folgenden Suchbegriffen filtern: SuS Sport Koga Lehrer
   => LDG-iPads werden nicht berücksichtig, da nicht alle immer vor Ort sind.
---

## Prompt für Copilot:

```
Ich übergebe dir folgende Dateien:

AssetCache_Co_alle_Standorte.csv (Cache-Logger-Daten):
Felder: SiteCode, Timestamp, PeerCnt, ClientsCnt, iOSUpdates, iOSBytes,
ServedDelta, OriginDelta, CacheUsed, CachePr, DNSRes, AppleReach, AppleTTFB, WiFiSNR

ClientsCnt hat das Format "aktiv/gesamt" (z. B. "14/122").
Extrahiere beide Werte getrennt:
- aktive Clients = Zahl vor dem Schrägstrich
- Geräte gesamt laut Cache = Zahl nach dem Schrägstrich
Der Quotient aktiv/gesamt zeigt die tatsächliche Cache-Nutzung.

Geraete_Global_Co_JJJJ-MM-TT.csv (iPad-Zustand, bereinigt):
Felder: model, osVersion, applePendingVersion, status, deviceConnectionState,
batteryLevel, organizationName

Das Feld organizationName enthält bereits nur das Schulkürzel (z. B. "EPS").
Verknüpfe direkt mit SiteCode aus der CO-CSV – kein Extrahieren nötig.

Hinweis: Falls HHS-N und HHS-W als separate Einträge vorhanden sind,
beide als "HHS" behandeln und zusammenführen.

---

SCOPE

Ausgewertet werden ausschließlich Standorte, die in BEIDEN Dateien
vorhanden sind (SiteCode in CO-CSV ∩ organizationName in Relution-Export).

Standorte, die nur in einer Datei vorkommen:
- Nur in Relution (kein Mac Mini / keine CO-Daten): aus der Analyse
  ausschließen, nicht bewerten, nicht in der Tabelle führen.
- Nur in CO-CSV (kein Relution-Eintrag): als Datenlücke vermerken.

Vor der Ausgabe bitte prüfen: Wie viele Standorte sind in beiden
Dateien vorhanden? Diese Zahl muss mit der Zeilenanzahl der
Standortübersicht übereinstimmen.

---

KONTEXT

Die CO-CSV enthält 15-Minuten-Messwerte der Apple Content Caching Server
(Mac Minis) an Schulen. Sie zeigt, ob und wie intensiv der lokale Cache
genutzt wurde, wie viel iOS-Software er geliefert hat, und ob die
Netzwerkanbindung zum Apple CDN unauffällig war.

Der Relution-Export zeigt den Zustand der iPads an jedem Standort:
welche iOS-Version installiert ist, ob ein Update aussteht, ob Geräte
verbunden oder inaktiv waren, und wie der Ladezustand war.

Das Ziel der Analyse ist es, für jeden Standort zu unterscheiden:
- Technische Ursachen für Update-Rückstand:
  Cache nicht aktiv, schlechte Netzanbindung (DNSRes=0, AppleReach=0,
  hoher AppleTTFB), kein ServedDelta trotz relevantem Zeitraum
- Organisatorische Ursachen:
  iPads offline (deviceConnectionState = INACTIVE), niedrige Batterie,
  Update steht aus (applePendingVersion nicht leer), obwohl Cache
  technisch aktiv war

---

WICHTIG ZUR AUSGABE

Die Standortübersicht muss alle Standorte im gemeinsamen Scope
vollständig ausgeben – keine Kürzung, kein Abbruch.
Falls die Tabelle in der Ausgabe zu lang wird: in zwei Blöcken
ausgeben (A–M, N–Z), aber niemals abschneiden.
Aussagen über „kein technischer Problemstandort" o. ä. sind nur
zulässig, wenn alle Standorte vollständig ausgewertet wurden.

---

ANALYSE-AUFGABEN

1. STANDORTÜBERSICHT (eine Zeile pro Schule)
   Erstelle eine Tabelle mit folgenden Spalten:
   - Schulkürzel (SiteCode)
   - Geräte gesamt
   - Geräte COMPLIANT (aktuelles iOS)
   - Geräte NONCOMPLIANT
   - Geräte INACTIVE
   - Geräte mit ausstehendem Update (applePendingVersion nicht leer)
   - Anteil Geräte mit Akku < 20 % (zum Zeitpunkt des Exports)
   - Durchschnittlicher ServedDelta im Betrachtungszeitraum (aus CO-CSV)
   - Durchschnittlicher OriginDelta im Betrachtungszeitraum (aus CO-CSV)
   - Durchschnittlicher AppleTTFB in ms (aus CO-CSV)
   - DNSRes und AppleReach: Anteil der Messungen mit Wert 1 (in %)
   - Auffälligkeit (deine Einschätzung: technisch / organisatorisch / unauffällig)

2. AUFFÄLLIGE STANDORTE
   Identifiziere Standorte, bei denen Update-Rückstand wahrscheinlich ist.
   Trenne dabei:

   A) Technisch auffällig:
      - DNSRes oder AppleReach: Anteil der Messungen mit Wert 1 unter 80 %
      - AppleTTFB∅ dauerhaft über 500 ms
      - ServedDelta∅ = 0 UND OriginDelta∅ = 0 über den gesamten Zeitraum:
        Cache-Dienst war mit hoher Wahrscheinlichkeit nicht aktiv.
        Klassifikation: TECHNISCH, unabhängig vom Gerätezustand.
        Handlungsvorschlag: Cache-Dienst auf dem Mac Mini prüfen / neu starten.
      - ServedDelta dauerhaft 0, obwohl iOSUpdates einen relevanten
        Versionsstand zeigt (und OriginDelta > 0)

   B) Organisatorisch auffällig:
      - Über 30 % der Geräte INACTIVE
      - Über 20 % der Geräte mit Akku < 20 %
      - Über 20 % der Geräte mit gesetztem applePendingVersion,
        obwohl Cache technisch aktiv war (ServedDelta∅ > 0)
      - ClientsCnt-Quotient (aktiv/gesamt) dauerhaft unter 50 %
        trotz technisch funktionierendem Cache

   C) Gemischt oder unklar:
      - Kombination beider Muster, oder zu wenig Daten für eindeutige Aussage

3. STANDORT-STECKBRIEFE (nur für auffällige Standorte)
   Pro auffälligem Standort: ein kurzer Absatz mit
   - beobachtetem Muster in den Cache-Daten
   - Situation der iPads laut Relution-Export
   - wahrscheinlichster Ursache (technisch / organisatorisch)
   - konkretem Handlungsvorschlag

4. GESAMTBILD
   Kurze Zusammenfassung (max. 10 Sätze):
   - Wie viele Standorte sind unauffällig?
   - Wo liegt der Schwerpunkt der Probleme (technisch oder organisatorisch)?
   - Gibt es ein Muster, das mehrere Schulen betrifft?
   - Welche zwei oder drei Standorte haben den dringendsten Handlungsbedarf?

---

HINWEISE ZUR INTERPRETATION

- ServedDelta = 0 über viele Messungen bedeutet: Cache hat in diesem
  Zeitraum nichts ausgeliefert. Das kann normal sein (kein Update-Anlass),
  ist aber in Kombination mit NONCOMPLIANT-Geräten ein Warnsignal.

- ServedDelta∅ = 0 UND OriginDelta∅ = 0: Cache-Dienst war nicht aktiv –
  weder lokale Auslieferung noch Nachladen vom Origin.
  Klassifikation: TECHNISCH, unabhängig vom Gerätezustand.

- OriginDelta hoch, ServedDelta niedrig: Cache lädt nach, hat aber
  noch wenig lokal verteilt – möglicherweise frühe Update-Phase.

- CachePr > 70: Cache steht unter Speicherdruck. Kann Effizienz
  beeinträchtigen.

- INACTIVE-Geräte zählen bei ClientsCnt nicht mit – das erklärt
  niedrige Quotienten auch bei technisch funktionierendem Cache.

- applePendingVersion gesetzt = Gerät weiß von Update, hat es aber
  noch nicht installiert. Häufig: Akku zu niedrig, Gerät nicht
  über Nacht eingesteckt, oder Gerät war nicht im WLAN.

- Bitte keine Rückschlüsse auf einzelne Geräte ziehen.
  Die Analyse erfolgt ausschließlich auf Standortebene (aggregiert
  pro Schulkürzel).
```

---

## PowerShell-Skript: CO-Dateien zusammenführen (Windows 11)

### Skriptdatei `Merge_Co_CSV.ps1`

Im Verzeichnis mit allen CO-CSV-Dateien ablegen und ausführen:

```powershell
$output = "AssetCache_Co_alle_Standorte.csv"
$files  = Get-ChildItem -Filter "*_AssetCache_Co_v*.csv" | Sort-Object Name

$first = $true
foreach ($file in $files) {
    if ($first) {
        Get-Content $file.FullName | Set-Content -Encoding UTF8 $output
        $first = $false
    } else {
        Get-Content $file.FullName | Select-Object -Skip 1 | Add-Content -Encoding UTF8 $output
    }
}

Write-Host "Fertig: $output ($($files.Count) Dateien zusammengeführt)"
```

Ausführen:
```
Rechtsklick => Mit PowerShell ausführen
```

Ergebnis: `AssetCache_Co_alle_Standorte.csv` – eine Datei, alle Standorte, ein Header.

## PowerShell-Skript: Relution-Export bereinigen (Windows 11)

### Skriptdatei `Relution-Export-Cleaner_Co.ps1`

Vor der Übergabe an Copilot den Relution-Export datenschutzkonform bereinigen:
- Spalte `name` wird entfernt (enthält Gerätenamen mit Schülernamen)
- `organizationName` wird auf das Schulkürzel gekürzt (Inhalt der ersten Klammer)

Das Ergebnis ist die Datei `Geraete_Global_Co_JJJJ-MM-TT.csv`, die direkt
für die Analyse verwendet werden kann.

```powershell
# Relution-Export-Cleaner_Co.ps1
# Bereinigt den Relution-Export:
# - entfernt Spalte "name" (Gerätename / Schülername)
# - kürzt organizationName auf Schulkürzel (Inhalt der ersten Klammer)

$input_file  = ".\Geraete_Global_*.csv"
$output_file = "Geraete_Global_Co_$(Get-Date -Format 'yyyy-MM-dd').csv"

$source = Get-ChildItem -Filter $input_file | Sort-Object LastWriteTime -Descending | Select-Object -First 1

if (-not $source) {
    Write-Host "Keine passende Datei gefunden (Muster: $input_file)"
    exit 1
}

Write-Host "Verarbeite: $($source.Name)"

$data = Import-Csv -Path $source.FullName -Encoding UTF8

$cleaned = $data | Select-Object `
    @{Name="model";                Expression={$_.model}},
    @{Name="osVersion";            Expression={$_.osVersion}},
    @{Name="applePendingVersion";  Expression={$_.applePendingVersion}},
    @{Name="lastConnectionDate";   Expression={$_.lastConnectionDate}},
    @{Name="deviceConnectionState";Expression={$_.deviceConnectionState}},
    @{Name="status";               Expression={$_.status}},
    @{Name="batteryLevel";         Expression={$_.batteryLevel}},
    @{Name="organizationName";     Expression={
        if ($_.organizationName -match '^\(([^)]+)\)') {
            $matches[1]
        } else {
            $_.organizationName
        }
    }}

$cleaned | Export-Csv -Path $output_file -NoTypeInformation -Encoding UTF8

Write-Host "Fertig: $output_file ($($cleaned.Count) Geräte)"
```

Ausführen:
```
Rechtsklick => Mit PowerShell ausführen
```

Ergebnis: `Geraete_Global_Co_JJJJ-MM-TT.csv` – ohne Gerätenamen,
`organizationName` reduziert auf Schulkürzel (z. B. `EPS`).

> **Hinweis HHS:** Falls der Standort in Relution als `HHS-N` und `HHS-W`
> geführt wird, beide Einträge vor der Übergabe manuell auf `HHS` vereinheitlichen,
> damit der Join mit dem `SiteCode` der CO-CSV funktioniert.

## Shell-Einzeiler: CO-Dateien zusammenführen (macOS)

Vor der Übergabe an Copilot alle CO-CSV-Dateien zu einer einzigen
zusammenführen (Header nur einmal, aus der ersten Datei):

```sh
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
```

Ergebnis: `AssetCache_Co_alle_Standorte.csv` – eine Datei,
alle Standorte, ein Header.

## Shell-Skript: Relution-Export bereinigen (macOS)

Vor der Übergabe an Copilot den Relution-Export datenschutzkonform bereinigen:
- Spalte `name` wird entfernt (enthält Gerätenamen mit Schülernamen)
- `organizationName` wird auf das Schulkürzel gekürzt (Inhalt der ersten Klammer)

Das Ergebnis ist die Datei `Geraete_Global_Co_JJJJ-MM-TT.csv`, die direkt
für die Analyse verwendet werden kann.

```sh
#!/bin/bash
# relution_cleaner_co.sh
# Bereinigt den Relution-Export:
# - entfernt Spalte "name" (Gerätename / Schülername)
# - kürzt organizationName auf Schulkürzel (Inhalt der ersten Klammer)

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
```

Ausführbar machen und starten:
```sh
chmod +x relution_cleaner_co.sh
./relution_cleaner_co.sh
```

Ergebnis: `Geraete_Global_Co_JJJJ-MM-TT.csv` – ohne Gerätenamen,
`organizationName` reduziert auf Schulkürzel (z. B. `EPS`).

> **Hinweis HHS:** Falls der Standort in Relution als `HHS-N` und `HHS-W`
> geführt wird, beide Einträge vor der Übergabe manuell auf `HHS` vereinheitlichen,
> damit der Join mit dem `SiteCode` der CO-CSV funktioniert.
