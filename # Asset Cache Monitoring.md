# Asset Cache Monitoring – KommunalBIT

Monitoring und Logging des Apple Content Caching auf Mac Minis in Schulen.  
**Aktuelle Version: 1.6.1**

---

## Motivation

In einer Umgebung mit vielen schulisch genutzten iPads ist Apple Content Caching ein wichtiger technischer Baustein, um Last, Bandbreite und Updateverteilung sinnvoll zu steuern. Da Verzögerungen bei der Installation aktueller iOS-Updates ein Sicherheitsrisiko darstellen, ist es das Ziel, an jeder Schule die bestmöglichen Voraussetzungen zu schaffen, um so viele Geräte wie möglich zeitnah zu aktualisieren.

Die entscheidenden Fragen:

- Wird der Cache tatsächlich genutzt?
- Wird er zum richtigen Zeitpunkt genutzt?
- Passt die Aktivität zur bekannten Geräteanzahl eines Standorts?
- Deuten Auffälligkeiten auf Infrastruktur- oder Konfigurationsprobleme hin – oder liegt die Ursache eher vor Ort, etwa beim Handling der iPads bzgl. Ladezustand und WLAN-Erreichbarkeit?

Der Schwerpunkt liegt nicht auf dem reinen Sammeln von Zahlen, sondern auf datenbasierter Einordnung. Das Ziel ist Risikoreduktion und Resilienz – nicht Kontrolle oder Schuldzuweisung.

---

## Funktionsweise

Das Skript läuft auf einem Mac Mini mit aktiviertem Apple Content Caching und wird alle **15 Minuten** durch einen LaunchDaemon ausgeführt. Es liest Metriken aus `AssetCacheManagerUtil`, ergänzt sie um Netzwerk- und WLAN-Diagnosewerte und schreibt sie in zwei CSV-Dateien.

---

## Ausgabeformat

Pro Host werden zwei parallele CSV-Dateien geschrieben, jeweils unter `/Library/Logs/KommunalBIT/`:

| Datei | Zweck |
|---|---|
| `<HOST>_RAW.csv` | Maschinenlesbar – reine Zahlenwerte, leere Felder, ISO-8601-Zeitstempel mit Zeitzone |
| `<HOST>_HU.csv` | Menschenlesbar – Einheiten (GB, %, ms, dB), `n/a` für fehlende Werte |

**Grundregel:** RAW ist die fachliche Quelle. HU ist die komfortable Ableitung für die Sichtprüfung.

Bei Erkennung einer neuen iOS-Version werden die bisherigen CSV-Dateien automatisch in `/Library/Logs/KommunalBIT/Archiv/` verschoben.

---

## CSV-Felder (23 Spalten)

### Identifikation & Zeit

| Feld | RAW | HU | Beschreibung |
|---|---|---|---|
| `Hostname` | Hostname des Mac Mini | = RAW | Vollständiger Hostname laut `scutil` |
| `Timestamp` | ISO-8601 mit Zeitzone (`2026-04-02T10:15:00+02:00`) | Lokal ohne Offset (`2026-04-02 10:15:00`) | Zeitpunkt der Messung |
| `TotalsSince` | Epochensekunden (`1743588000`) | Lesbares Datum (`2026-02-01`) | Zeitpunkt, seit dem die kumulativen Zähler laufen (Neustart des Caching-Dienstes) |

### Cache-Aktivität

| Feld | RAW | HU | Beschreibung |
|---|---|---|---|
| `TotReturned` | Bytes (Integer) | z. B. `142.3 GB` | Kumulativ: gesamte an Clients ausgelieferte Datenmenge seit `TotalsSince` |
| `TotOrigin` | Bytes (Integer) | z. B. `18.7 GB` | Kumulativ: gesamte von Apple-Servern geladene Datenmenge seit `TotalsSince` |
| `ServedDelta` | Bytes (Integer) | z. B. `1.2 GB` | **Im letzten Intervall** an Clients ausgeliefert (Differenz zum vorherigen Lauf) |
| `OriginDelta` | Bytes (Integer) | z. B. `240 MB` | **Im letzten Intervall** von Apple-Servern geladen (Differenz zum vorherigen Lauf) |
| `CacheUsed` | Bytes (Integer) | z. B. `85.4 GB` | Aktuell belegter Cache-Speicher |
| `CachePr` | Integer (0–100) | z. B. `42%` | `MaxCachePressureLast1Hour` – Verdrängungsdruck im Cache der letzten Stunde |
| `iOSBytes` | Bytes (Integer) | z. B. `74.2 GB` | Im Cache gehaltene Datenmenge für iOS-/iPadOS-Software |

### Clients

| Feld | RAW | HU | Beschreibung |
|---|---|---|---|
| `ClientsCnt` | `aktiv/gesamt` (z. B. `4/122`) oder nur `aktiv` wenn Standort unbekannt | Prozentsatz (z. B. `3.3%`) oder nur `aktiv` wenn Standort unbekannt | Aktive Clients der letzten ~16 Minuten aus dem Systemlog, bezogen auf den bekannten Gerätebestand des Standorts aus `schulen.conf` |

### iOS-Updates

| Feld | RAW | HU | Beschreibung |
|---|---|---|---|
| `iOSUpdates` | Versionsliste (z. B. `18.4;18.3.2`) | = RAW, aber für 19 Zeilen nach einer Änderung leer (Rauschunterdrückung) | Aktuelle iOS-/iPadOS-Versionen laut Apple GDMF API; Änderungen lösen CSV-Archivierung aus |

### Peers

| Feld | RAW | HU | Beschreibung |
|---|---|---|---|
| `Peers` | Semikolon-getrennte IP-Adressen (z. B. `10.1.2.3;10.1.2.4`) | Anzahl (z. B. `2`) | Andere erkannte Asset-Cache-Server im lokalen Netz |

### Netzwerk

| Feld | RAW | HU | Beschreibung |
|---|---|---|---|
| `EN0` | IP-Adresse oder Status (`down` / `noip` / `active`) | = RAW | Netzwerkinterface en0 (in der Regel LAN) |
| `EN1` | IP-Adresse oder Status | = RAW | Netzwerkinterface en1 (in der Regel WLAN) |
| `GatewayIP` | IP-Adresse des Default-Gateways | = RAW | Aus `route -n get default` |
| `DefaultIf` | Interface-Name (z. B. `en0`) | = RAW | Aktuell genutztes Default-Interface |
| `DNSRes` | `1` (erfolgreich) / `0` (fehlgeschlagen) | `yes` / `no` | DNS-Auflösung von `swcdn.apple.com` via `dscacheutil` |
| `AppleReach` | `1` / `0` | `yes` / `no` | HTTPS-Erreichbarkeit des Apple CDN (HTTP 2xx–4xx = erreichbar) |
| `AppleTTFB` | Millisekunden (Integer) | z. B. `38ms` | Time To First Byte gegen Apple CDN; leer wenn nicht erreichbar |

### WLAN (via `wdutil`)

| Feld | RAW | HU | Beschreibung |
|---|---|---|---|
| `WiFiSNR` | Integer (dB) | z. B. `42dB` | Signal-Rausch-Abstand (RSSI minus Noise); höher = besser |
| `WifiNoise` | Integer (dBm, negativ) | z. B. `-92dBm` | Rauschpegel; typisch –95 bis –75 dBm |
| `WifiCCA` | Integer (0–100) | z. B. `18%` | Clear Channel Assessment – Kanalauslastung; hohe Werte deuten auf WLAN-Überlastung hin |

> WLAN-Felder sind leer, wenn `wdutil` nicht verfügbar ist oder das WLAN-Interface nicht aktiv ist.

---

## Standortkonfiguration (`schulen.conf`)

Das Skript liest die Zuordnung von Schulkürzeln zu iPad-Anzahl aus:

```
/etc/kommunalbit/schulen.conf
```

**Format:** Eine Zeile pro Schule, Kürzel und Anzahl durch **Tab** getrennt. Zeilen mit `#` werden ignoriert.

```
# Beispiel
EIC	133
BRL	80
GSW	171
```

Das Kürzel wird aus dem Hostnamen extrahiert (erster Teil vor `-`). Fehlt die Datei oder ist ein Standort nicht eingetragen, wird `ClientsCnt` ohne Prozentwert ausgegeben.

**Diese Datei ist nicht im Repository** – sie wird über Relution MDM auf die Mac Minis verteilt und enthält keine öffentlich veröffentlichungswürdigen Informationen.

---

## Betriebsartefakte

| Pfad | Beschreibung |
|---|---|
| `/usr/local/bin/assetcache_logger.sh` | Monitoring-Skript |
| `/Library/LaunchDaemons/de.kommunalbit.assetcachelogger.plist` | LaunchDaemon (900 s Intervall) |
| `/Library/Logs/KommunalBIT/` | CSV-Ausgabe |
| `/Library/Logs/KommunalBIT/Archiv/` | Archiv bei iOS-Versionsänderung |
| `/etc/kommunalbit/schulen.conf` | Schultabelle (nicht im Repo) |
| `/var/tmp/assetcache_logger_state.tsv` | State-Datei für Delta-Berechnung |
| `/var/tmp/assetcache_iosupdates_hu_state.tsv` | State-Datei für HU-Sichtbarkeitsblock |
| `/var/tmp/assetcache_gdmf_state.tsv` | GDMF-Cache (SHA256 + letzte Versionsliste) |
| `/var/tmp/assetcache_gdmf_debug.log` | GDMF-Debuglog (max. 1000 Zeilen) |
| `/var/tmp/assetcache_logger.out` / `.err` | stdout/stderr des LaunchDaemon |

---

## Repository-Inhalt

| Datei | Beschreibung |
|---|---|
| `AssetCache_Monitoring_1.6.1.sh` | Hauptskript |
| `deploy_assetcache_logger.sh` | Deploy-Vorlage für Relution (ohne Schultabelle) |
| `uninstall_assetcache_logger.sh` | Deinstaller |
| `LaunchDaemon.txt` | LaunchDaemon-plist als Referenz |
| `BefehIe zum Installieren.txt` | Manuelle Installationsbefehle als Referenz |
| `README.md` | Kurzübersicht für GitHub |
| `# Asset Cache Monitoring.md` | Diese Datei |

---

## Deployment via Relution MDM

### Reihenfolge

1. **Deinstallieren** (`uninstall_assetcache_logger.sh`) auf dem Zielgerät ausführen  
   → Prüfen: `cat /var/tmp/assetcache_uninstall.log` → `RESULT=OK`

2. **Installieren** (Relution-Version von `deploy_assetcache_logger.sh`, ergänzt um `schulen.conf`-Heredoc in Schritt 3)  
   → Prüfen: `cat /var/tmp/assetcache_deploy.log` → `Deployment complete.`

3. **Erste CSV-Ausgabe** erscheint nach dem ersten Lauf (bis zu 15 Minuten)  
   → Prüfen: `ls /Library/Logs/KommunalBIT/`

### Bekannter Relution-Bug

Relution ersetzt in bestimmten String-Mustern Punkte durch Unterstriche:  
`raw.githubusercontent.com` → `raw_githubusercontent.com`

Das Deploy-Skript enthält bereits einen Workaround (`printf '\x2e'`). Beim Bearbeiten des Scripts in Relution immer den Deploy-Log auf die korrekte URL prüfen.

Gleiches gilt für Dateinamen mit Punkten (z. B. `.csv` → `_csv`), was in früheren Script-Versionen zu falsch benannten CSV-Dateien geführt hat.

---

## Wichtige Messgrößen für die Praxis

| Metrik | Aussage |
|---|---|
| `ServedDelta` hoch, `OriginDelta` niedrig | Cache wird gut genutzt – Geräte holen Updates lokal |
| `ServedDelta` und `OriginDelta` beide hoch | Cache lädt aktiv nach – Update-Welle läuft gerade |
| `ServedDelta` ≈ 0 | Keine Cache-Nutzung im Intervall – Geräte nicht aktiv oder nicht im WLAN |
| `CachePr` > 50 | Cache unter Speicherdruck – ggf. Cache-Größe anpassen |
| `ClientsCnt` weit unter Erwartung | Geräte nicht aktiv, nicht am Laden oder nicht im WLAN |
| `AppleReach` = 0 | Keine Verbindung zu Apple CDN – Netzwerkproblem prüfen |
| `WifiCCA` > 50 % | WLAN-Kanal überlastet – lokales WLAN-Problem |
| `Peers` = 0 | Kein Redundanz-Cache im Netz vorhanden |

---

## Versionierung

| Version | Änderung |
|---|---|
| 1.6.0 | Initiale Version mit vollständigem CSV-Schema (23 Felder) |
| 1.6.1 | Schultabelle aus Skript ausgelagert nach `/etc/kommunalbit/schulen.conf` |
