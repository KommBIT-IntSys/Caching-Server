# Copilot-Prompt: AssetCache-Monitoring – Standortanalyse iOS-Update

## Verwendung

Diesen Prompt zusammen mit zwei Dateien an Microsoft Copilot übergeben:

1. **CO-CSV** – zusammengeführte Cache-Logger-Daten aller Standorte
   (`*_AssetCache_Co_v*.csv`, siehe Skripte unter dem Prompt für Copilot)
   
2. **Relution-Export** – Geräteliste ohne Gerätenamen und ohne Schulnamen (siehe Skripte unter dem Prompt für Copilot)
   (Felder: `model | osVersion | applePendingVersion | lastConnectionDate | deviceConnectionState | status | batteryLevel | organizationName`)
Geräte auerdem vor dem Export mit folgenden Suchbegriffen filtern:
SuS Sport Koga Lehrer
=> LDG-iPads werden nicht berücksichtig, da nicht alle dauerhaft vor Ort sind.
---

## Prompt für Copilot:

```
Bitte analysiere die bereitgestellten Dateien `AssetCache_Co_alle_Standorte.csv` und `Geraete_Global_Co_YYYY-MM-DD.csv`
gemeinsam.

Ziel der Analyse ist es, datenbasiert zu bewerten, welche Schulstandorte im Zusammenhang mit iOS-/iPadOS-Updates zuerst
betrachtet werden sollten. Dabei soll unterschieden werden, ob Auffälligkeiten eher auf
Infrastruktur-/Cache-/Netzwerkprobleme oder eher auf organisatorische Ursachen hindeuten, zum Beispiel Geräte nicht
ausreichend geladen, nicht regelmäßig online oder nicht im geeigneten Zeitfenster erreichbar.

Wichtig: Der MDM-Status `COMPLIANT` darf nicht mit „aktuelles iOS/iPadOS“ gleichgesetzt werden.

Bewerte den Updatezustand primär anhand dieser Felder:

- `osVersion`
- `applePendingVersion`
- `iOSUpdates` aus der AssetCache-Co-Datei

Leite aus `iOSUpdates` die aktuell erwartete Zielversion beziehungsweise die relevanten aktuellen iOS-/iPadOS-Versionen ab.
Verwende `osVersion` als Hauptfeld, um zu bestimmen, ob ein Gerät bereits auf Zielversion ist oder darunter liegt.
Verwende `applePendingVersion`, um zu erkennen, ob ein Update bereits als ausstehend erkannt wurde.

Der MDM-Status `status` darf separat ausgewertet werden, aber nur als MDM-/Compliance-Indikator.
Er ist kein Ersatz für die OS-Versionsbewertung.
Ein Gerät kann MDM-seitig `COMPLIANT` sein, obwohl es nicht auf der neuesten OS-Version ist.
Umgekehrt kann ein Gerät nicht compliant sein, obwohl die OS-Version aktuell ist.

Stelle deshalb getrennt dar:

- Geräte auf Zielversion
- Geräte unter Zielversion
- Geräte mit `applePendingVersion`
- Geräte mit älteren Major-Versionen
- optional separat: MDM-Status `COMPLIANT` / `NONCOMPLIANT`

Wichtig: `ClientsCnt` ist keine harte Erfolgsschwelle und darf nicht isoliert bewertet werden.

`ClientsCnt` ist eine Intervall-/Aktivitätskennzahl aus den AssetCache-Logs. Sie zeigt, wie viele
eindeutige private Client-IP-Adressen im betrachteten Logfenster gesehen wurden. In 15-Minuten-Intervallen
ist es normal, dass nur ein Teil aller iPads gleichzeitig aktiv Cache-Anfragen erzeugt.
Ein niedriger `ClientsCnt`-Wert allein beweist daher weder geringe Nutzung
noch ein organisatorisches Problem.

Verwende `ClientsCnt` nur als Kontextsignal zusammen mit:

- `ServedDelta`
- `OriginDelta`
- `osVersion`
- `applePendingVersion`
- `lastConnectionDate`
- `batteryLevel`
- `DNSRes`
- `AppleReach`
- `AppleTTFB`
- `CachePr`

Interpretationslogik:

- `ClientsCnt` niedrig + `ServedDelta` niedrig + viele Geräte nicht aktuell + alte `lastConnectionDate`
   + niedrige Akkustände = möglicher Hinweis auf organisatorische Probleme, zum Beispiel Geräte nicht ausreichend
   geladen, nicht regelmäßig online oder nicht im Updatefenster erreichbar.
- `ClientsCnt` niedrig + `ServedDelta` hoch = kein direkter Fehler; der Cache kann trotzdem relevant ausgeliefert haben.
- `ClientsCnt` hoch + `ServedDelta` niedrig = prüfen, ob nur kleine Requests stattfinden
   oder ob die betrachtete Updatephase nicht aktiv war.
- `ClientsCnt` niedrig allein = kein Beweis für ein Problem.

Setze keine harte Schwelle wie „unter 50 % = kritisch“. Bewerte stattdessen Muster und Zusammenhänge.

Bitte liefere die Analyse standortweise mit folgenden Bestandteilen:

1. Kurzbewertung je Standort
   - Updatezustand
   - Pending-Updates
   - ältere Major-Versionen
   - Akku-/Online-Auffälligkeiten
   - Cache-Aktivität
   - Infrastrukturindikatoren

2. Priorisierte Standortliste
   - höchste Priorität zuerst
   - mit kurzer Begründung
   - getrennt nach vermuteter Ursache:
     - eher Infrastruktur / Cache / Netzwerk
     - eher Organisation / Geräteprozess
     - unklar / weiter prüfen

3. Keine Schuldzuweisung
   - Formuliere sachlich.
   - Ziel ist Ursachenklärung und Unterstützung, nicht Kontrolle oder Vorwurf.

4. Methodische Hinweise
   - Weise auf Unsicherheiten hin, zum Beispiel wenn Relution-Daten nur eine Momentaufnahme sind.
   - Weise darauf hin, wenn Cache-Daten und Relution-Daten zeitlich nicht perfekt deckungsgleich sind.
   - Weise darauf hin, wenn Werte nur gemeinsam interpretierbar sind.

Erstelle am Ende eine knappe Handlungsempfehlung:
Welche Standorte sollten zuerst angesprochen oder technisch geprüft werden, und warum?
```

---

## PowerShell-Skript: CO-Dateien zusammenführen (Windows 11)

### Skriptdatei `Merge_Co_CSV.ps1`

Im Verzeichnis mit allen CO-CSV-Dateien ablegen und ausführen:

```powershell
$output = "AssetCache_Co_alle_Standorte.csv"
$files  = Get-ChildItem -Filter "*_AssetCache_Co_v*.csv" | Sort-Object Name

$first = $true
foreach ($file in $files) {
    if ($first) {
        Get-Content $file.FullName | Set-Content -Encoding UTF8 $output
        $first = $false
    } else {
        Get-Content $file.FullName | Select-Object -Skip 1 | Add-Content -Encoding UTF8 $output
    }
}

Write-Host "Fertig: $output ($($files.Count) Dateien zusammengeführt)"
```

Ausführen:
```
Rechtsklick => Mit PowerShell ausführen
```

Ergebnis: `AssetCache_Co_alle_Standorte.csv` – eine Datei, alle Standorte, ein Header.

## PowerShell-Skript: Relution-Export bereinigen (Windows 11)

### Skriptdatei `Relution-Export-Cleaner_Co.ps1`

Vor der Übergabe an Copilot den Relution-Export datenschutzkonform bereinigen:
- Spalte `name` wird entfernt (enthält Gerätenamen mit Schülernamen)
- `organizationName` wird auf das Schulkürzel gekürzt (Inhalt der ersten Klammer)

Das Ergebnis ist die Datei `Geraete_Global_Co_JJJJ-MM-TT.csv`, die direkt
für die Analyse verwendet werden kann.

```powershell
# Relution-Export-Cleaner_Co.ps1
# Bereinigt den Relution-Export:
# - entfernt Spalte "name" (Gerätename / Schülername)
# - kürzt organizationName auf Schulkürzel (Inhalt der ersten Klammer)

$input_file  = ".\Geraete_Global_*.csv"
$output_file = "Geraete_Global_Co_$(Get-Date -Format 'yyyy-MM-dd').csv"

$source = Get-ChildItem -Filter $input_file | Sort-Object LastWriteTime -Descending | Select-Object -First 1

if (-not $source) {
    Write-Host "Keine passende Datei gefunden (Muster: $input_file)"
    exit 1
}

Write-Host "Verarbeite: $($source.Name)"

$data = Import-Csv -Path $source.FullName -Encoding UTF8

$cleaned = $data | Select-Object `
    @{Name="model";                Expression={$_.model}},
    @{Name="osVersion";            Expression={$_.osVersion}},
    @{Name="applePendingVersion";  Expression={$_.applePendingVersion}},
    @{Name="lastConnectionDate";   Expression={$_.lastConnectionDate}},
    @{Name="deviceConnectionState";Expression={$_.deviceConnectionState}},
    @{Name="status";               Expression={$_.status}},
    @{Name="batteryLevel";         Expression={$_.batteryLevel}},
    @{Name="organizationName";     Expression={
        if ($_.organizationName -match '^\(([^)]+)\)') {
            $matches[1]
        } else {
            $_.organizationName
        }
    }}

$cleaned | Export-Csv -Path $output_file -NoTypeInformation -Encoding UTF8

Write-Host "Fertig: $output_file ($($cleaned.Count) Geräte)"
```

Ausführen:
```
Rechtsklick => Mit PowerShell ausführen
```

Ergebnis: `Geraete_Global_Co_JJJJ-MM-TT.csv` – ohne Gerätenamen,
`organizationName` reduziert auf Schulkürzel (z. B. `EPS`).

> **Hinweis HHS:** Falls der Standort in Relution als `HHS-N` und `HHS-W`
> geführt wird, beide Einträge vor der Übergabe manuell auf `HHS` vereinheitlichen,
> damit der Join mit dem `SiteCode` der CO-CSV funktioniert.

## Shell-Einzeiler: CO-Dateien zusammenführen (macOS)

Vor der Übergabe an Copilot alle CO-CSV-Dateien zu einer einzigen
zusammenführen (Header nur einmal, aus der ersten Datei):

```sh
# Im Verzeichnis mit allen CO-CSV-Dateien ausführen:
first=1
for f in *_AssetCache_Co_v*.csv; do
  if [ "$first" -eq 1 ]; then
    cat "$f"
    first=0
  else
    tail -n +2 "$f"
  fi
done > AssetCache_Co_alle_Standorte.csv
```

Ergebnis: `AssetCache_Co_alle_Standorte.csv` – eine Datei,
alle Standorte, ein Header.

## Shell-Skript: Relution-Export bereinigen (macOS)

Vor der Übergabe an Copilot den Relution-Export datenschutzkonform bereinigen:
- Spalte `name` wird entfernt (enthält Gerätenamen mit Schülernamen)
- `organizationName` wird auf das Schulkürzel gekürzt (Inhalt der ersten Klammer)

Das Ergebnis ist die Datei `Geraete_Global_Co_JJJJ-MM-TT.csv`, die direkt
für die Analyse verwendet werden kann.

```sh
#!/bin/bash
# relution_cleaner_co.sh
# Bereinigt den Relution-Export:
# - entfernt Spalte "name" (Gerätename / Schülername)
# - kürzt organizationName auf Schulkürzel (Inhalt der ersten Klammer)

input=$(ls Geraete_Global_*.csv 2>/dev/null | sort -r | head -1)

if [ -z "$input" ]; then
  echo "Keine passende Datei gefunden (Muster: Geraete_Global_*.csv)"
  exit 1
fi

output="Geraete_Global_Co_$(date +%Y-%m-%d).csv"

echo "Verarbeite: $input"

awk -F',' -v OFS=',' '
NR==1 {
  for (i=1; i<=NF; i++) {
    gsub(/"/, "", $i)
    col[$i] = i
  }
  print "model","osVersion","applePendingVersion","lastConnectionDate",\
        "deviceConnectionState","status","batteryLevel","organizationName"
  next
}
{
  org = $col["organizationName"]
  gsub(/"/, "", org)
  if (match(org, /^\(([^)]+)\)/, m)) org = m[1]
  printf "\"%s\",\"%s\",\"%s\",\"%s\",\"%s\",\"%s\",\"%s\",\"%s\"\n",
    $col["model"], $col["osVersion"], $col["applePendingVersion"],
    $col["lastConnectionDate"], $col["deviceConnectionState"],
    $col["status"], $col["batteryLevel"], org
}
' "$input" > "$output"

count=$(tail -n +2 "$output" | wc -l | tr -d ' ')
echo "Fertig: $output ($count Geräte)"
```

Ausführbar machen und starten:
```sh
chmod +x relution_cleaner_co.sh
./relution_cleaner_co.sh
```

Ergebnis: `Geraete_Global_Co_JJJJ-MM-TT.csv` – ohne Gerätenamen,
`organizationName` reduziert auf Schulkürzel (z. B. `EPS`).

> **Hinweis HHS:** Falls der Standort in Relution als `HHS-N` und `HHS-W`
> geführt wird, beide Einträge vor der Übergabe manuell auf `HHS` vereinheitlichen,
> damit der Join mit dem `SiteCode` der CO-CSV funktioniert.
