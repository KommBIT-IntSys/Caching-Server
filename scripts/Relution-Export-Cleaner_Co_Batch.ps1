# Relution-Export-Cleaner_Co_Batch.ps1
# Bereinigt Relution-Exporte:
# - verarbeitet alle Dateien im Skriptordner, die mit Geraete_Global_202 oder Geräte_Global_202 beginnen
# - entfernt personenbezogene Spalten (z.B. "name") durch feste CO-Ausgabespalten
# - extrahiert Standortkuerzel aus organizationName (Inhalt der ersten Klammer)
# - bringt Spalten in definierte Reihenfolge
# - sortiert Zeilen alphabetisch nach Standort
# - uebernimmt den Zeitstempel der Quelldatei in den Ausgabedateinamen
# - toleriert abweichende Spaltennamen und zusaetzliche Spalten
# - normalisiert iOS-/iPadOS-Versionen zweistellig fuer KI-/Copilot-Auswertungen
# - bricht pro Datei bei fehlenden harten Pflichtspalten ab, verarbeitet aber weitere passende Dateien weiter
# - warnt bei fehlenden optionalen / weichen Pflichtspalten und laeuft weiter
# - prueft die Quellspalte name vor dem Entfernen auf LDG und unerwartete Namensmuster
# - entfernt lastIpAddress vor der Ausgabe, falls vorhanden

$inputPatterns = @(
    "Geraete_Global_202*.csv",
    "Geräte_Global_202*.csv"
)

# Harte Pflichtfelder: Fehlen fuehrt fuer die betroffene Datei zum Ueberspringen, weil die Auswertung sonst fachlich unzuverlaessig wird
$criticalColumns = @('Standort', 'model', 'osVersion', 'batteryLevel')

# Weiche Pflicht-/Hinweisfelder: Fehlen wird gemeldet, das Skript laeuft weiter
$optionalWarnColumns = @('lastConnectionDate', 'applePendingVersion', 'deviceConnectionState', 'status')

# Erwartete Namenskuerzel in der Quellspalte name. Die Spalte selbst wird nicht in die CO-Ausgabe uebernommen.
$expectedNameMarkers = @('SuS', 'Sport', 'Koga', 'Lehrer')

# ---------- Hilfsfunktionen ----------

function Stop-WithError {
    param([string]$message)
    Write-Host ""
    Write-Host "FEHLER: $message" -ForegroundColor Red
    Write-Host ""
    Write-Host "Druecke eine beliebige Taste zum Beenden..." -ForegroundColor Yellow
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 1
}

function Write-Warn {
    param([string]$message)
    Write-Host "WARNUNG: $message" -ForegroundColor Yellow
}

function Get-SiteCode {
    param([string]$orgName)
    if ([string]::IsNullOrWhiteSpace($orgName)) { return "" }
    if ($orgName -match '\(([^)]+)\)') { return $matches[1] }
    return $orgName
}

function Normalize-IosVersionText {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return $Text }

    # Normalisiert Versionssegmente zweistellig:
    # 18.7.7 -> 18.07.07
    # 26.5   -> 26.05
    # 15.3   -> 15.03
    # Betrifft auch Versionen in Texten wie "iPadOS < 18.7.7".
    return [regex]::Replace($Text, '(?<!\d)(\d+)(?:\.(\d+))(?:\.(\d+))?(?!\d)', {
        param($m)

        $major = $m.Groups[1].Value
        $minor = "{0:D2}" -f [int]$m.Groups[2].Value

        if ($m.Groups[3].Success) {
            $patch = "{0:D2}" -f [int]$m.Groups[3].Value
            return "$major.$minor.$patch"
        }

        return "$major.$minor"
    })
}

function Get-RelutionTimestampFromName {
    param([string]$FileName)

    # Erwartet bevorzugt Format: ..._JJJJ-MM-TT_HHMM.csv
    # Beispiel: Geraete_Global_2026-05-12_1553.csv -> 2026-05-12_1553
    if ($FileName -match '(\d{4}-\d{2}-\d{2}_\d{4})\.csv$') {
        return $matches[1]
    }

    # Fallback fuer Archivdateien ohne Uhrzeit: ..._JJJJ-MM-TT.csv
    if ($FileName -match '(\d{4}-\d{2}-\d{2})\.csv$') {
        return $matches[1]
    }

    return (Get-Date -Format 'yyyy-MM-dd_HHmm')
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

function Convert-RelutionExportFile {
    param([System.IO.FileInfo]$Source)

    Write-Host ""
    Write-Host "Verarbeite: $($Source.Name)" -ForegroundColor Cyan

    $timestamp = Get-RelutionTimestampFromName -FileName $Source.Name
    $outputFile = Join-Path $Source.DirectoryName "Geraete_Global_Co_$timestamp.csv"

    try {
        $data = Import-Csv -Path $Source.FullName -Encoding UTF8
    } catch {
        Write-Host "FEHLER: Datei konnte nicht gelesen werden: $($Source.FullName)`n$($_.Exception.Message)" -ForegroundColor Red
        return $false
    }

    if ($data.Count -eq 0) {
        Write-Host "FEHLER: Die Datei enthaelt keine Daten: $($Source.Name)" -ForegroundColor Red
        return $false
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

    $missingCritical = $criticalColumns | Where-Object { -not $resolvedMap[$_] }
    if ($missingCritical) {
        Write-Host "FEHLER: Folgende wichtige Pflichtspalten wurden im Relution-Export nicht gefunden:" -ForegroundColor Red
        Write-Host "  $($missingCritical -join ', ')" -ForegroundColor Red
        Write-Host "Diese Datei wird uebersprungen, weil die erzeugte Auswertung sonst fachlich unzuverlaessig waere." -ForegroundColor Red
        return $false
    }

    $missingOptionalWarn = $optionalWarnColumns | Where-Object { -not $resolvedMap[$_] }
    if ($missingOptionalWarn) {
        Write-Host ""
        Write-Warn "Folgende optionale Statusspalten wurden nicht gefunden: $($missingOptionalWarn -join ', ')"
        Write-Host "Die Datei wird trotzdem erzeugt; die fehlenden Felder werden leer ausgegeben." -ForegroundColor Yellow
    }

    $lastIpColumns = $availableColumns | Where-Object { $_ -ieq 'lastIpAddress' }
    if ($lastIpColumns) {
        Write-Host ""
        Write-Warn "Die Eingabedatei enthaelt die Spalte 'lastIpAddress'."
        Write-Host "Diese Spalte ist datenschutzsensibel und wird vor der CO-Ausgabe entfernt." -ForegroundColor Yellow
    }

    # ---------- Quellspalte name pruefen, bevor sie aus der CO-Ausgabe herausfaellt ----------

    $nameColumn = $availableColumns | Where-Object { $_ -ieq 'name' } | Select-Object -First 1
    if ($nameColumn) {
        $ldgRows = @($data | Where-Object { [string]($_.$nameColumn) -match '(?i)LDG' })
        if ($ldgRows.Count -gt 0) {
            Write-Host ""
            Write-Warn "In der Quellspalte 'name' taucht das Kuerzel 'LDG' auf ($($ldgRows.Count) Zeile(n))."
            Write-Host "Lehrerdienstgeraete sind eine eigene, datenschutzsensiblere Auswertungsebene und sollten nicht unbemerkt in SuS-/Fachgeraete-CO-Dateien geraten." -ForegroundColor Yellow
        }

        $unexpectedNameRows = @($data | Where-Object {
            $deviceName = [string]($_.$nameColumn)
            -not ($expectedNameMarkers | Where-Object { $deviceName -match [regex]::Escape($_) })
        })
        if ($unexpectedNameRows.Count -gt 0) {
            Write-Host ""
            Write-Warn "In der Quellspalte 'name' fehlen bei $($unexpectedNameRows.Count) Zeile(n) die erwarteten Kuerzel: $($expectedNameMarkers -join ', ')."
            Write-Host "Die Datei wird trotzdem erzeugt. Bitte pruefen, ob der Relution-Export korrekt gefiltert wurde oder ob neue Namensmuster dokumentiert werden muessen." -ForegroundColor Yellow

            $examples = @($unexpectedNameRows | Select-Object -First 5 | ForEach-Object { [string]($_.$nameColumn) }) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
            if ($examples.Count -gt 0) {
                Write-Host "Beispiele:" -ForegroundColor Yellow
                foreach ($example in $examples) {
                    Write-Host "  - $example" -ForegroundColor Yellow
                }
            }
        }
    } else {
        Write-Host ""
        Write-Warn "Die Quellspalte 'name' wurde nicht gefunden. LDG- und Namensmuster-Pruefung kann nicht durchgefuehrt werden."
        Write-Host "Die Datei wird trotzdem erzeugt; personenbezogene Namen werden weiterhin nicht in die CO-Ausgabe uebernommen." -ForegroundColor Yellow
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
                if ($targetCol -eq 'osVersion' -or $targetCol -eq 'applePendingVersion') {
                    $value = Normalize-IosVersionText $value
                }
                $outputRow[$targetCol] = $value
            } else {
                $outputRow[$targetCol] = ""
            }
        }

        [PSCustomObject]$outputRow
    }

    $cleaned = $cleaned | Sort-Object -Property Standort

    try {
        $cleaned | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8 -Delimiter ";"
    } catch {
        Write-Host "FEHLER: Ausgabedatei konnte nicht geschrieben werden: $outputFile`n$($_.Exception.Message)" -ForegroundColor Red
        return $false
    }

    Write-Host "Fertig: $(Split-Path $outputFile -Leaf)" -ForegroundColor Green
    Write-Host "  Eingabe:  $($data.Count) Geraete" -ForegroundColor Gray
    Write-Host "  Ausgabe:  $($cleaned.Count) Geraete, alphabetisch nach Standort" -ForegroundColor Gray
    if ($missingOptionalWarn) {
        Write-Host "  Hinweis:  Fehlende optionale Statusfelder: $($missingOptionalWarn -join ', ')" -ForegroundColor Yellow
    }
    if ($lastIpColumns) {
        Write-Host "  Hinweis:  lastIpAddress wurde nicht in die CO-Ausgabe uebernommen" -ForegroundColor Yellow
    }

    return $true
}

# ---------- Eingabedateien finden ----------

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($scriptDir)) { $scriptDir = (Get-Location).Path }

$sources = @()
foreach ($pattern in $inputPatterns) {
    $sources += Get-ChildItem -Path $scriptDir -Filter $pattern -File -ErrorAction SilentlyContinue
}

$sources = $sources |
    Where-Object { $_.Name -notmatch '_Co_' } |
    Sort-Object Name -Unique

if (-not $sources -or $sources.Count -eq 0) {
    Stop-WithError "Keine passende Eingabedatei gefunden.`nErwartet werden Dateien im Skriptordner nach dem Muster:`n  Geraete_Global_202*.csv`n  Geräte_Global_202*.csv"
}

Write-Host ""
Write-Host "Gefundene Eingabedateien: $($sources.Count)" -ForegroundColor Cyan

$ok = 0
$failed = 0
foreach ($source in $sources) {
    if (Convert-RelutionExportFile -Source $source) {
        $ok++
    } else {
        $failed++
    }
}

Write-Host ""
Write-Host "Batch abgeschlossen." -ForegroundColor Cyan
Write-Host "  Erfolgreich: $ok" -ForegroundColor Green
if ($failed -gt 0) {
    Write-Host "  Uebersprungen/Fehler: $failed" -ForegroundColor Red
} else {
    Write-Host "  Uebersprungen/Fehler: 0" -ForegroundColor Gray
}

Write-Host ""
Write-Host "Druecke eine beliebige Taste zum Beenden..." -ForegroundColor DarkGray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
