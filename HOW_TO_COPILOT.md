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
   - Geraete_Global_Co_YYYY-MM-DD.csv
   - oder ähnlich benannt

Ziel:
Standortweise bewerten, welche Auffälligkeiten beim iOS-/iPadOS-Updatestand bestehen und ob diese eher auf infrastrukturelle Ursachen, organisatorische Ursachen oder unklare Faktoren hindeuten.

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

Apple Content Caching speichert iOS-/iPadOS-Updates und andere Apple-Inhalte lokal auf einem Mac Mini im Standortnetzwerk zwischen.

Anfragen der iPads können dadurch vom lokalen Cache bedient werden, statt jeden Download einzeln aus dem Apple-Origin zu ziehen.

Das spart Bandbreite und beschleunigt Update-Wellen, sofern:

- der Cache erreichbar ist,
- der Cache genügend Speicher hat,
- DNS und Apple-Origin erreichbar sind,
- die iPads online, geladen und tatsächlich in Nutzung sind.

Die Cache-Speichergröße variiert pro Standort, weil sie an die SSD-Größe des jeweiligen Mac Mini gebunden ist. Deshalb ist `CachePr` nur prozentual interpretierbar. Aus `CachePr` kann nicht auf absolute GB-Werte geschlossen werden.

`Relution` ist das eingesetzte MDM. Der Relution-Export ist eine Momentaufnahme zum Exportzeitpunkt. Er ist kein historischer Verlauf.

AssetCache-Daten sind Zeitreihen. Relution-Daten sind Momentaufnahme.

Zeitversatz zwischen beiden Datenquellen ist möglich und muss ausdrücklich genannt werden.

---

## Datei 1: AssetCache-CO-Datei

Mögliche Dateinamen:

- `AssetCache_Co_alle_Standorte_Stunden.csv`
- `AssetCache_Co_alle_Standorte.csv`

Herkunft:
Zusammenführung mehrerer CO-CSV-Logs der Mac Minis, je Standort einer.

Struktur:
Eine Zeile pro Caching-Server pro Messintervall.

Bei der Stunden-Datei sind 15-Minuten-Werte bereits auf Stundenwerte verdichtet.

Aggregation über die Zeit ist erforderlich. Einzelzeilen sind nicht aussagekräftig.

---

## Datei-Varianten

### Stunden-Variante

`AssetCache_Co_alle_Standorte_Stunden.csv`

Diese Variante ist der Standard für Copilot Basic.

`ServedDelta` und `OriginDelta` sind bereits zu Stunden-Summen aggregiert.

Für Standort-Aggregate:

- `ServedDelta`: Summe über alle Stunden-Zeilen des Standorts
- `OriginDelta`: Summe über alle Stunden-Zeilen des Standorts
- `ClientsCnt`: Durchschnitt und Maximum über alle Stunden-Zeilen
- `CachePr`: Durchschnitt und Maximum über alle Stunden-Zeilen
- `DNSRes` / `AppleReach`: Auffälligkeiten über den Zeitraum ausweisen

### 15-Minuten-Variante

`AssetCache_Co_alle_Standorte.csv`

Diese Variante nur für Detailfragen verwenden.

`ServedDelta` und `OriginDelta` sind Deltas pro 15-Minuten-Intervall.

Für Standort-Aggregate:

- `ServedDelta`: Summe über alle Zeilen des Standorts
- `OriginDelta`: Summe über alle Zeilen des Standorts
- `ClientsCnt`: Durchschnitt und Maximum über alle Zeilen
- `CachePr`: Durchschnitt und Maximum über alle Zeilen

In beiden Varianten gilt:

Höherer `ServedDelta` = mehr Auslieferung aus dem Cache an Clients.

Höherer `OriginDelta` = mehr Nachladen vom Apple-Origin in den Cache.

---

## Wichtige AssetCache-Spalten

### `Standort`

Identifikator des Caching-Servers / Standorts.

Schlüssel für Aggregation und Matching gegen Relution.

Mögliche Aliasnamen:

- `Standort`
- `Hostname`
- `SiteCode`
- `Organisation`

Falls kein eindeutiger Standort erkennbar ist: als Schema-Problem ausweisen.

---

### `Timestamp`

Zeitpunkt der Messung.

Dient zur Bestimmung des Auswertungszeitraums.

Prüfe:

- frühester Timestamp
- spätester Timestamp
- offensichtliche Lücken
- ob der Zeitraum zum Relution-Exportdatum passt

---

### `iOSUpdates`

Vom Cache erkannte verfügbare iOS-/iPadOS-Versionen.

Primärquelle für die Zielversion.

Kann mehrere Werte enthalten, weil nicht alle iPad-Modelle dieselbe neueste Version erhalten können.

Beispiel:

`26.4|18.7.5`

Interpretation:

- Es kann eine aktuelle Major-Version geben.
- Zusätzlich kann es eine ältere unterstützte Major-Version für ältere Geräte geben.
- Nicht jedes Gerät muss zwingend auf die höchste Major-Version können.

Wenn `iOSUpdates` inkonsistent oder leer ist:

- nicht raten,
- als Unsicherheit ausweisen,
- ggf. mit Relution-Modellinformationen plausibilisieren.

---

### `ClientsCnt`

Anzahl der Clients, die im Intervall den Cache kontaktiert haben.

Wichtig:

`ClientsCnt` ist eine Intervall-Kennzahl, keine Gesamtnutzung.

Niedrige Werte pro Intervall sind nicht automatisch problematisch.

Interpretation nur zusammen mit:

- `ServedDelta`
- `OriginDelta`
- Zeitraum
- Anzahl Geräte am Standort
- Relution-Daten

Wenn `ClientsCnt` als Verhältnis dargestellt ist, z. B. `4/122`, dann bedeutet:

- 4 aktive Clients im Intervall
- 122 bekannte SuS-Geräte als Standortbasis

Wenn `ClientsCnt` als Prozentwert dargestellt ist, z. B. `3.3%`, dann bedeutet:

- Anteil aktiver Clients bezogen auf bekannte Standortbasis

---

### `ServedDelta`

Vom Cache an Clients ausgelieferte Datenmenge.

Delta-Wert pro Intervall oder Stunde.

Interpretation:

- hoch = Cache liefert aktiv an iPads aus
- dauerhaft 0 = Cache liefert nichts aus
- zusammen mit `OriginDelta` interpretieren

Besonders wichtig:

Ein Standort mit `ServedDelta` dauerhaft 0 und `OriginDelta` dauerhaft 0 über den gesamten Zeitraum muss immer explizit genannt werden.

Das ist ein Hinweis auf Cache-Totalausfall oder fehlende Nutzung des Cache-Dienstes.

Klassifikation zunächst: technisch / unklar, je nach weiteren Signalen.

---

### `OriginDelta`

Vom Cache aus dem Apple-Origin nachgeladene Datenmenge.

Interpretation:

- hoch + `ServedDelta` hoch = aktive Verteilphase
- hoch + `ServedDelta` niedrig = Cache füllt sich, liefert aber wenig aus
- dauerhaft hoch + hoher `CachePr` = möglicher Eviction-Druck
- dauerhaft 0 + `ServedDelta` 0 = Cache inaktiv oder nicht genutzt

`OriginDelta` allein ist nicht gut oder schlecht. Es zeigt nur, dass der Cache Inhalte vom Apple-Origin holt.

---

### `DNSRes`

DNS-Auflösung für Apple-Hostnames.

Mögliche Werte:

- `1` / `yes` = DNS funktioniert
- `0` / `no` = DNS funktioniert nicht
- leer / abweichend = im Schema-Check benennen

Interpretation:

DNSRes = 0 oder no ist ein technischer Hinweis.

Wenn DNS nicht funktioniert, können Apple-Origin-Zugriffe typischerweise nicht zuverlässig funktionieren.

Nicht mit Latenz verwechseln.

---

### `AppleReach`

Erreichbarkeit der Apple-Update-Server.

Mögliche Werte:

- `1` / `yes` = Apple-Origin erreichbar
- `0` / `no` = Apple-Origin nicht erreichbar
- leer / abweichend = im Schema-Check benennen

Interpretation:

AppleReach = 0 oder no ist ein technischer Hinweis.

Wenn AppleReach gestört ist, können Update-Inhalte nicht zuverlässig vom Apple-Origin nachgeladen werden.

---

### `AppleTTFB`

Time to First Byte zum Apple-Origin.

Einheit: Millisekunden.

Interpretation:

- niedriger = besser
- dauerhaft sehr hoch = mögliche externe Netz-, Proxy-, Firewall- oder Routing-Probleme
- einzelne Peaks nicht überbewerten

Nur zusammen mit DNSRes, AppleReach, ServedDelta und OriginDelta bewerten.

---

### `CachePr`

Cache Pressure, also Speicherdruck des Content Cache.

Einheit: Prozent, 0–100.

Wichtig:

`CachePr = 0` ist kein Hinweis auf Cache-Inaktivität.

`CachePr = 0` bedeutet nur: kein Speicherdruck gemessen.

Cache-Inaktivität ergibt sich ausschließlich aus:

`ServedDelta` dauerhaft 0 UND `OriginDelta` dauerhaft 0

Niemals aus `CachePr` allein.

Interpretation:

- 0 %: kein Speicherdruck, häufig normal
- 20 %: geringe bis mäßige Befüllung
- 40–60 %: gesundes Arbeitsfenster
- dauerhaft ≥ 80 %: möglicher Kapazitätsmangel / Eviction-Druck

Dauerhaft hoher `CachePr` zusammen mit hohem `OriginDelta` kann bedeuten:

Der Cache ist zu klein und muss Inhalte wiederholt nachladen.

Das ist eine infrastrukturelle Hypothese.

Ein einzelner Messwert reicht nicht. Bewertung über mehrere Intervalle.

---

### `WiFiSNR`

Signal-Rausch-Verhältnis am Caching-Server.

Einheit: dB.

Wichtig:

Dieser Wert misst die WLAN-Situation am Mac Mini, nicht die WLAN-Situation der iPads in den Klassenzimmern.

Interpretation:

- höher = besser
- niedriger Wert kann auf schlechte WLAN-Anbindung des Servers hindeuten
- bei LAN-Betrieb oder Serverraum ohne WLAN kann der Wert fehlen

Nur indirekter Infrastrukturindikator.

---

### `WifiNoise`

Störpegel am Caching-Server.

Einheit: dBm.

Nur zusammen mit WiFiSNR interpretieren.

---

### `WifiCCA`

Clear Channel Assessment / Airtime-Auslastung am Caching-Server.

Einheit: Prozent.

Höher = mehr Funkkanalbelegung.

Nur indirekter Hinweis, da nicht die iPad-Positionen gemessen werden.

---

## Datei 2: Relution-CO-Datei

Möglicher Dateiname:

`Geraete_Global_Co_YYYY-MM-DD.csv`

Herkunft:

Relution-Export, durch Cleaner-Skript datenschutzkonform aufbereitet.

Gerätenamen wurden entfernt. Organisationsnamen wurden auf Standortkürzel reduziert.

Struktur:

Eine Zeile pro iPad.

Wichtig:

Der Relution-Export ist eine Momentaufnahme zum Exportzeitpunkt.

Das Datum im Dateinamen ist der Exportzeitpunkt.

Der Exportzeitpunkt kann vom Zeitraum der AssetCache-Messungen abweichen.

Zeitversatz explizit benennen, nicht glätten.

---

## Mögliche Relution-Spalten und Aliasnamen

Spaltennamen können je nach Export abweichen.

Nutze Spalten per Name, nicht per Position.

Typische Aliasnamen:

| Bedeutung | Mögliche Spaltennamen |
|---|---|
| Standort / Organisation | `Organisation`, `Standort`, `SiteCode`, `Org`, `Organisationsname` |
| Installierte OS-Version | `osVersion`, `OS Version`, `Betriebssystemversion`, `iOS Version`, `iPadOS Version` |
| Ausstehendes Update | `applePendingVersion`, `OS Update Status`, `Ausstehendes Update`, `Pending Version` |
| Letzte Verbindung | `lastConnectionDate`, `Letzte Verbindung`, `Last Connection`, `Zuletzt verbunden` |
| Batteriestand | `batteryLevel`, `Batteriestand`, `Battery Level`, `Akku` |
| MDM-Konformität | `complianceStatus`, `Compliance`, `MDM Status` |
| Modell | `Modell`, `Model`, `Device Model`, `Gerätemodell` |

Wenn eine Spalte fehlt:

- nicht raten,
- fehlende Spalte nennen,
- Auswirkung auf die Aussagekraft erklären.

---

## Wichtige Relution-Spalten

### Organisation

Standortkürzel.

Schlüssel für Matching gegen AssetCache-Daten.

Wenn Kürzel in Relution und AssetCache nicht übereinstimmen:

- Mismatch ausweisen,
- Standort nicht stillschweigend zusammenführen.

---

### osVersion

Installierte iOS-/iPadOS-Version.

Hauptkriterium für den Updatestand.

Wichtig:

Versionsvergleiche als SemVer durchführen, nicht als Text/String.

Beispiel:

`17.10` darf nicht lexikalisch als kleiner als `17.2` interpretiert werden.

---

### applePendingVersion / OS Update Status

Erkannte ausstehende Update-Version oder Update-Status.

Interpretation:

Gefüllt / Pending vorhanden bedeutet:

Das Gerät erkennt ein Update, hat es aber noch nicht installiert.

Das kann auf organisatorische Ursachen hindeuten, z. B.:

- Gerät nicht lange genug online
- Gerät nicht ausreichend geladen
- Gerät wird selten genutzt
- Update wird nicht angestoßen oder nicht abgeschlossen

Aber:

Pending allein ist kein Beweis. Nur zusammen mit Batterie, letzter Verbindung und Cache-Aktivität interpretieren.

---

### lastConnectionDate / Letzte Verbindung

Letzter Kontakt des Geräts zum MDM.

Interpretation:

- viele alte Werte an einem Standort = organisatorischer Hinweis
- einzelne alte Werte = normal und nicht aussagekräftig
- sehr aktuelle Werte + trotzdem schlechter Updatestand = andere Ursachen prüfen

Nur als Muster über viele Geräte bewerten.

---

### batteryLevel / Batteriestand

Akkustand zum letzten MDM-Kontakt.

Wichtig:

Einheit prüfen:

- 0–100
- oder 0–1

Wenn Einheit 0–1: zur Bewertung in Prozent umrechnen.

Pflichtnennung:

Standorte, bei denen mehr als 20 % der Geräte unter 20 % Batteriestand liegen, immer explizit nennen.

Niedrige Akkustände sind ein eigenständiges Warnsignal.

Formulierungsbeispiel:

„X von Y Geräten hatten Batteriestand < 20 %. Updates können dadurch verhindert oder verzögert worden sein.“

Einschränkung:

Der Batteriestand stammt aus einer Momentaufnahme. Er beweist nicht, dass die Geräte im gesamten relevanten Zeitraum ungeladen waren.

---

### complianceStatus

MDM-Konformitätsstatus.

Wichtig:

`COMPLIANT` bedeutet nicht, dass die OS-Version aktuell ist.

Compliance niemals als Ersatz für OS-Bewertung verwenden.

Separat darstellen, aber nicht in die OS-Aktualität einrechnen.

---

### Modell

iPad-Modell, falls vorhanden.

Wichtig für Hardware-Cutoff.

Nicht jedes Modell kann jede neue Major-Version erhalten.

Wenn ältere Modelle strukturell keine aktuelle Major-Version erhalten können:

- nicht als Updateversagen werten,
- separat als Hardware-/Supportgrenze ausweisen.

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

Wenn etwas unklar ist:

- nicht raten,
- nicht still korrigieren,
- Unsicherheit benennen.

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

Leite die Zielversion aus `iOSUpdates` ab.

Wenn mehrere Zielversionen vorhanden sind, z. B.:

`26.4|18.7.5`

dann berücksichtige:

- verschiedene iPad-Modelle können unterschiedliche höchste unterstützte Versionen haben,
- ältere Major-Versionen können für ältere Geräte korrekt sein,
- Modellinformationen sind relevant, falls vorhanden.

Stelle getrennt dar:

- Geräte auf Zielversion
- Geräte unter Zielversion
- Geräte mit ausstehendem Update
- Geräte mit älteren Major-Versionen
- Geräte, die vermutlich durch Hardware-Cutoff begrenzt sind
- MDM-Compliance separat, aber nicht als OS-Aktualität

Keine Zielversion frei erfinden.

Wenn Zielversion unsicher ist:

- als unsicher kennzeichnen,
- Analyse trotzdem mit sichtbarer Einschränkung fortführen.

---

## Grundprinzipien der Interpretation

Keine Kennzahl isoliert bewerten.

Eine belastbare Hypothese braucht mehrere konsistente Signale.

Relution ist Momentaufnahme.

AssetCache ist Zeitreihe.

Zeitversatz ist möglich.

Widersprüche sind wichtig und dürfen nicht geglättet werden.

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
- viele Geräte mit niedrigem Batteriestand
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
- mögliche WLAN-/Netzindikatoren auffällig

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

Ein Standort mit:

`ServedDelta` dauerhaft 0

UND

`OriginDelta` dauerhaft 0

über den gesamten AssetCache-Zeitraum muss immer explizit genannt werden.

Unabhängig vom Gerätezustand.

Mögliche Klassifikation:

- technisch
- oder unklar, falls Datenlage eingeschränkt ist

Handlungsvorschlag:

Cache-Dienst auf dem lokalen Server prüfen, LaunchDaemon prüfen, AssetCacheManagerUtil-Status prüfen, Netzwerkpfad prüfen.

---

### Niedriger Batteriestand

Standorte, bei denen mehr als 20 % der Geräte unter 20 % Batteriestand liegen, immer explizit nennen.

Auch dann, wenn keine CO-Daten vorhanden sind.

Niedrige Akkustände können Updates verhindern oder verzögern.

Aber:

Batteriestand ist eine Momentaufnahme. Keine Aussage daraus machen, dass die Geräte im gesamten Zeitraum ungeladen waren.

---

### Standort-Mismatch

Standorte, die nur in einer Datei vorkommen, immer ausweisen.

Beispiele:

- Standort in Relution vorhanden, aber keine AssetCache-Daten
- AssetCache-Daten vorhanden, aber kein Relution-Standort
- Kürzel weichen ab

Nicht still ignorieren.

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

Vollständig, alle Standorte im Scope.

Keine Kürzung.

Falls zu lang:

- Block A–M
- Block N–Z

Diese Tabelle muss vor der Interpretation stehen.

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

Maximal 2–3 Sätze pro Standort.

Nur auf beobachtete Signale stützen.

Keine Spekulation ohne Kennzeichnung.

Jede Aussage als Befund, Hypothese oder Unsicherheit erkennbar machen.

---

### 5. Zusammenfassung

Kurz zusammenfassen:

- auffälligste Standorte
- wahrscheinlichste Muster
- technische Sofortprüfungen
- organisatorische Folgefragen
- offene Datenlücken

Keine Schuldzuweisungen.

Ziel ist Ursachenklärung und Priorisierung.

---

## Stilvorgaben

Schreibe sachlich, knapp und belastbar.

Keine Dramatisierung.

Keine Scheingenauigkeit.

Keine Schuldzuweisung.

Keine Aussagen wie „die Schule macht X falsch“, wenn nur Indizien vorliegen.

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
