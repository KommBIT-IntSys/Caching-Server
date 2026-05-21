# AssetCache Monitoring – KommunalBIT

[![ShellCheck](https://github.com/KommBIT-IntSys/Caching-Server/actions/workflows/shellcheck.yml/badge.svg?branch=main)](https://github.com/KommBIT-IntSys/Caching-Server/actions/workflows/shellcheck.yml) [![Lizenz: EUPL-1.2](https://img.shields.io/badge/Lizenz-EUPL--1.2-blue)](LICENSE)

Monitoring und Logging des Apple Content Caching.
Besonders interessant, wenn mehrere Standorte abgefragt und verglichen werden können und sollen.

Das Haupt-Skript erfasst alle 15 Minuten relevante Metriken des Content Caching und schreibt sie in drei CSV-Dateien: maschinenlesbar (RAW), menschenlesbar (HU) und datensparsam für KI-gestützte externe Auswertung (CO). Ziel ist es, Verzögerungen bei iOS-/iPadOS-Updates standortbasiert einordnen zu können – ob die Ursachen eher technischer oder organisatorischer Natur sind.

---

### Schnelleinstieg

[HOW_TO_COPILOT](<HOW_TO_COPILOT.md>)

### Dateien im Überblick

| Datei / Ordner                          | Inhalt                                                  |
|-----------------------------------------|---------------------------------------------------------|
| `scripts/assetcache_logger.sh`          | Hauptskript: erfasst Cache-Metriken der Mac Minis       |
| `HOW_TO_COPILOT.md`                     | Anleitung zur Auswertung mit Microsoft Copilot          |
| `scripts/` (Merge- und Cleaner-Skripte) | Hilfsskripte für Windows und macOS (Merge, Bereinigung) |
| `docs/`                                 | Technische Hintergrunddokumentation                     |

### Warum MS Copilot?

Nicht weil es die dafür beste KI wäre, sondern weil es derzeit die einzige ist, die der bayerische ÖD erlaubt.
Allerdings: Gut gepromptet liefert auch diese aussagekräftige und belastbare Ergebnisse.

---

## Lizenz

Dieses Projekt steht unter der European Union Public Licence (EUPL) v1.2.

➡ 
Nutzung, Anpassung und Weitergabe sind erlaubt.

Details:
- Rechtlich verbindlich: [LICENSE](<LICENSE>)
- Verständlich erklärt:  [Lizenz](<Lizenz.De.md>)

## Rechtlicher Hinweis

Dieses Repository enthält keine personenbezogenen Daten.
Die DSGVO‑konforme Nutzung im Betrieb obliegt der verantwortlichen Stelle.
Haftungsausschluss: [`DISCLAIMER`](DISCLAIMER)

**Aktuelle Version: [19.1](CHANGELOG.md)**

---

# Was das Skript erfasst

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

**RAW ist die primäre technische Datenbasis; _HU und _CO werden daraus abgeleitet.** _CO ist das bevorzugte Format für KI-gestützte oder externe Auswertung.

### Speicherorte ab v1.9.1

Ab Version 1.9.1 trennt das Projekt zwischen dauerhaftem Speicher und sichtbarer Ausgabe:

- `/Library/Application Support/KommunalBIT/AssetCacheLogger/journal/`  
  Dauerhaftes RAW-Journal. Dies ist die kanonische Datenquelle und soll macOS-Updates/Neustarts überstehen.

- `/Library/Logs/KommunalBIT/`  
  Sichtbarer Arbeitsordner für die aktuell erzeugten HU- und CO-Dateien. Dieser Ordner kann bei Bedarf aus dem RAW-Journal wiederhergestellt werden.

- `/Library/Application Support/KommunalBIT/AssetCacheLogger/archive/`  
  Sicherer Archivbereich für HU-/CO-Dateien, die durch automatische iOS-Versionswechsel oder das manuelle Archivierungsskript abgelegt werden.

Der alte Ordner `/Library/Logs/KommunalBIT/Archiv` wird ab v1.9.1 nicht mehr verwendet.

`<PREFIX>` entspricht in der Regel dem ersten Teil des Hostnamens vor dem ersten `-`. Vollständige Feldbeschreibung: [docs/AssetCache_Monitoring.md](docs/AssetCache_Monitoring.md).

---

## Deployment

**Voraussetzungen:**
- macOS mit aktiviertem Apple Content Caching
- MDM-System mit Root-Ausführungsrecht für Skripte (getestet mit Relution)
- Internetverbindung zu `raw.githubusercontent.com`

Das Deployment läuft über `scripts/deploy_assetcache_logger.sh`, ergänzt um die Tabelle der Standorte / Organisationen als Heredoc (nicht im Repo).
Installationspfade, Artefakte und manuelle Installationsbefehle: [docs/AssetCache_Monitoring.md](docs/AssetCache_Monitoring.md) und [docs/Befehle_zum_Installieren.txt](docs/Befehle_zum_Installieren.txt).

> **Hinweis Relution:** Das Deploy-Skript enthält Workarounds für einen bekannten Bug, der Punkte in Dateinamen und URLs durch Unterstriche ersetzt.

---

## Weitere Dokumentation

- [Vollständige technische Dokumentation](docs/AssetCache_Monitoring.md) – alle 23 CSV-Felder, Betriebsartefakte, Praxis-Interpretationstabelle
- [Versionierungsrichtlinie](docs/versioning-policy.md)
- [Changelog](CHANGELOG.md)
