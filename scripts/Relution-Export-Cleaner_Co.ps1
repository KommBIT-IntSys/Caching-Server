# Relution-Export-Cleaner_Co.ps1
# Bereinigt den Relution-Export:
# - entfernt personenbezogene Spalten (z.B. "name")
# - extrahiert Standortkuerzel aus organizationName (Inhalt der ersten Klammer)
# - bringt Spalten in definierte Reihenfolge
# - sortiert Zeilen alphabetisch nach Standort
# - uebernimmt den Zeitstempel der Quelldatei in den Ausgabedateinamen
# - toleriert abweichende Spaltennamen und zusaetzliche Spalten
# - meldet fehlende Felder klar und laesst Nutzer entscheiden ob fortgefahren wird

$input_pattern = ".\*_Global_*_????.csv"

# Alle Felder die vorhanden sein sollten - Fehlen wird gemeldet, Nutzer entscheidet
$criticalColumns = @('Standort', 'osVersion', 'model', 'lastConnectionDate', 'batteryLevel')

# ---------- Hilfsfunktionen ----------

# Fehlermeldung mit Abbruch - kein Fortfahren moeglich (z.B. Datei nicht gefunden)
function Stop-WithError {
    param([string]$message)
    Write-Host ""
    Write-Host "FEHLER: $message" -ForegroundColor Red
    Write-Host ""
    Write-Host "Druecke eine beliebige Taste zum Beenden..." -ForegroundColor Yellow
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 1
}

# Fehlermeldung mit Rueckfrage - Nutzer kann trotzdem fortfahren
function Ask-ContinueOnError {
    param([string]$message)
    Write-Host ""
    Write-Host "FEHLER: $message" -ForegroundColor Red
    Write-Host ""
    Write-Host "Fehlende Felder werden leer ausgegeben." -ForegroundColor Yellow
    Write-Host "Trotzdem fortfahren? (J/N): " -ForegroundColor Yellow -NoNewline
    $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    Write-Host $key.Character
    Write-Host ""
    if ($key.Character -ne 'j' -and $key.Character -ne 'J') {
        Write-Host "Abgebrochen." -ForegroundColor Red
        Write-Host "Druecke eine beliebige Taste zum Beenden..." -ForegroundColor Yellow
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        exit 1
    }
}

# ---------- Spalten-Mapping ----------
# Ziel-Spaltenname -> Liste moeglicher Quell-Namen, erster Treffer gewinnt

$columnMap = @{
    'Standort'              = @('organizationName', 'Organisation', 'Standort', 'SiteCode', 'Org')
    'model'                 = @('model', 'Modell', 'Device Model', 'Geraetemodell')
    'lastConnectionDate'    = @('lastConnectionDate', 'Letzte Verbindung', 'Last Connection', 'Zuletzt verbunden')
    'osVersion'             = @('osVersion', 'OS Version', 'Betriebssystemversion', 'iOS Version', 'iPadOS Version')
    'applePendingVersion'   = @('applePendingVersion', 'OS Update Status', 'Ausstehendes Update', 'Pending Version')
    'deviceConnectionState' = @('deviceConnectionState', 'Connection State', 'Verbindungsstatus')
    'status'                = @('status', 'Status', 'Compliance', 'complianceStatus', 'MDM Status')
    'batteryLevel'          = @('batteryLevel', 'Batteriestand', 'Battery Level', 'Akku')
}

# Definierte Ausgabe-Reihenfolge
$outputColumns = @(
    'Standort',
    'model',
    'lastConnectionDate',
    'osVersion',
    'applePendingVersion',
    'deviceConnectionState',
    'status',
    'batteryLevel'
)

# ---------- Eingabedatei finden ----------

$source = Get-ChildItem -Filter $input_pattern |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $source) {
    Stop-WithError "Keine passende Eingabedatei gefunden.`nErwartet wird eine Datei nach dem Muster: $input_pattern`nBitte Relution-Export im selben Ordner ablegen."
}

Write-Host ""
Write-Host "Verarbeite: $($source.Name)" -ForegroundColor Cyan

# ---------- Zeitstempel aus Quelldateiname extrahieren ----------
# Erwartet Format: ..._JJJJ-MM-TT_HHMM.csv
# Beispiel: Geraete_Global_2026-05-12_1553.csv -> 2026-05-12_1553

$timestamp = ""
if ($source.Name -match '(\d{4}-\d{2}-\d{2}_\d{4})\.csv$') {
    $timestamp = $matches[1]
} else {
    # Fallback: aktuelles Datum und Uhrzeit
    $timestamp = Get-Date -Format 'yyyy-MM-dd_HHmm'
    Write-Host "  Hinweis: Zeitstempel konnte nicht aus Dateiname extrahiert werden -- verwende aktuelle Zeit" -ForegroundColor DarkYellow
}

$output_file = "Geraete_Global_Co_$timestamp.csv"

# ---------- Einlesen ----------

try {
    $data = Import-Csv -Path $source.FullName -Encoding UTF8
} catch {
    Stop-WithError "Datei konnte nicht gelesen werden: $($source.FullName)`n$($_.Exception.Message)"
}

if ($data.Count -eq 0) {
    Stop-WithError "Die Datei enthaelt keine Daten: $($source.Name)"
}

# ---------- Spalten-Mapping aufloesen ----------

$resolvedMap = @{}
$availableColumns = $data[0].PSObject.Properties.Name

foreach ($targetCol in $columnMap.Keys) {
    $sourceCol = $null
    foreach ($candidate in $columnMap[$targetCol]) {
        if ($availableColumns -contains $candidate) {
            $sourceCol = $candidate
            break
        }
    }
    $resolvedMap[$targetCol] = $sourceCol
}

# ---------- Felder pruefen ----------

# Kritische Felder: Fehlen wird gemeldet, Nutzer entscheidet ob fortgefahren wird
$missingCritical = $criticalColumns | Where-Object { -not $resolvedMap[$_] }
if ($missingCritical) {
    Ask-ContinueOnError "Folgende Felder wurden im Export nicht gefunden:`n  $($missingCritical -join ', ')`nDie Ausgabe ist ohne diese Felder eingeschraenkt auswertbar."
}

# Optionale Felder: stiller Hinweis, kein Abbruch
foreach ($targetCol in $outputColumns) {
    if (-not $resolvedMap[$targetCol] -and $criticalColumns -notcontains $targetCol) {
        Write-Host "  Hinweis: Optionales Feld '$targetCol' nicht gefunden -- wird leer ausgegeben" -ForegroundColor DarkYellow
    }
}

# ---------- Standortkuerzel extrahieren ----------

function Get-SiteCode {
    param([string]$orgName)
    if ([string]::IsNullOrWhiteSpace($orgName)) { return "" }
    if ($orgName -match '\(([^)]+)\)') { return $matches[1] }
    return $orgName
}

# ---------- Daten transformieren ----------

$cleaned = $data | ForEach-Object {
    $row = $_
    $outputRow = [ordered]@{}

    foreach ($targetCol in $outputColumns) {
        $sourceCol = $resolvedMap[$targetCol]
        if ($sourceCol) {
            $value = $row.$sourceCol
            if ($targetCol -eq 'Standort') {
                $value = Get-SiteCode $value
            }
            $outputRow[$targetCol] = $value
        } else {
            $outputRow[$targetCol] = ""
        }
    }

    [PSCustomObject]$outputRow
}

# ---------- Alphabetisch nach Standort sortieren ----------

$cleaned = $cleaned | Sort-Object -Property Standort

# ---------- Ausgabe schreiben ----------

try {
    $cleaned | Export-Csv -Path $output_file -NoTypeInformation -Encoding UTF8
} catch {
    Stop-WithError "Ausgabedatei konnte nicht geschrieben werden: $output_file`n$($_.Exception.Message)"
}

Write-Host ""
Write-Host "Fertig: $output_file" -ForegroundColor Green
Write-Host "  Eingabe:  $($data.Count) Geraete" -ForegroundColor Gray
Write-Host "  Ausgabe:  $($cleaned.Count) Geraete, alphabetisch nach Standort" -ForegroundColor Gray
if ($missingCritical) {
    Write-Host "  Achtung:  Fehlende Felder in der Ausgabe: $($missingCritical -join ', ')" -ForegroundColor Yellow
}
Write-Host ""
Write-Host "Druecke eine beliebige Taste zum Beenden..." -ForegroundColor DarkGray
$null = $Host.UI.RawUI.ReadKey("NoEch
