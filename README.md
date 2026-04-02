# AssetCache Monitoring – KommunalBIT

Monitoring und Logging des Apple Content Caching auf Mac Minis in Schulen.

Das Skript erfasst alle 15 Minuten relevante Metriken des Content Caching und schreibt sie in zwei CSV-Dateien (maschinenlesbar und menschenlesbar). Ziel ist es, Verzögerungen bei iOS-/iPadOS-Updates datenbasiert einordnen zu können – ob die Ursache technischer oder organisatorischer Natur ist.

---

## Dateien in diesem Repository

| Datei | Beschreibung |
|---|---|
| `AssetCache_Monitoring_1.6.1.sh` | Hauptskript – erfasst Metriken und schreibt CSV-Dateien |
| `deploy_assetcache_logger.sh` | Deploy-Skript für Relution MDM |
| `uninstall_assetcache_logger.sh` | Deinstaller – entfernt alle installierten Dateien sauber |
| `LaunchDaemon.txt` | Referenz: LaunchDaemon-plist (wird vom Deploy-Skript automatisch geschrieben) |
| `BefehIe zum Installieren.txt` | Referenz: manuelle Installationsbefehle |

> **Nicht im Repository:** Die Schultabelle (`schulen.conf`) mit Schulkürzeln und iPad-Anzahl pro Standort. Diese wird über Relution als eingebettetes Heredoc auf die Mac Minis verteilt und lokal unter `/etc/kommunalbit/schulen.conf` abgelegt.

---

## Was das Skript erfasst

- **Cache-Metriken:** TotReturned, TotOrigin, ServedDelta, OriginDelta, CacheUsed, CachePr
- **Clients:** Aktive Geräte im letzten Intervall, optional als Prozentsatz des bekannten Gerätebestands
- **Netzwerk:** Interfacestatus (EN0/EN1), GatewayIP, DefaultInterface, DNS-Resolve-Check
- **Apple-Erreichbarkeit:** HTTPS-Erreichbarkeit + TTFB gegen Apple CDN
- **WLAN:** RSSI, Noise, Channel Utilization (CCA)
- **Peer-Erkennung:** Andere Cache-Server im Netz
- **iOS-Updates:** Aktuelle iOS-/iPadOS-Versionen via Apple GDMF API

### Ausgabeformat

Zwei parallele CSV-Dateien pro Host unter `/Library/Logs/KommunalBIT/`:

| Datei | Zweck |
|---|---|
| `*_RAW.csv` | Maschinenlesbar – reine Zahlenwerte, ISO-8601-Zeitstempel, leere Felder statt Platzhalter |
| `*_HU.csv` | Menschenlesbar – Einheiten (GB, %, ms), formatierte Werte, für schnelle Sichtprüfung |

---

## Deployment via Relution MDM

### Voraussetzungen
- Mac Mini mit aktiviertem Apple Content Caching
- Relution MDM mit Root-Ausführungsrecht für Skripte
- Internetverbindung zum Download von `raw.githubusercontent.com`

### Ablauf

**1. Deinstallieren (vor Erstinstallation oder Update)**

`uninstall_assetcache_logger.sh` als Relution-Skript deployen.  
Ergebnis prüfen: `cat /var/tmp/assetcache_uninstall.log`

**2. Installieren**

Das Relution-Script basiert auf `deploy_assetcache_logger.sh`, ergänzt um die Schultabelle als Heredoc in Schritt 3 (wird nicht auf GitHub veröffentlicht).

Das Skript erledigt automatisch:
- Anlegen der Verzeichnisse `/Library/Logs/KommunalBIT/` und `Archiv/`
- Schreiben von `/etc/kommunalbit/schulen.conf`
- Download von `AssetCache_Monitoring_1.6.1.sh` nach `/usr/local/bin/assetcache_logger.sh`
- Schreiben des LaunchDaemon-Plists
- Starten des Daemons

Ergebnis prüfen: `cat /var/tmp/assetcache_deploy.log`

### Bekannte Eigenheit: Relution-Dot-Bug

Relution ersetzt in bestimmten String-Mustern Punkte durch Unterstriche (z. B. `raw.githubusercontent.com` → `raw_githubusercontent.com`). Das Deploy-Skript enthält bereits einen Workaround (`printf '\x2e'`). Beim Einfügen oder Bearbeiten in Relution daher immer den Deploy-Log prüfen.

---

## Konfigurationsdatei `schulen.conf`

Format: eine Zeile pro Schule, Kürzel und Anzahl durch **Tab** getrennt.

```
# Beispiel
EIC	133
BRL	80
```

Die Datei liegt auf dem Mac Mini unter `/etc/kommunalbit/schulen.conf` und wird vom Monitoring-Skript beim Start eingelesen. Fehlt die Datei, läuft das Skript weiter – `ClientsCnt` wird dann ohne Prozentwert ausgegeben.

---

## Installierte Artefakte (Übersicht)

| Pfad | Beschreibung |
|---|---|
| `/usr/local/bin/assetcache_logger.sh` | Monitoring-Skript |
| `/Library/LaunchDaemons/de.kommunalbit.assetcachelogger.plist` | LaunchDaemon |
| `/Library/Logs/KommunalBIT/` | CSV-Ausgabe |
| `/library/Logs/KommunalBIT/Archiv/` | Archiv bei iOS-Versionsänderung |
| `/etc/kommunalbit/schulen.conf` | Schultabelle (nicht im Repo) |
| `/var/tmp/assetcache_*.tsv` | State-Dateien für Delta-Berechnung |

---

## Version

Aktuell: **1.6.1**
