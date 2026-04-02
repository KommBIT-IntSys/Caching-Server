# Versioning Policy

## Zweck

Diese Datei definiert, wie das Projekt versioniert wird.

Ziel ist nicht formale Perfektion, sondern ein belastbarer, nachvollziehbarer und im Betriebsalltag brauchbarer Umgang mit Änderungen an:

- Logger
- Deploy-Skript
- Cleanup-/Uninstall-Skript
- LaunchDaemon
- CSV-Feldern
- Konfigurationsformat
- Dokumentation

## Grundprinzip

Versioniert wird nicht nur Code, sondern der **produktive Projektstand**.

Eine Version beschreibt daher immer den zusammengehörigen Stand von:

- Skripten
- LaunchDaemon
- relevanter Dokumentation
- Konfigurationsannahmen
- Betriebslogik

## Versionsschema

Verwendet wird das Schema:

`MAJOR.MINOR.PATCH`

Beispiel: `1.6.1`

### PATCH
Kleine Korrekturen ohne grundlegende Änderung des fachlichen Verhaltens.

Typische Fälle:
- Quoting-Fixes
- Pfadkorrekturen
- robuste Fehlerbehandlung
- kleinere Deploy-/Cleanup-Fixes
- Doku-Korrekturen ohne fachliche Änderung

### MINOR
Neue Funktionen oder spürbare Erweiterungen innerhalb der bestehenden Projektlogik.

Typische Fälle:
- neues CSV-Feld
- neue GDMF-Logik
- neue Prüfschritte
- neue oder deutlich geänderte Deploy-Logik
- neue Auswertungsdimension wie `ClientsCnt`

### MAJOR
Grundlegende Umstellung des Projekts.

Typische Fälle:
- neues Datenmodell
- andere Grundstruktur der CSV-Ausgabe
- grundlegender Wechsel der Konfigurationslogik
- großer Umbau der Betriebsarchitektur

## Was eine Version umfasst

Eine Projektversion umfasst mindestens:

- `scripts/assetcache_logger.sh`
- `scripts/deploy_assetcache_logger.sh`
- `scripts/uninstall_assetcache_logger.sh`
- `launchd/de.kommunalbit.assetcachelogger.plist`
- `README.md`
- `CHANGELOG.md`

Wenn eine dieser Komponenten fachlich betroffen ist, soll ihr Stand zur Version passen.

## Release-Regeln

Ein Versionssprung erfolgt nur, wenn der Stand mindestens diese Bedingungen erfüllt:

1. Der Code ist konsistent eingecheckt.
2. README und Changelog passen fachlich dazu.
3. Der Rollout-Zweck der Version ist klar.
4. Es ist nachvollziehbar, ob es sich um Test-, Übergangs- oder Produktivstand handelt.

## Produktivstand vs. Experiment

### Produktivstand
Ein Stand, der grundsätzlich auf Schul-Macs verteilt werden darf.

### Teststand
Ein Stand, der bewusst nur auf Testsystemen oder ausgewählten Geräten geprüft wird.

Empfohlene Kennzeichnung:
- Release/Tag nur für produktionsnahe oder definierte Teststände
- unfertige Zwischenstände nur als normale Commits

## Dateinamen vs. Versionsnummer

Die Versionsnummer gehört primär in:

- Git-Tags / Releases
- `CHANGELOG.md`
- Dokumentation

Nicht jeder Release soll neue Dateinamen erzwingen.

Daher gilt:
- stabile Dateinamen im Repository bevorzugen
- Versionssprünge über Git und Dokumentation abbilden
- Version im Dateinamen nur dann, wenn technisch oder betrieblich wirklich nötig

## Dokumentationspflicht

Bei jeder fachlich relevanten Änderung ist mindestens zu prüfen, ob angepasst werden müssen:

- `README.md`
- `CHANGELOG.md`
- technische Detaildoku in `docs/`
- Konfigurationsbeispiele in `config/`

## Sensible Daten

Produktive Standortdaten gehören nicht in den allgemeinen Repo-Kern.

Ins Repository gehören nur:
- Beispielkonfigurationen
- anonymisierte Beispiele
- veröffentlichbare technische Dokumentation

Nicht ins Repository gehören:
- echte Schulkürzel mit Produktivbezug
- produktive Tabellenstände
- interne Sonderlogik, sofern sie nicht abstrahiert ist

## Historische Realität des Projekts

Das Projekt ist nicht aus formalem Greenfield-Engineering entstanden, sondern aus iterativer praktischer Arbeit im Feldbetrieb.

Deshalb gilt rückblickend:
- frühe Versionen sind nicht immer streng rekonstruierbar
- stille Korrekturen und manuelle Zwischenstände haben existiert
- ab Repository-Einführung und strukturierter Pflege gilt ein höherer Anspruch an Nachvollziehbarkeit

## Zielzustand

Der Zielzustand ist:

- ein klar definierter produktiver Stand
- nachvollziehbare Änderungen
- saubere Trennung von Code, Doku und Konfiguration
- belastbare Reproduzierbarkeit von Rollouts

---

## Projektgeschichte und Entwicklung

### Ausgangspunkt

Das Projekt entstand aus einer praktischen betrieblichen Frage:

Wie lässt sich belastbar erkennen, ob Apple Content Caching an verteilten Schulstandorten tatsächlich den erwarteten Nutzen bringt – insbesondere rund um iOS-/iPadOS-Updates – und ob Auffälligkeiten eher technische oder organisatorische Ursachen haben?

Im Zentrum stand von Anfang an nicht nur das reine Monitoring, sondern die Unterscheidung zwischen:

- infrastrukturellen Ursachen auf zentraler oder technischer Seite
- organisatorischen bzw. lokalen Ursachen an den einzelnen Standorten

### Frühe Phase

Die frühe Phase war explorativ geprägt. Zunächst wurde untersucht:

- welche Kennzahlen `AssetCacheManagerUtil status` überhaupt zuverlässig liefert
- welche davon im realen Betrieb aussagekräftig sind
- wie Delta-Werte aus kumulativen Zählern sinnvoll berechnet werden können
- welche Netzwerk- und Erreichbarkeitsprüfungen den Cache-Betrieb sinnvoll ergänzen

Bereits in dieser Phase wurde deutlich, dass reine Momentaufnahmen nicht genügen. Deshalb entstand früh der Ansatz eines periodischen Loggings mit Zustandsdatei und Delta-Berechnung.

### Erste nutzbare Monitoring-Versionen

Mit den frühen produktiv brauchbaren Versionen wurde der Grundstein gelegt:

- LaunchDaemon-basierter Betrieb im 15-Minuten-Takt
- Logging zentraler Cache-Metriken
- Speicherung auf dem Zielsystem unter `/Library/Logs/KommunalBIT/`
- Nutzung einer State-Datei für Differenzberechnung

In dieser Phase ging es vor allem darum, aus vielen möglichen Kennzahlen diejenigen auszuwählen, die im Alltag tatsächlich interpretierbar sind.

### Methodischer Reifeschritt: Raw und Hu

Ein entscheidender Entwicklungsschritt war die Trennung in zwei CSV-Ausgaben:

- **Raw** als fachliche, maschinenlesbare Quelle
- **Hu** als menschenlesbare Sicht für schnelle Prüfung

Diese Trennung war mehr als ein Komfortmerkmal. Sie definierte die Architektur des Projekts neu:

- Rohdaten bleiben stabil und weiterverarbeitbar
- komfortable Sichtprüfung bleibt möglich
- kosmetische Darstellung und fachliche Quelle werden nicht vermischt

Diese Entscheidung prägt das Projekt bis heute.

### Netzwerk- und Reachability-Diagnostik

Im weiteren Verlauf wurde klar, dass Cache-Nutzung allein nicht ausreicht. Ergänzt wurden daher unter anderem:

- DNS-Resolve-Checks
- HTTPS-Erreichbarkeit gegen Apple-CDN
- `AppleTTFB` als grober Antwortindikator
- Interface-Status
- Gateway- und Default-Interface-Ermittlung
- Peer-Erkennung

So entwickelte sich das Projekt von einfachem Cache-Logging zu einem kompakteren Betriebsdiagnose-Werkzeug.

### iOS-/iPadOS-Release-Bezug über GDMF

Ein weiterer wesentlicher Schritt war die Integration von Apple GDMF-Daten.

Damit wurde es möglich, Cache-Aktivität nicht nur abstrakt zu messen, sondern in Beziehung zu konkreten iOS-/iPadOS-Release-Zeitpunkten zu setzen. Diese Ergänzung war fachlich wichtig, weil das Projekt genau dort seinen größten Nutzen entfaltet: rund um relevante Updatefenster.

### Standortbezug und `ClientsCnt`

Später kam die Einsicht hinzu, dass reine Aktivitätsdaten ohne Verhältnis zur bekannten Gerätebasis eines Standorts nur begrenzten Aussagewert haben.

Deshalb wurde die standortbezogene Zuordnung einer bekannten iPad-Anzahl eingeführt. Daraus entstand `ClientsCnt` als zusätzliche Einordnungshilfe.

Diese Erweiterung diente nicht der Statistik um ihrer selbst willen, sondern der besseren Interpretation:
Nicht jede geringe Aktivität ist auffällig; entscheidend ist ihr Verhältnis zur erwartbaren Gerätebasis.

### Rollout-Realität und Relution-Sonderlogik

Parallel zur fachlichen Entwicklung lief die betriebliche Realität der Verteilung.

Das Projekt musste nicht nur Daten sammeln, sondern auch:
- robust installiert werden
- sauber aktualisiert werden
- Altlasten entfernen
- mit Besonderheiten von Relution umgehen

Besonders prägend war dabei ein Relution-spezifisches Problem, bei dem Punkte in bestimmten Kontexten zu Unterstrichen verändert wurden. Daraus ergaben sich Workarounds in Deploy- und Cleanup-Skripten.

Diese Phase machte deutlich, dass das Projekt nicht nur fachlich, sondern auch betrieblich gehärtet werden musste.

### Von gewachsener Bastelrealität zu versionierter Struktur

Wie viele funktionierende technische Projekte entstand auch dieses nicht als vollständig vorausgeplantes System, sondern iterativ im Feldbetrieb.

Dazu gehörten:
- manuelle Zwischenstände
- spontane Korrekturen
- nicht immer vollständig dokumentierte lokale Änderungen
- pragmatische Tests unter realen Einsatzbedingungen

Mit der Zeit wurde jedoch klar, dass diese Arbeitsweise an Grenzen stößt. Daraus entstand der Schritt hin zu:

- Repository-Struktur
- klarer Trennung von Code, Doku und Konfiguration
- Changelog
- Versionierungsrichtlinie
- veröffentlichbarem Kern mit Beispielkonfiguration statt Produktivdaten

### Heutiger Stand

Der aktuelle Stand des Projekts ist das Ergebnis dieser Entwicklung.

Das Projekt ist heute:

- ein Monitoring-Werkzeug für Apple Content Caching im Schulumfeld
- ein Hilfsmittel zur Interpretation von Update-Verzögerungen
- ein Werkzeug zur Unterscheidung technischer und organisatorischer Ursachen
- ein praxisnahes Betriebsprojekt mit wachsender Versions- und Dokumentationsdisziplin

Die aktuelle Repository-Struktur bildet diesen Reifegrad sichtbar ab:
- `scripts/`
- `launchd/`
- `config/`
- `docs/`

### Leitgedanke

Der Leitgedanke des Projekts ist über alle Versionen hinweg gleich geblieben:

Nicht spekulieren, sondern messen.  
Nicht vorschnell Schuld zuweisen, sondern Ursachen trennen.  
Nicht bloß Zahlen sammeln, sondern daraus belastbare Gespräche und sinnvolle Verbesserungen ableiten.
