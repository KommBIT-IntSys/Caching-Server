# Changelog

Alle nennenswerten Änderungen an diesem Projekt werden in dieser Datei dokumentiert.

Das Format orientiert sich lose an Keep a Changelog.
Versionen folgen keiner starren SemVer-Interpretation, sondern einer praxisorientierten Projektversionierung:

- **Patch**: kleine Korrekturen, keine grundlegende Änderung des Projektverhaltens
- **Minor**: neue Felder, neue Funktionen, neue Deploy-/Betriebslogik
- **Major**: grundlegende Umstellungen an Architektur, Datenmodell oder Betriebsweise

## [1.6.1] - 2026-04-02

### Added
- Repository in produktnähere Struktur überführt:
  - `scripts/`
  - `launchd/`
  - `docs/`
  - `config/`
- `CHANGELOG.md` ergänzt
- `docs/versioning-policy.md` ergänzt
- `config/schulen.conf.example` als veröffentlichbare Beispielkonfiguration ergänzt
- `docs/Befehle_zum_Installieren.txt` als rohe Referenz für manuelle Installation ergänzt

### Changed
- Hauptskript im Repository auf stabilen Dateinamen `assetcache_logger.sh` umgestellt
- Deploy-/Uninstall-Skripte in `scripts/` einsortiert
- LaunchDaemon in `launchd/` abgelegt
- README auf neue Repository-Struktur und Projektbeschreibung angepasst

### Fixed
- Öffentlicher Projektkern klarer von produktiven Standortdaten getrennt
- Frühere flache Root-Struktur des Repositories aufgeräumt

---

## [1.6.0]

### Added
- `ClientsCnt` als standortbezogene Einordnung der Aktivität anhand bekannter Gerätebasis
- robustere Rollout-/Cleanup-Logik für breite Verteilung
- konsolidierte Installer-/Cleanup-Versionierung

### Changed
- Projekt auf produktionsnähere Verteilung über Relution ausgerichtet
- stille Korrekturen aus der 1.5-Phase übernommen

### Fixed
- Header-/Datenzeilen-Konsistenz in CSV-Logik
- Umgang mit Hostnames, die nicht in der Schultabelle auftauchen
- Bereinigung historischer Sonderbehandlungen wie `EPS_neu`

---

## [1.5.x]

### Added
- standortbezogene Client-Kapazitätslogik über harte Schultabelle
- Darstellung der aktuellen Aktivität relativ zur bekannten Geräteanzahl

### Changed
- Ausgabeformat für `ClientsCnt`:
  - Raw: Verhältnis `N/Total`
  - Hu: Prozentwert

### Notes
- Diese Phase diente vor allem der Einordnung der Cache-Aktivität im Verhältnis zur bekannten iPad-Basis eines Standorts.

---

## [1.4]

### Added
- `iOSUpdates`-Feld auf Basis von Apple GDMF
- Sichtbarkeitsfenster für iOS-/iPadOS-Release-Ereignisse
- stärkere Trennung zwischen Raw- und Hu-Logik

### Changed
- `iOSUpdates` in die CSV-Struktur integriert
- Human-readable-Ausgabe weiter geschärft
- fehlende Werte in Hu als `n/a`, in Raw als leer geführt

### Removed
- weniger nützliche oder redundant gewordene Detailausgaben wie `AppleTotal`

### Notes
- Schwerpunkt war die Verbindung von Cache-Monitoring und konkreten iOS-/iPadOS-Release-Ereignissen.

---

## [1.3]

### Added
- Aufteilung in zwei CSV-Dateien:
  - Raw
  - Hu
- Version in Dateinamen der erzeugten CSV-Ausgaben
- klarere Definition von Maschinenlesbarkeit vs. Sichtprüfung

### Changed
- Raw als primäre fachliche Quelle definiert
- Hu ausdrücklich als abgeleitete, menschenlesbare Sicht positioniert
- Netzwerk- und Reachability-Metriken weiter verfeinert

### Fixed
- Fallback-Verhalten bei fehlendem `MaxCachePressureLast1Hour`
- verschiedene Formatierungs- und Feldkonsistenzprobleme

### Notes
- Diese Version war der eigentliche methodische Reifeschritt des Projekts.

---

## [1.2]

### Added
- regelmäßiges Logging zentraler Apple Content Caching-Metriken
- LaunchDaemon-basierter Betrieb
- State-Datei für Intervall-/Delta-Berechnung
- Logging von Cache-, Netzwerk- und Apple-Erreichbarkeitswerten

### Notes
- Erste ernsthaft nutzbare Version des Monitorings im Feldbetrieb.

---

## [1.0 - 1.1]

### Notes
- frühe Projekt- und Erkundungsphase
- Fokus auf:
  - Verstehen der Apple-Content-Caching-Metriken
  - Auswahl brauchbarer Kennzahlen
  - erste Auswerte- und Logging-Versuche
  - Prüfung, welche Daten im Schulbetrieb wirklich Aussagekraft haben
