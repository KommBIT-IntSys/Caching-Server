# HOW TO COPILOT – iOS-Updatestand auswerten

Kurzanleitung zur standortbasierten Auswertung des iOS-/iPadOS-Updatestands mit Microsoft Copilot.

Ziel: Für jeden Standort einschätzen, ob Update-Rückstände eher technische Ursachen, organisatorische Ursachen oder unklare Ursachen haben.

Die Auswertung ist keine Schuldzuweisung. Sie dient der Priorisierung: Welche Standorte sollten zuerst betrachtet werden, und mit welcher Hypothese?

---

## Was du brauchst

Du brauchst am Ende zwei Auswertungsdateien, erzeugt aus drei Vorbereitungsschritten.

### 1. AssetCache-CO-Dateien zusammenführen

Alle CO-CSV-Dateien der Caching-Server zu einer gemeinsamen Datei zusammenführen.

Ergebnis:

`AssetCache_Co_alle_Standorte.csv`

Skripte:

- Windows: `scripts/Merge_Co_CSV.ps1`
- macOS: `scripts/merge_co_csv.sh`

### 2. AssetCache-CO-Datei auf Stundenwerte verdichten

Empfohlen für die Auswertung mit Microsoft Copilot, besonders mit Copilot Basic.

Ergebnis:

`AssetCache_Co_alle_Standorte_Stunden.csv`

Skript:

- Windows: `scripts/AssetCache_Verdichten_Co.ps1`

Die 15-Minuten-Datei enthält mehr Details, ist aber für Copilot Basic oft zu groß oder zu kleinteilig. Große Dateien können still gekürzt oder falsch aggregiert werden. Die Stunden-Datei ist deshalb der Standard für die erste Auswertung.

Die 15-Minuten-Datei nur verwenden, wenn gezielt Detailfragen zu kurzen Zeitfenstern geprüft werden sollen.

### 3. Relution-Export datenschutzkonform bereinigen

MDM-Export bereinigen: Gerätenamen entfernen, Organisationsname auf Standortkürzel reduzieren.

Ergebnis:

`Geraete_Global_Co_JJJJ-MM-TT.csv`

Skripte:

- Windows: `scripts/Relution-Export-Cleaner_Co.ps1`
- macOS: `scripts/relution_cleaner_co.sh`

---

## So geht’s

1. AssetCache-CO-Dateien zusammenführen.
2. Zusammengeführte AssetCache-CO-Datei auf Stundenwerte verdichten.
3. Relution-Export bereinigen.
4. Microsoft Copilot öffnen.
5. Diese zwei Dateien hochladen:
   - `AssetCache_Co_alle_Standorte_Stunden.csv`
   - `Geraete_Global_Co_JJJJ-MM-TT.csv`
6. Den Prompt aus dem Abschnitt „Prompt für Microsoft Copilot“ vollständig hineinkopieren.
7. Auswertung prüfen.
8. Bei Bedarf Detailfragen mit der 15-Minuten-Datei nachschärfen.

---

# Prompt für Microsoft Copilot

```text
# AUFGABE (Kurzfassung)

Du analysierst zwei CSVs aus dem Asset-Cache-Monitoring von KommunalBIT. Ziel: standortweise einschätzen, ob Update-Rückstände an iPadOS-Geräten eher infrastrukturelle, organisatorische oder unklare Ursachen haben. Explorativ, keine Schuldzuweisungen.

# DOMÄNE

## Kontext

Apple Content Caching speichert iPadOS-Updates und Apple-Inhalte lokal auf einem Mac Mini je Standort zwischen. Das spart Bandbreite und beschleunigt Update-Wellen, vorausgesetzt: Cache-Dienst läuft, Speicher reicht, DNS und Apple-Origin sind erreichbar, iPads sind online und in Nutzung. `Relution` ist das eingesetzte MDM.

## Datenquellen

**1. AssetCache-CSV** — Zeitreihe, eine Zeile pro Caching-Server pro Messintervall. Zwei Varianten:
- `AssetCache_Co_alle_Standorte_Stunden.csv` — Stundenwerte, Standardvariante.
- `AssetCache_Co_alle_Standorte.csv` — 15-Min-Werte, nur für Detailfragen.

**2. Relution-CSV** — Momentaufnahme, eine Zeile pro iPad. `Geraete_Global_Co_JJJJ-MM-TT.csv`. Datum im Dateinamen = Exportdatum.

Das Suffix `_Co_` markiert DSGVO-konform aufbereitete Varianten.

**Matching-Schlüssel** zwischen beiden Dateien: Standortkürzel (`Standort` bzw. `Organisation`/`SiteCode`/`Org`).

**Zeitversatz** zwischen AssetCache-Zeitraum und Relution-Exportdatum ist möglich. Immer explizit benennen, nicht glätten. AssetCache ist Zeitreihe, Relution ist Momentaufnahme.

## Zielversion und Modellkompatibilität

Zielversion = neuester Eintrag in `iOSUpdates`. Format z. B. `26.3|18.7.5` (Pipe-getrennt: aktuelle Major + zuletzt unterstützte Vor-Major). Alle bei KommunalBIT eingesetzten Modelle (iPad A16, iPad 8th–10th Gen, iPad Air 3rd Gen) unterstützen iPadOS 26. Geräte unter Zielversion gelten als nicht aktuell.

Versionsvergleich numerisch nach Komponenten Major.Minor.Patch, nicht lexikalisch — `17.10` ist *größer* als `17.2`, nicht kleiner.

## AssetCache-Spalten

| Spalte | Bedeutung | Auffälligkeit |
|---|---|---|
| `Standort`/`Hostname` | Standortkürzel; Schlüssel für Aggregation und Matching | nicht eindeutig → Schema-Problem |
| `Timestamp` | Messzeitpunkt | Lücken und Zeitraumränder beachten |
| `iOSUpdates` | Letzte zwei iOS-Versionen aus gdmf.apple.com | – |
| `ClientsCnt` | Cache-Clients im Intervall; Format `4/122` (aktiv/Standortbasis) oder `3.3%` (Anteil) | dauerhaft niedrig nicht automatisch problematisch |
| `ServedDelta` | Vom Cache an Clients ausgeliefert (Δ pro Intervall/Stunde) | dauerhaft 0 = Cache liefert nichts aus |
| `OriginDelta` | Vom Cache aus Apple-Origin nachgeladen (Δ) | allein nicht gut/schlecht; siehe Muster unten |
| `CachePr` | Speicherdruck Cache, 0–100 % | 0–30 % unkritisch · 40–60 % gesund · ≥80 % möglicher Eviction-Druck. **`CachePr=0` ≠ Cache-Inaktivität**, nur „kein Speicherdruck gemessen" |
| `DNSRes` | DNS-Auflösung Apple-Hostnames; `1`/`yes` ok, `0`/`no` nicht | 0/no = technischer Hinweis |
| `AppleReach` | HTTPS-Erreichbarkeit Apple-Update-Server; `1`/`yes` vs `0`/`no` | 0/no = technischer Hinweis |
| `AppleTTFB` | Time to First Byte Apple-Origin (ms) | dauerhaft hoch trotz DNSRes/AppleReach ok = Netz-/Routing-Hinweis |
| `WiFiSNR` (dB) | WLAN-SNR am Mac Mini, *nicht* an iPads | dauerhaft niedrig + WLAN-betriebener Server |
| `WifiNoise` (dBm) | WLAN-Störpegel am Mac Mini | nur mit `WiFiSNR`/`WifiCCA` zusammen interpretieren |
| `WifiCCA` (%) | Airtime-Auslastung am Mac Mini | dauerhaft hoch = Funkkanal überlastet |

**Aggregation Pflicht.** Einzelzeilen sind nicht aussagekräftig. Pro Standort: `ServedDelta`/`OriginDelta` als Summe; `ClientsCnt`/`CachePr` als Durchschnitt + Maximum; `DNSRes`/`AppleReach` als Auffälligkeitskennzeichnung über den Zeitraum.

**Cache-Totalausfall-Definition:** `ServedDelta` *und* `OriginDelta` dauerhaft 0 über den gesamten Zeitraum. Ausschließlich aus dieser Kombination, niemals aus `CachePr` allein. Vor Klassifikation prüfen, ob Ferien, Wochenenden oder Logging-Lücken denselben Befund erzeugen.

## Relution-Spalten

| Bedeutung | Spaltennamen (Aliasse möglich) |
|---|---|
| Standort | `Organisation`, `Standort`, `SiteCode`, `Org` |
| OS-Version | `osVersion`, `OS Version`, `Betriebssystemversion`, `iOS Version`, `iPadOS Version` |
| Pending Update | `applePendingVersion`, `OS Update Status`, `Ausstehendes Update` |
| Letzte Verbindung | `lastConnectionDate`, `Letzte Verbindung`, `Last Connection` |
| Akku | `batteryLevel`, `Batteriestand`, `Battery Level` |
| Compliance | `complianceStatus`, `Compliance`, `MDM Status` |
| Modell | `Modell`, `Model`, `Device Model`, `Gerätemodell` |

Spalten per Name nutzen, nicht per Position. Fehlende Spalten benennen, nicht raten.

**Auslegung:**
- `osVersion` < Zielversion → nicht aktuell.
- `applePendingVersion` gefüllt → Gerät erkennt Update, hat es aber nicht installiert. Hinweis auf organisatorische Ursache *nur* zusammen mit `batteryLevel`, `lastConnectionDate`, Cache-Aktivität.
- `lastConnectionDate` nur als Muster über viele Geräte werten, nicht als Einzelwert.
- `batteryLevel`: Einheit prüfen (0–1 vs 0–100). Momentaufnahme — keine Zeitraum-Aussage.
- `complianceStatus = COMPLIANT` ≠ OS-aktuell. Compliance separat ausweisen, nicht in OS-Bewertung mischen.

# AUFGABE & VORGEHEN

Strikte Reihenfolge. Keine Interpretation vor Schritt 3.

**1. Schema-Prüfung.** Erkannte Dateien, vorhandene Spalten (inkl. Aliasse), fehlende Spalten, Codierungen (`DNSRes`/`AppleReach` 0/1 vs yes/no, `batteryLevel` 0–1 vs 0–100), AssetCache-Zeitraum, Relution-Exportdatum, Standort-Matching, relevante Unsicherheiten. Nicht still korrigieren.

**2. Standort-Matching.** Standorte nur in einer Datei: ausweisen, nicht stillschweigend zusammenführen.

**3. Standort-Aggregat-Tabelle.** Vollständig, alle Standorte. Mindestspalten: Standort · Geräte (Relution) · auf Zielversion (Anzahl + Anteil) · unter Zielversion · Pending Update · ältere Major-Version · Akku <20 % · älteste/jüngste letzte Verbindung · Summe ServedDelta · Summe OriginDelta · ClientsCnt Ø/Max · CachePr Ø/Max · DNSRes/AppleReach auffällig · Datenlage (gut/eingeschränkt/unklar).

Tabelle nicht kürzen. Bei mehr als 25 Standorten: zuerst die vollständige Tabelle ausgeben, Schritte 4–6 in einer Folge-Antwort ankündigen.

**4. Priorisierung.** Pro Standort: Priorität (hoch/mittel/niedrig), Einordnung (Infrastruktur/Organisation/unklar), wichtigste Signale, empfohlener nächster Prüfschritt.

**5. Begründung je auffälligem Standort.** Max 2–3 Sätze. Jede Aussage als Befund / Hypothese / Unsicherheit erkennbar.

**6. Zusammenfassung.** Auffälligste Standorte, wahrscheinlichste Muster, technische Sofortprüfungen, organisatorische Folgefragen, offene Datenlücken.

**Abschluss:** Maximal 5 konkrete Folgefragen oder Prüfpunkte.

## Pflichtnennungen

- **Cache-Totalausfall** (Definition s. o.): Klassifikation technisch. Prüfvorschlag: Cache-Dienst, LaunchDaemon, AssetCacheManagerUtil-Status, Netzpfad zu Apple-Origin. Bei sehr wenigen Datenzeilen: als Datenlückenproblem ausweisen, nicht als Klassifikations-Unsicherheit.
- **Akku <20 %** bei mehr als 20 % der Geräte eines Standorts: explizit nennen.
- **Standort-Mismatch**: in nur einer Datei vorkommende Standorte explizit, nicht still ignorieren.

## Disziplin

- **Befund** = direkt aus Daten beobachtbar.
- **Hypothese** = fachliche Deutung aus mehreren Signalen.
- **Unsicherheit** = fehlende, widersprüchliche oder zeitversetzte Daten.

Keine Kennzahl isoliert bewerten. Widersprüche nicht glätten. Keine Scheinsicherheit, keine Schuldzuweisungen.

Stilbeispiele: „Die Daten sprechen für …" · „Naheliegende Hypothese: …" · „Vor Bewertung sollte geprüft werden …" · „Datenlage hier eingeschränkt, weil …"

## Interpretationsmuster

**Eher organisatorisch:** viele Geräte unter Zielversion + viele Pending + viele alte `lastConnectionDate` + viele niedrige `batteryLevel` + geringe Cache-Aktivität + keine DNSRes/AppleReach/CachePr-Probleme.

**Eher infrastrukturell:** Geräte aktiv/regelmäßig verbunden + Updatestand bleibt zurück + DNSRes/AppleReach auffällig ODER ServedDelta+OriginDelta dauerhaft 0 ODER dauerhaft hoher CachePr ODER OriginDelta hoch bei niedrigem ServedDelta ODER auffällige AppleTTFB/WLAN-Werte.

**Unklar:** Datenquellen widersprechen sich, Zeiträume passen nicht zusammen, Spalten fehlen, Zielversion unklar, Standort-Matching unsicher.
---

## Hintergrund

Wer den Prompt anpassen oder weiterentwickeln will, findet die
methodischen Erkenntnisse aus seiner bisherigen Entwicklung in
[docs/Prompt-Entwicklung.md](docs/Prompt-Entwicklung.md).
