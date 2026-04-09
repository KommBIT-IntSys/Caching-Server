# Changelog

Alle nennenswerten Änderungen an diesem Projekt werden in dieser Datei dokumentiert.

Das Format orientiert sich lose an Keep a Changelog.
Versionen folgen keiner starren SemVer-Interpretation, sondern einer praxisorientierten Projektversionierung:

- **Patch**: kleine Korrekturen, keine grundlegende Änderung des Projektverhaltens
- **Minor**: neue Felder, neue Funktionen, neue Deploy-/Betriebslogik
- **Major**: grundlegende Umstellungen an Architektur, Datenmodell oder Betriebsweise

> Hinweis zur Datierung:
> Tagesgenaue Datumsangaben werden nur dort geführt, wo sie aus Artefakten oder dem Projektverlauf klar belegbar sind.
> Frühere Versionen sind teilweise historisch rekonstruiert und daher bewusst ohne exaktes Tagesdatum belassen.

## [1.6.2] - 2026-04-05

### Changed
- `TotalsSince` in der HU-Ansicht erhält ein 20-Zeilen-Sichtbarkeitsfenster analog zu `iOSUpdates`:
  nach einer Änderung wird der Wert für 20 Zeilen angezeigt, danach leer
  – reduziert Rauschen in der HU-Datei im Normalfall (gleichbleibende Zählerbasis)
- `SCRIPT_VER` auf `1.6.2` gesetzt

### Notes
- RAW-Ausgabe von `TotalsSince` unverändert; nur HU betroffen
- neue State-Datei: `/var/tmp/assetcache_totalssince_hu_state.tsv`
- Uninstaller bereinigt neue State-Datei mit

---

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
- Hauptskript von standortspezifischer Konfiguration getrennt
- produktive Schultabelle aus dem veröffentlichten Skript entfernt und in externe Konfiguration überführt
- Deploy-/Uninstall-Skripte in `scripts/` einsortiert
- LaunchDaemon in `launchd/` abgelegt
- README auf neue Repository-Struktur und Projektbeschreibung angepasst

### Fixed
- öffentlicher Projektkern klarer von produktiven Standortdaten getrennt
- frühere flache Root-Struktur des Repositories aufgeräumt

### Notes
- Diese Version markiert die veröffentlichbare Hauptlinie des Projekts.
- Frühere `1.6.4`-Artefakte dienten primär der Umgehung eines Relution-Deploy-Bugs und sind nicht als fachlich führender Stand des Monitorings zu verstehen.
- Fachlicher Kern und Messlogik des Hauptskripts entsprechen weiterhin dem `1.6.0`-Stand; `1.6.1` fokussiert auf Veröffentlichbarkeit, Strukturtrennung und Dokumentation.

---

## [1.6.0] - 2026-03-11

### Added
- `ClientsCnt` als standortbezogene Einordnung der Aktivität anhand bekannter Gerätebasis
- standortbezogene SuS-Basis über integrierte Standorttabelle
- robustere Rollout-/Cleanup-Logik für breite Verteilung
- konsolidierte Installer-/Cleanup-Versionierung

### Changed
- Projekt auf produktionsnähere Verteilung über Relution ausgerichtet
- CSV-Ausgabe vollständig CSV-sicher gequotet, inklusive Header
- Standorttabelle im Skript bewusst weit oben platziert, um Pflege und Aktualisierung zu erleichtern
- Schema stabilisiert, ohne zusätzliche Spalten einzuführen

### Fixed
- Header-/Datenzeilen-Konsistenz in CSV-Logik
- Umgang mit Hostnames, die nicht in der Schultabelle auftauchen
- Bereinigung historischer Sonderbehandlungen wie `EPS_neu`

### Notes
- Diese Version konsolidiert die fachlichen und formatbezogenen Korrekturen der `1.5`-Phase.
- `ClientsCnt` wird in RAW als `active/total` und in HU als Prozentwert dargestellt; bei unbekanntem Standort nur als Aktivwert.

---

## [1.5.x] - 2026-02 bis 2026-03

### Added
- standortbezogene Client-Kapazitätslogik über harte Schultabelle
- Darstellung der aktuellen Aktivität relativ zur bekannten Geräteanzahl
- `ClientsCnt` auf Basis aktiver Client-IP-Adressen aus Unified Logs
- GDMF-Change-Detection mit State-Datei und Debug-Log
- Auto-Archivierung der CSV-Dateien bei `iOSUpdates`-Änderungen
- Timeout-Schutz für langsame oder hängende Systemkommandos

### Changed
- Ausgabeformat für `ClientsCnt`:
  - RAW: Verhältnis `N/Total`
  - HU: Prozentwert
- Apple-Reachability robuster ausgewertet, um Fehlfälle wie `yes` bei `0ms` zu vermeiden
- Byte-Umrechnung und Human-Units fachlich bereinigt
- erstes Delta nach Neuinstallation / Epochenwechsel korrekt als `0`
- HU-Peer-Darstellung als Anzahl statt Rohwert

### Notes
- Diese Phase diente vor allem der Einordnung der Cache-Aktivität im Verhältnis zur bekannten iPad-Basis eines Standorts.
- `1.5.x` war weniger eine einzelne Freigabe als eine operative und fachliche Reifephase vor der Konsolidierung in `1.6.0`.

---

## [1.4]

### Added
- `iOSUpdates`-Feld auf Basis von Apple GDMF
- Sichtbarkeitsfenster für iOS-/iPadOS-Release-Ereignisse
- stärkere Trennung zwischen RAW- und HU-Logik

### Changed
- `iOSUpdates` in die CSV-Struktur integriert
- Human-readable-Ausgabe weiter geschärft
- fehlende Werte in HU als `n/a`, in RAW als leer geführt
- methodische Verknüpfung von Cache-Monitoring und konkreten iOS-/iPadOS-Release-Ereignissen

### Removed
- weniger nützliche oder redundant gewordene Detailausgaben wie `AppleTotal`

### Notes
- Schwerpunkt war die Verbindung von Cache-Monitoring und konkreten iOS-/iPadOS-Release-Ereignissen.

---

## [1.3]

### Added
- Aufteilung in zwei CSV-Dateien:
  - RAW
  - HU
- Version in Dateinamen der erzeugten CSV-Ausgaben
- klarere Definition von Maschinenlesbarkeit vs. Sichtprüfung

### Changed
- RAW als primäre fachliche Quelle definiert
- HU ausdrücklich als abgeleitete, menschenlesbare Sicht positioniert
- Netzwerk- und Reachability-Metriken weiter verfeinert

### Fixed
- Fallback-Verhalten bei fehlendem `MaxCachePressureLast1Hour`
- verschiedene Formatierungs- und Feldkonsistenzprobleme

### Notes
- Diese Version war der eigentliche methodische Reifeschritt des Projekts.

---

## [1.2] - 2026-02-25

### Added
- erstes feldtaugliches Viertelstunden-Logging zentraler Apple Content-Caching-Metriken
- LaunchDaemon-basierter Betrieb
- State-Datei für Intervall-/Delta-Berechnung
- Logging von Cache-, Netzwerk- und Apple-Erreichbarkeitswerten in eine einzelne CSV-Datei
- erste Generation der Apple-Checks inklusive `AppleTTFB_ms` und `AppleTotal_ms`
- erste WLAN-Metriken mit `WifiRSSI`, `WifiNoise` und `WifiCCA`
- manueller Installationspfad über Shell-Skript und LaunchDaemon

### Notes
- Erste ernsthaft nutzbare Version des Monitorings im Feldbetrieb.
- Noch keine Trennung zwischen RAW und HU.
- Ausgangspunkt für die spätere methodische Aufteilung und Feldbereinigung.

---

## [1.0 - 1.1]

### Notes
- frühe Projekt- und Erkundungsphase
- Fokus auf:
  - Verstehen der Apple-Content-Caching-Metriken
  - Auswahl brauchbarer Kennzahlen
  - erste Auswerte- und Logging-Versuche
  - Prüfung, welche Daten im Schulbetrieb wirklich Aussagekraft haben

---

## Historische Nebenlinie: Relution-Deployment-Artefakte (`1.6.3` / `1.6.4`)

### Notes
- temporäre operative Deploy-/Cleanup-Artefakte für Relution-Rollout
- dienten primär der robusten Verteilung und Fehlerumgehung im MDM-Kontext
- nicht als eigene fachliche Evolutionsstufe des Datenmodells zu lesen
- fachlich führend für die Monitoring-Logik blieb die `1.6.x`-Hauptlinie
