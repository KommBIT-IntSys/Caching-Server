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
# Datenmodell: Asset Cache & Relution Export

Du analysierst zwei CSV-Dateien gemeinsam:

1. AssetCache-CO-Datei:
   - bevorzugt: AssetCache_Co_alle_Standorte_Stunden.csv
   - alternativ: AssetCache_Co_alle_Standorte.csv

2. Relution-CO-Datei:
   - Geraete_Global_Co_JJJJ-MM-TT.csv
   - oder ähnlich benannt

Ziel:
Standortweise bewerten, welche Auffälligkeiten beim -/iPadOS-Updatestand bestehen und ob diese eher auf infrastrukturelle Ursachen, organisatorische Ursachen oder unklare Faktoren hindeuten.

Wichtig:
Die Auswertung ist explorativ. Keine Schuldzuweisungen. Keine Scheinsicherheit. Unsicherheiten ausdrücklich benennen.

Arbeite streng in dieser Reihenfolge:

1. Schema prüfen.
2. Standort-Matching prüfen.
3. Rechnerische Standort-Aggregate erstellen.
4. Erst danach interpretieren.
5. Ergebnis priorisieren.

Keine Interpretation vor der rechnerischen Standort-Aggregat-Tabelle.

---

## Hintergrund: Apple Content Caching

Apple Content Caching speichert -/iPadOS-Updates und andere Apple-Inhalte lokal auf einem Mac Mini im Standortnetzwerk zwischen. Anfragen der iPads werden dadurch vom lokalen Cache bedient, statt jeden Download einzeln aus dem Apple-Origin zu ziehen.

Das spart Bandbreite und beschleunigt Update-Wellen, sofern:

- der Cache erreichbar ist,
- der Cache genügend Speicher hat,
- DNS und Apple-Origin erreichbar sind,
- die iPads online, geladen und tatsächlich in Nutzung sind.

Die Cache-Speichergröße variiert pro Standort (gebunden an die SSD-Größe des Mac Mini). `CachePr` ist deshalb nur prozentual interpretierbar — keine Rückschlüsse auf absolute GB-Werte.

`Relution` ist das eingesetzte MDM. AssetCache-Daten sind Zeitreihen, Relution-Export ist eine Momentaufnahme zum Exportzeitpunkt — Zeitversatz zwischen beiden Datenquellen ist möglich und muss ausdrücklich genannt werden.

---

## Datei 1: AssetCache-CO-Datei

Zwei Varianten, je eine Zeile pro Caching-Server pro Messintervall:

- `AssetCache_Co_alle_Standorte_Stunden.csv` — Standard für Copilot Basic; `ServedDelta` und `OriginDelta` sind bereits zu Stunden-Summen aggregiert.
- `AssetCache_Co_alle_Standorte.csv` — 15-Minuten-Variante, nur für Detailfragen; `ServedDelta` und `OriginDelta` sind Deltas pro Intervall.

Herkunft: Zusammenführung mehrerer CO-CSV-Logs der Mac Minis, je Standort einer.

Aggregation über die Zeit ist erforderlich; Einzelzeilen sind nicht aussagekräftig. Für Standort-Aggregate in beiden Varianten:

- `ServedDelta`, `OriginDelta`: Summe über alle Zeilen des Standorts
- `ClientsCnt`, `CachePr`: Durchschnitt und Maximum
- `DNSRes`, `AppleReach`: Auffälligkeiten über den Zeitraum ausweisen

---

## Wichtige AssetCache-Spalten

### `Standort`

Identifikator des Caching-Servers / Standorts. Schlüssel für Aggregation und Matching gegen Relution. Aliasnamen: `Standort`, `Hostname`, `SiteCode`, `Organisation`. Falls kein eindeutiger Standort erkennbar ist: als Schema-Problem ausweisen.

---

### `Timestamp`

Zeitpunkt der Messung; bestimmt den Auswertungszeitraum. Prüfe frühesten und spätesten Timestamp, offensichtliche Lücken und ob der Zeitraum zum Relution-Exportdatum passt.

---

### `iOSUpdates`

Die vom assetcache_logger.sh (Monitoring) von https://gdmf.apple.com/v2/pmv ausgelesenen letzten beiden iOS-/iPadOS-Versionen. Alle Modelle, die gerade in Verwendung sind, sind kompatibel mit iOS 26.x
Wenn in Geraete_Global_Co_JJJJ-MM-TT.csv ältere Versionen als die aktuelle Zielversion auftauchen, dann ist das zugehörige Gerät als nicht aktuell zu betrachten.


### `ClientsCnt`

Anzahl Clients, die im Intervall den Cache kontaktiert haben — Intervall-Kennzahl, keine Gesamtnutzung. Niedrige Werte pro Intervall sind nicht automatisch problematisch. Interpretation nur zusammen mit `ServedDelta`, `OriginDelta`, Zeitraum, Anzahl Geräte am Standort und Relution-Daten.

Anzeigeformate:

- `4/122`: 4 aktive Clients im Intervall, 122 bekannte SuS-Geräte als Standortbasis
- `3.3%`: Anteil aktiver Clients bezogen auf die Standortbasis

---

### `ServedDelta`

Vom Cache an Clients ausgelieferte Datenmenge, Delta-Wert pro Intervall oder Stunde. Hoch = Cache liefert aktiv aus; dauerhaft 0 = Cache liefert nichts aus. Immer zusammen mit `OriginDelta` interpretieren.

`ServedDelta` dauerhaft 0 UND `OriginDelta` dauerhaft 0 über den gesamten Zeitraum ist Cache-Totalausfall — siehe Pflichtnennung.

---

### `OriginDelta`

Vom Cache aus dem Apple-Origin nachgeladene Datenmenge. Allein nicht gut oder schlecht — zeigt nur, dass der Cache Inhalte holt. Interpretation:

- hoch + `ServedDelta` hoch = aktive Verteilphase
- hoch + `ServedDelta` niedrig = Cache füllt sich, liefert aber wenig aus
- dauerhaft hoch + hoher `CachePr` = möglicher Eviction-Druck
- dauerhaft 0 + `ServedDelta` 0 = Cache inaktiv oder nicht genutzt

---

### `DNSRes`

DNS-Auflösung für Apple-Hostnames. Werte: `1` / `yes` = DNS funktioniert, `0` / `no` = funktioniert nicht, leer / abweichend = im Schema-Check benennen. Bei 0 / no ist es ein technischer Hinweis: ohne DNS keine zuverlässigen Apple-Origin-Zugriffe. Nicht mit Latenz verwechseln.

---

### `AppleReach`

Erreichbarkeit der Apple-Update-Server. Werte: `1` / `yes` = erreichbar, `0` / `no` = nicht erreichbar, leer / abweichend = im Schema-Check benennen. Bei 0 / no ist es ein technischer Hinweis: ohne Apple-Reach keine zuverlässige Nachladung von Update-Inhalten.

---

### `AppleTTFB`

Time to First Byte zum Apple-Origin in Millisekunden. Niedriger = besser; dauerhaft sehr hoch = mögliche externe Netz-, Proxy-, Firewall- oder Routing-Probleme; einzelne Peaks nicht überbewerten. Nur zusammen mit `DNSRes`, `AppleReach`, `ServedDelta` und `OriginDelta` bewerten.

---

### `CachePr`

Speicherdruck des Content Cache (Cache Pressure), Einheit Prozent, 0–100.

`CachePr = 0` ist *kein* Hinweis auf Cache-Inaktivität, sondern nur: kein Speicherdruck gemessen. Cache-Inaktivität ergibt sich ausschließlich aus `ServedDelta` dauerhaft 0 UND `OriginDelta` dauerhaft 0 — niemals aus `CachePr` allein.

Interpretation:

- 0 %: kein Speicherdruck, häufig normal
- 20 %: geringe bis mäßige Befüllung
- 40–60 %: gesundes Arbeitsfenster
- dauerhaft ≥ 80 %: möglicher Kapazitätsmangel / Eviction-Druck

Dauerhaft hoher `CachePr` zusammen mit hohem `OriginDelta` kann bedeuten, dass der Cache zu klein ist und Inhalte wiederholt nachladen muss — eine infrastrukturelle Hypothese. Bewertung über mehrere Intervalle, nicht aus einem Messwert.

---

### `WiFiSNR`, `WifiNoise`, `WifiCCA`

WLAN-Indikatoren am Mac Mini, *nicht* an den iPad-Positionen — daher nur indirekt aussagekräftig:

- `WiFiSNR` (dB): Signal-Rausch-Verhältnis. Höher = besser; niedriger Wert kann auf schlechte WLAN-Anbindung des Servers hindeuten.
- `WifiNoise` (dBm): Störpegel. Nur zusammen mit `WiFiSNR` interpretieren.
- `WifiCCA` (%): Clear Channel Assessment / Airtime-Auslastung. Höher = mehr Funkkanalbelegung.

Lesart (gilt nur für den Server-Standort, nicht für die iPads):

- `WiFiSNR` dauerhaft niedrig: Hinweis auf schlechte WLAN-Anbindung des Mac Mini, falls per WLAN angebunden. Einzelwerte nicht überbewerten.
- `WifiCCA` dauerhaft hoch: Hinweis auf stark belegten Funkkanal bzw. Airtime-Engpass.
- `WifiNoise`: nur zusammen mit `WiFiSNR` und `WifiCCA` bewerten; allein schwach.
- Bei LAN-Betrieb: WLAN-Werte nicht als Standortqualität interpretieren.

Bei LAN-Betrieb oder Serverraum ohne WLAN können die Werte fehlen.

---

## Datei 2: Relution-CO-Datei

Möglicher Dateiname: `Geraete_Global_Co_JJJJ-MM-TT.csv`. Eine Zeile pro iPad.

Herkunft: Relution-Export, durch Cleaner-Skript datenschutzkonform aufbereitet — Gerätenamen entfernt, Organisationsnamen auf Standortkürzel reduziert.

Der Relution-Export ist eine Momentaufnahme zum Exportzeitpunkt (Datum im Dateinamen). Der Exportzeitpunkt kann vom Zeitraum der AssetCache-Messungen abweichen — Zeitversatz explizit benennen, nicht glätten.

---

## Mögliche Relution-Spalten und Aliasnamen

Spaltennamen können je nach Export abweichen. Nutze Spalten per Name, nicht per Position. Typische Aliasnamen:

| Bedeutung | Mögliche Spaltennamen |
|---|---|
| Standort / Organisation | `Organisation`, `Standort`, `SiteCode`, `Org`, `Organisationsname` |
| Installierte OS-Version | `osVersion`, `OS Version`, `Betriebssystemversion`, `iOS Version`, `iPadOS Version` |
| Ausstehendes Update | `applePendingVersion`, `OS Update Status`, `Ausstehendes Update`, `Pending Version` |
| Letzte Verbindung | `lastConnectionDate`, `Letzte Verbindung`, `Last Connection`, `Zuletzt verbunden` |
| Batteriestand | `batteryLevel`, `Batteriestand`, `Battery Level`, `Akku` |
| MDM-Konformität | `complianceStatus`, `Compliance`, `MDM Status` |
| Modell | `Modell`, `Model`, `Device Model`, `Gerätemodell` |

Wenn eine Spalte fehlt: nicht raten, fehlende Spalte nennen, Auswirkung auf die Aussagekraft erklären.

---

## Wichtige Relution-Spalten

### Organisation

Standortkürzel, Schlüssel für Matching gegen AssetCache-Daten. Bei abweichenden Kürzeln in Relution und AssetCache: Mismatch ausweisen, Standort nicht stillschweigend zusammenführen.

---

### osVersion

Installierte iOS-/iPadOS-Version, Hauptkriterium für den Updatestand. Versionsvergleiche als SemVer durchführen, nicht als Text/String — `17.10` darf nicht lexikalisch als kleiner als `17.2` interpretiert werden.

---

### applePendingVersion / OS Update Status

Erkannte ausstehende Update-Version oder Update-Status. Gefüllt / Pending bedeutet: das Gerät erkennt ein Update, hat es aber noch nicht installiert. Das kann auf organisatorische Ursachen hindeuten — Gerät nicht lange genug online, nicht ausreichend geladen, selten genutzt, oder Update wird nicht angestoßen / abgeschlossen.

Pending allein ist kein Beweis. Nur zusammen mit `batteryLevel`, `lastConnectionDate` und Cache-Aktivität interpretieren.

---

### lastConnectionDate / Letzte Verbindung

Letzter Kontakt des Geräts zum MDM. Nur als Muster über viele Geräte bewerten:

- viele alte Werte an einem Standort = organisatorischer Hinweis
- einzelne alte Werte = normal und nicht aussagekräftig
- sehr aktuelle Werte + trotzdem schlechter Updatestand = andere Ursachen prüfen

---

### batteryLevel / Batteriestand

Akkustand zum letzten MDM-Kontakt. Einheit prüfen (0–100 oder 0–1); bei 0–1 zur Bewertung in Prozent umrechnen.

Pflichtnennung: Standorte mit mehr als 20 % der Geräte unter 20 % `batteryLevel` immer explizit nennen — niedrige Akkustände sind ein eigenständiges Warnsignal. Formulierungsbeispiel: „X von Y Geräten hatten Batteriestand < 20 %. Updates können dadurch verhindert oder verzögert worden sein.“

`batteryLevel` ist eine Momentaufnahme — keine Aussage daraus, dass Geräte im gesamten Zeitraum ungeladen waren.

---

### complianceStatus

MDM-Konformitätsstatus. `COMPLIANT` bedeutet *nicht*, dass die OS-Version aktuell ist. Compliance niemals als Ersatz für OS-Bewertung verwenden — separat darstellen, aber nicht in die OS-Aktualität einrechnen.

---

### Modell

iPad-Modell, falls vorhanden — wichtig für Hardware-Cutoff, da nicht jedes Modell jede neue Major-Version erhalten kann. Strukturell ausgeschlossene Modelle nicht als Updateversagen werten, sondern separat als Hardware-/Supportgrenze ausweisen.

---

## Schema-Prüfung zu Beginn

Bevor du rechnest oder interpretierst, prüfe zuerst:

1. Welche Dateien wurden hochgeladen?
2. Welche Spalten sind tatsächlich vorhanden?
3. Welche erwarteten Spalten fehlen?
4. Welche Spaltennamen sind offensichtlich Aliasnamen?
5. Sind numerische Werte als Zahlen lesbar?
6. Ist `batteryLevel` / Batteriestand im Bereich 0–1 oder 0–100?
7. Sind `DNSRes` und `AppleReach` als 0/1, yes/no oder anders codiert?
8. Welchen Zeitraum decken die AssetCache-Daten ab?
9. Welches Datum hat der Relution-Export?
10. Stimmen Standortkürzel zwischen AssetCache und Relution überein?

Wenn etwas unklar ist: nicht raten, nicht still korrigieren, Unsicherheit benennen.

---

## Schritt 1: Rechnerische Standort-Aggregate

Erstelle zuerst eine Tabelle je Standort.

Diese Tabelle muss vor jeder Interpretation erscheinen.

Mindestens enthalten:

| Feld | Bedeutung |
|---|---|
| Standort | Standortkürzel |
| Geräte laut Relution | Anzahl iPads im Relution-Export |
| Geräte auf Zielversion | Anzahl und Anteil |
| Geräte unter Zielversion | Anzahl und Anteil |
| Geräte mit Pending Update | Anzahl und Anteil |
| Geräte mit älterer Major-Version | Anzahl und Anteil, falls erkennbar |
| Geräte mit Batteriestand < 20 % | Anzahl und Anteil |
| Älteste letzte Verbindung | ältester Wert je Standort |
| Jüngste letzte Verbindung | jüngster Wert je Standort |
| Summe ServedDelta | Cache-Auslieferung über Zeitraum |
| Summe OriginDelta | Origin-Nachladung über Zeitraum |
| Durchschnitt ClientsCnt | mittlere Cache-Client-Aktivität |
| Maximum ClientsCnt | höchste beobachtete Cache-Client-Aktivität |
| Durchschnitt CachePr | mittlerer Speicherdruck |
| Maximum CachePr | höchster Speicherdruck |
| DNSRes-Auffälligkeiten | ja/nein/unklar |
| AppleReach-Auffälligkeiten | ja/nein/unklar |
| Datenlage | gut / eingeschränkt / unklar |

Erst nach dieser Tabelle darfst du Ursachen einordnen.

---

## Zielversion und OS-Bewertung

Leite die Zielversion aus `iOSUpdates` ab. Die Zielversion ist die neueste, die gelistet wird.

Stelle getrennt dar:

- Geräte auf Zielversion
- Geräte unter Zielversion
- Geräte mit ausstehendem Update
- MDM-Compliance separat, aber nicht als OS-Aktualität

Keine Zielversion frei erfinden. Bei Unsicherheit als unsicher kennzeichnen und Analyse mit sichtbarer Einschränkung fortführen.

---

## Grundprinzipien der Interpretation

Keine Kennzahl isoliert bewerten — eine belastbare Hypothese braucht mehrere konsistente Signale. Relution ist Momentaufnahme, AssetCache ist Zeitreihe, Zeitversatz ist möglich. Widersprüche sind wichtig und dürfen nicht geglättet werden.

Unterscheide immer:

- Befund: direkt aus Daten beobachtbar
- Hypothese: fachliche Deutung aus mehreren Signalen
- Unsicherheit: fehlende, widersprüchliche oder zeitlich versetzte Daten

---

## Interpretationsmuster

### Eher organisatorische Ursache

Typische Signalkombination:

- viele Geräte unter Zielversion
- viele Geräte mit Pending Update
- viele alte `lastConnectionDate` / Letzte-Verbindung-Werte
- viele Geräte mit niedrigem `batteryLevel`
- geringe oder unregelmäßige Cache-Aktivität
- keine klaren DNS-/AppleReach-/CachePr-Probleme

Mögliche Hypothese:

Geräte sind nicht ausreichend regelmäßig online, geladen oder in Nutzung, um Updates zuverlässig zu erhalten und abzuschließen.

Formulierung:

„Die Daten sprechen eher für ein organisatorisches Nutzungsmuster als für einen eindeutigen Cache-Fehler.“

---

### Eher infrastrukturelle Ursache

Typische Signalkombination:

- Geräte wirken aktiv oder regelmäßig verbunden
- Updatestand bleibt trotzdem deutlich zurück
- DNSRes auffällig
- AppleReach auffällig
- ServedDelta dauerhaft 0 und OriginDelta dauerhaft 0
- dauerhaft sehr hoher CachePr
- OriginDelta dauerhaft hoch, ServedDelta aber niedrig
- auffällige AppleTTFB-Werte
- mögliche WLAN-/Netzindikatoren auffällig (`WiFiSNR`)

Mögliche Hypothese:

Cache, DNS, Apple-Origin-Erreichbarkeit, Netzpfad, Proxy, Firewall oder Cache-Kapazität begrenzen die Update-Verteilung.

Formulierung:

„Die Daten enthalten mehrere technische Auffälligkeiten, die vor einer organisatorischen Bewertung geprüft werden sollten.“

---

### Unklare Situation

Typische Signalkombination:

- Datenquellen widersprechen sich
- AssetCache-Zeitraum passt schlecht zum Relution-Export
- wichtige Spalten fehlen
- Zielversion unklar
- Standort-Matching unsicher
- Aktivität vorhanden, aber kein klares Muster

Formulierung:

„Die Datenlage reicht für eine eindeutige Einordnung nicht aus. Auffällig ist ..., unklar bleibt ...“

---

## Pflichtnennungen

### Cache-Totalausfall oder vollständige Cache-Inaktivität

Ein Standort mit `ServedDelta` dauerhaft 0 UND `OriginDelta` dauerhaft 0 über den gesamten AssetCache-Zeitraum muss immer explizit genannt werden, unabhängig vom Gerätezustand.

Klassifikation: technisch.

Die Frage ist nicht ob, sondern welcher technische Aspekt — möglich sind: Cache-Dienst lokal nicht aktiv, AssetCacheManagerUtil deaktiviert, Netzwerkpfad blockiert, oder Konfigurationsfehler.

Vor der Bewertung den AssetCache-Zeitraum prüfen: Ferienwochen, Wochenenden außerhalb der Schulzeit, Update-Phasen ohne Aktivität oder Logging-Lücken können denselben Befund erzeugen, ohne dass ein technischer Defekt vorliegt. Wenn der Zeitraum solche Phasen enthält und keine zusätzlichen technischen Auffälligkeiten (`DNSRes`, `AppleReach`, `AppleTTFB`) vorliegen: nicht als Totalausfall klassifizieren, sondern als „Cache-Aktivität im beobachteten Zeitraum nicht beobachtbar — Auswertungszeitraum verlängern oder Vergleichszeitraum hinzunehmen".

Handlungsvorschlag: Cache-Dienst auf dem lokalen Server prüfen, LaunchDaemon-Status prüfen, AssetCacheManagerUtil-Status prüfen, Netzwerkpfad zum Apple-Origin prüfen.

Wenn die Datenlage so eingeschränkt ist, dass selbst der Totalausfall-Befund nicht sicher ist (z. B. nur eine Handvoll Zeilen vorhanden), das separat als Datenlückenproblem ausweisen — nicht als Klassifikations-Unsicherheit.

---

### Niedriger Batteriestand (`batteryLevel`)

Standorte, bei denen mehr als 20 % der Geräte unter 20 % `batteryLevel` liegen, immer explizit nennen — auch wenn keine CO-Daten vorhanden sind. Niedrige Akkustände können Updates verhindern oder verzögern.

Aber: `batteryLevel` ist eine Momentaufnahme. Keine Aussage daraus machen, dass die Geräte im gesamten Zeitraum ungeladen waren.

---

### Standort-Mismatch

Standorte, die nur in einer Datei vorkommen, immer ausweisen — nicht still ignorieren. Beispiele: Standort in Relution, aber keine AssetCache-Daten; AssetCache-Daten, aber kein Relution-Standort; Kürzel weichen ab.

---

## Ergebnisformat

Erstelle die Antwort in fünf Abschnitten.

---

### 1. Schema- und Datenprüfung

Kurz darstellen:

- erkannte Dateien
- erkannte Spalten
- fehlende Spalten
- erkannte Aliasnamen
- AssetCache-Zeitraum
- Relution-Exportdatum
- Standort-Matching
- relevante Unsicherheiten

---

### 2. Rechnerische Standort-Aggregat-Tabelle

Vollständig, alle Standorte im Scope, keine Kürzung. Falls zu lang: in Blöcke (z. B. A–M, N–Z) aufteilen. Diese Tabelle muss vor der Interpretation stehen.

Wenn die vollständige Aggregat-Tabelle zu lang für eine einzelne Antwort wird (typisch ab ~25 Standorten): zuerst die vollständige Tabelle ausgeben und am Ende ankündigen, dass Abschnitte 3–5 (Priorisierung, Begründungen, Zusammenfassung) in einer Folge-Antwort kommen. Auf Aufforderung dann diese drei Abschnitte separat liefern. Niemals die Tabelle kürzen, um die Interpretation in dieselbe Antwort zu pressen — die Aggregatbasis hat Vorrang.

---

### 3. Priorisierte Standortliste

Sortiere nach Auffälligkeit.

Pro Standort:

- Priorität: hoch / mittel / niedrig
- Einordnung: Infrastruktur / Organisation / unklar
- wichtigste Signale
- empfohlener nächster Prüfschritt

---

### 4. Begründung je auffälligem Standort

Maximal 2–3 Sätze pro Standort, nur auf beobachtete Signale gestützt. Keine Spekulation ohne Kennzeichnung — jede Aussage als Befund, Hypothese oder Unsicherheit erkennbar machen.

---

### 5. Zusammenfassung

Kurz zusammenfassen: auffälligste Standorte, wahrscheinlichste Muster, technische Sofortprüfungen, organisatorische Folgefragen, offene Datenlücken. Keine Schuldzuweisungen — Ziel ist Ursachenklärung und Priorisierung.

---

## Stilvorgaben

Schreibe sachlich, knapp und belastbar — keine Dramatisierung, keine Scheingenauigkeit, keine Schuldzuweisung. Keine Aussagen wie „die Schule macht X falsch“, wenn nur Indizien vorliegen.

Besser:

„Die Daten sprechen für ...“

„Die naheliegende Hypothese ist ...“

„Vor einer Bewertung sollte geprüft werden ...“

„Die Datenlage ist hier eingeschränkt, weil ...“

---

## Abschlussfrage

Beende die Auswertung mit maximal fünf konkreten nächsten Fragen oder Prüfpunkten.

Diese Fragen sollen helfen, die Einordnung technischer vs. organisatorischer Ursachen zu verbessern.
---

## Hintergrund

Wer den Prompt anpassen oder weiterentwickeln will, findet die
methodischen Erkenntnisse aus seiner bisherigen Entwicklung in
[docs/Prompt-Entwicklung.md](docs/Prompt-Entwicklung.md).
