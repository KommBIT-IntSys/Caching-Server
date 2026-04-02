# Changelog

Alle relevanten Änderungen werden in dieser Datei dokumentiert.  
Format orientiert sich an [Keep a Changelog](https://keepachangelog.com/de/1.0.0/).  
Versionierung folgt [Semantic Versioning](https://semver.org/lang/de/).

---

## [1.6.1] – 2026-04-02

### Geändert
- Schultabelle (SuS-Anzahl pro Standort) aus dem Monitoring-Skript ausgelagert
  nach `/etc/kommunalbit/schulen.conf` – sensible Standortdaten liegen nicht mehr im Repo
- Monitoring-Skript im Repo auf stabilen Namen `scripts/assetcache_logger.sh` umgestellt
  (Versionierung erfolgt künftig über Git-Tags und Releases)
- Repo-Struktur in Unterverzeichnisse gegliedert: `scripts/`, `launchd/`, `docs/`, `config/`

### Hinzugefügt
- `scripts/deploy_assetcache_logger.sh` – Deploy-Script für Relution MDM
- `scripts/uninstall_assetcache_logger.sh` – Deinstaller
- `config/schulen.conf.example` – Beispielkonfiguration für die Schultabelle
- `docs/versioning-policy.md` – Versionierungsrichtlinie
- `CHANGELOG.md` – diese Datei
- `README.md` – GitHub-Übersicht

### Bekannte Eigenheit
- Relution MDM ersetzt in Scripts Punkte durch Unterstriche in bestimmten
  String-Mustern (z. B. `raw.githubusercontent.com` → `raw_githubusercontent.com`).
  Das Deploy-Script enthält einen Workaround via `printf '\x2e'`.

---

## [1.6.0] – 2026-03-XX

### Hinzugefügt
- Erstes vollständiges CSV-Schema mit 23 Feldern (RAW + HU parallel)
- GDMF-basierte iOS-/iPadOS-Versionserkennung mit Caching
- Automatische CSV-Archivierung bei iOS-Versionsänderung
- Delta-Berechnung für ServedDelta / OriginDelta über State-Datei
- WLAN-Metriken via `wdutil` (SNR, Noise, CCA)
- Apple CDN Erreichbarkeit + TTFB
- Peer-Erkennung (andere Cache-Server im Netz)
