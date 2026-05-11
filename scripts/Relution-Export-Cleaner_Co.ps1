# Relution-Export-Cleaner_Co.ps1
# Bereinigt den Relution-Export:
# - entfernt personenbezogene Spalten (z.B. "name")
# - extrahiert Standortkürzel aus organizationName (Inhalt der ersten Klammer)
# - bringt Spalten in definierte Reihenfolge
# - toleriert abweichende Spaltennamen und zusätzliche Spalten

$input_pattern = ".\*_Global_*_????.csv"
$output_file = "Geraete_Global_Co_$(Get-Date -Format 'yyyy-MM-dd').csv"

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
    Write-Host "Keine passende Datei gefunden (Muster: $input_pattern)" -ForegroundColor Red
    exit 1
}

Write-Host "Verarbeite: $($source.Name)" -ForegroundColor Cyan

# Rohdaten einlesen
$data = Import-Csv -Path $source.FullName -Encoding UTF8

if ($data.Count -eq 0) {
    Write-Host "Keine Daten in der Datei gefunden" -ForegroundColor Red
    exit 1
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

# Warnung bei fehlenden Spalten
foreach ($targetCol in $outputColumns) {
    if (-not $resolvedMap[$targetCol]) {
        Write-Host "Warnung: Spalte '$targetCol' nicht im Export gefunden" -ForegroundColor Yellow
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
$cleaned | Export-Csv -Path $output_file -NoTypeInformation -Encoding UTF8

Write-Host "Fertig: $output_file" -ForegroundColor Green
Write-Host "  Eingabe:  $($data.Count) Geräte" -ForegroundColor Gray
Write-Host "  Ausgabe:  $($cleaned.Count) Geräte" -ForegroundColor Gray
Write-Host "  Spalten:  $($outputColumns -join ', ')" -ForegroundColor Gray
