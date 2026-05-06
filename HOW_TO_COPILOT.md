# HOW TO COPILOT – iOS-Updatestand auswerten

## Kurzanleitung
zur standortbasierten Auswertung des iOS-Updatestands
mit Microsoft Copilot. Ziel: für jeden Standort einschätzen,
ob Update-Rückstände technische oder organisatorische Ursachen haben.

## Was du brauchst

Zwei Dateien, die du vor der Auswertung vorbereitest:

**1. AssetCache_Co_alle_Standorte.csv**
Alle CO-CSV-Dateien der Caching-Server zu einer Datei zusammenführen.
→ [`scripts/Merge_Co_CSV.ps1`](scripts/Merge_Co_CSV.ps1) (Windows)
→ [`scripts/merge_co_csv.sh`](scripts/merge_co_csv.sh) (macOS)

**2. Geraete_Global_Co_JJJJ-MM-TT.csv**
MDM-Export datenschutzkonform bereinigen:
Gerätenamen entfernen, Organisationsname auf Kürzel kürzen.
→ [`scripts/Relution-Export-Cleaner_Co.ps1`](scripts/Relution-Export-Cleaner_Co.ps1) (Windows)
→ [`scripts/relution_cleaner_co.sh`](scripts/relution_cleaner_co.sh) (macOS)

## So geht's

1. Beide Skripte ausführen → zwei CSV-Dateien liegen bereit
2. Microsoft Copilot öffnen
3. Beide CSV-Dateien hochladen
4. Den Prompt unten vollständig hineinkopieren
5. Auswertung erhalten
6. Weitere Fragen stellen

---

## Prompt für MS Copilot

---

```
# Datenmodell: Asset Cache & Relution Export

> **Zweck:** Diese Sektion wird dem Auswertungs-Prompt **vor** den
> `GRUNDPRINZIPIEN` vorangestellt. Sie liefert einer kontextfreien
> KI das benötigte Domänenwissen über die zwei Eingabedateien und
> ihre Felder. Ohne diese Sektion arbeitet der Prompt nur dann
> verlässlich, wenn die KI die Begriffe (`AssetCache`, `Relution`,
> `applePendingVersion`, `WiFiSNR`, `CachePr` etc.) bereits aus
> eigenem Vorwissen kennt — was bei schwächeren Modellen oder bei
> Übertragung an andere Organisationen nicht vorausgesetzt werden
> darf.

> **Robustheitshinweis:** Alle Felder werden über ihren
> Spaltennamen referenziert, nicht über die Position. Die
> Reihenfolge der Spalten in den CSVs darf beliebig sein. Fehlende
> oder umbenannte Spalten sind in der Schema-Validierung am Beginn
> der Auswertung explizit zu benennen, bevor mit der inhaltlichen
> Analyse begonnen wird.

---

## Hintergrund: Apple Content Caching (Kontext für die KI)

Apple Content Caching speichert iOS-/iPadOS-Updates und andere
Apple-Inhalte lokal auf einem Mac Mini im Schul- oder
Standortnetzwerk zwischen. Anfragen der iPads werden vom Cache
bedient, statt jeden Download einzeln aus dem Apple-Origin zu
ziehen. Das spart Bandbreite und beschleunigt Update-Wellen
erheblich — sofern der Cache groß genug ist, das benötigte
Material vorzuhalten, und sofern die Endgeräte den Cache
tatsächlich erreichen.

Die dem Cache zugewiesene Speichergröße variiert pro Standort,
weil sie an die SSD-Größe des jeweiligen Mac Mini und an die
lokale Konfiguration gebunden ist. Beobachtete Bandbreite in der
KommunalBIT-Umgebung: rund 80 GB bis 300+ GB pro Standort. Diese
Variabilität ist für die Interpretation von `CachePr` (siehe
unten) entscheidend.

`Relution` ist das eingesetzte Mobile Device Management (MDM).
Es liefert pro iPad einen Datensatz mit Versions-, Status- und
Verfügbarkeitsinformationen — als Momentaufnahme zum
Exportzeitpunkt, ohne historischen Verlauf.

---

## Datei 1: `AssetCache_Co_alle_Standorte.csv`

**Herkunft:** Zusammenführung mehrerer CO-CSV-Logs der
Apple-Content-Caching-Server (Mac Minis), je Standort einer. Die
einzelnen Logs werden durch ein vorgelagertes Merge-Skript zu
einer Datei zusammengeführt.

**Datenstruktur:** Eine Zeile pro Caching-Server pro
Messintervall (Polling-Logger). Mehrere Zeilen pro Standort über
den Auswertungszeitraum hinweg. **Eine Aggregation über die Zeit
ist erforderlich**, um Standort-Profile zu bilden — Einzelzeilen
sind nicht aussagekräftig.

**Zeilenmenge:** Typisch hunderte bis tausende Zeilen, abhängig
von Auswertungszeitraum × Standortzahl × Polling-Intervall.

| Spaltenname          | Bedeutung                                                                      | Wertetyp / Einheit                                 | Interpretationsrichtung              | Hinweis / Caveat                                                                                                                                                                                                                                                                   |
|----------------------|--------------------------------------------------------------------------------|----------------------------------------------------|--------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `Standort` (o. ä.)   | Identifikator des Caching-Servers / der Schule                                 | String, Kürzel                                     | kategorial                           | Schlüssel für Aggregation und für das Matching gegen die Relution-Datei. Genauer Spaltenname kann je nach Logger-Implementierung variieren.                                                                                                                                        |
| `Timestamp` (o. ä.)  | Zeitpunkt der Messung                                                          | ISO-8601 Datetime                                  | chronologisch                        | Definiert das Polling-Intervall. Differenzen zwischen aufeinanderfolgenden Timestamps ergeben das Intervallfenster für die Delta-Felder.                                                                                                                                            |
| `iOSUpdates`         | Vom Asset Cache als verfügbar erkannte iOS-/iPadOS-Update-Versionen            | String (ggf. komma- oder semikolongetrennte Liste) | kategorial                           | **Primärquelle für die Ableitung der Zielversion.** Kann pro Standort und über die Zeit variieren. Bei Inkonsistenz oder Mehrfachnennung: Zielversion als unsicher kennzeichnen, nicht raten.                                                                                      |
| `ClientsCnt`         | Anzahl unterschiedlicher Clients, die im Intervall den Cache kontaktiert haben | Integer, Zählwert                                  | höher = mehr Aktivität im Intervall  | **Intervall-Kennzahl, NICHT Gesamtnutzung.** Schwankt mit Polling-Fenster, Tageszeit, Schulferien. Niedriger Wert ≠ Problem.                                                                                                                                                       |
| `ServedDelta`        | Vom Cache an Clients ausgelieferte Datenmenge im Intervall                     | Bytes, Delta seit letzter Messung                  | höher = mehr Cache-Auslieferung      | Nur in Kombination mit `ClientsCnt` und `iOSUpdates` interpretierbar.                                                                                                                                                                                                             |
| `OriginDelta`        | Vom Cache aus dem Apple-Origin nachgeladene Datenmenge im Intervall            | Bytes, Delta seit letzter Messung                  | für sich allein nicht bewertbar      | `OriginDelta` hoch + `ServedDelta` niedrig: Cache füllt sich, liefert aber wenig aus. `OriginDelta` hoch + `ServedDelta` hoch: aktive Verteilphase. `OriginDelta` dauerhaft hoch + `CachePr` dauerhaft hoch: Hinweis auf Eviction-Druck (Cache zu klein für das gehaltene Material). |
| `DNSRes`             | DNS-Auflösung für Apple-Hostnames vom Caching-Server aus                      | vermutlich Latenz in ms oder Statuscode            | bei Latenz: niedriger = besser       | **Semantik vor Implementierung verifizieren** (Latenz vs. Boolean vs. Status).                                                                                                                                                                                                    |
| `AppleReach`         | Erreichbarkeit der Apple-Update-Server vom Caching-Server aus                  | vermutlich Boolean oder Statuscode                 | true / OK = besser                   | **Format verifizieren** (Boolean / Statuscode / Latenz-Wert).                                                                                                                                                                                                                     |
| `AppleTTFB`          | Time to First Byte zum Apple-Origin                                            | Millisekunden                                      | niedriger = besser                   | Indikator für die externe Anbindungsqualität des Caching-Servers.                                                                                                                                                                                                                 |
| `CachePr`            | **Cache Pressure** — Auslastung des dem Cache zugewiesenen Speichers           | Prozent (0–100)                                    | **U-förmig**, siehe unten            | Die zugrundeliegende Cache-Größe variiert pro Standort (typisch 80–300+ GB) und ist nicht in der CSV enthalten. Daher sind nur prozentuale Vergleiche zwischen Standorten zulässig, keine absoluten Speicheraussagen.                                                              |
| `WiFiSNR`            | Signal-Rausch-Verhältnis des am Caching-Server anliegenden WLANs               | dB                                                 | höher = besser                       | **Indirekter Indikator:** misst die Anbindung des Servers, nicht die der iPads im Klassenzimmer. Aussagekraft für Endgeräte-Konnektivität daher begrenzt.                                                                                                                          |

### Interpretation von `CachePr` (Cache Pressure)

`CachePr` ist eine **U-förmige Kennzahl**, keine monoton
"höher-ist-besser/schlechter"-Größe. Sie wird mit den folgenden
Erfahrungswerten interpretiert:

- **um 20 %** → Cache wird kaum gefüllt. Häufig korreliert mit
  niedrigem `ClientsCnt` und niedrigem `ServedDelta` über längere
  Zeit. Hypothese: geringe Nutzung des Standorts oder Geräte
  erreichen den Cache nicht.
- **40–60 %** → gesundes Arbeitsfenster. Cache wird genutzt, hat
  aber Reserven für neue Versionen.
- **dauerhaft 80 % und höher** → **Kapazitätsmangel**. Der Cache
  kann nicht alle benötigten Versionen gleichzeitig vorhalten,
  ältere Inhalte werden evictet, Updates müssen wiederholt aus
  dem Apple-Origin nachgeladen werden. Erkennbar typischerweise
  zusätzlich an dauerhaft erhöhtem `OriginDelta` während aktiver
  Update-Phasen. Konkrete Behebungsmaßnahme: zugewiesene
  Cache-Größe erhöhen (z. B. externe USB-C-SSD am Mac Mini, neue
  Konfiguration). Das ist eine **infrastrukturelle**, klar
  adressierbare Ursache — nicht organisatorisch.

Ein einzelner Messwert reicht nicht für eine Bewertung; es muss
über mehrere Polling-Intervalle hinweg ein konsistentes Bild
entstehen.

---

## Datei 2: `Geraete_Global_Co_YYYY-MM-DD.csv`

**Herkunft:** Export aus dem Relution MDM. Vor der Auswertung
durch das Cleaner-Skript datenschutzkonform aufbereitet:
Gerätenamen entfernt, Organisationsname auf Kürzel reduziert.

**Datenstruktur:** Eine Zeile pro verwaltetem iPad.
**Momentaufnahme** zum Exportzeitpunkt — kein historischer
Verlauf.

**Zeitversatz:** Das Datum im Dateinamen (`YYYY-MM-DD`) ist der
Exportzeitpunkt. Dieser kann vom Zeitraum der Cache-Messungen
abweichen. Differenzen sind in der Auswertung explizit zu
benennen, nicht zu glätten.

**Zeilenmenge:** Eine Zeile pro Gerät. In der
KommunalBIT-Konstellation typischerweise einige tausend Zeilen,
bei kleineren Organisationen entsprechend weniger.

| Spaltenname                  | Bedeutung                                                       | Wertetyp / Einheit                      | Interpretationsrichtung                                | Hinweis / Caveat                                                                                                                                                                                                                                                  |
|------------------------------|-----------------------------------------------------------------|-----------------------------------------|--------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `Organisation` (o. ä.)       | Kürzel der Schule / Organisation, dem das Gerät zugeordnet ist  | String, Kürzel                          | kategorial                                             | **Schlüssel für das Matching gegen die AssetCache-Datei.** Kürzel müssen zwischen beiden Dateien identisch sein, sonst kein Join möglich.                                                                                                                         |
| `osVersion`                  | Aktuell auf dem Gerät installierte iOS-/iPadOS-Version          | String, SemVer-ähnlich (z. B. `18.2.1`) | **Hauptkriterium** für Updatestand                     | Vergleich gegen die aus `iOSUpdates` abgeleitete Zielversion. **Stringvergleich vermeiden** — als SemVer parsen, sonst gilt `17.10` lexikalisch als kleiner als `17.2`.                                                                                           |
| `applePendingVersion`        | Von Apple bzw. dem MDM erkannte ausstehende Update-Version      | String oder leer                        | gefüllt = Update erkannt, aber noch nicht installiert  | Wichtigster Indikator für die Trennung "weiß Bescheid, tut aber nichts" (eher organisatorisch) vs. "weiß nichts" (eher infrastrukturell oder Hardware-Cutoff).                                                                                                    |
| `lastConnectionDate`         | Letzter Kontakt des Geräts zum MDM                              | ISO-8601 Datetime                       | aktueller = wahrscheinlicher in Nutzung                | Nur als **Muster über viele Geräte** aussagekräftig. Viele alte Werte + niedrige `batteryLevel` → Hinweis auf organisatorisches Problem. Einzelnes altes Datum ist bedeutungslos.                                                                                  |
| `batteryLevel`               | Akkustand zum Zeitpunkt des letzten MDM-Kontakts                | Integer 0–100 oder Float 0–1            | höher = wahrscheinlicher gerade in Nutzung / geladen   | **Einheit verifizieren.** Massenhafte niedrige Werte sind ein organisatorischer Indikator (Geräte liegen ungeladen im Schrank).                                                                                                                                    |
| `complianceStatus` (o. ä.)   | MDM-Konformitäts-Status                                         | Enum: `COMPLIANT` / `NONCOMPLIANT`      | kategorial                                             | **Sagt nichts über OS-Aktualität aus.** Nur als separater Datenpunkt darstellen, niemals in die OS-Bewertung einfließen lassen.                                                                                                                                    |
| `Modell` (falls vorhanden)   | iPad-Modellbezeichnung                                          | String                                  | kategorial                                             | Optional, aber wertvoll: erklärt, warum bestimmte Geräte die aktuelle Zielversion strukturell nicht mehr erhalten können (Hardware-Cutoff durch Apple).                                                                                                           |

---

## Verwendungshinweise für die KI

1. **Felder per Spaltenname referenzieren, nicht per Position.**
   Die CSV-Spaltenreihenfolge ist nicht garantiert und kann
   zwischen Organisationen unterschiedlich sein.
2. **Schema-Validierung als ersten Schritt der Auswertung:**
   Prüfen, ob die erwarteten Spalten vorhanden sind, ob der
   abgedeckte Zeitraum konsistent ist, ob die Standort-Kürzel
   zwischen beiden Dateien matchen. Lücken explizit benennen,
   bevor inhaltlich bewertet wird.
3. **Versionsvergleiche immer als SemVer**, nicht als String:
   Major/Minor/Patch numerisch vergleichen.
4. **Zeitliche Aggregation der AssetCache-Daten je Standort**
   über den gesamten Auswertungszeitraum durchführen, bevor mit
   der Relution-Momentaufnahme verglichen wird. Kennzahlen wie
   `CachePr`, `ClientsCnt`, `ServedDelta`, `OriginDelta` sind als
   Verläufe / Mittelwerte / Maxima je Standort zu betrachten,
   nicht als Einzelwerte.
5. **Standort-Matching** zwischen den beiden Dateien über das
   Organisations-/Standort-Kürzel. Mismatches explizit ausweisen.
6. **Kausale Ketten bevorzugen, Einzelsignale meiden:** Eine
   belastbare Hypothese braucht mindestens zwei konsistente
   Signale aus unterschiedlichen Feldern. Beispiel: "hohe
   `CachePr` + hohe `OriginDelta` + viele Geräte unter
   Zielversion" → infrastrukturelle Hypothese (Cache-Kapazität).
   Einzelnes hohes `CachePr` ohne weitere Korrelation → Hinweis,
   nicht Befund.

---

## Bekannte Unsicherheiten / vor Implementierung verifizieren

- Genaue Spaltennamen für **Standort** und **Timestamp** in
  `AssetCache_Co_alle_Standorte.csv`.
- Semantik von **`DNSRes`** (Latenz in ms vs. Statuscode vs.
  Boolean).
- Format von **`AppleReach`** (Boolean vs. Statuscode vs.
  Latenz).
- Einheit von **`batteryLevel`** in der konkreten
  Relution-Export-Variante (0–100 ganzzahlig vs. 0–1 als Anteil).
- Existieren im AssetCache-Log weitere Felder, die der aktuelle
  Prompt nicht referenziert? Falls ja: ergänzen oder explizit als
  "wird nicht ausgewertet" deklarieren, damit eine schwache KI
  sie nicht spekulativ heranzieht.
- Existieren in der Relution-Variante anderer Organisationen
  abweichende Spaltennamen? Falls ja: entweder normalisieren im
  Cleaner-Skript oder im Prompt ein Mapping vorsehen.

---

Bitte analysiere die bereitgestellten Dateien AssetCache_Co_alle_Standorte.csv und Geraete_Global_Co_YYYY-MM-DD.csv gemeinsam.

Ziel der Analyse ist es, standortweise zu bewerten, welche Auffälligkeiten beim iOS-/iPadOS-Updatezustand bestehen und ob diese eher auf infrastrukturelle Ursachen (Cache / Netzwerk), organisatorische Ursachen (Gerätenutzung / Ladeverhalten / Online-Zeiten) oder unklare Faktoren hindeuten.

Die Auswertung ist explorativ. Es dürfen keine festen Schwellenwerte verwendet werden. Unsicherheiten müssen ausdrücklich benannt werden.

---

GRUNDPRINZIPIEN

- Keine Kennzahl darf isoliert bewertet werden. Alle Aussagen müssen auf Kombinationen mehrerer Signale basieren.
- Der MDM-Status COMPLIANT ist kein Indikator für eine aktuelle OS-Version.
- ClientsCnt ist kein Maß für Gesamtnutzung, sondern eine Intervall-Aktivitätskennzahl.
- Relution-Daten sind eine Momentaufnahme, Cache-Daten sind Intervallwerte. Zeitliche Abweichungen sind möglich.
- Widersprüche oder fehlende Daten sind als Unsicherheit zu kennzeichnen, nicht zu glätten.

---

ZIELVERSION UND OS-BEWERTUNG

Leite die erwartete Zielversion aus dem Feld iOSUpdates (AssetCache) ab.

- Wenn iOSUpdates je Standort konsistent ist: nutze diese als Referenz.
- Wenn iOSUpdates fehlt, widersprüchlich oder uneinheitlich ist: kennzeichne die Zielversion als unsicher.

Bewerte Geräte anhand:

- osVersion → Hauptkriterium
- applePendingVersion → zeigt erkannte Update-Bereitschaft

Stelle getrennt dar:

- Geräte auf Zielversion
- Geräte unter Zielversion
- Geräte mit applePendingVersion
- Geräte mit älteren Major-Versionen

Optional:

- MDM-Status (COMPLIANT / NONCOMPLIANT) separat darstellen, aber nicht zur OS-Bewertung verwenden

---

AKTIVITÄT UND CACHE-NUTZUNG

Verwende ausschließlich im Zusammenhang:

- ClientsCnt
- ServedDelta
- OriginDelta

Interpretation:

- Niedriger ClientsCnt allein ist kein Problemindikator
- Niedriger ClientsCnt + niedriger ServedDelta kann auf geringe Nutzung hindeuten
- Hoher ServedDelta bei niedrigem ClientsCnt ist möglich und kein Fehler
- Hoher ClientsCnt bei niedrigem ServedDelta erfordert Kontext (z. B. kleine Requests oder falsches Zeitfenster)

---

GERÄTEVERFÜGBARKEIT

Nutze:

- lastConnectionDate
- batteryLevel

Interpretation nur als Muster:

- Viele alte Verbindungen + niedrige Akkustände → Hinweis auf organisatorische Probleme
- Einzelwerte sind nicht aussagekräftig

Akku-Schwellenwert (gilt auch ohne CO-Daten)

- Standorte, bei denen mehr als 20 % der Geräte einen batteryLevel
  unter 20 aufweisen, sind immer explizit zu nennen – unabhängig davon,
  ob CO-CSV-Daten vorliegen oder nicht.

- Niedrige Akkustände sind ein eigenständiges Warnsignal:
  sie erklären fehlgeschlagene oder verzögerte Updates unabhängig
  von Cache- oder Netzwerkproblemen.

- Formuliere den Befund sachlich, z. B.:
  „X von Y Geräten hatten zum Zeitpunkt des Exports einen Akkustand
  unter 20 % – Updates können dadurch verhindert oder verzögert worden sein."

---

INFRASTRUKTURINDIKATOREN

Nutze:

- DNSRes
- AppleReach
- AppleTTFB
- CachePr
- WiFiSNR

Bewerte diese nur im Zusammenhang mit Aktivität und Updatezustand.

---

INTERPRETATIONSMUSTER

Hinweis auf organisatorische Ursachen (Hypothese):

- Viele Geräte unter Zielversion
- Geringe Aktivität
- Alte lastConnectionDate
- Niedrige Akkustände

Hinweis auf infrastrukturelle Ursachen (Hypothese):

- Geräte sind aktiv
- aber Updates kommen nicht voran
- gleichzeitig auffällige Netzwerk- oder Cache-Indikatoren

Unklare Situation:

- widersprüchliche Signale
- fehlende oder inkonsistente Daten

In allen Fällen:

- keine Urteile, nur Hypothesen
- Hypothesen müssen begründet werden

---

ERGEBNISFORMAT

1. Kurzbewertung je Standort:

- Updatezustand
- Pending Updates
- ältere Versionen
- Aktivität
- Geräteverfügbarkeit
- Infrastrukturindikatoren

2. Priorisierte Standortliste:

- sortiert nach Auffälligkeit (höchste Priorität zuerst)
- Einordnung je Standort:
  - eher Infrastruktur / Cache / Netzwerk
  - eher Organisation / Geräteprozess
  - unklar / weiter prüfen

3. Begründung:

- maximal 2–3 Sätze pro Standort
- ausschließlich auf beobachteten Signalen basierend

4. Methodische Hinweise:

- explizite Nennung von Unsicherheiten
- Hinweise auf Momentaufnahme (MDM) und Zeitversatz
- klare Trennung zwischen:
  - Befund (mehrere konsistente Signale)
  - Hypothese (unsichere oder einzelne Signale)

---

ZUSAMMENFASSUNG

Erstelle am Ende eine kompakte Gesamteinschätzung:

- Welche Standorte sind aktuell am auffälligsten?
- Welche Hypothesen ergeben sich daraus?
- Welche Faktoren sind noch unklar?

Keine Schuldzuweisungen. Ziel ist Ursachenklärung und Priorisierung für weitere Analyse.
```

