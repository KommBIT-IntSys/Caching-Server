# Asset Cache Monitoring – KommunalBIT

Monitoring und Logging des Apple Content Caching auf Mac Minis in Schulen.  
**Aktuelle Version: 1.9.1**

---

## Ziel des Projekts

Das Projekt dient nicht der Datensammlung um der Datensammlung willen. Es soll handlungsfähig machen.

In einer Umgebung mit vielen iPads ist Apple Content Caching ein wichtiger technischer Baustein, um Last, Bandbreite und Updateverteilung sinnvoll zu steuern. Verzögerungen bei iOS-/iPadOS-Updates können ein Sicherheitsrisiko darstellen. Deshalb soll das Monitoring helfen, standortbezogen zu klären, ob Update-Rückstände eher technische Ursachen haben oder ob die Ursache eher im organisatorischen Umgang mit Geräten liegt, etwa Ladezustand, WLAN-Erreichbarkeit oder Zeitpunkt der Nutzung.

Die zentralen Fragen sind:

- Wird der Cache tatsächlich genutzt?
- Wird er zum richtigen Zeitpunkt genutzt?
- Passt die Cache-Aktivität zur bekannten Geräteanzahl eines Standorts?
- Ist der Standort technisch grundsätzlich updatefähig?
- Deuten Auffälligkeiten auf Infrastruktur-, Netzwerk-, WLAN- oder Konfigurationsprobleme hin?
- Wo sollte zuerst gehandelt werden, um Updatefähigkeit und Resilienz messbar zu verbessern?

Die Auswertung soll zwei Entscheidungsmodi unterstützen:

1. **Statistik / Flottenwirkung**  
   Wo kann mit vertretbarem Aufwand ein großer messbarer Anteil des Gesamtbestands verbessert werden?

2. **Relevanz / Sicherheitswirkung**  
   Wo liegen die kritischeren Update- oder Erreichbarkeitsprobleme, unabhängig davon, ob dort sehr viele Geräte betroffen sind?

Diese beiden Perspektiven dürfen nicht vermischt werden. Ein Standort kann statistisch wichtig sein, ohne sicherheitskritisch ganz oben zu stehen. Umgekehrt kann ein kleiner Standort sicherheitsrelevant auffallen, obwohl er für die Gesamtquote kaum Gewicht hat.

---

## Kurzüberblick

Das Hauptskript `scripts/assetcache_logger.sh` läuft auf einem Mac mini mit aktiviertem Apple Content Caching. Es wird über einen LaunchDaemon alle 15 Minuten gestartet.

Der Logger sammelt in einem Durchlauf:

- Content-Caching-Metriken aus `AssetCacheManagerUtil`
- Cache-Deltas seit dem letzten Lauf
- erkannte Peers
- aktive Clients im letzten Zeitfenster
- aktuelle iOS-/iPadOS-Versionen aus Apple GDMF
- Netzwerkstatus, Default Gateway und DNS
- Apple-CDN-Erreichbarkeit und TTFB
- WLAN-Metriken, falls der Mac mini per WLAN betrieben wird

Ab Version 1.9.1 trennt das System strikt zwischen dauerhaftem Speicher und sichtbarer Ausgabe.

---

## Speicherarchitektur ab v1.9.1

Version 1.9.1 führt einen dauerhaften RAW-Journal-Speicher unter `Application Support` ein. Dieser ist die kanonische Datenquelle. Die sichtbaren HU-/CO-Dateien unter `/Library/Logs/KommunalBIT` sind daraus ableitbare Arbeitsdateien.

| Bereich | Pfad | Zweck |
|---|---|---|
| Dauerhaftes RAW-Journal | `/Library/Application Support/KommunalBIT/AssetCacheLogger/journal/` | Technische Wahrheit; soll macOS-Updates und Neustarts überstehen |
| State-Dateien | `/Library/Application Support/KommunalBIT/AssetCacheLogger/state/` | Laufzustände, Deltas, GDMF-Cache, Archivstatus, sichtbare Epoche |
| Boot-Erkennung | `/Library/Application Support/KommunalBIT/AssetCacheLogger/boot/` | Erkennung von Neustarts über `kern.boottime` |
| Sicheres Archiv | `/Library/Application Support/KommunalBIT/AssetCacheLogger/archive/` | Archivierte HU-/CO-Dateien bei manueller Archivierung oder iOS-Versionswechsel |
| Statuslog | `/Library/Application Support/KommunalBIT/AssetCacheLogger/status.log` | Dauerhaftes Betriebs-/Diagnoseprotokoll des Loggers |
| Sichtbarer Arbeitsordner | `/Library/Logs/KommunalBIT/` | Aktuelle HU-/CO-Dateien für Sichtprüfung und Export |

Der alte Ordner `/Library/Logs/KommunalBIT/Archiv` wird ab Version 1.9.1 nicht mehr verwendet.

---

## Dateinamen

### Dauerhaftes RAW-Journal

Das RAW-Journal ist nicht mehr an die Skriptversion gekoppelt, sondern an `RAW_SCHEMA_VER`.

Beispiel:

```text
/Library/Application Support/KommunalBIT/AssetCacheLogger/journal/TEN_AssetCacheRaw_schema1.csv
```

Dadurch kann ein Patch- oder Minor-Update des Skripts erfolgen, ohne das dauerhafte RAW-Journal künstlich neu zu beginnen. Solange sich das RAW-Schema nicht ändert, bleibt `schema1` bestehen.

### Sichtbare HU-/CO-Dateien

Die sichtbaren Arbeitsdateien tragen weiter die Skriptversion.

Beispiele:

```text
/Library/Logs/KommunalBIT/TEN_AssetCache_Hu_v1.9.1.csv
/Library/Logs/KommunalBIT/TEN_AssetCache_Co_v1.9.1.csv
```

### Sichtbare RAW-Datei

Standardmäßig wird keine sichtbare RAW-Datei mehr geschrieben. Die RAW-Daten liegen dauerhaft im Journal unter Application Support.

Im Skript existiert dafür:

```zsh
EXPORT_VISIBLE_RAW=0
```

Wird dieser Wert bewusst auf `1` gesetzt, kann zusätzlich eine sichtbare RAW-Datei unter `/Library/Logs/KommunalBIT` erzeugt werden. Der Normalbetrieb benötigt das nicht.

---

## Verarbeitungsmodell

Das Skript arbeitet RAW-first.

1. **Startup**
   - Verzeichnisstruktur unter Application Support sicherstellen
   - alte State-Dateien aus `/var/tmp` nach Application Support migrieren
   - Boot-Wechsel erkennen
   - sichtbare HU-/CO-Dateien bei Bedarf aus dem RAW-Journal rekonstruieren

2. **Collect**
   - alle relevanten Systemwerte einmalig im aktuellen Durchlauf erfassen
   - keine getrennten Messungen für RAW, HU oder CO

3. **RAW berechnen**
   - vollständige technische Datenstruktur erzeugen
   - Delta-Werte aus State-Dateien ableiten

4. **RAW-Journal schreiben**
   - RAW-Zeile zuerst dauerhaft ins Journal schreiben
   - Journal ist die kanonische Datenquelle

5. **HU ableiten**
   - menschenlesbare View mit Einheiten, `yes/no`, `n/a` und reduzierten IP-Details

6. **CO ableiten**
   - datensparsame Analyse-View für Copilot/Excel/standortbezogene Auswertung

7. **Sichtbare Dateien schreiben**
   - HU und CO werden unter `/Library/Logs/KommunalBIT` erzeugt oder fortgeschrieben

HU und CO führen keine eigenen Systemabfragen durch. Beide sind Ableitungen aus derselben RAW-Zeile.

---

## Rebuild-Mechanismus

Wenn `/Library/Logs/KommunalBIT` fehlt oder die sichtbaren HU-/CO-Dateien fehlen oder leer sind, baut der Logger diese Dateien aus dem RAW-Journal neu auf.

Das ist der Kern der v1.9.1-Härtung: Wenn ein macOS-Update, ein Neustart oder ein anderes Systemverhalten den sichtbaren Logordner entfernt, bleiben die Daten unter Application Support erhalten.

Typischer Ablauf:

1. `/Library/Logs/KommunalBIT` fehlt.
2. Logger startet über LaunchDaemon.
3. Logger legt den sichtbaren Ordner neu an.
4. Logger rekonstruiert HU und CO aus dem RAW-Journal.
5. Logger schreibt anschließend die aktuelle RAW-Zeile ins Journal und aktualisiert die sichtbaren HU-/CO-Dateien.

Der Rebuild ist bewusst deterministisch. Er verwendet das RAW-Journal als Quelle, nicht Live-Statefiles. Leere CSV-Felder bleiben erhalten.

---

## Automatische Archivierung bei iOS-/iPadOS-Versionswechsel

Der Logger erkennt Änderungen der aktuell relevanten iOS-/iPadOS-Versionen über Apple GDMF.

Wenn sich `iOSUpdates` ändert, archiviert der Logger die aktuellen sichtbaren HU-/CO-Dateien unter:

```text
/Library/Application Support/KommunalBIT/AssetCacheLogger/archive/
```

Dabei gilt:

- Das RAW-Journal bleibt unverändert.
- HU und CO werden als sichtbare Dateien neu begonnen.
- Ein Manifest wird im Archivordner abgelegt.
- `visible_epoch_<PREFIX>.tsv` wird gesetzt, damit ein späterer Rebuild nur den neuen sichtbaren Abschnitt rekonstruiert.
- Die neue iOS-Version wird in HU für ein Sichtfenster mehrfach angezeigt, damit der Versionswechsel beim Öffnen der Datei auffällt.

Die alte Archivlogik unter `/Library/Logs/KommunalBIT/Archiv` wird nicht mehr verwendet.

---

## Manuelle Archivierung über Relution

Das manuelle Archivierungsskript `scripts/archive_assetcache_logs.sh` hat eine bewusst enge Aufgabe.

Es tut genau dies:

1. LaunchDaemon stoppen und deaktivieren.
2. eventuell noch laufenden Loggerprozess beenden.
3. aktuelle sichtbare HU-/CO-Dateien aus `/Library/Logs/KommunalBIT` nach `/Library/Application Support/KommunalBIT/AssetCacheLogger/archive/` verschieben.
4. nicht neu starten.

Es tut ausdrücklich nicht:

- keine neuen Messdaten erzeugen
- keinen Rebuild auslösen
- keine Statusdateien erzeugen
- das RAW-Journal verschieben, kopieren, löschen oder zurücksetzen
- den Daemon danach wieder starten

Visuelle Kontrolle nach der Archivierung:

```text
/Library/Logs/KommunalBIT/
```

enthält keine aktuellen HU-/CO-Dateien mehr.

```text
/Library/Application Support/KommunalBIT/AssetCacheLogger/archive/
```

enthält die verschobenen HU-/CO-Dateien.

Der Neustart erfolgt erst wieder durch das Deploy-Skript oder eine bewusste manuelle Aktivierung des LaunchDaemons.

---

## Deploy über Relution

Das Deploy-Skript `scripts/deploy_assetcache_logger.sh` bringt den Ziel-Mac in den produktiven Zustand.

Aufgaben:

- sichtbaren Arbeitsordner unter `/Library/Logs/KommunalBIT` anlegen
- Application-Support-Struktur anlegen
- ACL für den lokalen Benutzer `admin` setzen, damit der Bereich im Finder inspiziert und kopiert werden kann
- `assetcache_logger.sh` von GitHub herunterladen
- Skript nach `/usr/local/bin/assetcache_logger.sh` installieren
- LaunchDaemon-Plist schreiben
- LaunchDaemon explizit aktivieren, bootstrappen und starten
- Workarounds gegen Relution-Dot-Mangling anwenden

Das Deploy-Skript archiviert keine bestehenden Monitoringdaten. Archivierung ist Aufgabe des separaten Archivierungsskripts.

Wichtig: Wenn vorher das Archivierungsskript gelaufen ist, ist der LaunchDaemon absichtlich deaktiviert. Das Deploy-Skript aktiviert ihn wieder.

---

## Relution-Dot-Mangling

In Relution wurden in der Praxis Punkte in bestimmten Strings oder Dateinamen zu Unterstrichen verändert. Betroffen waren unter anderem:

- `.plist`
- `.sh`
- `.out`
- `.err`
- `.conf`
- `raw.githubusercontent.com`

Die Relution-facing Skripte bauen solche Teile deshalb zur Laufzeit über eine `DOT`-Variable zusammen, zum Beispiel:

```zsh
DOT="$(printf '\x2e')"
SH_EXT="${DOT}sh"
PLIST_EXT="${DOT}plist"
```

Diese Umgehung ist Absicht und soll nicht „vereinfacht“ werden.

---

## Standortkonfiguration `schulen.conf`

Die Datei:

```text
/etc/kommunalbit/schulen.conf
```

enthält die bekannte relevante SuS-iPad-Gesamtzahl je Standort.

Format:

```text
KÜRZEL<TAB>ANZAHL
```

Beispiel:

```text
TEN	99
GSW	173
ASGS	122
```

Diese Werte werden für `ClientsCnt` verwendet. In RAW und CO erscheint `ClientsCnt` als `aktiv/gesamt`, wenn die Gesamtzahl bekannt ist. In HU wird daraus ein Prozentwert.

Die produktive Standorttabelle wird nicht im öffentlichen Repository gepflegt. Sie stammt aus interner Relution-Auswertung und wird im produktiven Relution-Deploy-Skript gepflegt oder ergänzt. Das Repository kann Beispielwerte oder eine Beispielkonfiguration enthalten, aber keine verbindliche produktive Standortliste.

---

## CSV-Ausgaben

### RAW-Journal

Das RAW-Journal enthält die vollständige technische Datenbasis.

Eigenschaften:

- dauerhaft unter Application Support
- ISO-8601-Zeitstempel mit Zeitzone
- Zahlenwerte als Bytes oder Integer
- leere Felder für nicht verfügbare Werte
- IP-Adressen können enthalten sein
- technische Grundlage für Rebuild und tiefe Diagnose

Normaler Pfad:

```text
/Library/Application Support/KommunalBIT/AssetCacheLogger/journal/<PREFIX>_AssetCacheRaw_schema1.csv
```

### HU-Datei

HU steht für Human Readable.

Eigenschaften:

- sichtbar unter `/Library/Logs/KommunalBIT`
- für schnelle Sichtprüfung durch Menschen
- lesbare Einheiten wie `GB`, `MB`, `ms`, `dB`
- `yes/no` statt 0/1 bei Erreichbarkeit
- IP-Details werden in menschenlesbarer Form reduziert
- nicht primär für maschinelle Auswertung gedacht

Beispiel:

```text
/Library/Logs/KommunalBIT/TEN_AssetCache_Hu_v1.9.1.csv
```

### CO-Datei

CO ist die datensparsame Analyse-View.

Eigenschaften:

- sichtbar unter `/Library/Logs/KommunalBIT`
- kein voller Hostname
- keine IP-Adressen
- flache Struktur
- numerische Werte möglichst als Zahlen
- geeignet für Microsoft Copilot, Excel und standortbezogene Auswertung

Beispiel:

```text
/Library/Logs/KommunalBIT/TEN_AssetCache_Co_v1.9.1.csv
```

Für KI-gestützte Auswertungen ist CO das bevorzugte Format.

---

## CO-CSV-Felder

Die CO-Datei enthält 14 Spalten.

| Feld | Format | Nutzen |
|---|---|---|
| `SiteCode` | Standortkürzel | Join mit Relution-Export; kein voller Hostname |
| `Timestamp` | ISO 8601 mit Zeitzone | zeitliche Einordnung |
| `PeerCnt` | Integer oder leer | Anzahl erkannter Cache-Peers |
| `ClientsCnt` | `aktiv/gesamt` oder `aktiv` | Aktivitätsverhältnis im letzten Zeitfenster |
| `iOSUpdates` | Versionsliste | aktuell relevante iOS-/iPadOS-Versionen |
| `iOSBytes` | Bytes | iOS-Softwareanteil im Cache |
| `ServedDelta` | Bytes | im Intervall an Clients ausgelieferte Daten |
| `OriginDelta` | Bytes | im Intervall vom Origin/CDN nachgeladene Daten |
| `CacheUsed` | Bytes | belegter Cache |
| `CachePr` | 0–100 oder leer | Cache-Druckindikator |
| `DNSRes` | 0 / 1 | DNS-Auflösung für Apple-Update-Infrastruktur |
| `AppleReach` | 0 / 1 | Apple-CDN erreichbar |
| `AppleTTFB` | Millisekunden | Time to First Byte zu Apple |
| `WiFiSNR` | dB oder leer | WLAN-Signalqualität, relevant bei WLAN-Betrieb |

Nicht enthalten in CO:

- voller Hostname
- konkrete IP-Adressen
- `TotalsSince`
- kumulative Totals (`TotReturned`, `TotOrigin`)
- Interface-IP-Werte `EN0`, `EN1`
- `GatewayIP`
- `DefaultIf`
- `WifiNoise`
- `WifiCCA`

---

## RAW-/HU-Felder

RAW und HU verwenden dieselbe 23-Spalten-Struktur. RAW enthält technische Werte, HU enthält lesbare Ableitungen.

| Feld | RAW | HU | Interpretation |
|---|---|---|---|
| `Hostname` | voller Hostname | voller Hostname | Gerät, auf dem der Logger läuft |
| `Timestamp` | ISO 8601 mit Zeitzone | `YYYY-MM-DD HH:MM:SS` | Zeitpunkt der Messung |
| `TotalsSince` | ISO 8601 oder leer | lesbarer Zeitpunkt oder leer | Startzeit der aktuellen Cache-Zähler-Epoche |
| `Peers` | Peer-IP-Liste, `;`-getrennt | Anzahl Peers | andere Caches im Netz |
| `ClientsCnt` | `aktiv/gesamt` oder `aktiv` | Prozentwert oder aktiv | aktive Cache-Clients im letzten Zeitfenster |
| `iOSUpdates` | Versionsliste | sichtbares Updatefenster oder leer/`n/a` | aktuell relevante iOS-/iPadOS-Versionen |
| `iOSBytes` | Bytes | KB/MB/GB/TB | iOS-Softwareanteil im Cache |
| `TotReturned` | Bytes kumulativ | KB/MB/GB/TB | seit `TotalsSince` an Clients geliefert |
| `TotOrigin` | Bytes kumulativ | KB/MB/GB/TB | seit `TotalsSince` vom Origin geladen |
| `ServedDelta` | Bytes | KB/MB/GB/TB | im Intervall an Clients geliefert |
| `OriginDelta` | Bytes | KB/MB/GB/TB | im Intervall vom Origin geladen |
| `CacheUsed` | Bytes | KB/MB/GB/TB | aktuell belegter Cache |
| `CachePr` | 0–100 oder leer | 0–100, Default 0 | Cache Pressure der letzten Stunde |
| `EN0` | `down`, `noip` oder IP | `down`, `noip` oder `up` | Zustand Ethernet |
| `EN1` | `down`, `noip` oder IP | `down`, `noip` oder `up` | Zustand WLAN |
| `GatewayIP` | IP oder leer | `yes`/`no` | Default Gateway vorhanden |
| `DefaultIf` | Interface | Interface | Default Route Interface |
| `DNSRes` | 0 / 1 | `yes`/`no` | DNS-Auflösung für `swcdn.apple.com` |
| `AppleReach` | 0 / 1 | `yes`/`no` | Apple-CDN per HTTPS erreichbar |
| `AppleTTFB` | ms | `n/a` oder `123ms` | Antwortzeit Apple-CDN |
| `WiFiSNR` | dB oder leer | `n/a` oder `XdB` | Signalqualität bei WLAN |
| `WifiNoise` | dBm oder leer | `n/a` oder `XdBm` | Rauschpegel bei WLAN |
| `WifiCCA` | Prozent oder leer | `n/a` oder `X%` | Channel-Auslastung bei WLAN |

---

## Interpretation wichtiger Felder

### `ClientsCnt`

`ClientsCnt` ist ein Aktivitätsfenster, keine Compliance-Quote.

Beispiel:

```text
5/171
```

bedeutet: Im betrachteten Zeitfenster wurden fünf unterschiedliche interne Client-IP-Adressen im Cache-Log erkannt, bei einem bekannten relevanten Standortbestand von 171 SuS-iPads.

Niedrige Werte können bedeuten:

- wenige Geräte waren im WLAN aktiv
- Geräte waren ausgeschaltet oder leer
- Updatezeitpunkt passte nicht zur Nutzung
- der Standort nutzt Geräte organisatorisch anders
- Log-Fenster war schlicht ruhig

Niedrige Werte bedeuten nicht automatisch, dass der Cache defekt ist.

### `ServedDelta` und `OriginDelta`

Diese beiden Werte sind die wichtigsten Aktivitätsindikatoren.

- `ServedDelta`: Daten, die der Cache im Intervall an Clients ausgeliefert hat
- `OriginDelta`: Daten, die der Cache im Intervall vom Apple Origin/CDN nachgeladen hat

Typische Lesart:

- hoher `ServedDelta`, niedriger `OriginDelta`: Cache wirkt gut
- hoher `OriginDelta`: Cache lädt gerade nach oder hat Inhalte noch nicht lokal
- beide niedrig: wenig Aktivität oder keine Update-/Nutzungswelle

### `DNSRes`, `AppleReach`, `AppleTTFB`

Diese Werte zeigen, ob der Standort Apple grundsätzlich erreichen kann.

- `DNSRes=1` bzw. `yes`: Name wird aufgelöst
- `AppleReach=1` bzw. `yes`: HTTPS-Verbindung zu Apple funktioniert
- `AppleTTFB`: grobe Antwortzeit bis zum ersten Byte

Richtwerte für `AppleTTFB`:

- unter 150 ms: sehr gut
- 150–500 ms: unauffällig bis brauchbar
- über 500 ms: beobachten
- leer oder `n/a`: keine valide Messung

Einzelwerte sind weniger wichtig als Muster über mehrere Intervalle.

### `CachePr`

`CachePr` steht für `MaxCachePressureLast1Hour`.

Interpretation:

- dauerhaft niedrig: Cache hat ausreichend Platz
- steigend oder hoch: Cache könnte unter Druck stehen
- leer in RAW / `0` in HU: Wert wurde nicht geliefert oder nicht erkannt

Ein leerer oder niedriger Wert ist nicht automatisch ein Problem.

### `Peers`

Peers sind andere Apple Content Caches im selben relevanten Netz.

Viele oder wechselnde Peers können die Interpretation erschweren, weil Last und Requests zwischen Caches verteilt werden. In CO wird deshalb nur die Anzahl der Peers ausgegeben, nicht die IP-Liste.

### WLAN-Werte

WLAN-Werte sind vor allem relevant, wenn der Mac mini nicht per LAN angebunden ist.

`WiFiSNR`:

- ab 30 dB: sehr gut
- 20–29 dB: brauchbar
- 10–19 dB: kritisch beobachten
- unter 10 dB: häufig problematisch

`WifiNoise`:

- etwa -90 bis -100 dBm: gut
- um -85 dBm: beobachten
- -80 dBm oder höher: häufig auffällig

`WifiCCA` zeigt die Kanalbelegung. Hohe Werte können auf ein stark ausgelastetes Funkumfeld hinweisen.

---

## Schnelle Betriebsprüfung

### LaunchDaemon prüfen

```zsh
sudo launchctl print system/de.kommunalbit.assetcachelogger | head -80
```

Wichtig:

- `path` zeigt auf `/Library/LaunchDaemons/de.kommunalbit.assetcachelogger.plist`
- `program` zeigt auf `/usr/local/bin/assetcache_logger.sh`
- `run interval = 900 seconds`
- `last exit code = 0` ist ideal
- `state = not running` ist bei einem Intervall-Job nicht automatisch falsch

Der Logger läuft kurz, schreibt seine Zeile und beendet sich wieder. Er muss nicht dauerhaft als Prozess laufen.

### Syntax prüfen

```zsh
sudo zsh -n /usr/local/bin/assetcache_logger.sh
```

Erwartung: keine Ausgabe.

### Speicherorte prüfen

```zsh
sudo find "/Library/Application Support/KommunalBIT/AssetCacheLogger" -maxdepth 3 -print
sudo find /Library/Logs/KommunalBIT -maxdepth 2 -print
```

Erwartung:

- Application Support enthält `journal`, `state`, `boot`, `archive`
- `/Library/Logs/KommunalBIT` enthält aktuelle HU-/CO-Dateien
- kein `/Library/Logs/KommunalBIT/Archiv` im Normalbetrieb

### Zeilenzahlen prüfen

Beispiel für Standort `TEN`:

```zsh
sudo wc -l "/Library/Application Support/KommunalBIT/AssetCacheLogger/journal/TEN_AssetCacheRaw_schema1.csv"
sudo wc -l /Library/Logs/KommunalBIT/TEN_AssetCache_Hu_v1.9.1.csv
sudo wc -l /Library/Logs/KommunalBIT/TEN_AssetCache_Co_v1.9.1.csv
```

Wenn kein `visible_epoch` gesetzt ist und kein Rebuild/Schreibvorgang gerade läuft, sollten die Zeilenzahlen übereinstimmen.

Nach automatischer iOS-Wechsel-Archivierung kann das sichtbare HU/CO nur den Abschnitt seit `visible_epoch` zeigen; das RAW-Journal bleibt länger.

### Statuslog prüfen

```zsh
sudo tail -80 "/Library/Application Support/KommunalBIT/AssetCacheLogger/status.log"
```

Typische gute Einträge:

```text
INFO start v1.9.1 schema=schema1 host=TEN-Mac-Mini-Caching-Server prefix=TEN
INFO RAW-Zeile ins Journal geschrieben ts=...
INFO HU aus RAW-Journal wiederhergestellt (... Datenzeilen)
INFO CO aus RAW-Journal wiederhergestellt (... Datenzeilen)
```

---

## Test: sichtbaren Logordnerverlust simulieren

Dieser Test prüft den zentralen v1.9.1-Schutzmechanismus.

```zsh
sudo mv /Library/Logs/KommunalBIT "/Library/Logs/KommunalBIT_TESTWEG_$(date +%Y%m%d_%H%M%S)"
sudo /usr/local/bin/assetcache_logger.sh

sudo wc -l "/Library/Application Support/KommunalBIT/AssetCacheLogger/journal/TEN_AssetCacheRaw_schema1.csv"
sudo wc -l /Library/Logs/KommunalBIT/TEN_AssetCache_Hu_v1.9.1.csv
sudo wc -l /Library/Logs/KommunalBIT/TEN_AssetCache_Co_v1.9.1.csv
sudo tail -40 "/Library/Application Support/KommunalBIT/AssetCacheLogger/status.log"
```

Erwartung:

- `/Library/Logs/KommunalBIT` wird neu angelegt.
- HU und CO werden aus dem RAW-Journal rekonstruiert.
- Der Logger schreibt anschließend eine neue RAW-Zeile.
- Am Ende sind Journal und sichtbare Dateien konsistent.

Der verschobene `TESTWEG`-Ordner ist nur Testmaterial und kann nach Abschluss entfernt werden.

---

## Typischer Betriebsablauf bei Versionswechsel

1. Archivierungsskript über Relution ausführen.
2. Visuell prüfen: HU/CO sind aus `/Library/Logs/KommunalBIT` verschwunden und liegen unter Application Support/archive.
3. Deploy-Skript über Relution ausführen.
4. Prüfen: LaunchDaemon ist geladen, Logger läuft erfolgreich.
5. Nach erstem Lauf prüfen: HU/CO werden unter `/Library/Logs/KommunalBIT` neu erzeugt.
6. Optional: Rebuild-Test nur auf Pilotstandort durchführen.

Das Archivierungsskript startet den Daemon bewusst nicht neu. Das Deploy-Skript übernimmt die Wiederaktivierung.

---

## Datenschutz und Datenminimierung

Das Projekt verarbeitet technische Betriebsdaten zur standortbezogenen Einordnung der iOS-/iPadOS-Updatefähigkeit. Ziel ist nicht Kontrolle einzelner Personen oder einzelner Geräte, sondern bessere Updatefähigkeit, Resilienz und Risikoreduktion.

Wichtige Grundsätze:

- CO enthält keine IP-Adressen.
- CO enthält keinen vollen Hostnamen.
- CO ist das bevorzugte Format für externe oder KI-gestützte Auswertung.
- RAW bleibt intern und enthält technische Details.
- Relution-Exporte müssen vor Auswertung datensparsam bereinigt werden.
- LDG-Auswertungen sind eine eigene, sensiblere Ebene und dürfen nicht unreflektiert mit SuS-Flottenstatistik vermischt werden.

---

## Umgang mit Standorten ohne Caching-Server

Standorte mit weniger als 32 iPads haben normalerweise keinen Caching-Server. Für solche Standorte gibt es folglich keine AssetCache-Monitoringdaten. Das ist keine Monitoring-Anomalie.

Diese Standorte müssen in der Auswertung anders behandelt werden:

- kein Cachelog erwartet
- keine `ClientsCnt`-Vergleichswerte aus AssetCache
- Bewertung primär über Relution-/MDM-Daten und organisatorischen Kontext

---

## Bekannte Grenzen

Das Monitoring zeigt technische Indizien, keine vollständige Wahrheit.

Beispiele:

- `ClientsCnt` zeigt aktive Cache-Clients im Logfenster, nicht alle eingeschalteten Geräte.
- Ein ruhiges Zeitfenster kann organisatorisch normal sein.
- Peers können Last verteilen und die Standortinterpretation erschweren.
- Apple-CDN-Werte sind Momentaufnahmen.
- WLAN-Werte sind nur relevant, wenn der Mac mini tatsächlich per WLAN arbeitet.
- RAW-Journal und sichtbare HU/CO können nach einer bewussten iOS-Wechsel-Archivierung unterschiedliche historische Reichweiten haben.

Die Daten müssen immer im Standortkontext interpretiert werden.

---

## Kurzfassung für Betrieb und Fehlersuche

Wenn etwas merkwürdig aussieht, zuerst diese Reihenfolge prüfen:

1. Läuft der LaunchDaemon grundsätzlich?

   ```zsh
   sudo launchctl print system/de.kommunalbit.assetcachelogger | head -80
   ```

2. Ist das Skript syntaktisch gültig?

   ```zsh
   sudo zsh -n /usr/local/bin/assetcache_logger.sh
   ```

3. Gibt es ein dauerhaftes RAW-Journal?

   ```zsh
   sudo find "/Library/Application Support/KommunalBIT/AssetCacheLogger/journal" -maxdepth 1 -print
   ```

4. Gibt es sichtbare HU-/CO-Dateien?

   ```zsh
   sudo find /Library/Logs/KommunalBIT -maxdepth 1 -name "*AssetCache*.csv" -print
   ```

5. Was sagt das Statuslog?

   ```zsh
   sudo tail -80 "/Library/Application Support/KommunalBIT/AssetCacheLogger/status.log"
   ```

6. Falls `/Library/Logs/KommunalBIT` fehlt: Rebuild testen.

   ```zsh
   sudo /usr/local/bin/assetcache_logger.sh
   ```

Die zentrale Denkregel ab v1.9.1 lautet:

**Application Support ist die dauerhafte Wahrheit. `/Library/Logs/KommunalBIT` ist sichtbare Ausgabe.**
