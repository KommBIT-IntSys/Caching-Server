# Versionierungsrichtlinie

## Schema

Dieses Projekt verwendet [Semantic Versioning](https://semver.org/lang/de/) in der Form `MAJOR.MINOR.PATCH`.

| Stelle | Bedeutung | Beispiel |
|---|---|---|
| MAJOR | Grundlegende Änderung des CSV-Schemas oder der Betriebslogik | `2.0.0` |
| MINOR | Neue Felder, neue Funktionen, rückwärtskompatibel | `1.7.0` |
| PATCH | Fehlerbehebungen, Anpassungen ohne Schema-Änderung | `1.6.2` |

---

## Dateiname des Monitoring-Skripts

Das Skript liegt im Repo unter dem **stabilen Namen** `scripts/assetcache_logger.sh`.  
Die Version lebt ausschließlich in:
- Git-Tags (`v1.6.1`)
- GitHub Releases
- Der Variable `SCRIPT_VER` im Skript selbst
- Diesem Changelog

Das Deploy-Script auf dem Mac installiert das Skript als `/usr/local/bin/assetcache_logger.sh` – der Zielname ist ebenfalls stabil und versionsunabhängig.

---

## Releases und Tags

Jeder ausrollbare Stand erhält:
1. Einen Git-Tag (`v1.6.1`)
2. Einen GitHub Release mit Beschreibung der Änderungen
3. Einen Eintrag in `CHANGELOG.md`

Der `main`-Branch entspricht immer dem aktuell ausrollbaren Stand.  
Experimentelle Änderungen werden auf Feature-Branches entwickelt.

---

## Wann wird eine neue Version erstellt?

| Situation | Versionssprung |
|---|---|
| CSV-Schema geändert (Felder hinzugefügt/entfernt/umbenannt) | MINOR |
| Konfigurationslogik geändert (z. B. neue State-Datei) | MINOR |
| Schultabelle oder schulen.conf-Format geändert | PATCH |
| Bugfix im Script | PATCH |
| Deploy- oder Uninstall-Script geändert | PATCH (eigenes Versionsfeld im Script) |
| Nur Dokumentation geändert | kein Release nötig |

---

## Sensible Daten

Folgendes gehört **nicht** in dieses Repository:
- Echte Schulkürzel mit Gerätezahlen → gehört in `/etc/kommunalbit/schulen.conf` auf dem Zielsystem
- Hostnamen oder IP-Adressen einzelner Standorte
- MDM-Zugangsdaten oder API-Schlüssel
