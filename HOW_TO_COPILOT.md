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

```
# Datenmodell: Asset Cache & Relution Export

> **Zweck:** Domänenwissen für die KI über die zwei Eingabedateien.
> Ohne diese Sektion arbeitet der Prompt nur dann verlässlich, wenn
> die KI die Begriffe (`AssetCache`, `Relution`, `applePendingVersion`,
> `WiFiSNR`, `CachePr` etc.) bereits aus eigenem Vorwissen kennt.

> **Robustheitshinweis:** Felder werden über Spaltennamen referenziert,
> nicht über Position. Spaltenreihenfolge darf beliebig sein.
> Fehlende oder umbenannte Spalten in der Schema-Validierung am Beginn
> der Auswertung explizit benennen.

---

## Hintergrund: Apple Content Caching

Apple Content Caching speichert iOS-/iPadOS-Updates und andere
Apple-Inhalte lokal auf einem Mac Mini im Standortnetzwerk zwischen.
Anfragen der iPads werden vom Cache bedient, statt jeden Download
einzeln aus dem Apple-Origin zu ziehen. Das spart Bandbreite und
beschleunigt Update-Wellen — sofern der Cache groß genug ist und
die Endgeräte ihn tatsächlich erreichen.

Die Cache-Speichergröße variiert pro Standort (typisch 80–300+ GB),
weil sie an die SSD-Größe des Mac Mini gebunden ist. Diese
Variabilität ist für die Interpretation von `CachePr` entscheidend.

`Relution` ist das eingesetzte MDM. Es liefert pro iPad einen
Datensatz als Momentaufnahme zum Exportzeitpunkt — kein historischer Verlauf.

---

## Datei 1: `AssetCache_Co_alle_Standorte.csv`

**Herkunft:** Zusammenführung mehrerer CO-CSV-Logs der Mac Minis,
je Standort einer.

**Struktur:** Eine Zeile pro Caching-Server pro Messintervall.
Mehrere Zeilen pro Standort über den Auswertungszeitraum.
**Aggregation über die Zeit ist erforderlich** — Einzelzeilen sind
nicht aussagekräftig.

| Spalte         | Bedeutung                                              | Typ / Einheit            | Richtung                       | Hinweis                                                                                                                                                                                                                              |
|----------------|--------------------------------------------------------|--------------------------|--------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `Standort`     | Identifikator des Caching-Servers / Standorts          | String, Kürzel           | kategorial                     | Schlüssel für Aggregation und Matching gegen Relution. Genauer Spaltenname kann variieren.                                                                                                                                          |
| `Timestamp`    | Zeitpunkt der Messung                                  | ISO-8601                 | chronologisch                  | Definiert das Polling-Intervall.                                                                                                                                                                                                     |
| `iOSUpdates`   | Vom Cache erkannte verfügbare iOS-/iPadOS-Versionen    | String (ggf. Liste)      | kategorial                     | **Primärquelle für die Zielversion.** Bei Inkonsistenz: als unsicher kennzeichnen, nicht raten.                                                                                                                                      |
| `ClientsCnt`   | Clients, die im Intervall den Cache kontaktiert haben  | Integer                  | höher = mehr Aktivität         | **Intervall-Kennzahl, NICHT Gesamtnutzung.** Wenige Clients pro 15-Minuten-Fenster sind normal. Niedriger Wert ≠ Problem.                                                                                                            |
| `ServedDelta`  | Vom Cache an Clients ausgelieferte Datenmenge          | Bytes, Delta             | höher = mehr Auslieferung      | Nur mit `ClientsCnt` und `iOSUpdates` interpretierbar.                                                                                                                                                                               |
| `OriginDelta` | Vom Cache aus Apple-Origin nachgeladene Datenmenge     | Bytes, Delta             | für sich allein nicht bewertbar | Hoch + `ServedDelta` niedrig: Cache füllt sich. Hoch + `ServedDelta` hoch: aktive Verteilphase. Dauerhaft hoch + `CachePr` hoch: Eviction-Druck.                                                                                       |
| `DNSRes`       | DNS-Auflösung für Apple-Hostnames                      | Latenz ms / Statuscode   | bei Latenz: niedriger = besser | **Semantik vor Implementierung verifizieren.**                                                                                                                                                                                       |
| `AppleReach`   | Erreichbarkeit der Apple-Update-Server                 | Boolean / Statuscode     | true / OK = besser             | **Format verifizieren.**                                                                                                                                                                                                              |
| `AppleTTFB`    | Time to First Byte zum Apple-Origin                    | ms                       | niedriger = besser             | Indikator für externe Anbindungsqualität.                                                                                                                                                                                            |
| `CachePr`      | **Cache Pressure** — Auslastung des Cache-Speichers    | Prozent (0–100)          | **U-förmig**, siehe unten      | **`CachePr = 0` ist kein Hinweis auf Cache-Inaktivität** — es bedeutet, dass kein Speicherdruck gemessen wurde. Das ist bei normaler oder geringer Nutzung der Regelfall. Cache-Inaktivität ergibt sich ausschließlich aus `ServedDelta∅ = 0` UND `OriginDelta∅ = 0` — niemals aus `CachePr` allein. Cache-Größe variiert pro Standort und ist nicht in der CSV. Nur prozentuale Vergleiche zulässig, keine absoluten Speicheraussagen.                                                                                                  |
| `WiFiSNR`      | Signal-Rausch-Verhältnis am Caching-Server             | dB                       | höher = besser                 | **Indirekt:** misst Anbindung des Servers, nicht der iPads im Klassenzimmer.                                                                                                                                                         |
### Hinweis zur Datei-Variante

Diese Datei kann in zwei Varianten vorliegen:

- **15-Minuten-Variante** (`AssetCache_Co_alle_Standorte.csv`):
  `ServedDelta` und `OriginDelta` sind Deltas pro 15-Minuten-Intervall.
  Für Standort-Aggregate: Mittelwert oder Summe über alle Zeilen des Standorts.

- **Stunden-Variante** (`AssetCache_Co_alle_Standorte_Stunden.csv`):
  `ServedDelta` und `OriginDelta` sind bereits zu Stunden-Summen aggregiert.
  Für Standort-Aggregate: Summe über alle Stunden-Zeilen des Standorts.
  In beiden Fällen gilt: höherer Wert = mehr Cache-Aktivität.

### Interpretation von `CachePr` (U-förmig)

- **0 %** → kein Speicherdruck gemessen. Häufigster Normalzustand außerhalb
  aktiver Update-Wellen. Kein Hinweis auf Cache-Inaktivität.
  Cache-Inaktivität ergibt sich ausschließlich aus `ServedDelta∅ = 0`
  UND `OriginDelta∅ = 0`.
- **um 20 %** → Cache wird kaum gefüllt. Häufig korreliert mit
  niedrigem `ClientsCnt` und `ServedDelta`. Hypothese: geringe
  Nutzung oder Geräte erreichen den Cache nicht.
- **40–60 %** → gesundes Arbeitsfenster.
- **dauerhaft ≥ 80 %** → **Kapazitätsmangel**. Cache kann nicht alle
  benötigten Versionen halten, ältere werden evictet, Updates wiederholt
  aus Apple-Origin nachgeladen. Erkennbar zusätzlich an dauerhaft
  erhöhtem `OriginDelta` während Update-Phasen. **Infrastrukturelle**
  Ursache, klar adressierbar (Cache-Größe erhöhen, z. B. externe SSD).

Ein einzelner Messwert reicht nicht. Bewertung über mehrere Polling-Intervalle.

### Pflichtnennung Cache-Totalausfall

Ein Standort mit `ServedDelta∅ = 0` UND `OriginDelta∅ = 0` über
den gesamten Zeitraum muss immer explizit genannt werden —
unabhängig vom Gerätezustand. Cache-Dienst war nicht aktiv
(weder lokal noch Origin). Klassifikation: **TECHNISCH**.
Handlungsvorschlag: Cache-Dienst auf dem lokalen Server prüfen / neu starten.

---

## Datei 2: `Geraete_Global_Co_YYYY-MM-DD.csv`

**Herkunft:** Relution-Export, durch Cleaner-Skript datenschutzkonform
aufbereitet (Gerätenamen entfernt, Organisationsname auf Kürzel reduziert).

**Struktur:** Eine Zeile pro iPad. **Momentaufnahme** zum Exportzeitpunkt.

**Zeitversatz:** Datum im Dateinamen (`YYYY-MM-DD`) ist Exportzeitpunkt
und kann vom Zeitraum der Cache-Messungen abweichen. Differenzen
explizit benennen, nicht glätten.

| Spalte                | Bedeutung                                          | Typ / Einheit                 | Richtung                                        | Hinweis                                                                                                                                                                       |
|-----------------------|----------------------------------------------------|-------------------------------|-------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `Organisation`        | Kürzel des Standorts                               | String                        | kategorial                                      | **Schlüssel für Matching gegen AssetCache.** Kürzel müssen identisch sein, sonst kein Join.                                                                                  |
| `osVersion`           | Installierte iOS-/iPadOS-Version                   | SemVer (z. B. `18.2.1`)       | **Hauptkriterium**                              | Vergleich gegen Zielversion aus `iOSUpdates`. **Als SemVer parsen, nicht als String** — sonst gilt `17.10` lexikalisch < `17.2`.                                              |
| `applePendingVersion` | Erkannte ausstehende Update-Version                | String oder leer              | gefüllt = Update erkannt, nicht installiert     | Trennt "weiß Bescheid, tut aber nichts" (organisatorisch) von "weiß nichts" (infrastrukturell oder Hardware-Cutoff).                                                          |
| `lastConnectionDate`  | Letzter Kontakt zum MDM                            | ISO-8601                      | aktueller = wahrscheinlicher in Nutzung         | Nur als **Muster über viele Geräte** aussagekräftig. Einzelnes altes Datum ist bedeutungslos.                                                                                  |
| `batteryLevel`        | Akkustand zum letzten MDM-Kontakt                  | Integer 0–100 oder Float 0–1  | höher = wahrscheinlicher geladen / in Nutzung   | **Einheit verifizieren.** Massenhaft niedrige Werte = organisatorischer Indikator (Geräte ungeladen im Schrank).                                                              |
| `complianceStatus`    | MDM-Konformitäts-Status                            | `COMPLIANT` / `NONCOMPLIANT`  | kategorial                                      | **Sagt nichts über OS-Aktualität aus.** Separat darstellen, niemals in OS-Bewertung einfließen lassen.                                                                       |
| `Modell`              | iPad-Modell (falls vorhanden)                      | String                        | kategorial                                      | Erklärt, warum bestimmte Geräte die Zielversion strukturell nicht erhalten können (Hardware-Cutoff durch Apple).                                                              |

### Pflichtnennung Akkustand

Standorte, bei denen mehr als 20 % der Geräte `batteryLevel` < 20
aufweisen, immer explizit nennen — auch ohne CO-Daten. Niedrige
Akkustände sind eigenständiges Warnsignal und erklären verzögerte
Updates unabhängig von Cache- oder Netzwerkproblemen.

Formulierungsbeispiel: „X von Y Geräten hatten Akkustand < 20 % —
Updates können dadurch verhindert oder verzögert worden sein."

---

## Verwendungshinweise für die KI

1. **Felder per Spaltenname referenzieren**, nicht per Position.
2. **Schema-Validierung als ersten Schritt:** vorhandene Spalten,
   Zeitraum-Konsistenz, Kürzel-Matching prüfen. Lücken benennen,
   bevor inhaltlich bewertet wird.
3. **Versionsvergleiche als SemVer**, nicht als String.
4. **Zeitliche Aggregation der AssetCache-Daten je Standort** über
   den Auswertungszeitraum, bevor mit der Relution-Momentaufnahme
   verglichen wird.
5. **Standort-Matching** über das Kürzel. Mismatches ausweisen.
6. **Kausale Ketten bevorzugen, Einzelsignale meiden:** Eine
   belastbare Hypothese braucht mindestens zwei konsistente Signale
   aus unterschiedlichen Feldern.

---

## Vor Implementierung verifizieren

- Genaue Spaltennamen für **Standort** und **Timestamp** in der CO-CSV.
- Semantik von `DNSRes` (Latenz / Statuscode / Boolean).
- Format von `AppleReach` (Boolean / Statuscode / Latenz).
- Einheit von `batteryLevel` (0–100 oder 0–1).
- Weitere Felder im AssetCache-Log, die der Prompt nicht referenziert.
- Abweichende Spaltennamen in Relution-Varianten anderer Organisationen.

---

# Auswertungs-Prompt

Bitte analysiere die bereitgestellten Dateien
`AssetCache_Co_alle_Standorte.csv` und `Geraete_Global_Co_YYYY-MM-DD.csv`
gemeinsam.

Ziel: standortweise bewerten, welche Auffälligkeiten beim
iOS-/iPadOS-Updatezustand bestehen und ob diese eher auf
infrastrukturelle Ursachen (Cache / Netzwerk), organisatorische
Ursachen (Gerätenutzung / Ladeverhalten / Online-Zeiten) oder
unklare Faktoren hindeuten.

Die Auswertung ist explorativ. Keine festen Schwellenwerte.
Unsicherheiten ausdrücklich benennen.

---

## Grundprinzipien

- Keine Kennzahl isoliert bewerten — Aussagen basieren auf
  Kombinationen mehrerer Signale.
- MDM-Status `COMPLIANT` ist kein Indikator für aktuelle OS-Version.
- `ClientsCnt` ist Intervall-Kennzahl, nicht Gesamtnutzung.
- Relution = Momentaufnahme, Cache = Intervallwerte. Zeitversatz möglich.
- Widersprüche und fehlende Daten als Unsicherheit kennzeichnen, nicht glätten.

---

## Zielversion und OS-Bewertung

Zielversion aus `iOSUpdates` ableiten. Bei Inkonsistenz als
unsicher kennzeichnen.

Stelle getrennt dar:
- Geräte auf Zielversion
- Geräte unter Zielversion
- Geräte mit `applePendingVersion`
- Geräte mit älteren Major-Versionen
- optional: MDM-Status separat (nicht für OS-Bewertung verwenden)

---

## Interpretationsmuster (als Hypothese, nicht als Urteil)

**Organisatorische Ursachen:** viele Geräte unter Zielversion +
geringe Aktivität + alte `lastConnectionDate` + niedrige Akkustände.

**Infrastrukturelle Ursachen:** Geräte aktiv, aber Updates
kommen nicht voran + auffällige Netzwerk-/Cache-Indikatoren
(z. B. dauerhaft hoher `CachePr`, `ServedDelta∅ = 0` und `OriginDelta∅ = 0`).

**Unklare Situation:** widersprüchliche oder fehlende Signale.

---

## Ergebnisformat

1. **Standortübersicht** — vollständig, alle Standorte im Scope,
   keine Kürzung. Falls zu lang: zwei Blöcke (A–M, N–Z).
   Pro Standort: Updatezustand, Pending, ältere Versionen,
   Aktivität, Geräteverfügbarkeit, Infrastrukturindikatoren.

2. **Priorisierte Liste** — sortiert nach Auffälligkeit,
   Einordnung je Standort: Infrastruktur / Organisation / unklar.

3. **Begründung** — max. 2–3 Sätze pro Standort, ausschließlich
   auf beobachteten Signalen.

4. **Methodische Hinweise** — Unsicherheiten, Momentaufnahme-Hinweis,
   Zeitversatz, klare Trennung zwischen **Befund** (mehrere
   konsistente Signale) und **Hypothese** (unsicher / einzelne Signale).

5. **Zusammenfassung** — auffälligste Standorte, daraus folgende
   Hypothesen, offene Fragen.

Keine Schuldzuweisungen. Ziel ist Ursachenklärung und Priorisierung.
```

