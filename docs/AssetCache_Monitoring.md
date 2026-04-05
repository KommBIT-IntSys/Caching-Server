# Asset Cache Monitoring – KommunalBIT

Monitoring und Logging des Apple Content Caching auf Mac Minis in Schulen.  
**Aktuelle Version: 1.6.2**

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

Das Skript läuft auf einem Mac Mini mit aktiviertem Apple Content Caching und wird alle **15 Minuten** durch einen LaunchDaemon ausgeführt. Es liest Metriken aus `AssetCacheManagerUtil`, ergänzt sie um Netzwerk- und WLAN-Diagnosewerte und schreibt sie in zwei CSV-Dateien.

---

## Ausgabeformat

Pro Host werden zwei parallele CSV-Dateien geschrieben, jeweils unter `/Library/Logs/KommunalBIT/`:

| Datei | Zweck |
|---|---|
| `<HOST>_RAW.csv` | Maschinenlesbar – reine Zahlenwerte, leere Felder, ISO-8601-Zeitstempel mit Zeitzone |
| `<HOST>_HU.csv` | Menschenlesbar – Einheiten (GB, %, ms, dB), `n/a` für fehlende Werte |

**Grundregel:** RAW ist die fachliche Quelle. HU ist die komfortable Ableitung für die Sichtprüfung.

Bei Erkennung einer neuen iOS-Version werden die bisherigen CSV-Dateien automatisch in `/Library/Logs/KommunalBIT/Archiv/` verschoben.

---

## Grundprinzip der CSV-Ausgaben

Das Monitoring erzeugt zwei CSV-Dateien mit weitgehend identischem fachlichem Inhalt, aber unterschiedlicher Zielrichtung:

- **RAW-CSV**: für maschinelle Auswertung, Skripte, Filter und Import in Analysewerkzeuge
- **HU-CSV**: für schnelle Sichtprüfung durch Menschen

Die **RAW-CSV** ist streng, nüchtern und möglichst verlustfrei formatiert.  
Die **HU-CSV** ist darauf optimiert, dass man sie direkt öffnet und zügig versteht.

Die Human-readable-Datei soll innerhalb weniger Sekunden Antworten auf drei Fragen geben:

1. Ist der Cache grundsätzlich aktiv und liefert er Daten aus?
2. Gibt es Hinweise auf Engpässe, Netzwerkprobleme oder Fehlkonfiguration?
3. Passt die Aktivität grob zur erwartbaren Zahl der iPads am Standort?

Sie ist also kein Rohdatenarchiv, sondern ein bewusst lesbares Diagnoseprotokoll.

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
- **RAW:** Epochensekunden, z. B. `1743588000`
- **HU:** lesbares Datum, z. B. `2026-02-01` – wird nur für 20 Zeilen nach einer Änderung angezeigt, danach leer (analog zu `iOSUpdates`)

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
Zeigt, wie viel Material der Cache „von außen“ holen musste, um es später lokal weiterzugeben.

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

### iOSBytes

**Bedeutung:**  
Im Cache gehaltene Datenmenge für iOS-/iPadOS-Software.

**Nutzen:**  
Hilft, allgemeine Cache-Nutzung von update-bezogener Nutzung zu unterscheiden.

**Darstellung:**
- **RAW:** Bytes (Integer)
- **HU:** z. B. `74.2 GB`

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

### Peers

**Bedeutung:**  
Liste anderer im Netz erkannter Content-Caching-Peers.

**Nutzen:**  
Zeigt, ob der Cache andere Caches in seiner Umgebung sieht. Das kann für Architektur, Reichweite und Redundanz relevant sein.

**Darstellung:**
- **RAW:** semikolon-getrennte IP-Adressen, z. B. `10.1.2.3;10.1.2.4`
- **HU:** Anzahl, z. B. `2`

---

### EN0

**Bedeutung:**  
Status des Netzwerkinterfaces `en0` (in der Regel LAN).

**Nutzen:**  
Sehr kompakte, aber diagnostisch starke Sicht auf die tatsächliche Netzsituation.

**Darstellung:**
- **RAW:** IP-Adresse oder Status (`down` / `noip` / `active`)
- **HU:** identisch zu RAW

---

### EN1

**Bedeutung:**  
Status des Netzwerkinterfaces `en1` (in der Regel WLAN).

**Nutzen:**  
Ergänzt `EN0` und hilft, die tatsächlich aktive Netzlage des Systems zu verstehen.

**Darstellung:**
- **RAW:** IP-Adresse oder Status
- **HU:** identisch zu RAW

---

### GatewayIP

**Bedeutung:**  
IP-Adresse des aktuell genutzten Default-Gateways.

**Nutzen:**  
Hilft, Netzkontext und Routinglage sichtbar zu machen.

**Darstellung:**
- **RAW:** IP-Adresse des Default-Gateways
- **HU:** identisch zu RAW

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

> WLAN-Felder sind leer, wenn `wdutil` nicht verfügbar ist oder das WLAN-Interface nicht aktiv ist.

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

Noch wertvoll wird eine Monitoring-CSV-Datei in Kombination
- mit den Werten der anderen Caching-Server
- mit einer geeigneten Auswertung aller SuS-iPads in Relution - Felder: Organisation | Gerätename | OS Version | OS Update Status | Letzte Verbindung | Batteriestand

Verknüpft man all diese Dateien ein, zwei Wochen nach einem iOS-Update auf intelligente Art, ergibt sich schnell eine klare Handlungsperspektive für jeden einzelnen Standort.

Genau darin liegt ihr Wert: Sie macht aus verstreuten Cache-Metriken eine lesbare Geschichte.

---

## Standortkonfiguration (`schulen.conf`)

Das Skript liest die Zuordnung von Schulkürzeln zu iPad-Anzahl lokal aus:

`/etc/kommunalbit/schulen.conf`

Die Tabelle der Schulen mit der jeweiligen Anzahl an SuS- (Schüler und Schülerinnen-) iPads wurde aus datenschutzrechtlichen Gründen nicht in das öffentliche Repo übernommen. Sie enthält standortbezogene Bestandsdaten, die nur intern verwaltet werden sollen. Die Tabelle wird stattdessen über das Monitoring Deploy-Script in Relution mitgegeben, wo sie passwort-geschützt, aber für alle Admins leicht zugänglich ist.
