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

---

## [1.9.1] - 2026-05-20

### Hinzugefügt
- Dauerhaftes RAW-Journal unter `/Library/Application Support/KommunalBIT/AssetCacheLogger/journal/`.
- Rebuild-Mechanismus für sichtbare HU-/CO-CSV-Dateien aus dem RAW-Journal.
- Geschützter Archivspeicherort unter `/Library/Application Support/KommunalBIT/AssetCacheLogger/archive/`.
- Admin-ACL-Handhabung im Relution-Deploy-Skript für lokales Einsehen/Kopieren.

### Geändert
- `/Library/Logs/KommunalBIT` ist nur noch das sichtbare Arbeits-/Ausgabe-Verzeichnis für HU- und CO-Dateien.
- RAW wird standardmäßig nicht mehr sichtbar geschrieben; die kanonischen RAW-Daten liegen im Application-Support-Journal.
- Das manuelle Archivierungsskript verschiebt nur sichtbare HU-/CO-Dateien in das Application-Support-Archiv und stoppt den Daemon, ohne ihn neu zu starten.
- Das Deploy-Skript aktiviert, bootstrapt und startet den LaunchDaemon nach dem Deployment explizit.

### Behoben
- Datenverlust verhindert, wenn `/Library/Logs/KommunalBIT` während eines macOS-Updates oder Neustarts verschwindet.
- Verwendung von `/Library/Logs/KommunalBIT/Archiv` als maßgeblichem Archivspeicherort entfernt.
- zsh-Glob-Handhabung in Archiv-/Logger-Skripten mit `NULL_GLOB` korrigiert.
- Relution-Punkt-Mangling-Probleme für `.sh`, `.plist`, `.out`, `.err` und `.conf` behoben.
- Rebuild-Behandlung leerer CSV-Felder und sichtbare Epochen-Behandlung rund um iOS-Update-Wechsel korrigiert.

---

## [1.9.0] - 2026-05-19

### Hinzugefügt
- `assetcache_logger.sh`: dauerhaftes RAW-Journal unter
  `/Library/Application Support/KommunalBIT/AssetCacheLogger/journal/`
  (überlebt macOS-Update-Neustarts; an `RAW_SCHEMA_VER` gebunden, nicht an `SCRIPT_VER`)
- `assetcache_logger.sh`: Rebuild von HU und CO deterministisch aus RAW-Journal
  (nach Neustart oder Verlust von `/Library/Logs/KommunalBIT`)
- `assetcache_logger.sh`: Boot-Erkennung via `kern.boottime`; Rebuild wird bei
  erkanntem Neustart ausgelöst
- `assetcache_logger.sh`: dauerhaftes Statuslog unter
  `/Library/Application Support/KommunalBIT/AssetCacheLogger/status.log`
- `assetcache_logger.sh`: `EXPORT_VISIBLE_RAW=0` (Standard); sichtbares RAW nur
  bei expliziter Aktivierung
- `assetcache_logger.sh`: `iso_to_hu_ts()` – ISO-8601 → HU-lesbarer Zeitstempel
  (für Rebuild ohne Live-Statefiles)

### Geändert
- `assetcache_logger.sh`: `/Library/Logs/KommunalBIT` ist nur noch sichtbarer
  Ausgabeort; RAW-Journal liegt dauerhaft unter Application Support
- `assetcache_logger.sh`: Statefiles von `/var/tmp` nach
  `Application Support/state/` verlagert; einmalige automatische Migration
- `assetcache_logger.sh`: Archivierung via `cp` statt `mv`; RAW-Journal wird
  niemals verschoben; nach Archiv-Copy werden sichtbare Dateien zurückgesetzt
- `assetcache_logger.sh`: `GDMF_DEBUGLOG` liegt jetzt ebenfalls unter
  Application Support (nicht mehr `/var/tmp`)
- `SCRIPT_VER` → `1.9.0`

### Hinweise
- Keine Änderung an CSV-Schemata, Feldnamen oder Feldreihenfolge.
- Erster Lauf nach Update von v1.8.x: Statefiles werden automatisch migriert;
  neue HU-/CO-Dateien starten mit v1.9.0-Namen; altes RAW (v1.8.x) bleibt
  unberührt.
- `RAW_SCHEMA_VER="schema1"` – Journal-Name ändert sich bei zukünftigen
  Patch-/Minor-Versionen nicht; nur bei bewusstem Schema-Bruch anheben.

---

## [1.8.3] - 2026-05-19

### Hinzugefügt
- `scripts/LSI-Apple-Auswertung-v5.2.sh` als vollwertige macOS-/zsh-Implementierung der LSI-/Apple-Sicherheitsauswertung ergänzt.
- Damit steht die LSI-/Apple-Auswertung neben der PowerShell-Version auch auf macOS zur Verfügung.
- Das Skript bildet die komplexe Auswertungslogik der PowerShell-Version eigenständig nach, insbesondere:
  - Abfrage und Verarbeitung der WID-/LSI-Datenbasis
  - Auswertung relevanter Apple-Advisories
  - CVE-, Exploit- und NoPatch-Erkennung
  - Ermittlung und Bewertung von MinFix-Versionen je iOS-/iPadOS-Zweig
  - Ausgabe eines Managementreports
  - Ausgabe einer vollständigen Detail-/Gesamtauswertung als CSV
  - inkrementelles Betriebsmodell mit vorhandenen Ergebnisdateien
  - Bereinigung nicht mehr relevanter iOS-/iPadOS-Versionen anhand gepflegter `RELEVANT_VERSIONS`
- Die LSI-/Apple-Auswertung ist damit nicht mehr an einen Windows-Arbeitsplatz gebunden.

### Geändert
- Die operative Auswertungskette des Projekts ist ab diesem Stand praktisch wieder multiplattformfähig:
  - Windows 11: PowerShell-Skripte für Relution-Export-Bereinigung, CO-Merge und LSI-/Apple-Auswertung.
  - macOS: Shell-/zsh-Skripte für Relution-Export-Bereinigung, CO-Merge und LSI-/Apple-Auswertung.
- Die macOS-Skripte sind nicht nur Hilfswerkzeuge, sondern bilden die für den Betrieb relevanten Auswertungsschritte vollständig genug ab, um auch auf einem Mac-Administrationsarbeitsplatz belastbare Ergebnisse zu erzeugen.

### Einordnung
- Der AssetCache-Logger selbst bleibt macOS-/Mac-mini-spezifisch und läuft weiterhin auf den Caching-Servern.
- Die vorbereitenden und auswertenden Arbeitsschritte können ab diesem Stand jedoch sowohl unter Windows 11 als auch unter macOS durchgeführt werden.
- Diese Version markiert damit einen eigenständigen Projektmeilenstein: Die Sicherheitsauswertung und die CO-/Relution-Auswertung sind nicht mehr Windows-zentriert, sondern plattformübergreifend nutzbar.

---

## [1.8.2] - 2026-05

### Geändert
- `assetcache_logger.sh`: iOS-/iPadOS-Versionsnotation in der CO-Ausgabe
  normalisiert (zweistellige Segmente): `18.7.7` → `18.07.07`,
  `26.5` → `26.05`. RAW und HU bleiben Apple-nah unverändert.
- `assetcache_logger.sh`: GDMF-Abfrage holt letzten zwei iOS-Hauptversionen
  als `|`-getrennten String; GDMF-Debuglog mit automatischem Trim auf 1000 Zeilen.
- `assetcache_logger.sh`: Archivierung triggert bei iOS-Versionswechsel
  anhand GDMF-Signatur.
- `.github/workflows/shellcheck.yml`: zsh-spezifische ShellCheck-Regeln
  (SC2206, SC2296, SC2178, SC2128) zu den Excludes ergänzt; Konfiguration
  auf `SHELLCHECK_OPTS` als Umgebungsvariable umgestellt.

### Hinweise
- Keine Änderung an CSV-Schemata, Feldnamen, Feldreihenfolge oder Messlogik.
- Die Versionsnormalisierung gilt ausschließlich für CO-Ausgaben;
  leere Versionen werden leer gelassen, nicht durch Nullwerte ersetzt.

---

## [LSI-Apple-Auswertung v5.2] - 2026-05

> Eigenständiges Windows-Hilfsskript zur standortunabhängigen Sicherheits-
> auswertung. Versionsreihe läuft parallel zur Hauptversionierung.

### macOS-Pendant
- `scripts/LSI-Apple-Auswertung-v5.2.sh` — funktional identisches macOS-Äquivalent
  zu `LSI-Apple-Auswertung-v5.2.ps1`.
  Abhängigkeiten: `curl` (macOS-nativ), `jq` (Homebrew), `python3` (macOS-nativ).
  Gleiche Parameter, gleiche CSV-Ausgaben (Semicolon, UTF-8, identische Spalten).
  Inkrementelles Betriebsmodell und RELEVANT_VERSIONS-Bereinigung vollständig portiert.

### v5.2 (aktuell)
- `$ScriptWidApiKey` direkt im Skript eintragbar — Rechtklick-Ausführung
  ohne vorherige Umgebungsvariablen-Konfiguration möglich.
- Ausgabedateien umbenannt: `LSI-Apple-Gesamtauswertung_*.csv` und
  `LSI-Apple-Managementreport_*.csv`.
- `ConvertTo-NormalizedAppleVersions` greift auch Marketingnamen
  wie "macOS Sequoia < 15.03".

### v5.1
- Managementreport `AppleUrls`-Duplikate behoben: URLs werden aus
  `|`-getrennten Feldern korrekt dedupliziert.
- `LSI-Automatisch-Gefunden_*.csv` wird nicht mehr geschrieben;
  Kandidatenliste erscheint nur noch in der Konsolenausgabe.

### v5.0
- Inkrementelles Betriebsmodell: Erstlauf legt Datei neu an (Deckel 100),
  Folgeläufe arbeiten datums-basiert inkrementell (Deckel 50).
- `RELEVANT_VERSIONS`-Array als Selbstwissen im Skript-Header;
  veraltete Versionen werden aus bestehender Ausgabe bereinigt.
- iOS-Versionsnotation in CO-Ausgaben normalisiert (führende Nullen).
- `Invoke-WidApi`: UTF-8-Encoding-Fix für PS5/WID-API (Mojibake-Prävention).
- Neue Spalten: `Exploit`, `NoPatch`, `MinFixVersions`,
  `MinFixIosLinie18`, `MinFixIosLinie26`, `MinFixIpadOsLinie18`,
  `MinFixIpadOsLinie26`.
- Deduplikation mehrerer Apple-URLs pro LSI-Eintrag.

---

## [1.8.1] - 2026-05-05

### Hinzugefügt
- `scripts/Merge_Co_CSV.ps1` – CO-CSV-Dateien aller Standorte unter
  Windows zusammenführen (Header einmalig, Daten akkumuliert)
- `scripts/Relution-Export-Cleaner_Co_Batch.ps1` – Relution-Export unter
  Windows datenschutzkonform bereinigen: Gerätenamen entfernen,
  organizationName auf Standortkürzel kürzen, Dateiname mit Datum
- `scripts/merge_co_csv.sh` – CO-CSV-Dateien unter macOS zusammenführen
- `scripts/relution_cleaner_co.sh` – Relution-Export unter macOS
  datenschutzkonform bereinigen

### Geändert
- Projekt erweitert um einen reproduzierbaren, Copilot-gestützten Analyse-Workflow zur standortbasierten Bewertung des iOS-/iPadOS-Updatestands
- `COPILOT.md` umbenannt in `HOW TO COPILOT.md` – Zielrichtung
  gewechselt: von interner KI-Instruktion zu menschenlesbarer
  Schritt-für-Schritt-Anleitung für Anwender
- `HOW TO COPILOT.md` vollständig neu strukturiert: Kurzanleitung
  mit Vorbereitungsschritten, Links zu Skripten, Copilot-Prompt
- Copilot-Prompt inhaltlich weiterentwickelt: Bewertung des
  Updatezustands primär über `osVersion` / `applePendingVersion` /
  `iOSUpdates`, nicht über MDM-Status `COMPLIANT`; `ClientsCnt`
  als Kontextsignal statt harte Schwelle; explorativer Ansatz
  mit Hypothesenformulierung statt Urteilen
- `README.md` überarbeitet: klarere Struktur, Schnelleinstieg
  direkt zu `HOW TO COPILOT.md`, Abschnitt „Warum MSCopilot?"
  mit sachlichem Hinweis auf behördliche Einschränkung ergänzt

### Hinweise
- Keine Änderung an Hauptskript, Messlogik, CSV-Schemata oder
  Felddefinitionen
- Skripte in `scripts/` ergänzen den bestehenden Ordner;
  Deployment- und Hauptskripte unverändert
- `HOW TO COPILOT.md` wird mit jedem Auswertungszyklus
  weiterentwickelt; Prompt-Optimierung ist iterativer Prozess

---

## [1.8.0] - 2026-04-28

### Geändert
- Hauptskript architektonisch als RAW-first Pipeline strukturiert.
- Klare Lesereihenfolge im Skript: Collect → RAW → HU → CO → Write.
- HU- und CO-Ausgaben sind ausdrücklich als Ableitungen aus der RAW-Datenbasis kommentiert.
- Schreibreihenfolge der CSV-Dateien klar auf RAW → HU → CO festgelegt.
- `SCRIPT_VER` auf `1.8.0` gesetzt.

### Dokumentation
- Abschnitt „Interne Datenverarbeitung (RAW-first-Prinzip)" in `docs/AssetCache_Monitoring.md` ergänzt.
- Veraltete Formulierungen „zwei CSV-Dateien" und „RAW- und HU-CSV" korrigiert.
- `CLAUDE.md`: Architekturhinweis zur RAW-first-Pipeline ergänzt.

### Hinweise
- Diese Version führt erstmals eine durchgängige Auswertungskette ein:
  AssetCache CO-Daten + bereinigter Relution-Export → strukturierte Analyse → priorisierte Standortbewertung
- Der Fokus verschiebt sich damit von reinem Monitoring hin zu datenbasierter Entscheidungsunterstützung
- Keine Änderung an CSV-Schemata, Feldnamen, Feldreihenfolge oder Messlogik.
- Diese Version bereitet die spätere Weiterentwicklung der HU-Datei zur Bewertungs-/Entscheidungsansicht vor.
- RAW bleibt die technische Wahrheit; HU und CO sind Views.

---

## [1.7.1] - 2026-04-27

### Geändert
- CO-Ausgabe wird künftig als `<PREFIX>_AssetCache_Co_v<VERSION>.csv` geschrieben
- RAW bleibt weiterhin `<PREFIX>_AssetCacheRaw_v<VERSION>.csv`
- HU bleibt weiterhin `<PREFIX>_AssetCache_Hu_v<VERSION>.csv`
- `SCRIPT_VER` auf `1.7.1` gesetzt

### Hinweise
- Der Unterstrich vor `Co` ist bewusst: Die datensparsame CO-Datei steht dadurch in alphabetischen Dateilisten vor der HU-Datei
- Das unterstützt die sichere Standardauswahl bei manueller Weitergabe oder KI-gestützter Analyse
- Keine Änderung an Feldanzahl, Feldreihenfolge, Messlogik oder Datenschutzmodell

---

## [1.7.0] - 2026-04-23

### Hinzugefügt
- Neue CO-CSV-Ausgabe (`<PREFIX>_AssetCacheCo_v<VERSION>.csv`) pro Host
- CO folgt dem Prinzip der Datensparsamkeit: speziell für KI-gestützte oder externe Auswertung konzipiert, insbesondere zur Kombination mit einem datensparsam vorbereiteten Relution-/MDM-Export
- CO enthält 14 Felder: `SiteCode`, `Timestamp`, `PeerCnt`, `ClientsCnt`, `iOSUpdates`, `iOSBytes`, `ServedDelta`, `OriginDelta`, `CacheUsed`, `CachePr`, `DNSRes`, `AppleReach`, `AppleTTFB`, `WiFiSNR`
- Archivierung bei iOS-Versionsänderung schließt nun auch die CO-Datei ein
- `SCRIPT_VER` auf `1.7.0` gesetzt

### Hinweise
- `SiteCode` in CO entspricht dem Hostnamen-Präfix (z. B. `ASGS` statt `ASGS-Mac-Mini-Caching-Server-0`)
- CO enthält bewusst keine IP-Adressen (EN0/EN1, GatewayIP), keinen vollen Hostnamen, keine kumulativen Totals (TotReturned, TotOrigin), kein TotalsSince und keine reinen Troubleshooting-Felder (DefaultIf, WifiNoise, WifiCCA)
- RAW und HU bleiben vollständig erhalten; CO kommt als drittes Format hinzu
- CSV-Struktur von RAW und HU (Feldanzahl, Reihenfolge, Spaltennamen, Quoting) unverändert
- Für KI-gestützte Auswertung soll bevorzugt CO verwendet werden, nicht RAW oder HU

---

## [1.6.3] - 2026-04-15

### Geändert
- HU-Ausgabe: `EN0` und `EN1` geben keine konkreten IPv4-Adressen mehr aus; stattdessen `down`, `noip` oder `up`
- HU-Ausgabe: `GatewayIP` gibt keine konkrete IPv4-Adresse mehr aus; stattdessen `yes` (Gateway vorhanden) oder `no`
- RAW-Ausgabe: `EN0`, `EN1`, `GatewayIP` vollständig unverändert
- `SCRIPT_VER` auf `1.6.3` gesetzt

### Dokumentation
- `docs/AssetCache_Monitoring.md`: `EN0`, `EN1`, `GatewayIP` mit klarer RAW/HU-Unterscheidung dokumentiert; Hinweis ergänzt, dass HU für externe Auswertungen bevorzugt werden soll
- `docs/AssetCache_Monitoring.md`: Datenminimierungsprinzip für Relution-Standardexport an zwei Stellen explizit dokumentiert – Gerätename ist für die standortbezogene Auswertung bewusst nicht erforderlich

### Hinweise
- Neue Hilfsfunktionen `hu_iface_state()` und `hu_gateway_state()` im Hauptskript
- CSV-Struktur (Feldanzahl, Reihenfolge, Spaltennamen, Quoting) bleibt identisch
- Bewusste fachliche Änderung des HU-Formats aus Gründen der Datenminimierung

---

## [1.6.2] - 2026-04-05

### Geändert
- `TotalsSince` in der HU-Ansicht erhält ein 20-Zeilen-Sichtbarkeitsfenster analog zu `iOSUpdates`:
  nach einer Änderung wird der Wert für 20 Zeilen angezeigt, danach leer
  – reduziert Rauschen in der HU-Datei im Normalfall (gleichbleibende Zählerbasis)
- `SCRIPT_VER` auf `1.6.2` gesetzt

### Hinweise
- RAW-Ausgabe von `TotalsSince` unverändert; nur HU betroffen
- neue State-Datei: `/var/tmp/assetcache_totalssince_hu_state.tsv`
- Uninstaller bereinigt neue State-Datei mit

---

## [1.6.1] - 2026-04-02

### Hinzugefügt
- Repository in produktnähere Struktur überführt:
  - `scripts/`
  - `launchd/`
  - `docs/`
  - `config/`
- `scripts/archive_assetcache_logs.sh` als eigenständiges Skript zur CSV-Archivierung vor Updates
- `CHANGELOG.md` ergänzt
- `docs/versioning-policy.md` ergänzt
- `config/schulen.conf.example` als veröffentlichbare Beispielkonfiguration ergänzt
- `docs/Befehle_zum_Installieren.txt` als rohe Referenz für manuelle Installation ergänzt

### Geändert
- Hauptskript im Repository auf stabilen Dateinamen `assetcache_logger.sh` umgestellt
- Hauptskript von standortspezifischer Konfiguration getrennt
- produktive Schultabelle aus dem veröffentlichten Skript entfernt und in externe Konfiguration überführt
- Deploy-/Uninstall-Skripte in `scripts/` einsortiert
- LaunchDaemon in `launchd/` abgelegt
- README auf neue Repository-Struktur und Projektbeschreibung angepasst

### Behoben
- öffentlicher Projektkern klarer von produktiven Standortdaten getrennt
- frühere flache Root-Struktur des Repositories aufgeräumt

### Hinweise
- Diese Version markiert die veröffentlichbare Hauptlinie des Projekts.
- Frühere `1.6.4`-Artefakte dienten primär der Umgehung eines Relution-Deploy-Bugs und sind nicht als fachlich führender Stand des Monitorings zu verstehen.
- Fachlicher Kern und Messlogik des Hauptskripts entsprechen weiterhin dem `1.6.0`-Stand; `1.6.1` fokussiert auf Veröffentlichbarkeit, Strukturtrennung und Dokumentation.

---

## [1.6.0] - 2026-03-11

### Hinzugefügt
- `ClientsCnt` als standortbezogene Einordnung der Aktivität anhand bekannter Gerätebasis
- standortbezogene SuS-Basis über integrierte Standorttabelle
- robustere Rollout-/Cleanup-Logik für breite Verteilung
- konsolidierte Installer-/Cleanup-Versionierung

### Geändert
- Projekt auf produktionsnähere Verteilung über Relution ausgerichtet
- CSV-Ausgabe vollständig CSV-sicher gequotet, inklusive Header
- Standorttabelle im Skript bewusst weit oben platziert, um Pflege und Aktualisierung zu erleichtern
- Schema stabilisiert, ohne zusätzliche Spalten einzuführen

### Behoben
- Header-/Datenzeilen-Konsistenz in CSV-Logik
- Umgang mit Hostnames, die nicht in der Schultabelle auftauchen
- Bereinigung historischer Sonderbehandlungen wie `EPS_neu`

### Hinweise
- Diese Version konsolidiert die fachlichen und formatbezogenen Korrekturen der `1.5`-Phase.
- `ClientsCnt` wird in RAW als `active/total` und in HU als Prozentwert dargestellt; bei unbekanntem Standort nur als Aktivwert.

---

## [1.5.x] - 2026-03

### Hinzugefügt
- standortbezogene Client-Kapazitätslogik über harte Schultabelle
- Darstellung der aktuellen Aktivität relativ zur bekannten Geräteanzahl
- `ClientsCnt` auf Basis aktiver Client-IP-Adressen aus Unified Logs
- GDMF-Change-Detection mit State-Datei und Debug-Log
- Auto-Archivierung der CSV-Dateien bei `iOSUpdates`-Änderungen
- Timeout-Schutz für langsame oder hängende Systemkommandos

### Geändert
- Ausgabeformat für `ClientsCnt`:
  - RAW: Verhältnis `N/Total`
  - HU: Prozentwert
- Apple-Reachability robuster ausgewertet, um Fehlfälle wie `yes` bei `0ms` zu vermeiden
- Byte-Umrechnung und Human-Units fachlich bereinigt
- erstes Delta nach Neuinstallation / Epochenwechsel korrekt als `0`
- HU-Peer-Darstellung als Anzahl statt Rohwert

### Hinweise
- Diese Phase diente vor allem der Einordnung der Cache-Aktivität im Verhältnis zur bekannten iPad-Basis eines Standorts.
- `1.5.x` war weniger eine einzelne Freigabe als eine operative und fachliche Reifephase vor der Konsolidierung in `1.6.0`.

---

## [1.4] - 2026-02-27

### Hinzugefügt
- `iOSUpdates`-Feld auf Basis von Apple GDMF
- Sichtbarkeitsfenster für iOS-/iPadOS-Release-Ereignisse
- stärkere Trennung zwischen RAW- und HU-Logik

### Geändert
- `iOSUpdates` in die CSV-Struktur integriert
- Human-readable-Ausgabe weiter geschärft
- fehlende Werte in HU als `n/a`, in RAW als leer geführt
- methodische Verknüpfung von Cache-Monitoring und konkreten iOS-/iPadOS-Release-Ereignissen

### Entfernt
- weniger nützliche oder redundant gewordene Detailausgaben wie `AppleTotal`

### Hinweise
- Schwerpunkt war die Verbindung von Cache-Monitoring und konkreten iOS-/iPadOS-Release-Ereignissen.

---

## [1.3] - 2026-02-26

### Hinzugefügt
- Aufteilung in zwei CSV-Dateien:
  - RAW
  - HU
- Version in Dateinamen der erzeugten CSV-Ausgaben
- klarere Definition von Maschinenlesbarkeit vs. Sichtprüfung

### Geändert
- RAW als primäre fachliche Quelle definiert
- HU ausdrücklich als abgeleitete, menschenlesbare Sicht positioniert
- Netzwerk- und Reachability-Metriken weiter verfeinert

### Behoben
- Fallback-Verhalten bei fehlendem `MaxCachePressureLast1Hour`
- verschiedene Formatierungs- und Feldkonsistenzprobleme

### Hinweise
- Diese Version war der eigentliche methodische Reifeschritt des Projekts.

---

## [1.2] - 2026-02-20

### Hinzugefügt
- erstes feldtaugliches Viertelstunden-Logging zentraler Apple Content-Caching-Metriken
- LaunchDaemon-basierter Betrieb
- State-Datei für Intervall-/Delta-Berechnung
- Logging von Cache-, Netzwerk- und Apple-Erreichbarkeitswerten in eine einzelne CSV-Datei
- erste Generation der Apple-Checks inklusive `AppleTTFB_ms` und `AppleTotal_ms`
- erste WLAN-Metriken mit `WifiRSSI`, `WifiNoise` und `WifiCCA`
- manueller Installationspfad über Shell-Skript und LaunchDaemon

### Hinweise
- Erste ernsthaft nutzbare Version des Monitorings im Feldbetrieb.
- Noch keine Trennung zwischen RAW und HU.
- Ausgangspunkt für die spätere methodische Aufteilung und Feldbereinigung.

---

## [1.0 - 1.1]

### Hinweise
- frühe Projekt- und Erkundungsphase
- Fokus auf:
  - Verstehen der Apple-Content-Caching-Metriken
  - Auswahl brauchbarer Kennzahlen
  - erste Auswerte- und Logging-Versuche
  - Prüfung, welche Daten im Schulbetrieb wirklich Aussagekraft haben

---

## Historische Nebenlinie: Relution-Deployment-Artefakte (`1.6.3` / `1.6.4`)

### Hinweise
- temporäre operative Deploy-/Cleanup-Artefakte für Relution-Rollout
- dienten primär der robusten Verteilung und Fehlerumgehung im MDM-Kontext
- nicht als eigene fachliche Evolutionsstufe des Datenmodells zu lesen
- fachlich führend für die Monitoring-Logik blieb die `1.6.x`-Hauptlinie
