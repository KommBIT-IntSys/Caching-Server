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

> **Warum Microsoft Copilot?**
> Nicht weil es die dafür beste KI wäre, sondern weil es derzeit
> die einzige ist, die der bayerische ÖD erlaubt.
> Allerdings: Gut gepromptet liefert auch diese aussagekräftige
> und belastbare Ergebnisse.

---

## Prompt für MS Copilot

---

```
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

