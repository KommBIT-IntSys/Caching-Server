# Copilot-Prompt: AssetCache-Monitoring – Standortanalyse iOS-Update

## Verwendung

Diesen Prompt zusammen mit zwei Dateien an Microsoft Copilot übergeben.
Vorbereitung in dieser Reihenfolge:

1. CO-CSV-Dateien zusammenführen (Shell- oder PowerShell-Skript, siehe unten)
   → Ergebnis: `AssetCache_Co_alle_Standorte.csv`

2. Relution-Export aus dem MDM exportieren, bereinigen
   (`Relution-Export-Cleaner_Co.ps1` ausführen, siehe unten)
   → Ergebnis: `Geraete_Global_Co_YYYY-MM-DD.csv`

3. Beide Dateien zusammen mit diesem Prompt an Microsoft Copilot übergeben.

---

## Hinweis: Join-Schlüssel

Die CO-CSV enthält das Feld `SiteCode` (z. B. `GYF`).  
Im Relution-Export steht das Schulkürzel in Klammern am Anfang von `organizationName`,  
z. B. `(GYF) Gymnasium Friderici...`.

Für den Join: Kürzel aus `organizationName` extrahieren (Inhalt der ersten Klammer)
und mit `SiteCode` abgleichen.

---

## Prompt

```
Ich übergebe dir zwei Dateien:

Datei 1 – CO-CSV:
Zusammengeführte Cache-Logger-Daten aller Standorte.
Dateiname: AssetCache_Co_alle_Standorte.csv
Felder: SiteCode, Timestamp, PeerCnt, ClientsCnt, iOSUpdates, iOSBytes,
ServedDelta, OriginDelta, CacheUsed, CachePr, DNSRes, AppleReach, AppleTTFB, WiFiSNR

ClientsCnt hat das Format "aktiv/gesamt" (z. B. "14/122").
Extrahiere beide Werte getrennt für die Analyse.

Datei 2 – Relution-Export (bereinigt):
Dateiname: Geraete_Global_Co_YYYY-MM-DD.csv
Felder: model, osVersion, applePendingVersion, lastConnectionDate,
deviceConnectionState, status, batteryLevel, organizationName

organizationName enthält bereits nur das Schulkürzel (z. B. "EPS").
Verknüpfe direkt mit SiteCode aus der CO-CSV.

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
      - AppleTTFB∅ über 500 ms
      - ServedDelta∅ = 0 über den gesamten Betrachtungszeitraum
        (auch wenn OriginDelta = 0: Cache-Dienst möglicherweise inaktiv)

   B) Organisatorisch auffällig:
      - Über 20 % der Geräte mit Akku unter 20 %
      - Über 30 % der Geräte INACTIVE
      - Über 20 % der Geräte mit gesetztem applePendingVersion,
        obwohl ServedDelta > 0

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

- ServedDelta∅ = 0 UND OriginDelta∅ = 0: Cache-Dienst war
  wahrscheinlich nicht aktiv. Netzanbindung separat prüfen.

- OriginDelta∅ hoch, ServedDelta∅ niedrig: Cache lädt aktiv nach,
  hat aber wenig lokal verteilt. Typisch für frühe Update-Phase
  oder zu wenige aktive Clients.

- CachePr > 70: Cache steht unter Speicherdruck. Kann Effizienz
  beeinträchtigen.

- INACTIVE-Geräte zählen bei ClientsCnt nicht mit – das erklärt
  niedrige Prozentwerte auch bei technisch funktionierendem Cache.

- applePendingVersion gesetzt = Gerät weiß von Update, hat es aber
  noch nicht installiert. Häufig: Akku zu niedrig, Gerät nicht
  über Nacht eingesteckt, oder Gerät war nicht im WLAN.

- ClientsCnt "aktiv/gesamt": Der Quotient zeigt, wie viele Geräte
  den Cache tatsächlich genutzt haben. Dauerhaft niedrige Quotienten
  trotz funktionierendem Cache deuten auf INACTIVE-Geräte oder
  Ladeprobleme.

- Standorte mit zwei Teilkürzeln (z. B. HHS-N / HHS-W) wurden
  vor der Analyse zu einem Kürzel zusammengeführt und sind
  als ein Standort zu behandeln.

- Bitte keine Rückschlüsse auf einzelne Geräte ziehen.
  Die Analyse erfolgt ausschließlich auf Standortebene (aggregiert
  pro Schulkürzel).
```

---

## Shell-Einzeiler: CO-Dateien zusammenführen

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

## PowerShell-Skript: CO-Dateien zusammenführen (Windows 11)

### Variante 1 – Skriptdatei `merge_co_csv.ps1`

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
powershell -ExecutionPolicy Bypass -File merge_co_csv.ps1
```

---

### Variante 2 – PowerShell-Einzeiler

```powershell
$f = Get-ChildItem "*_AssetCache_Co_v*.csv" | Sort-Object Name; Get-Content $f[0].FullName | Set-Content -Encoding UTF8 AssetCache_Co_alle_Standorte.csv; $f | Select-Object -Skip 1 | ForEach-Object { Get-Content $_.FullName | Select-Object -Skip 1 | Add-Content -Encoding UTF8 AssetCache_Co_alle_Standorte.csv }
```

---

Ergebnis: `AssetCache_Co_alle_Standorte.csv` – eine Datei, alle Standorte, ein Header.

> **Hinweis:** Falls PowerShell die Ausführung von `.ps1`-Dateien blockiert,
> entweder den Einzeiler direkt ins PowerShell-Fenster einfügen,
> oder einmalig für den aktuellen Benutzer freigeben:
> `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`

---

## Relution-Export bereinigen: `Relution-Export-Cleaner_Co.ps1`

Vor der Übergabe an Copilot den Relution-Rohdatenexport bereinigen:
Gerätenamen (`name`) werden entfernt (Datenschutz / Datensparsamkeit),
und `organizationName` wird auf das Schulkürzel gekürzt –
den Inhalt der ersten Klammer, z. B. `(GYF) Gymnasium Friderici...` → `GYF`.
So kann Copilot den Join mit dem `SiteCode`-Feld der CO-CSV direkt durchführen,
ohne manuellen Zwischenschritt.

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
powershell -ExecutionPolicy Bypass -File Relution-Export-Cleaner_Co.ps1
```

Ergebnis: `Geraete_Global_Co_YYYY-MM-DD.csv` – ohne Gerätenamen,
`organizationName` reduziert auf Schulkürzel (z. B. "EPS").

> **Hinweis HHS:** Falls ein Standort in Relution als HHS-N und HHS-W
> geführt wird, beide vor der Übergabe manuell auf "HHS" vereinheitlichen,
> damit der Join mit dem SiteCode der CO-CSV funktioniert.

