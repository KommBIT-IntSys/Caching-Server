# Asset Cache Monitoring – KommunalBIT

Monitoring und Logging des Apple Content Caching auf Mac Minis in Schulen.  
**Aktuelle Version: 1.8.0**

---

## Motivation

In einer Umgebung mit vielen schulisch genutzten iPads ist Apple Content Caching ein wichtiger technischer Baustein, um Last, Bandbreite und Updateverteilung sinnvoll zu steuern. Da Verzögerungen bei der Installation aktueller iOS-Updates ein Sicherheitsrisiko darstellen, ist es das Ziel, an jeder Schule die bestmöglichen Voraussetzungen zu schaffen, um so viele Geräte wie möglich zeitnah zu aktualisieren.

Die entscheidenden Fragen:

- Wird der Cache tatsächlich genutzt?
- Wird er zum richtigen Zeitpunkt genutzt?
- Passt die Aktivität zur bekannten Geräteanzahl eines Standorts?
- Deuten Auffälligkeiten auf Infrastruktur- oder Konfigurationsprobleme hin – oder liegt die Ursache eher vor Ort, etwa beim Handling der iPads bzgl. Ladezustand und WLAN-Erreichbarkeit?

Der Schwerpunkt liegt nicht auf dem reinen Sammeln von Zahlen, sondern auf datenbasierter Einordnung. Das Ziel ist Risikoreduktion und Resilienz – nicht Kontrolle oder Schuldzuweisung.

---

## Funktionsweise

Das Skript läuft auf einem Mac Mini mit aktiviertem Apple Content Caching und wird alle **15 Minuten** durch einen LaunchDaemon ausgeführt. Es liest Metriken aus `AssetCacheManagerUtil`, ergänzt sie um Netzwerk- und WLAN-Diagnosewerte und schreibt sie in drei CSV-Dateien (RAW, HU und CO).

---

## Interne Datenverarbeitung (RAW-first-Prinzip)

Das Monitoring-Skript arbeitet nach einem klaren, einheitlichen Verarbeitungsmodell:

1. **Collect (Snapshot)**
   Alle relevanten Systemwerte werden einmalig im selben Durchlauf erfasst
   (Content Caching, Netzwerk, Apple-Erreichbarkeit, WLAN).

2. **RAW-Datenbasis**
   Aus diesem Snapshot wird die vollständige RAW-Datenstruktur aufgebaut.
   Diese bildet die vollständige, technische Datenbasis des Systems.

3. **Ableitung von HU und CO**
   Die beiden weiteren CSV-Formate werden ausschließlich aus der RAW-Datenbasis erzeugt:
   - **HU (Human Readable)**: menschenlesbare Darstellung mit Einheiten und vereinfachter Sicht
   - **CO (Companion / KI-Format)**: datensparsame, maschinenlesbare Auswahl für externe Auswertung

4. **Keine zusätzlichen Systemabfragen**
   HU und CO führen keine eigenen Messungen durch.
   Alle drei CSV-Dateien basieren auf demselben technischen Zustand.

Dieses Prinzip stellt sicher, dass alle Ausgaben konsistent sind und sich direkt miteinander vergleichen lassen.

---

## Skripte im MDM-/Relution-Betrieb

Das Projekt besteht nicht nur aus dem eigentlichen Monitoring-Skript, sondern aus mehreren Skripten mit klar getrennter Zuständigkeit im Betriebsmodell.

Kurz gesagt:

- `assetcache_logger.sh` misst und protokolliert
- `deploy_assetcache_logger.sh` installiert und aktiviert
- `uninstall_assetcache_logger.sh` entfernt und bereinigt
- Archiv-/Hilfsskripte sichern Übergänge bei Update, Wartung und Rollout

Nicht jedes Skript läuft dauerhaft. Die Betriebs- und Hilfsskripte werden bei Bedarf über Relution ausgeführt. Das eigentliche Monitoring läuft danach lokal und autonom über den LaunchDaemon weiter.

---

### `scripts/assetcache_logger.sh`

Das ist das eigentliche Monitoring-Skript.

Es erfasst die relevanten Content-Caching-, Netzwerk-, Reachability- und WLAN-Daten und schreibt drei CSV-Dateien: RAW als technische Primärquelle, HU und CO als daraus abgeleitete Views. Hier entsteht die fachliche Datengrundlage des Projekts.

**Aufgaben:**

- Metriken aus `AssetCacheManagerUtil` auslesen
- Delta-Werte berechnen
- Peer-, Client-, Netzwerk- und Apple-Erreichbarkeitsdaten erfassen
- RAW-, HU- und CO-CSV schreiben (RAW als Primärquelle, HU und CO als Ableitungen)
- State-Dateien verwalten
- CSV-Dateien bei neuen iOS-/iPadOS-Versionen archivieren

**Nicht seine Aufgabe:** Deployment, Deinstallation oder manuelle Bereinigung.

---

### `scripts/deploy_assetcache_logger.sh`

Das ist das Installations- und Bereitstellungsskript für den Relution-Betrieb.

Es bringt das Zielsystem in den gewünschten Zustand: Hauptskript, LaunchDaemon, Verzeichnisse, Rechte und produktive `schulen.conf`.

**Aufgaben:**

- `assetcache_logger.sh` bereitstellen oder aktualisieren
- LaunchDaemon anlegen oder aktualisieren
- Verzeichnisse und Rechte herstellen
- `schulen.conf` mitgeben
- Regelbetrieb aktivieren

**Besonderheit:**  
Es enthält Workarounds für den bekannten Relution-Bug, bei dem Punkte in bestimmten Strings oder Dateinamen durch Unterstriche ersetzt werden können.

**Nicht seine Aufgabe:** fachliche Messlogik.

#### Herkunft und Pflege der Standorttabelle

Die produktive `schulen.conf` wird nicht im öffentlichen Repository gepflegt.

Grundlage für diese Tabelle ist eine geeignete interne Auswertung aus Relution, aus der hervorgeht, wie viele relevante SuS-iPads einem Standort aktuell zugeordnet sind. Diese Information wird auf einem lokalen, passwortgeschützten Admin-Rechner weiterverarbeitet und in das für das Monitoring benötigte Format überführt.

Für diese interne Auswertung gilt das Prinzip der Datenminimierung. Für die standortbezogene Ableitung der Tabelle werden Organisationszuordnung und fachlich notwendige Zustandsdaten benötigt; Gerätebezeichnungen einzelner iPads werden dafür bewusst nicht benötigt und sollen nicht Bestandteil des Standardexports sein.

Verwendet wird dabei eine tabgetrennte Tabelle nach dem Muster:

```text
SCHULKÜRZEL<TAB>ANZAHL
```

Diese Tabelle wird vor dem Ausrollen des Deploy-Skripts manuell in die Relution-Version des Skripts eingefügt bzw. dort aktualisiert. Das Repository enthält dafür nur die veröffentlichbare Logik und gegebenenfalls eine Beispielkonfiguration, nicht jedoch die produktiven Standortdaten.

Pflegen, erzeugen und einfügen können diese Tabelle nur Personen mit entsprechendem Zugriff auf die Relution-Auswertung und auf die MDM-Deployment-Verwaltung. Dadurch bleiben öffentliches Repository, produktive Standortdaten und tatsächlicher Rollout organisatorisch und technisch voneinander getrennt.

---

### `scripts/uninstall_assetcache_logger.sh`

Das ist das Rückbau- und Bereinigungsskript.

Es entfernt das Monitoring sauber vom System und beseitigt dabei auch Altlasten früherer Versionen oder problematischer Deployments.

**Aufgaben:**

- LaunchDaemon stoppen und entfernen
- installiertes Monitoring-Skript entfernen
- State-Dateien bereinigen
- historische Altlasten oder falsch benannte Dateien entfernen
- sauberen Ausgangszustand für Neuinstallation oder Test herstellen

**Wichtig:**  
Es ist nicht nur ein formales Gegenstück zum Deploy-Skript, sondern ausdrücklich auch ein Bereinigungswerkzeug.

---

### Archiv- und Hilfsskripte

Diese Skripte unterstützen Rollout, Wartung und Versionswechsel.

Ihre Aufgabe ist nicht das laufende Monitoring, sondern ein sauberer Übergang zwischen Betriebszuständen, etwa durch Stoppen des Daemon, Archivieren bestehender CSV-Dateien oder Vorbereiten eines neuen Deployments.

**Typische Aufgaben:**

- Daemon vor Wartung oder Archivierung stoppen
- bestehende CSV-Dateien ins Archiv verschieben
- Schreibkonflikte vermeiden
- Folge-Deployment vorbereiten

**Nicht ihre Aufgabe:** vollständige Inbetriebnahme oder fachliche Messung.

---

### Typischer Ablauf im Betrieb

1. System bei Bedarf bereinigen
2. bestehende CSV-Dateien vor Update archivieren
3. neue Version per Deploy-Skript ausrollen
4. LaunchDaemon übernimmt den Regelbetrieb
5. `assetcache_logger.sh` läuft lokal alle 15 Minuten
6. Wartung, Update oder Bereinigung bei Bedarf gezielt über Hilfsskripte anstoßen

---

### Warum diese Trennung wichtig ist

Die Aufteilung auf mehrere Skripte trennt Messlogik, Verteilung, Bereinigung und Wartung sauber voneinander.

Das macht das Projekt robuster, verständlicher und im Relution-Betrieb besser beherrschbar.

---

## Ausgabeformat

Pro Host werden drei parallele CSV-Dateien geschrieben, jeweils unter `/Library/Logs/KommunalBIT/`:

| Datei | Zweck |
|---|---|
| `<PREFIX>_AssetCacheRaw_v<VERSION>.csv` | Maschinenlesbar – reine Zahlenwerte, leere Felder, ISO-8601-Zeitstempel mit Zeitzone |
| `<PREFIX>_AssetCache_Hu_v<VERSION>.csv` | Menschenlesbar – Einheiten (GB, %, ms, dB), `n/a` für fehlende Werte |
| `<PREFIX>_AssetCache_Co_v<VERSION>.csv` | Datensparsam – kein voller Hostname, keine IPs, maschinenlesbar, für KI-gestützte externe Auswertung |

`<PREFIX>` entspricht in der Regel dem ersten Teil des Hostnamens vor dem ersten `-`.

**Grundregel:** RAW ist die primäre technische Datenbasis; HU und CO werden daraus abgeleitet. **CO ist das bevorzugte Format für KI-gestützte oder externe Auswertung** – insbesondere in Kombination mit einem datensparsam vorbereiteten Relution-/MDM-Export.

Bei Erkennung einer neuen iOS-Version werden alle drei CSV-Dateien automatisch in `/Library/Logs/KommunalBIT/Archiv/` verschoben.

---

## Grundprinzip der CSV-Ausgaben

Das Monitoring erzeugt drei CSV-Dateien mit unterschiedlicher Zielrichtung:

- **RAW-CSV**: für maschinelle Auswertung, Skripte, Filter und Import in Analysewerkzeuge – vollständig, verlustfrei, intern
- **HU-CSV**: für schnelle Sichtprüfung durch Menschen – lesbar, mit Einheiten, intern
- **CO-CSV**: für KI-gestützte oder externe Auswertung – datensparsam, keine IPs, kein voller Hostname

Die **RAW-CSV** ist streng, nüchtern und möglichst verlustfrei formatiert.  
Die **HU-CSV** ist darauf optimiert, dass man sie direkt öffnet und zügig versteht.  
Die **CO-CSV** ist auf sichere, datensparsame Weitergabe optimiert – insbesondere zur Kombination mit einem geeignet reduzierten Relution-/MDM-Export für KI-gestützte Standortanalyse.

RAW ist die primäre Datenquelle; HU und CO werden intern aus RAW abgeleitet, ohne eigene Systemabfragen.

Die Human-readable-Datei soll innerhalb weniger Sekunden Antworten auf drei Fragen geben:

1. Ist der Cache grundsätzlich aktiv und liefert er Daten aus?
2. Gibt es Hinweise auf Engpässe, Netzwerkprobleme oder Fehlkonfiguration?
3. Passt die Aktivität grob zur erwartbaren Zahl der iPads am Standort?

Sie ist also kein Rohdatenarchiv, sondern ein bewusst lesbares Diagnoseprotokoll.

> **Für KI-gestützte Auswertung:** Bevorzugt die **CO-CSV** verwenden, nicht RAW oder HU. CO enthält keine konkreten IP-Adressen, keinen vollen Hostnamen und keine reinen Troubleshooting-Felder. In Kombination mit einem ebenfalls datensparsam vorbereiteten Relution-Export (Felder: Organisation | OS Version | OS Update Status | Letzte Verbindung) ist CO das geeignete Eingabeformat für KI-Assistenten wie Microsoft Copilot.

---

## CO-CSV-Felder (14 Spalten)

Die CO-Datei enthält eine bewusst reduzierte Auswahl aus dem Gesamtdatenmodell. Sie folgt dem Prinzip der Datensparsamkeit: Es werden nur Felder aufgenommen, die für die kombinierte Auswertung mit Relution-/MDM-Daten fachlich notwendig sind.

**Nicht enthalten in CO:** voller Hostname, TotalsSince, TotReturned, TotOrigin, EN0/EN1 (IP), GatewayIP, DefaultIf, WifiNoise, WifiCCA.

| Feld | Format | Nutzen |
|---|---|---|
| `SiteCode` | Zeichenkette (PREFIX) | Standortbezug für Join mit Relution-Export; kein voller Hostname |
| `Timestamp` | ISO 8601 mit Zeitzone | zeitliche Einordnung; maschinenlesbar und stabil |
| `PeerCnt` | Integer | Anzahl erkannter Cache-Peers; strukturelle Einordnung, keine IP-Adressen |
| `ClientsCnt` | `aktiv/gesamt` oder `aktiv` | Aktivitätsverhältnis; zentraler Einordnungswert |
| `iOSUpdates` | Versionsliste | aktuell relevante iOS-/iPadOS-Versionen; Update-Kontext |
| `iOSBytes` | Bytes (Integer) | iOS-Softwareanteil im Cache; unterscheidet allgemeine von update-bezogener Nutzung |
| `ServedDelta` | Bytes (Integer) | primärer Aktivitätsindikator im Intervall |
| `OriginDelta` | Bytes (Integer) | Nachladebedarf im Intervall; zusammen mit ServedDelta entscheidend |
| `CacheUsed` | Bytes (Integer) | aktueller Cachebelegungsstand |
| `CachePr` | Integer 0–100 | Cache-Druckindikator; wichtiger Gesundheitswert |
| `DNSRes` | 0 / 1 | DNS-Auflösung funktionsfähig |
| `AppleReach` | 0 / 1 | Apple CDN erreichbar |
| `AppleTTFB` | Millisekunden (Integer) | Apple CDN-Latenz aus Standortsicht |
| `WiFiSNR` | Integer (dB), leer wenn LAN | WLAN-Signalqualität; relevant wenn Mac Mini per WLAN betrieben wird |

**Bewusste Designentscheidungen für CO:**
- `SiteCode` statt `Hostname`: Das Schulkürzel (z. B. `ASGS`) ist für die standortbezogene Analyse ausreichend; unnötige Infrastrukturdetails wie vollständiger Gerätename entfallen.
- Keine IP-Adressen (EN0/EN1, GatewayIP): Für die Frage „Ist der Standort technisch unauffällig?" genügen `DNSRes` und `AppleReach`.
- Keine kumulativen Totals (TotReturned, TotOrigin): Für Intervallanalyse sind Deltawerte aussagekräftiger.
- `TotalsSince` entfällt: Für KI-Auswertung nicht notwendig; wird nur für tiefes technisches Troubleshooting benötigt.
- `WiFiSNR` inklusive: Kann leer sein (LAN-Betrieb), gibt aber bei WLAN-Problemen wichtigen Kontext.

---

## CSV-Felder (23 Spalten)

### Hostname

**Bedeutung:**  
Der Name des Rechners, auf dem das Monitoring läuft.

**Nutzen:**  
Wichtig, wenn CSV-Dateien aus mehreren Schulen oder Testsystemen zusammengeführt werden. Der Hostname macht sofort sichtbar, von welchem Mac Mini ein Datensatz stammt.

**Darstellung:**
- **RAW:** Hostname des Mac Mini
- **HU:** identisch zu RAW

---

### Timestamp

**Bedeutung:**  
Zeitpunkt der Messung.

**Nutzen:**  
Erlaubt die zeitliche Einordnung jedes Datensatzes. Zusammen mit den Delta-Werten lässt sich nachvollziehen, ob in einem bestimmten Intervall tatsächlich Cache-Aktivität stattfand.

**Darstellung:**
- **RAW:** ISO-8601 mit Zeitzone, z. B. `2026-04-02T10:15:00+02:00`
- **HU:** lokal lesbar ohne Offset, z. B. `2026-04-02 10:15:00`

---

### TotalsSince

**Bedeutung:**  
Zeitpunkt, seit dem die vom System gemeldeten kumulierten Gesamtzähler gelten.

**Nutzen:**  
Die Gesamtwerte des Content Cache sind nicht „für immer“, sondern beziehen sich auf eine Zählerbasis, die sich ändern kann, etwa nach Neustarts oder internen Resets. `TotalsSince` markiert den Startpunkt dieser Zählperiode.

**Interpretation:**  
Wenn sich `TotalsSince` ändert, dürfen Delta-Werte nicht blind mit der vorherigen Zeile verglichen werden.

**Darstellung:**
- **RAW:** ISO-8601 mit Zeitzone, z. B. `2026-02-01T10:15:00+02:00`
- **HU:** lesbares Datum, z. B. `2026-02-01` – wird nur für 20 Zeilen nach einer Änderung angezeigt, danach leer (analog zu `iOSUpdates`)

---

### Peers

**Bedeutung:**  
Liste anderer im Netz erkannter Content-Caching-Peers.

**Nutzen:**  
Zeigt, ob der Cache andere Caches in seiner Umgebung sieht. Das kann für Architektur, Reichweite und Redundanz relevant sein.

**Darstellung:**
- **RAW:** semikolon-getrennte IP-Adressen, z. B. `10.1.2.3;10.1.2.4`
- **HU:** Anzahl, z. B. `2`

---

### ClientsCnt

**Bedeutung:**  
Relation zwischen aktuell aktiven Clients und der für den Standort hinterlegten Gesamtzahl relevanter Geräte.

**Nutzen:**  
Dieses Feld verbindet technische Aktivität mit dem organisatorischen Standortkontext. Es soll nicht nur zeigen, dass etwas passiert, sondern ob die beobachtete Aktivität grob zur Größe des Standorts passt.

**Sonderfall:**  
Wenn ein Hostname keiner bekannten Schule zugeordnet ist, wird nur die erkennbare aktive Client-Zahl protokolliert, ohne Prozentbezug.

**Darstellung:**
- **RAW:** `aktiv/gesamt` (z. B. `4/122`) oder nur `aktiv`, wenn Standort unbekannt
- **HU:** Prozentsatz (z. B. `3.3%`) oder nur `aktiv`, wenn Standort unbekannt

**Quelle:**  
Aktive Clients der letzten ca. 16 Minuten aus dem Systemlog, bezogen auf den bekannten Gerätebestand des Standorts aus `schulen.conf`.

---

### iOSUpdates

**Bedeutung:**  
Kurzinformation zu den aktuell relevanten iOS-/iPadOS-Versionen laut Apple GDMF API.

**Nutzen:**  
Dieses Feld macht sichtbar, ob gerade ein relevantes Update-Ereignis im Raum steht. Es verknüpft technische Aktivität mit dem äußeren Anlass.

**Besonderheit:**  
Änderungen der Versionsliste lösen CSV-Archivierung aus.

**Darstellung:**
- **RAW:** Versionsliste, z. B. `18.4;18.3.2`
- **HU:** grundsätzlich wie RAW, aber wird nur für 20 Zeilen nach einer Änderung angezeigt, danach leer – reduziert Rauschen im Normalfall

---

### iOSBytes

**Bedeutung:**  
Im Cache gehaltene Datenmenge für iOS-/iPadOS-Software.

**Nutzen:**  
Hilft, allgemeine Cache-Nutzung von update-bezogener Nutzung zu unterscheiden.

**Darstellung:**
- **RAW:** Bytes (Integer)
- **HU:** z. B. `74.2 GB`

---

### TotReturned

**Bedeutung:**  
Gesamtmenge aller Daten, die der Cache seit `TotalsSince` an Clients ausgeliefert hat.

**Nutzen:**  
Das ist einer der zentralen Aktivitätsindikatoren des gesamten Systems. Er zeigt, ob der Cache tatsächlich als lokaler Verteiler arbeitet.

**Darstellung:**
- **RAW:** Bytes (Integer)
- **HU:** z. B. `142.3 GB`

---

### TotOrigin

**Bedeutung:**  
Gesamtmenge aller Daten, die der Cache seit `TotalsSince` von Apple-Servern bezogen und lokal gespeichert hat.

**Nutzen:**  
Zeigt, wie viel Material der Cache „von außen” holen musste, um es später lokal weiterzugeben.

**Interpretation:**  
Im Zusammenspiel mit `TotReturned` erkennt man grob das Verhältnis zwischen Einspeicherung und Auslieferung.

**Darstellung:**
- **RAW:** Bytes (Integer)
- **HU:** z. B. `18.7 GB`

---

### ServedDelta

**Bedeutung:**  
Datenmenge, die seit der letzten verwertbaren Messung zusätzlich an Clients ausgeliefert wurde.

**Nutzen:**  
Das ist die eigentliche Aktivität im Intervall. Während `TotReturned` die Historie zeigt, sagt `ServedDelta`, was seit der letzten Zeile passiert ist.

**Interpretation:**
- `0 B`: Im letzten Intervall keine erkennbare Auslieferung
- kleiner Wert: leichte Aktivität
- großer Wert: aktive Nutzung, oft Update- oder Installationsphase

**Darstellung:**
- **RAW:** Bytes (Integer)
- **HU:** z. B. `1.2 GB`

---

### OriginDelta

**Bedeutung:**  
Datenmenge, die der Cache seit der letzten verwertbaren Messung neu von Apple-Servern bezogen hat.

**Nutzen:**  
Ergänzt `ServedDelta`. Während `ServedDelta` die Ausgabe an Clients beschreibt, zeigt `OriginDelta`, ob der Cache im gleichen Zeitraum auch neue Inhalte von Apple nachgeladen hat.

**Interpretation:**
- **ServedDelta hoch, OriginDelta niedrig:** viel wurde aus lokal vorhandenem Cache bedient
- **ServedDelta hoch, OriginDelta ebenfalls hoch:** Aktivität läuft, aber der Cache muss zugleich viel neu beschaffen
- **OriginDelta hoch, ServedDelta niedrig:** der Cache füllt sich, aber es wurde noch wenig lokal weiterverteilt

**Darstellung:**
- **RAW:** Bytes (Integer)
- **HU:** z. B. `240 MB`

---

### CacheUsed

**Bedeutung:**  
Aktuell belegter Speicherplatz des Content Cache.

**Nutzen:**  
Zeigt, wie viel Platz der Cache derzeit insgesamt nutzt.

**Einordnung:**  
Allein betrachtet ist dieser Wert nur begrenzt aussagekräftig. Spannend wird er vor allem zusammen mit SSD-Größe, `CachePr` und realem Aktivitätsniveau.

**Darstellung:**
- **RAW:** Bytes (Integer)
- **HU:** z. B. `85.4 GB`

---

### CachePr

**Bedeutung:**  
`MaxCachePressureLast1Hour`, also ein Verdichtungs- bzw. Druckindikator des Cache innerhalb der letzten Stunde.

**Nutzen:**  
Einer der wichtigsten Gesundheitswerte des Systems. Er gibt Hinweise darauf, ob der Cache unter Platzdruck steht und Inhalte aggressiv verdrängen muss.

**Grobe Einordnung:**
- **0–30 %**: unkritisch
- **30–70 %**: beobachten
- **70–100 %**: deutlicher Druck, mögliche Effizienzverluste

**Hinweis:**  
Ein leerer oder fehlender Wert bedeutet nicht automatisch einen Fehler; in der HU-CSV wird ein fehlendes `0` bewusst menschenfreundlich als `0` dargestellt.

**Darstellung:**
- **RAW:** Integer (0–100)
- **HU:** z. B. `42%`

---

### EN0

**Bedeutung:**  
Status des Netzwerkinterfaces `en0` (in der Regel LAN).

**Nutzen:**  
Sehr kompakte, aber diagnostisch starke Sicht auf die tatsächliche Netzsituation.

**Darstellung:**
- **RAW:** konkrete IPv4-Adresse des Interfaces, oder `down` bzw. `noip`
- **HU:** `down`, `noip` oder `up` (konkrete IP-Adresse wird zu `up` normalisiert)

HU enthält bewusst keine konkreten IP-Adressen. Für externe oder außerhäusige Auswertungen soll bevorzugt die HU-Version verwendet werden.

---

### EN1

**Bedeutung:**  
Status des Netzwerkinterfaces `en1` (in der Regel WLAN).

**Nutzen:**  
Ergänzt `EN0` und hilft, die tatsächlich aktive Netzlage des Systems zu verstehen.

**Darstellung:**
- **RAW:** konkrete IPv4-Adresse des Interfaces, oder `down` bzw. `noip`
- **HU:** `down`, `noip` oder `up` (konkrete IP-Adresse wird zu `up` normalisiert)

Gleiche Normalisierungslogik wie `EN0`.

---

### GatewayIP

**Bedeutung:**  
IP-Adresse des aktuell genutzten Default-Gateways.

**Nutzen:**  
Hilft, Netzkontext und Routinglage sichtbar zu machen.

**Darstellung:**
- **RAW:** konkrete IPv4-Adresse des Default-Gateways, oder leer wenn kein Gateway ermittelt wurde
- **HU:** `yes` wenn ein Gateway vorhanden ist, `no` wenn keines ermittelt wurde

Auch hier enthält HU bewusst keine konkrete IP-Adresse.

---

### DefaultIf

**Bedeutung:**  
Die Netzwerkschnittstelle, über die die Standardroute läuft.

**Nutzen:**  
Hilft zusammen mit `EN0`, `EN1` und `GatewayIP`, das tatsächlich genutzte Netz zu erkennen.

**Darstellung:**
- **RAW:** Interface-Name, z. B. `en0`
- **HU:** identisch zu RAW

---

### DNSRes

**Bedeutung:**  
Ergebnis eines DNS-Resolve-Checks für `swcdn.apple.com`.

**Nutzen:**  
Schneller Nachweis, ob die Namensauflösung für relevante Apple-Ziele grundsätzlich funktioniert.

**Darstellung:**
- **RAW:** `1` (erfolgreich) / `0` (fehlgeschlagen)
- **HU:** `yes` / `no`

---

### AppleReach

**Bedeutung:**  
Ergebnis eines einfachen Erreichbarkeitstests zum Apple CDN (Content Delivery Network).

**Nutzen:**  
Ergänzt den DNS-Check um die Frage, ob das Ziel nicht nur auflösbar, sondern auch erreichbar ist.

**Interpretation:**  
HTTP 2xx bis 4xx gilt als erreichbar.

**Darstellung:**
- **RAW:** `1` / `0`
- **HU:** `yes` / `no`

---

### AppleTTFB

**Bedeutung:**  
Time To First Byte gegen das Apple CDN.

**Nutzen:**  
Ein pragmatischer Indikator für Netz- und Serverantwortverhalten aus Sicht des Standorts.

**Grobe Einordnung:**
- unter ca. 150 ms: sehr gut
- 150–500 ms: okay bis unauffällig
- deutlich darüber: auffällig, beobachten

**Darstellung:**
- **RAW:** Millisekunden (Integer)
- **HU:** z. B. `38ms`

**Hinweis:**  
Leer, wenn das Ziel nicht erreichbar ist.

---

### WiFiSNR

**Bedeutung:**  
Signal-Rausch-Abstand des WLANs in dB.

**Nutzen:**  
Wertvoller Qualitätsindikator, falls der Mac Mini tatsächlich per WLAN arbeitet oder testweise dort positioniert ist.

**Darstellung:**
- **RAW:** Integer (dB)
- **HU:** z. B. `42dB`

---

### WifiNoise

**Bedeutung:**  
Gemessener Rauschpegel des WLANs.

**Nutzen:**  
Ergänzt `WiFiSNR` und hilft bei der Einordnung gestörter Funkumgebungen.

**Darstellung:**
- **RAW:** Integer (dBm, negativ)
- **HU:** z. B. `-92dBm`

---

### WifiCCA

**Bedeutung:**  
Clear Channel Assessment, vereinfacht: wie stark der Funkkanal belegt oder beschäftigt ist.

**Nutzen:**  
Hilft einzuschätzen, ob ein Standort auf WLAN-Ebene unter Konkurrenz oder Kanalstress leidet.

**Darstellung:**
- **RAW:** Integer (0–100)
- **HU:** z. B. `18%`

> Wenn `wdutil` nicht verfügbar ist oder das WLAN-Interface nicht aktiv ist, bleiben die WLAN-Felder in RAW leer; in HU erscheinen sie als `n/a`.

---

## Warum die Human-readable-CSV bewusst anders formatiert ist

Die HU-Datei ist nicht bloß eine „schönere“ RAW-Datei. Sie verfolgt ein anderes Ziel:

- Byte-Werte werden lesbar skaliert
- Zeitstempel werden menschlich dargestellt
- fehlende Werte werden als `n/a` oder `0` so dargestellt, dass man sie beim Lesen korrekt einordnet
- Prozent- und Diagnosefelder sollen auf einen Blick erfassbar sein

Sie ist damit das operative Sichtfenster für schnelle Beurteilung, während die RAW-Datei die analytische Grundlage für spätere systematische Auswertung bleibt.

---

## Wichtige Felder für die schnelle Lagebeurteilung

Wenn man eine HU-CSV rasch überfliegt, sind diese Felder meist zuerst interessant:

- `ServedDelta`
- `OriginDelta`
- `ClientsCnt`
- `iOSUpdates`
- `iOSBytes`
- `CachePr`
- `AppleTTFB`
- `EN0`, `EN1`, `DefaultIf`, `GatewayIP`

Diese Kombination beantwortet oft die Kernfrage:

**Ist der Standort gerade aktiv, plausibel versorgt und technisch unauffällig?**

---

## Einordnung der CSV insgesamt

Die CSV ist kein Selbstzweck. Sie dient dazu, für die Schulen datenbasiert zu unterscheiden zwischen:

- wenig Aktivität, weil gerade schlicht nichts los ist
- wenig Aktivität trotz relevantem Update-Anlass
- technischer Unauffälligkeit bei organisatorischem Rückstand
- technischer Auffälligkeit mit möglichem Infrastrukturbezug

Noch wertvoller wird eine Monitoring-CSV-Datei in Kombination

- mit den Werten der anderen Caching-Server
- mit einer geeigneten Auswertung aller SuS-iPads in Relution – Felder: Organisation | OS Version | OS Update Status | Letzte Verbindung | Batteriestand
- mit dieser Dokumentation als fachlichem Kontext

**Empfehlung für KI-gestützte Auswertung:** Bevorzugt die **CO-CSV** (`<PREFIX>_AssetCache_Co_v<VERSION>.csv`) verwenden. Sie ist speziell für diesen Zweck entworfen: kein voller Hostname, keine IP-Adressen, nur die fachlich notwendigen Felder. In Kombination mit einem datensparsam vorbereiteten Relution-Export (Spalte Gerätename möglichst weglassen oder nachträglich entfernen) ergibt sich ein geeignetes Eingabeformat für Copilot oder vergleichbare KI-Assistenten.

Der Gerätename wird für diese Auswertung bewusst nicht benötigt und sollte aus Gründen der Datenminimierung nicht Teil des Standardexports sein. Die Analyse erfolgt auf aggregierter Standortebene, nicht auf Ebene einzelner Geräte (Anmerkung: in der aktuellen Version von Relution 26.1.1 ist es leider nicht möglich, die Gerätenamen beim Export wegzulassen - man kann aber natürlich die Spalte nachträglich entfernen).

Verknüpft man diese Daten ein, zwei Wochen nach einem iOS-Update, kann daraus im Kontext dieser Dokumentation eine belastbare Auswertung mit klaren Handlungsvorschlägen pro Standort entstehen.

---

## Standortkonfiguration (`schulen.conf`)

Das Skript liest die Zuordnung von Schulkürzeln zu iPad-Anzahl lokal aus:

`/etc/kommunalbit/schulen.conf`

Diese Datei ist bewusst nicht Teil des öffentlichen Repositories. Sie enthält die produktive standortbezogene Konfiguration für `ClientsCnt` und wird im internen Deployment-Kontext über Relution mitgegeben.

Die Trennung zwischen öffentlichem Projektkern und produktiver Standorttabelle ist Absicht: Die veröffentlichbare Monitoring-Logik bleibt dadurch von intern zu pflegenden Standortdaten getrennt.

Wie diese Tabelle erzeugt, gepflegt und in das Deploy-Skript übernommen wird, ist im Abschnitt zu `scripts/deploy_assetcache_logger.sh` beschrieben.
