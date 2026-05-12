# Relution-Export-Cleaner_Co.ps1
# Bereinigt den Relution-Export:
# - entfernt personenbezogene Spalten (z.B. "name")
# - extrahiert Standortkürzel aus organizationName (Inhalt der ersten Klammer)
# - bringt Spalten in definierte Reihenfolge
# - toleriert abweichende Spaltennamen und zusätzliche Spalten

$input_pattern = ".\*_Global_*_????.csv"
$output_file = "Geraete_Global_Co_$(Get-Date -Format 'yyyy-MM-dd_HHmm').csv"

# Pflichtfelder: Fehlen diese, wird die Verarbeitung abgebrochen
$requiredColumns = @('Standort', 'osVersion', 'model')

# Fehler anzeigen, Fenster offen lassen
function Stop-WithError {
    param([string]$message)
    Write-Host ""
    Write-Host "FEHLER: $message" -ForegroundColor Red
    Write-Host ""
    Write-Host "Drücke eine beliebige Taste zum Beenden..." -ForegroundColor Yellow
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 1
}

# Spalten-Mapping: Ziel-Spaltenname -> Liste möglicher Quell-Namen
# Erster Treffer im Header gewinnt
$columnMap = @{
    'Standort'              = @('organizationName', 'Organisation', 'Standort', 'SiteCode', 'Org')
    'model'                 = @('model', 'Modell', 'Device Model', 'Gerätemodell')
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

# Neueste passende Datei finden
$source = Get-ChildItem -Filter $input_pattern | Sort-Object LastWriteTime -Descending | Select-Object -First 1

if (-not $source) {
    Stop-WithError "Keine passende Eingabedatei gefunden.`nErwartet wird eine Datei nach dem Muster: $input_pattern`nBitte Relution-Export im selben Ordner ablegen."
}

Write-Host "Verarbeite: $($source.Name)" -ForegroundColor Cyan

# Rohdaten einlesen
try {
    $data = Import-Csv -Path $source.FullName -Encoding UTF8
} catch {
    Stop-WithError "Datei konnte nicht gelesen werden: $($source.FullName)`n$($_.Exception.Message)"
}

if ($data.Count -eq 0) {
    Stop-WithError "Die Datei enthält keine Daten: $($source.Name)"
}

# Spalten-Mapping auflösen: Für jede Ziel-Spalte die erste vorhandene Quell-Spalte finden
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

# Pflichtfelder prüfen — fehlt eines, Abbruch mit Fehlermeldung
$missingRequired = $requiredColumns | Where-Object { -not $resolvedMap[$_] }
if ($missingRequired) {
    Stop-WithError "Pflichtfeld(er) nicht im Export gefunden: $($missingRequired -join ', ')`nOhne diese Spalten ist die Ausgabe nicht auswertbar."
}

# Optionale Spalten: Warnung, kein Abbruch
foreach ($targetCol in $outputColumns) {
    if (-not $resolvedMap[$targetCol] -and $requiredColumns -notcontains $targetCol) {
        Write-Host "  Hinweis: Optionale Spalte '$targetCol' nicht gefunden — wird leer ausgegeben" -ForegroundColor Yellow
    }
}

# Funktion: Standortkürzel aus organizationName extrahieren
function Get-SiteCode {
    param([string]$orgName)
    
    if ([string]::IsNullOrWhiteSpace($orgName)) {
        return ""
    }
    
    # Erste Klammer im String suchen (egal ob am Anfang, in der Mitte oder am Ende)
    if ($orgName -match '\(([^)]+)\)') {
        return $matches[1]
    }
    
    # Keine Klammer gefunden: Originalwert zurückgeben
    return $orgName
}

# Daten transformieren
$cleaned = $data | ForEach-Object {
    $row = $_
    $outputRow = [ordered]@{}
    
    foreach ($targetCol in $outputColumns) {
        $sourceCol = $resolvedMap[$targetCol]
        
        if ($sourceCol) {
            $value = $row.$sourceCol
            
            # Sonderbehandlung für Standort: Kürzel extrahieren
            if ($targetCol -eq 'Standort') {
                $value = Get-SiteCode $value
            }
            
            $outputRow[$targetCol] = $value
        } else {
            # Spalte nicht vorhanden: leerer Wert
            $outputRow[$targetCol] = ""
        }
    }
    
    [PSCustomObject]$outputRow
}

# Ausgabe schreiben
try {
    $cleaned | Export-Csv -Path $output_file -NoTypeInformation -Encoding UTF8
} catch {
    Stop-WithError "Ausgabedatei konnte nicht geschrieben werden: $output_file`n$($_.Exception.Message)"
}

Write-Host "Fertig: $output_file" -ForegroundColor Green
Write-Host "  Eingabe:  $($data.Count) Geräte" -ForegroundColor Gray
Write-Host "  Ausgabe:  $($cleaned.Count) Geräte" -ForegroundColor Gray
Write-Host "  Spalten:  $($outputColumns -join ', ')" -ForegroundColor Gray


Write-Host "Fertig: $output_file" -ForegroundColor Green
Write-Host "  Eingabe:  $($data.Count) Geräte" -ForegroundColor Gray
Write-Host "  Ausgabe:  $($cleaned.Count) Geräte" -ForegroundColor Gray
Write-Host "  Spalten:  $($outputColumns -join ', ')" -ForegroundColor Gray
