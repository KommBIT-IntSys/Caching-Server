# Asset Cache Monitoring

Monitoring und Logging des Content Caching unserer Mac Minis in den Schulen.

Es dient dazu, den Betrieb des Content Caching auf unseren Mac Minis nachvollziehbar zu beobachten, relevante Metriken regelmäßig (aktuell: jede Viertelsunde) zu erfassen und in Form einer CSV-Datei für technische Analyse und standortbezogene Bewertung bereitzustellen.

Der Schwerpunkt liegt nicht auf dem reinem Sammeln von Zahlen, sondern auf der Frage, ob Verzögerungen bei den iPad-/iOS-Updates eher auf infrastrukturelle Probleme oder eher auf organisatorische bzw. lokale Nutzungsgewohnheiten zurückzuführen ist.

## Motivation

In einer Umgebung mit vielen schulisch genutzten iPads ist Apple Content Caching ein wichtiger technischer Baustein, um Last, Bandbreite und Updateverteilung sinnvoll zu steuern.
Da Verzögerungen bei der Installation der letzten iOS-Updates sehr oft ein Sicherheitsrisiko darstellen, ist uns daran gelegen, an jeder Schule die bestmöglichen Vorraussetzungen zu schaffen,
um so viele iPads so schnell wie möglich zu aktualisieren. 


Die entscheidenden Fragen, die man einem Cache stellen kann:

- Wird er tatsächlich genutzt?
- Wird er zum richtigen Zeitpunkt genutzt?
- Passt die Aktivität zur bekannten Geräteanzahl eines Standorts?
- Deuten Auffälligkeiten auf Struktur- oder Konfigurationsprobleme hin, oder liegt die Ursache eher vor Ort, etwa beim Handling der iPads bzgl. Ladezustand der Akkus und Ort der Lagerung / Erreichbarkeit des WLAN.

Dieses Projekt soll dafür belastbare Daten liefern.

## Zielbild

Das Projekt soll Standorte identifizierbar machen, die bei iOS-/iPadOS-Updates deutlich hinterherhinken oder sich im Cache-Verhalten auffällig verhalten.

Dabei gilt als Grundprinzip:

- technische Ursachen zuerst auf eigener Seite prüfen
- zuerst zentrale Infrastrukturprobleme beheben
- organisatorische Ursachen nicht spekulativ, sondern datenbasiert ansprechen
- Ggf. Unterstützung konstruktiv und faktenbasiert anbieten

Das Ziel ist Risikoreduktion und Resilienz aller Komponenten, nicht Kontrolle oder Schuldzuweisung.

## Kernfunktionen

Das Logger-Skript erfasst in regelmäßigen Intervallen unter anderem:

- Summenwerte wie TotalBytesReturnedToClients
- Summenwerte wie TotalBytesStoredFromOrigin
- Intervall-Deltas aus kumulativen Zählern
- CacheUsed
- MaxCachePressureLast1Hour (CachePr)
- CacheDetails mit Fokus auf iOS Software
- Peer-Erkennung
- Netzwerkstatus der beiden Interfaces von en0 / en1 (in aller Regel LAN / WLAN)
- Default Interface
- Gateway-IP
- DNS-Resolve-Check für Apple-Ziele
- HTTPS-/Erreichbarkeitstest gegen Apple-CDN
- AppleTTFB als einfacher Antwortindikator
- GDMF-basierte iOS-/iPadOS-Updateinformationen
- optional standortbezogene Zusatzinformation wie bekannte Gerätekapazität bzw. ClientsCnt

## Ausgabeformate

Die Ausgabe erfolgt bewusst in zwei getrennten CSV-Dateien:

### Raw

Die Raw-Datei ist die primäre, maschinenlesbare Quelle.

Merkmale:

- stabile Struktur
- möglichst roh und eindeutig
- leere Felder statt kosmetischer Platzhalter
- ISO-8601-Zeitstempel mit Zeitzone
- numerische Werte ohne dekorative Zusätze
- für Parsing, Weiterverarbeitung und spätere Analyse gedacht

### Hu

Die Hu-Datei ist die menschenlesbare Variante.

Merkmale:

- kompakter und schneller erfassbar
- Werte teilweise in lesbarer Form formatiert
- Einheiten wie %, ms, oder GB
- gedacht für die schnelle Sichtprüfung und ad-hoc-Einschätzung

Die Grundregel lautet:

Raw ist die fachliche Quelle.  
Hu ist die komfortable Ableitung.

## Typischer Einsatz

Das Skript läuft auf einem Mac Mini mit aktiviertem Apple Content Caching und wird periodisch durch einen LauchDaemon ausgeführt.

Aktuell ist der periodische Betrieb auf ein Intervall von 900 Sekunden (aka Viertelstunde) ausgelegt.

Wichtige Betriebsartefakte:

- Skript: /usr/local/bin/assetcache_logger.sh
- LaunchDaemon: /Library/LaunchDaemons/de.kommunalbit.assetcachelogger.plist
- Logs / CSV: /Library/Logs/KommunalBIT/
- State-Datei: /var/tmp/assetcache_logger_state.tsv

## Projektbestandteile

Dieses Repository enthält:

- den Logger aka das Skript, das mitliest und in eine CSV-Datei schreibt
- Installer-/Deploy-Skripte für Relution
- Cleanup-/Deinstaller-Skripte
- LaunchDaemon-Definition
- Dokumentation zu CSV-Feldern, Rollout und Troubleshooting
- Beispielkonfigurationen
- anonymisierte Beispieldaten

## Repository-Struktur

Empfohlene Struktur:

- `scripts/`  
  Enthält Logger, Installer, Cleanup und ggf. gemeinsame Hilfsfunktionen.

- `launchd/`  
  Enthält die LaunchDaemon-`plist`.

- `config/`  
  Enthält Beispielkonfigurationen, aber keine sensiblen produktiven Standortdaten.

- `docs/`  
  Enthält technische und fachliche Dokumentation.

- `examples/`  
  Enthält anonymisierte Beispiel-CSV-Dateien oder Musterausgaben.

## Deployment über Relution

Die Verteilung erfolgt über Relution.

Grundprinzip:

1. Ein Installer-Skript wird per Relution auf dem Zielsystem mit Root-Rechten ausgeführt.
2. Das Skript installiert oder aktualisiert Logger und LaunchDaemon.
3. Der LaunchDaemon übernimmt den periodischen Betrieb.
4. Die .CSV-Dateien werden lokal auf dem Zielsystem geschrieben.
5. Bei Bedarf bereinigt ein Cleanup-/Deinstaller-Skript ältere oder fehlerhafte Stände.

Relution ist dabei der Verteilmechanismus, nicht die eigentliche Fachlogik des Projekts.

## Aktueller Fokus

Der aktuelle Fokus liegt auf:

- stabilem Logging
- robuster Verteilung
- sauberer Versionierung
- nachvollziehbarer Dokumentation
- belastbarer Auswertbarkeit
- schrittweiser Trennung von Code und standortbezogener Konfiguration

## Wichtige Messgrößen im Überblick

Einige zentrale Felder:

- `ServedDelta`  
  Datenmenge, die im letzten Intervall an Clients ausgeliefert wurde.

- `OriginDelta`  
  Datenmenge, die im letzten Intervall von Apples Update-Servern geladen wurde.

- `CachePr`  
  Verdichteter Hinweis auf Speicherdruck bzw. Verdrängungsdruck im Cache.

- `AppleTTFB`  
  Time To First Byte gegen ein Apple-Ziel; grober Indikator für Erreichbarkeit und Reaktionsverhalten.

- `Peers`  
  Erkannte andere Cache-Server im Netz.

- `ClientsCnt`  
  Verhältnis der erkannten Nachfragen von iPads zum bekannten Gerätebestand eines Standorts.

- `iOSUpdates`  
  GDMF-basierte Sicht auf aktuelle relevante iOS-/iPadOS-Versionen.

Die vollständige Feldbeschreibung steht in `docs/csv-fields.md`.

## Warum dieses Projekt nicht nur "Monitoring" ist

Das Projekt ist kein Selbstzweck und kein bloßes Sammeln relevanter Kennzahlen.

Es soll helfen, nach relevanten Releases zeitnah und belastbar zu beantworten:

- Welche Standorte zeigen plausibles Verhalten?
- Welche nicht?
- Wo muss technisch eingegriffen werden?
- Wo sollte organisatorisch angesetzt werden?
- Wo lohnt sich gezielte Beratung?

## Konfiguration und sensible Daten

Produktive Standortdaten, Zuordnungstabellen, Host-spezifische Sonderlogik und andere sensible Informationen sollen nicht unkontrolliert in den allgemeinen Projektkern gelangen.

Deshalb gilt:

- Im Repository liegen nur Beispiel- oder anonymisierte Konfigurationen.
- Echte Standortdaten gehören in lokale oder private Konfigurationsdateien.
- Veröffentlichbare und interne Projektanteile sollen sauber getrennt bleiben.

## Versionierung

Dieses Projekt soll versionssauber geführt werden.

Das bedeutet insbesondere:

- Änderungen werden nachvollziehbar dokumentiert.
- Ausrollbare Stände erhalten klare Versionsnummern.
- Produktive und experimentelle Stände werden getrennt gehalten.
- Dokumentation und Code sollen denselben fachlichen Stand widerspiegeln.

Weitere Details stehen in `docs/versioning-policy.md`.

## Dokumentation

Weiterführende Dokumentation befindet sich in:

- `docs/overview.md`
- `docs/csv-fields.md`
- `docs/rollout-relution.md`
- `docs/troubleshooting.md`
- `docs/versioning-policy.md`

## Status

Aktiver Entwicklungs- und Betriebsstand.

Referenz für den aktuellen Rollout-Stand ist derzeit die konsistente Versionierung von Installer und Cleanup im Bereich `v1.6.4`.

## Hinweis

Dieses Repository bildet den technischen Kern des Projekts ab.

Nicht allgemein veröffentlichungsfähige Betriebsdetails, echte Standortdaten und lokale Sonderkonfigurationen sollten getrennt gehalten werden.