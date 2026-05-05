# Copilot-Prompt: AssetCache-Monitoring – Standortanalyse iOS-Update

## Verwendung

Diesen Prompt zusammen mit zwei Dateien an Microsoft Copilot übergeben:

1. **CO-CSV** – zusammengeführte Cache-Logger-Daten aller Standorte
   (`*_AssetCache_Co_v*.csv`, idealerweise als eine zusammengeführte Datei)
2. **Relution-Export** – Geräteliste ohne Gerätenamen
   (Felder: `model | osVersion | applePendingVersion | status | deviceConnectionState | batteryLevel | organizationName`)

> Das Feld `lastIpAddress` im Relution-Export wird nicht benötigt
> und kann vor der Übergabe entfernt werden.

---

## Hinweis: Join-Schlüssel

Die CO-CSV enthält das Feld `SiteCode` (z. B. `GYF`).  
Im Relution-Export steht das Schulkürzel in Klammern am Anfang von `organizationName`,  
z. B. `(GYF) Gymnasium Friderici...`.

Für den Join: Kürzel aus `organizationName` extrahieren (Inhalt der ersten Klammer)
und mit `SiteCode` abgleichen.

---

## Prompt für Copilot:

```
Ich übergebe dir zwei Dateien:

Datei 1 – CO-CSV (Cache-Logger-Daten):
Felder: SiteCode, Timestamp, PeerCnt, ClientsCnt, iOSUpdates, iOSBytes,
ServedDelta, OriginDelta, CacheUsed, CachePr, DNSRes, AppleReach, AppleTTFB, WiFiSNR

ClientsCnt hat das Format "aktiv/gesamt" (z. B. "14/122").
Extrahiere beide Werte getrennt:
- aktive Clients = Zahl vor dem Schrägstrich
- Geräte gesamt laut Cache = Zahl nach dem Schrägstrich
Der Quotient aktiv/gesamt zeigt die tatsächliche Cache-Nutzung.

Datei 2 – Relution-Export (iPad-Zustand, bereinigt):
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
