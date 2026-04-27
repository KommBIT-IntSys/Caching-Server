# AssetCache Monitoring – KommunalBIT

[![ShellCheck](https://github.com/KommBIT-IntSys/Caching-Server/actions/workflows/shellcheck.yml/badge.svg?branch=main)](https://github.com/KommBIT-IntSys/Caching-Server/actions/workflows/shellcheck.yml)

Monitoring und Logging des Apple Content Caching auf Mac Minis in Schulen.

Das Haupt-Skript erfasst alle 15 Minuten relevante Metriken des Content Caching und schreibt sie in drei CSV-Dateien: maschinenlesbar (RAW), menschenlesbar (HU) und datensparsam für KI-gestützte externe Auswertung (CO). Ziel ist es, Verzögerungen bei iOS-/iPadOS-Updates standortbasiert einordnen zu können – ob die Ursachen eher technischer oder organisatorischer Natur sind.

## Rechtlicher Hinweis

Dieses Repository enthält keine personenbezogenen Daten.
Die DSGVO‑konforme Nutzung im Betrieb obliegt der verantwortlichen Stelle.
Urheberrecht, Nutzungsvorbehalt und Haftungsausschluss sind in den Dateien `LICENSE` und `DISCLAIMER` geregelt.

**Aktuelle Version: [1.8.0](CHANGELOG.md)**

> Die öffentliche Hauptlinie des Projekts ist ab Version 1.6.1 bewusst von standortspezifischer Produktivkonfiguration getrennt. Frühere 1.6.4-Artefakte dienten vor allem der Umgehung eines Relution-spezifischen Deploy-Problems.

---

## Repository-Struktur

```
scripts/
  assetcache_logger.sh           – Monitoring-Skript (wird als /usr/local/bin/assetcache_logger.sh installiert)
  deploy_assetcache_logger.sh    – Deploy-Vorlage für Relution MDM
  uninstall_assetcache_logger.sh – Deinstaller
  archive_assetcache_logs.sh     – Archiviert bestehende CSV-Dateien vor Updates
launchd/
  de.kommunalbit.assetcachelogger.plist  – LaunchDaemon-Referenz
docs/
  AssetCache_Monitoring.md       – Vollständige technische Dokumentation
  versioning-policy.md           – Versionierungsrichtlinie
  Befehle_zum_Installieren.txt   – Manuelle Installationsbefehle (Referenz)
config/
  schulen.conf.example           – Beispielformat für die Schultabelle
.github/workflows/
  shellcheck.yml                 – CI: ShellCheck-Linting bei Push/PR auf scripts/**
CHANGELOG.md                     – Änderungshistorie
CLAUDE.md                        – Leitfaden für KI-Assistenten
DISCLAIMER                       – Urheberrecht und Nutzungsvorbehalt
LICENSE                          – Lizenztext
README.md                        – Diese Datei
```

> **Nicht im Repository:** Die produktive Schultabelle (`/etc/kommunalbit/schulen.conf`) mit echten Schulkürzeln und iPad-Zahlen. Sie wird über Relution MDM auf die Mac Minis verteilt.

---

## Was das Skript erfasst

- **Peer-Erkennung:** Andere Cache-Server im Netz
- **Clients:** Aktive Geräte im letzten Intervall, optional als Prozentsatz des bekannten Gerätebestands
- **iOS-Updates:** Aktuelle iOS-/iPadOS-Versionen via Apple GDMF API, gecachte iOS-Datenmenge
- **Cache-Metriken:** TotReturned, TotOrigin, ServedDelta, OriginDelta, CacheUsed, CachePr
- **Netzwerk:** Interfacestatus (EN0/EN1), GatewayIP, DefaultInterface, DNS-Resolve-Check
- **Apple-Erreichbarkeit:** HTTPS-Erreichbarkeit + TTFB gegen Apple CDN
- **WLAN:** SNR, Noise, Channel Utilization (CCA)

Ausgabe: Drei CSV-Dateien pro Host unter `/Library/Logs/KommunalBIT/`:
- `<PREFIX>_AssetCacheRaw_v<VERSION>.csv` – maschinenlesbar, vollständige Rohdaten (intern/technisch)
- `<PREFIX>_AssetCache_Hu_v<VERSION>.csv` – menschenlesbar, mit Einheiten (intern/Sichtprüfung)
- `<PREFIX>_AssetCache_Co_v<VERSION>.csv` – datensparsam, kein voller Hostname, keine IPs (KI-/externe Auswertung)

**RAW ist die primäre technische Datenbasis; HU und CO werden daraus abgeleitet.** CO ist das bevorzugte Format für KI-gestützte oder externe Auswertung.

`<PREFIX>` entspricht in der Regel dem ersten Teil des Hostnamens vor dem ersten `-`. Vollständige Feldbeschreibung: [docs/AssetCache_Monitoring.md](docs/AssetCache_Monitoring.md).

---

## Deployment via Relution MDM

### Voraussetzungen
- macOS-Device mit aktiviertem Apple Content Caching
- Relution MDM mit Root-Ausführungsrecht für Skripte
- Internetverbindung zu `raw.githubusercontent.com`

### Ablauf

**1. Installieren**

Basiert auf `scripts/deploy_assetcache_logger.sh`, ergänzt um die produktive Schultabelle als Heredoc in Schritt 3 (nicht im Repo).

Ergebnis: `cat /var/tmp/assetcache_deploy.log` → `Deployment complete.`

**2. Prüfen**

```sh
# CSV-Dateien vorhanden?
ls /Library/Logs/KommunalBIT/

# Daemon läuft?
launchctl list de.kommunalbit.assetcachelogger

# Schultabelle korrekt?
cat -A /etc/kommunalbit/schulen.conf | head -5
# ^I = Tab (korrekt), Leerzeichen = Relution hat Tabs gefressen
```

### Bekannter Relution-Bug

Relution 26.1.1 ersetzt in Scripts Punkte durch Unterstriche in bestimmten Mustern  
(z. B. `raw.githubusercontent.com` → `raw_githubusercontent.com`, `.csv` → `_csv`).  
Das Deploy-Script und der Uninstaller enthalten bereits Workarounds. Beim Bearbeiten in Relution immer den Deploy-Log auf korrekte URLs und Dateinamen prüfen.

---

## Installierte Artefakte

| Pfad | Beschreibung |
|---|---|
| `/usr/local/bin/assetcache_logger.sh` | Monitoring-Skript |
| `/Library/LaunchDaemons/de.kommunalbit.assetcachelogger.plist` | LaunchDaemon (900 s) |
| `/Library/Logs/KommunalBIT/` | CSV-Ausgabe |
| `/Library/Logs/KommunalBIT/Archiv/` | Archiv bei iOS-Versionsänderung |
| `/etc/kommunalbit/schulen.conf` | Schultabelle (nicht im Repo) |
| `/var/tmp/assetcache_*.tsv` | State-Dateien für Delta-Berechnung |

---

## Weitere Dokumentation

- [Vollständige technische Dokumentation](docs/AssetCache_Monitoring.md) – alle 23 CSV-Felder, Betriebsartefakte, Praxis-Interpretationstabelle
- [Versionierungsrichtlinie](docs/versioning-policy.md)
- [Changelog](CHANGELOG.md)
