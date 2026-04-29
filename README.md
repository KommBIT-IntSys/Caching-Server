# AssetCache Monitoring – KommunalBIT

[![ShellCheck](https://github.com/KommBIT-IntSys/Caching-Server/actions/workflows/shellcheck.yml/badge.svg?branch=main)](https://github.com/KommBIT-IntSys/Caching-Server/actions/workflows/shellcheck.yml)

Monitoring und Logging des Apple Content Caching.
Besonders interessant, wemn mehrere Standorte abgefragt und verglichen werden können und sollen.

Das Haupt-Skript erfasst alle 15 Minuten relevante Metriken des Content Caching und schreibt sie in drei CSV-Dateien: maschinenlesbar (RAW), menschenlesbar (HU) und datensparsam für KI-gestützte externe Auswertung (CO). Ziel ist es, Verzögerungen bei iOS-/iPadOS-Updates standortbasiert einordnen zu können – ob die Ursachen eher technischer oder organisatorischer Natur sind.

## Rechtlicher Hinweis

Dieses Repository enthält keine personenbezogenen Daten.
Die DSGVO‑konforme Nutzung im Betrieb obliegt der verantwortlichen Stelle.
Urheberrecht, Nutzungsvorbehalt und Haftungsausschluss sind in den Dateien `LICENSE` und `DISCLAIMER` geregelt.

**Aktuelle Version: [1.8.0](CHANGELOG.md)**

---

## Repository-Struktur

```
scripts/    – Monitoring, Deployment, Deinstallation, Archivierung
launchd/    – LaunchDaemon-Konfiguration
docs/       – Vollständige technische Dokumentation
config/     – Beispielkonfiguration schulen.conf
```

> **Nicht im Repository:** Die produktive Schultabelle (`/etc/kommunalbit/schulen.conf`) mit Schulkürzeln und Gerätezahlen. Sie wird über MDM verteilt und enthält keine personenbezogenen Daten.

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

**RAW ist die primäre technische Datenbasis; _HU und _CO werden daraus abgeleitet.** _CO ist das bevorzugte Format für KI-gestützte oder externe Auswertung.

`<PREFIX>` entspricht in der Regel dem ersten Teil des Hostnamens vor dem ersten `-`. Vollständige Feldbeschreibung: [docs/AssetCache_Monitoring.md](docs/AssetCache_Monitoring.md).

---

## Deployment

**Voraussetzungen:**
- macOS mit aktiviertem Apple Content Caching
- MDM-System mit Root-Ausführungsrecht für Skripte (getestet mit Relution)
- Internetverbindung zu `raw.githubusercontent.com`

Das Deployment läuft über `scripts/deploy_assetcache_logger.sh`, ergänzt um die produktive Schultabelle als Heredoc (nicht im Repo).
Installationspfade, Artefakte und manuelle Installationsbefehle: [docs/AssetCache_Monitoring.md](docs/AssetCache_Monitoring.md) und [docs/Befehle_zum_Installieren.txt](docs/Befehle_zum_Installieren.txt).

> **Hinweis Relution:** Das Deploy-Skript enthält Workarounds für einen bekannten Bug, der Punkte in Dateinamen und URLs durch Unterstriche ersetzt.

---

## Weitere Dokumentation

- [Vollständige technische Dokumentation](docs/AssetCache_Monitoring.md) – alle 23 CSV-Felder, Betriebsartefakte, Praxis-Interpretationstabelle
- [Versionierungsrichtlinie](docs/versioning-policy.md)
- [Changelog](CHANGELOG.md)
