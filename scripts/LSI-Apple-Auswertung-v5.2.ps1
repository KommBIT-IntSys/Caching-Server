# LSI-Apple-Auswertung-v5.2.ps1
# Automatik-Version mit inkrementellem Betriebsmodell:
# - sucht passende Apple/iOS/iPadOS/Safari Security Advisories über die WID-API
# - filtert lokal nach Zeitraum, Risiko und Titel-RegEx
# - zeigt die gefundene LSI-Auswahlliste in der Konsole
# - wertet jede gefundene LSI-Meldung aus
# - speichert je Meldung JSON und Einzel-CSV (optional)
# - schreibt eine Gesamt-CSV (versionsnormalisiert)
# - schreibt zusätzlich einen kompakten Managementreport
# - erkennt vorhandene Gesamtauswertung und arbeitet inkrementell
# - bereinigt veraltete Versionen anhand der Liste $RELEVANT_VERSIONS
#
# Änderungen v5.2 gegenüber v5.1.2:
# - Inkrementelles Betriebsmodell:
#     * Erstlauf (keine LSI-Apple-Gesamtauswertung_*.csv vorhanden):
#         Vollanlage, MaxAdvisories-Deckel automatisch auf 100 angehoben
#     * Folgelauf (LSI-Apple-Gesamtauswertung_*.csv vorhanden):
#         Datum aus neuestem LsiStand der Vordatei + Sicherheitspuffer,
#         nur Neues abfragen, mit bestehender Datei mergen,
#         Deckel bleibt bei -MaxAdvisories (Default 50)
# - RELEVANT_VERSIONS als Selbstwissen im Skript-Header
#     (manuell zu pflegende Liste der iOS-Zweige im Feld)
# - Bereinigung: Einträge, deren BetroffeneVersionen/BehobenDurch
#     keinen Zweig aus RELEVANT_VERSIONS mehr treffen, werden entfernt
# - iOS-/iPadOS-/Apple-Versionsnotation in Ausgaben normalisiert (führende Nullen
#     pro Segment): 18.7.7 → 18.07.07, 26.5 → 26.05.
#     Apple-RAW-Strings in BetroffeneVersionen/BehobenDurch werden
#     in den Versionsteilen normalisiert, die übrigen Worte bleiben.
#     Fehlende Versionen werden leer gelassen, nicht künstlich gefüllt.
# - Standard-Default für MaxAdvisories von 25 auf 50 erhöht
#     (Erstlauf-Override 100, Folgelauf in der Praxis selten relevant)
# - Rechtklick-ausführbar unter Windows 11
# - Optionaler API-Key-Platzhalter direkt im Skript: $ScriptWidApiKey = "dein-api-key"
#   Wenn dort ein echter Key eingetragen ist, setzt das Skript WID_API_KEY selbst.
# - Managementreport AppleUrls-Duplikate behoben (URLs werden aus
#     | -getrennten Feldern korrekt dedupliziert)
# - Ausgabedateien heißen ohne Co-/Versionssuffix:
#     LSI-Apple-Gesamtauswertung_<Zeitstempel>.csv
#     LSI-Apple-Managementreport_<Zeitstempel>.csv
# - Versionsnormalisierung erkennt auch Produktnamen mit Marketingnamen,
#     z. B. macOS Sequoia < 15.3 -> macOS Sequoia < 15.03
# - LSI-Automatisch-Gefunden_*.csv wird nicht mehr geschrieben
#     (Kandidatenliste erscheint nur noch in der Konsolenausgabe)
#
# Übernommen aus v4.8:
# - UTF-8-Encoding-Fix für die WID-API (Invoke-WidApi)
# - Spalten Exploit und NoPatch in der Gesamt-CSV
# - Spalten MinFixVersions, MinFixIosLinie18, MinFixIosLinie26,
#   MinFixIpadOsLinie18, MinFixIpadOsLinie26 in der Gesamt-CSV
# - Deduplikation der Apple-Entries pro (LsiId, Komponente, CVEs);
#   mehrere Apple-URLs werden im AppleUrl-Feld mit " | " zusammengeführt
#
# Nutzung:
#   Variante A: API-Key oben im Skript bei $ScriptWidApiKey eintragen.
#   Variante B: $env:WID_API_KEY = "lsiwid_..."
#   powershell.exe -ExecutionPolicy Bypass -File .\LSI-Apple-Auswertung-v5.2.ps1
#
# Rechtklick unter Windows 11:
#   Datei -> Rechtsklick -> "Mit PowerShell ausführen"
#   Wenn oben im Skript bei $ScriptWidApiKey ein echter API-Key eingetragen ist,
#   sind keine Vorarbeiten am Rechner nötig. Alternativ muss WID_API_KEY
#   als Umgebungsvariable vorhanden sein.
#
# Beispiele:
#   powershell.exe -ExecutionPolicy Bypass -File .\LSI-Apple-Auswertung-v5.2.ps1 -DaysBack 90 -MaxAdvisories 50
#   powershell.exe -ExecutionPolicy Bypass -File .\LSI-Apple-Auswertung-v5.2.ps1 -DaysBack 365 -MaxAdvisories 100 -OnlySubscribed $false
#   powershell.exe -ExecutionPolicy Bypass -File .\LSI-Apple-Auswertung-v5.2.ps1 -DaysBack 90 -MaxAdvisories 50 -KeepRawJson
#   powershell.exe -ExecutionPolicy Bypass -File .\LSI-Apple-Auswertung-v5.2.ps1 -DaysBack 90 -MaxAdvisories 50 -KeepPerAdvisoryCsv
#   powershell.exe -ExecutionPolicy Bypass -File .\LSI-Apple-Auswertung-v5.2.ps1 -ForceFullRun
#
# Parameter im Detail:
#   -DaysBack           : Zeitfenster (Tage) für die WID-Abfrage.
#                         Im Folgelauf wird das Skript dieses Fenster
#                         automatisch verkleinern, sofern eine
#                         bestehende Gesamtauswertung gefunden wird.
#                         Bei -ForceFullRun gilt der angegebene Wert.
#                         Default: 365. Bisher genutzte Werte: 90, 365, max. 1000.
#
#   -MaxAdvisories      : Sicherheitsdeckel pro Run für WID-Kandidaten.
#                         Im Erstlauf (keine vorhandene Ausgabedatei)
#                         wird der Deckel automatisch auf 100 angehoben.
#                         Im Folgelauf gilt der angegebene Wert.
#                         Default: 50. Bisher genutzte Werte: 10-50.
#
#   -OnlySubscribed     : nur abonnierte WID-Advisories berücksichtigen.
#                         Default: $true
#
#   -Classifications    : Risikoklassen, die einbezogen werden.
#                         Default: "hoch", "kritisch"
#
#   -TitleRegex         : Titel-Filter (RegEx). Default: Apple iOS/iPadOS/Safari.
#
#   -PageSize           : Pagination-Größe der WID-API. Default: 100.
#
#   -KeepRawJson        : zusätzlich Roh-JSON je LSI-Meldung speichern.
#   -KeepPerAdvisoryCsv : zusätzlich Einzel-CSV je LSI-Meldung speichern.
#
#   -ForceFullRun       : Inkrementlogik überspringen und Vollanlage erzwingen
#                         (vorhandene Gesamtauswertung wird ignoriert).
#
# Standard:
#   - Roh-JSON wird nicht gespeichert.
#   - Einzel-CSV je LSI-Meldung wird nicht gespeichert.
# Nur mit -KeepRawJson werden LSI-SEC-*.json-Dateien geschrieben.
# Nur mit -KeepPerAdvisoryCsv werden LSI-SEC-*_Apple-Auswertung_*.csv-Dateien geschrieben.
#
# Ausgabe:
#   Alle Dateien werden in denselben Ordner geschrieben, in dem dieses Skript liegt.

param(
    [int]$DaysBack = 365,
    [int]$MaxAdvisories = 50,
    [bool]$OnlySubscribed = $true,
    [string[]]$Classifications = @("hoch", "kritisch"),
    [string]$TitleRegex = "Apple.*(iOS|iPadOS)|iOS.*iPadOS|Apple Safari",
    [int]$PageSize = 100,
    [switch]$KeepRawJson,
    [switch]$KeepPerAdvisoryCsv,
    [switch]$ForceFullRun
)

$ErrorActionPreference = "Stop"

# =============================================================================
# LOKALE KONFIGURATION
# =============================================================================
# Optional: API-Key direkt hier eintragen, damit das Skript auch auf einem
# anderen Rechner ohne vorher gesetzte Umgebungsvariable laufen kann.
# Platzhalter unverändert lassen, wenn der Key weiterhin über WID_API_KEY kommt.
$ScriptWidApiKey = ">Dein-LSI-API-Key"

function Set-WidApiKeyFromScript {
    param(
        [string]$ApiKey
    )

    if ($ApiKey -and $ApiKey.Trim() -ne "" -and $ApiKey -ne "dein-api-key") {
        $env:WID_API_KEY = $ApiKey
    }
}

Set-WidApiKeyFromScript -ApiKey $ScriptWidApiKey

# --------------------------------------------------------------------
# RELEVANT_VERSIONS — Selbstwissen des Skripts
# --------------------------------------------------------------------
# Liste der iOS-/iPadOS-Zweige, die aktuell im Feld vertreten sind.
# Einträge können Major-Versionen ("18", "26") oder Minor-Linien
# ("18.07", "18.10", "26.05") sein. Die Liste wird beim Matching
# normalisiert (führende Nullen pro Segment).
#
# Wirkung:
#   - Filter beim Folgelauf: Einträge, deren BetroffeneVersionen oder
#     BehobenDurch keinen dieser Zweige mehr trifft, werden aus der
#     fortgeschriebenen Gesamtauswertung entfernt (Bereinigung).
#   - Filter bei Neuabfragen: gleicher Mechanismus, neue Einträge
#     ohne Treffer werden gar nicht erst übernommen.
#
# Pflege: Diese Liste ist manuell zu aktualisieren, wenn eine alte
#         iOS-Linie aus dem Feld verschwindet oder eine neue Major
#         aufkommt. Bewusste Schwelle, kein Automatismus.
# --------------------------------------------------------------------
$script:RELEVANT_VERSIONS = @(
    "18",
    "26"
)

if ($PSScriptRoot) {
    $outDir = $PSScriptRoot
}
else {
    $outDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    if (-not $outDir) {
        $outDir = (Get-Location).Path
    }
}

New-Item -ItemType Directory -Force -Path $outDir | Out-Null

if (-not $env:WID_API_KEY) {
    throw "Umgebungsvariable WID_API_KEY fehlt. Setze sie vorher in PowerShell mit: `$env:WID_API_KEY = 'dein-api-key'"
}

$headers = @{
    "Accept"    = "*/*"
    "X-Api-Key" = $env:WID_API_KEY
}

$OutputColumns = @(
    "LsiId",
    "LsiTitel",
    "LsiRisiko",
    "Exploit",
    "NoPatch",
    "LsiInitialdatum",
    "LsiStand",
    "BetroffeneVersionen",
    "BehobenDurch",
    "MinFixVersions",
    "MinFixIosLinie18",
    "MinFixIosLinie26",
    "MinFixIpadOsLinie18",
    "MinFixIpadOsLinie26",
    "QuelleDeutsch",
    "AppleUrl",
    "Komponente",
    "ImpactOriginal",
    "DescriptionOriginal",
    "CVEs",
    "Qualitaet",
    "KurzbeschreibungDE"
)

# --------------------------------------------------------------------
# Helper: WID-API mit UTF-8-Decoding aufrufen
# In PS 5 ignoriert Invoke-RestMethod fehlende charset-Angaben und
# fällt auf die System-Codepage zurück. Folge: "ermÃ¶glicht" statt
# "ermöglicht". Wir lesen die Bytes selbst und decodieren als UTF-8.
# --------------------------------------------------------------------
function Invoke-WidApi {
    param([string]$Uri)

    $response = Invoke-WebRequest -Uri $Uri -Headers $headers -Method Get -UseBasicParsing -ErrorAction Stop

    $stream = $response.RawContentStream
    $stream.Position = 0
    $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8)
    $jsonText = $reader.ReadToEnd()
    $reader.Close()

    return $jsonText | ConvertFrom-Json
}

# --------------------------------------------------------------------
# Helper: einzelnes Versionssegment normalisieren
# 7 → 07, 10 → 10, 26 → 26. Leerstring bleibt leer.
# Nicht-numerische Segmente werden unverändert durchgereicht.
# --------------------------------------------------------------------
function Get-NormalizedVersion {
    param([string]$Version)

    if ([string]::IsNullOrWhiteSpace($Version)) {
        return ""
    }

    $segments = $Version.Trim() -split "\."
    $normalized = @()
    foreach ($seg in $segments) {
        if ($seg -match '^\d+$') {
            $normalized += "{0:D2}" -f [int]$seg
        }
        else {
            $normalized += $seg
        }
    }
    return $normalized -join "."
}

# --------------------------------------------------------------------
# Helper: Versions-Zahlen in Apple-Produktstrings normalisieren
# "Apple iOS < 18.7.5" → "Apple iOS < 18.07.05"
# "Apple iPadOS 26.3" → "Apple iPadOS 26.03"
# Nur Zahlen direkt hinter Apple-Produktnamen werden angefasst.
# CVE-IDs, Jahreszahlen und sonstiger Text bleiben unberührt.
# --------------------------------------------------------------------
function ConvertTo-NormalizedAppleVersions {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $Text
    }

    # Erkennt u. a.:
    #   Apple iOS < 18.7.5      -> Apple iOS < 18.07.05
    #   Apple iPadOS 26.3       -> Apple iPadOS 26.03
    #   macOS Sequoia < 15.3    -> macOS Sequoia < 15.03
    #   Apple macOS Sonoma 14.7 -> Apple macOS Sonoma 14.07
    # Der optionale Marketingname zwischen Produkt und Operator/Version
    # wird mitgenommen, aber nicht verändert.
    return [regex]::Replace(
        $Text,
        '((?:Apple\s+)?(?:iOS|iPadOS|Safari|macOS|watchOS|tvOS|visionOS)(?:\s+[A-Za-z][A-Za-z0-9._-]*){0,4}\s+(?:[<>=]+\s*)?)(\d+(?:\.\d+)*)',
        {
            param($m)
            $prefix = $m.Groups[1].Value
            $version = $m.Groups[2].Value
            return $prefix + (Get-NormalizedVersion -Version $version)
        }
    )
}

# --------------------------------------------------------------------
# Helper: prüft, ob ein Eintrag noch zu RELEVANT_VERSIONS passt
# Trifft einer der konfigurierten Zweige in BetroffeneVersionen
# ODER in BehobenDurch, gilt der Eintrag als relevant.
# Vergleicht in normalisierter Form, damit "18" auch "18.07.05" matcht.
# --------------------------------------------------------------------
function Test-IsRelevantEntry {
    param(
        [string]$BetroffeneVersionen,
        [string]$BehobenDurch
    )

    if (-not $script:RELEVANT_VERSIONS -or $script:RELEVANT_VERSIONS.Count -eq 0) {
        return $true
    }

    $combined = "$BetroffeneVersionen $BehobenDurch"
    if ([string]::IsNullOrWhiteSpace($combined)) {
        return $false
    }

    # Alle Versions-Strings in Apple-Produktkontext aus dem Text ziehen
    $versionMatches = [regex]::Matches(
        $combined,
        '(?:iOS|iPadOS|Safari|macOS|watchOS|tvOS|visionOS)\s+(?:[<>=]+\s*)?(\d+(?:\.\d+)*)'
    )

    foreach ($m in $versionMatches) {
        $found = $m.Groups[1].Value
        $foundNorm = Get-NormalizedVersion -Version $found

        foreach ($relevant in $script:RELEVANT_VERSIONS) {
            $relevantNorm = Get-NormalizedVersion -Version $relevant
            if ($foundNorm -eq $relevantNorm -or $foundNorm -like "$relevantNorm.*") {
                return $true
            }
        }
    }

    return $false
}

# --------------------------------------------------------------------
# Helper: Apple-"BehobenDurch"-Strings in Linien-Versionen zerlegen
# Erwartet Einträge wie "Apple iOS 18.7.5", "Apple iPadOS 26.3".
# Liefert ein Hash mit Compact-String und vier Linien-Versionen.
# Alle Versions-Strings werden hier bereits normalisiert ausgegeben.
# --------------------------------------------------------------------
function Get-MinFixBreakdown {
    param([string[]]$FixedNames)

    $result = @{
        Compact       = ""
        IosLinie18    = ""
        IosLinie26    = ""
        IpadOsLinie18 = ""
        IpadOsLinie26 = ""
    }

    if (-not $FixedNames -or $FixedNames.Count -eq 0) {
        return $result
    }

    $parts = @()

    foreach ($name in $FixedNames) {
        if ($name -match "^Apple\s+(iOS|iPadOS|Safari|macOS|watchOS|tvOS|visionOS)\s+(\d+(?:\.\d+)*)") {
            $product = $Matches[1]
            $version = $Matches[2]
            $major   = ($version -split "\.")[0]
            $normVer = Get-NormalizedVersion -Version $version

            $parts += "$product $normVer"

            switch ("$product/$major") {
                "iOS/18"    { if (-not $result.IosLinie18)    { $result.IosLinie18    = $normVer } }
                "iOS/26"    { if (-not $result.IosLinie26)    { $result.IosLinie26    = $normVer } }
                "iPadOS/18" { if (-not $result.IpadOsLinie18) { $result.IpadOsLinie18 = $normVer } }
                "iPadOS/26" { if (-not $result.IpadOsLinie26) { $result.IpadOsLinie26 = $normVer } }
            }
        }
    }

    $result.Compact = ($parts | Sort-Object -Unique) -join ", "
    return $result
}

# --------------------------------------------------------------------
# Helper: doppelte Apple-Entries je LSI zusammenführen
# Eine LSI-Meldung verlinkt häufig mehrere Apple-Support-URLs
# (z. B. iOS 18.x und iOS 26.x). Component/Impact/CVE sind dann
# identisch. Wir gruppieren nach (LsiId, Komponente, CVEs) und
# mergen die AppleUrl-Werte zu einem durch " | " getrennten String.
# --------------------------------------------------------------------
function Merge-DuplicateEntries {
    param([array]$Entries)

    if (-not $Entries -or $Entries.Count -eq 0) {
        return @()
    }

    $grouped = $Entries | Group-Object LsiId, Komponente, CVEs
    $merged = @()

    foreach ($g in $grouped) {
        $first = $g.Group[0]

        if ($g.Count -gt 1) {
            $urls = @($g.Group |
                ForEach-Object { $_.AppleUrl } |
                Where-Object { $_ } |
                Sort-Object -Unique)
            $first.AppleUrl = ($urls -join " | ")
        }

        $merged += $first
    }

    return $merged
}

# --------------------------------------------------------------------
# Helper: jüngste vorhandene Gesamtauswertung im outDir suchen
# Fehler-CSVs werden ausgeklammert. Liefert FileInfo oder $null.
# --------------------------------------------------------------------
function Get-LatestExistingGesamtCsv {
    param([string]$Directory)

    $files = Get-ChildItem -Path $Directory -Filter "LSI-Apple-Gesamtauswertung_*.csv" -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notmatch "Fehler" } |
        Sort-Object LastWriteTime -Descending

    if (-not $files -or $files.Count -eq 0) {
        return $null
    }

    return $files | Select-Object -First 1
}

# --------------------------------------------------------------------
# Helper: jüngsten vorhandenen Managementreport im outDir suchen
# Liefert FileInfo oder $null. Wird genutzt, damit Folgeläufe die
# bestehende Reportdatei aktualisieren statt eine neue zu erzeugen.
# --------------------------------------------------------------------
function Get-LatestExistingManagementReportCsv {
    param([string]$Directory)

    $files = Get-ChildItem -Path $Directory -Filter "LSI-Apple-Managementreport_*.csv" -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending

    if (-not $files -or $files.Count -eq 0) {
        return $null
    }

    return $files | Select-Object -First 1
}

# --------------------------------------------------------------------
# Helper: Datumsbereich einer vorhandenen Gesamtauswertung ermitteln
# Liest LsiStand-Spalte, gibt Min/Max + Anzahl Zeilen zurück.
# --------------------------------------------------------------------
function Get-ExistingDateRange {
    param([string]$CsvPath)

    $rows = @(Import-Csv -Path $CsvPath -Delimiter ";" -Encoding UTF8)
    if (-not $rows -or $rows.Count -eq 0) {
        return $null
    }

    $dates = @()
    foreach ($row in $rows) {
        if ($row.LsiStand) {
            try {
                $d = [DateTime]::Parse($row.LsiStand)
                $dates += $d
            }
            catch {
                # ungültiges Datumsfeld überspringen
            }
        }
    }

    if ($dates.Count -eq 0) {
        return $null
    }

    return @{
        Oldest   = ($dates | Measure-Object -Minimum).Minimum
        Newest   = ($dates | Measure-Object -Maximum).Maximum
        RowCount = $rows.Count
        Rows     = $rows
    }
}

# --------------------------------------------------------------------
# Helper: bestehende Zeilen mit neuen mergen
# Schlüssel: (LsiId, Komponente, CVEs). Neue Einträge überschreiben.
# --------------------------------------------------------------------
function Merge-WithExistingRows {
    param(
        [array]$ExistingRows,
        [array]$NewRows
    )

    $merged = [ordered]@{}

    foreach ($row in $ExistingRows) {
        $key = "$($row.LsiId)|$($row.Komponente)|$($row.CVEs)"
        $merged[$key] = $row
    }

    foreach ($row in $NewRows) {
        $key = "$($row.LsiId)|$($row.Komponente)|$($row.CVEs)"
        $merged[$key] = $row
    }

    return @($merged.Values)
}

Write-Host "LSI-Apple-Auswertung v5.2"
Write-Host "--------------------------"
Write-Host ""

function Get-SpecialAppleSummary {
    param(
        [string]$Text
    )

    $t = $Text.ToLowerInvariant()

    # Restfälle aus 90-Tage-Testlauf
    if ($t -match "crash a system process|system process.*crash") {
        return "Eine App kann unter Umständen einen Systemprozess zum Absturz bringen."
    }
    if ($t -match "access notes attachments|notes attachments") {
        return "Eine App kann unter Umständen auf Notes-Anhänge zugreifen."
    }
    if ($t -match "physical proximity.*out of bounds write|limited out of bounds write|out of bounds write") {
        return "Ein Angreifer in physischer Nähe kann unter Umständen einen begrenzten Speicher-Schreibfehler auslösen."
    }

    # Netzwerk / Mail / Privacy / Web-Sonderfälle
    if ($t -match "privileged network position|intercept network traffic") {
        return "Ein Angreifer in privilegierter Netzwerkposition kann unter Umständen Netzwerkverkehr abfangen."
    }
    if ($t -match "hide ip address|block all remote content|all mail content|load remote images|remote content.*loaded|remote content.*mail|mail previews|remote images.*lockdown mode|lockdown mode.*remote images") {
        return "E-Mail-Inhalte können unter Umständen trotz Schutzoptionen wie IP-Adresse verbergen, externe Inhalte blockieren oder Lockdown Mode geladen werden."
    }
    if ($t -match "keychain") {
        return "Ein lokaler Angreifer kann unter Umständen auf Schlüsselbund-Inhalte zugreifen oder den Zustand des Schlüsselbunds verändern."
    }
    if ($t -match "same origin policy|cross-origin") {
        return "Manipulierter Webinhalt kann unter Umständen die Same-Origin-Sicherheitsgrenze umgehen."
    }
    if ($t -match "cross-site scripting") {
        return "Der Besuch einer manipulierten Webseite kann unter Umständen Cross-Site-Scripting ermöglichen."
    }
    if ($t -match "script message handlers|other origins") {
        return "Eine bösartige Webseite kann unter Umständen auf Schnittstellen zugreifen, die für andere Web-Ursprünge vorgesehen sind."
    }
    if ($t -match "restricted web content outside the sandbox|outside the sandbox|web content sandbox") {
        return "Eine bösartige Webseite kann unter Umständen Sandbox-Grenzen für Webinhalte umgehen."
    }
    if ($t -match "leaked dns queries|private relay") {
        return "Ein entfernter Angreifer kann unter Umständen DNS-Anfragen trotz aktiviertem Private Relay einsehen."
    }

    # Datenzugriff / Datenschutz
    if ($t -match "access protected user data|protected user data|access user-sensitive data|sensitive data logged|sensitive contact information|read sensitive contact information|disclosure of user information|disclose user information|user information|process memory|memory contents|disclose memory|safari history|deleted notes|passkeys without authentication|private browsing tabs") {
        return "Eine App oder ein Angreifer kann unter Umständen auf geschützte oder sensible Nutzerdaten zugreifen."
    }
    if ($t -match "identifying information leaked|identify what other apps|identify what other applications|installed apps|enumerate.*installed apps") {
        return "Eine App kann unter Umständen Informationen zur Identität oder zu installierten Apps des Nutzers auslesen."
    }
    if ($t -match "observe system-wide network connections") {
        return "Eine App kann unter Umständen systemweite Netzwerkverbindungen beobachten."
    }
    if ($t -match "monitor keystrokes") {
        return "Eine App kann unter Umständen Tastatureingaben ohne Zustimmung des Nutzers überwachen."
    }
    if ($t -match "passcode.*read aloud|voiceover") {
        return "Der Gerätecode kann unter Umständen über VoiceOver vorgelesen werden."
    }
    if ($t -match "s/mime|encrypted e-mail|encrypted email") {
        return "Bei S/MIME-verschlüsselten E-Mails können unter Umständen Absenderinformationen oder Klartextinhalte offengelegt werden."
    }

    # Datei-/Sandbox-/Systemschutz
    if ($t -match "bypass gatekeeper|gatekeeper checks|file quarantine bypass") {
        return "Ein manipuliertes Disk-Image oder eine manipulierte Datei kann unter Umständen Gatekeeper- oder Quarantäne-Prüfungen umgehen."
    }
    if ($t -match "bypass signature validation|signature validation") {
        return "Eine bösartige App kann unter Umständen Signaturprüfungen umgehen."
    }
    if ($t -match "bypass sandbox restrictions|circumvent sandbox restrictions|sandbox restrictions|break out of web content sandbox") {
        return "Eine App oder Webseite kann unter Umständen Sandbox-Beschränkungen umgehen."
    }
    if ($t -match "write arbitrary files|overwrite arbitrary files|read arbitrary files|delete files|access a user's files|protected system files|protected parts of the file system|modify protected") {
        return "Eine App oder ein Angreifer kann unter Umständen Dateien lesen, verändern, überschreiben oder löschen, für die keine Berechtigung besteht."
    }

    # UI-/Sperrbildschirm-/Spoofing-Fälle
    if ($t -match "address bar spoofing|user interface spoofing|ui spoofing") {
        return "Der Besuch einer manipulierten Webseite kann unter Umständen eine gefälschte Adresszeile oder Benutzeroberfläche anzeigen."
    }
    if ($t -match "fail to lock|persistently fail to lock") {
        return "Ein Gerät kann unter Umständen dauerhaft nicht korrekt gesperrt werden."
    }
    if ($t -match "3d model.*face id|face id") {
        return "Ein speziell präpariertes 3D-Modell kann unter Umständen eine Face-ID-Authentifizierung auslösen."
    }

    # Netzwerk-/Transport-/sonstige Sicherheitsmechanismen
    if ($t -match "app transport security") {
        return "Eine App kann unter Umständen App-Transport-Security-Vorgaben nicht korrekt durchsetzen."
    }
    if ($t -match "live caller id") {
        return "Informationen können unter Umständen trotz deaktivierter Live-Caller-ID-Erweiterung an diese Erweiterung gelangen."
    }
    if ($t -match "additional logging") {
        return "Eine bösartige App kann unter Umständen durch zusätzliche Protokollierung Daten anderer Apps auslesen."
    }
    if ($t -match "messages group.*continue to receive messages") {
        return "Ein Nutzer kann unter Umständen nach Verlassen einer Nachrichten-Gruppe weiterhin Nachrichten dieser Gruppe erhalten."
    }

    # Speicher / Formate
    if ($t -match "maliciously crafted usd file|usd file") {
        return "Eine manipulierte USD-Datei kann unter Umständen Speicherinhalte offenlegen."
    }
    if ($t -match "maliciously crafted audio file") {
        return "Eine manipulierte Audiodatei kann unter Umständen Nutzerdaten oder Speicherinformationen offenlegen."
    }
    if ($t -match "multiple issues in hdf5|hdf5") {
        return "Mehrere Schwachstellen in der HDF5-Verarbeitung können unter Umständen sicherheitsrelevante Auswirkungen haben."
    }

    return $null
}

function Get-SpecialAppleQuality {
    param(
        [string]$Text
    )

    $t = $Text.ToLowerInvariant()

    # Restfälle aus 90-Tage-Testlauf
    if ($t -match "access notes attachments|notes attachments") {
        return "relevant"
    }
    if ($t -match "crash a system process|system process.*crash|physical proximity.*out of bounds write|limited out of bounds write|out of bounds write") {
        return "mittel"
    }

    # Sehr relevant
    if (
        $t -match "elevate.*privileges|local attacker.*privileges|bypass signature validation|actively exploited|passkeys without authentication|face id|arbitrary files|protected system files|protected parts of the file system|modify protected|delete files|overwrite arbitrary files|read arbitrary files|break out of web content sandbox|bypass sandbox restrictions|circumvent sandbox restrictions|sandbox restrictions"
    ) {
        return "sehr relevant"
    }

    # Relevant
    if (
        $t -match "privileged network position|intercept network traffic|hide ip address|block all remote content|all mail content|load remote images|remote content|mail previews|keychain|same origin policy|cross-origin|cross-site scripting|script message handlers|other origins|restricted web content outside the sandbox|outside the sandbox|leaked dns queries|private relay|access protected user data|protected user data|access user-sensitive data|sensitive data logged|sensitive contact information|user information|process memory|memory contents|safari history|deleted notes|private browsing tabs|identifying information|identify what other apps|identify what other applications|installed apps|observe system-wide network connections|monitor keystrokes|passcode|voiceover|s/mime|encrypted e-mail|encrypted email|gatekeeper|file quarantine|address bar spoofing|user interface spoofing|ui spoofing|fail to lock|app transport security|live caller id|additional logging|messages group|maliciously crafted usd file|maliciously crafted audio file|hdf5"
    ) {
        return "relevant"
    }

    return $null
}

function New-GermanSummary {
    param(
        [string]$Impact,
        [string]$Description
    )

    $s = "$Impact $Description"

    $special = Get-SpecialAppleSummary -Text $s
    if ($special) {
        return $special
    }

    if ($s -match "bypass Gatekeeper|Gatekeeper checks|file quarantine bypass") {
        return "Ein manipuliertes Disk-Image oder eine manipulierte Datei kann unter Umständen Gatekeeper- oder Quarantäne-Prüfungen umgehen."
    }
    if ($s -match "enumerate.*installed apps|installed apps") {
        return "Eine App kann unter Umständen die installierten Apps eines Nutzers auflisten."
    }
    if ($s -match "remote images.*Mail.*Lockdown Mode|Lockdown Mode.*remote images") {
        return "Beim Antworten auf eine E-Mail können unter Umständen trotz Lockdown Mode externe Bilder geladen werden."
    }
    if ($s -match "App Privacy Report logging|circumvent.*Privacy Report") {
        return "Eine App kann unter Umständen die Protokollierung im App-Datenschutzbericht umgehen."
    }
    if ($s -match "Content Security Policy|CSP") {
        return "Manipulierter Webinhalt kann unter Umständen eine wichtige Web-Sicherheitsregel umgehen."
    }
    if ($s -match "unexpected Safari crash") {
        return "Manipulierter Webinhalt kann unter Umständen Safari zum Absturz bringen."
    }
    if ($s -match "unexpected process crash|process crash|terminate the process") {
        if ($s -match "web content|website|WebKit|WebRTC") {
            return "Manipulierter Webinhalt kann unter Umständen einen Prozess- oder Browserabsturz verursachen."
        }
        if ($s -match "audio|media") {
            return "Eine manipulierte Mediendatei kann unter Umständen einen Prozessabsturz verursachen."
        }
        return "Manipulierte Inhalte können unter Umständen einen Prozessabsturz verursachen."
    }
    if ($s -match "leak sensitive kernel state") {
        return "Eine App kann unter Umständen sensible Kernel-Zustandsinformationen offenlegen."
    }
    if ($s -match "access user-sensitive data|user-sensitive data") {
        return "Eine App kann unter Umständen auf sensible Nutzerdaten zugreifen."
    }
    if ($s -match "restricted content from the lock screen|lock screen") {
        return "Geschützte Inhalte können unter Umständen vom Sperrbildschirm aus sichtbar werden."
    }
    if ($s -match "maliciously crafted website.*leak sensitive data|website may leak sensitive data") {
        return "Der Besuch einer manipulierten Webseite kann unter Umständen sensible Daten offenlegen."
    }
    if ($s -match "malicious iframe.*download settings|iframe.*download settings") {
        return "Ein manipuliertes eingebettetes Webelement kann unter Umständen Download-Einstellungen einer anderen Webseite missbrauchen."
    }

    if ($s -match "arbitrary code execution|execute arbitrary code|code execution") {
        if ($s -match "web content|HTML|Safari|WebKit") {
            return "Manipulierter Webinhalt kann Schadcodeausführung ermöglichen."
        }
        if ($s -match "image|photo|picture") {
            return "Ein manipuliertes Bild kann Schadcodeausführung ermöglichen."
        }
        if ($s -match "file|media|document") {
            return "Eine manipulierte Datei kann Schadcodeausführung ermöglichen."
        }
        return "Manipulierte Inhalte können Schadcodeausführung ermöglichen."
    }
    if ($s -match "gain root privileges|root privileges") {
        return "Eine App kann unter Umständen höchste Systemrechte erlangen."
    }
    if ($s -match "local attacker.*elevate.*privileges|elevate their privileges") {
        return "Ein lokaler Angreifer kann unter Umständen seine Rechte auf dem Gerät erweitern."
    }
    if ($s -match "gain elevated privileges|elevate privileges|elevated privileges|privilege escalation|increase privileges") {
        return "Eine App kann unter Umständen erweiterte Rechte auf dem Gerät erlangen."
    }
    if ($s -match "kernel privileges") {
        return "Eine App kann unter Umständen Rechte im Betriebssystem-Kernel erlangen."
    }
    if ($s -match "write kernel memory|modify kernel memory") {
        return "Eine App kann unter Umständen Speicherbereiche des Betriebssystem-Kernels verändern."
    }
    if ($s -match "read kernel memory|disclose kernel memory|kernel memory disclosure") {
        return "Eine App kann unter Umständen Speicherinhalte des Betriebssystem-Kernels auslesen."
    }
    if ($s -match "break out of its sandbox|escape its sandbox|sandbox escape") {
        return "Eine bösartige App kann unter Umständen aus ihrer geschützten Sandbox ausbrechen."
    }
    if ($s -match "bypass Pointer Authentication|bypass.*PAC") {
        return "Eine App kann unter Umständen einen Schutzmechanismus gegen Speicherangriffe umgehen."
    }

    if ($s -match "sensitive user data|sensitive user information|access sensitive|sensitive information|disclose sensitive") {
        return "Eine App oder ein Angreifer kann unter Umständen auf sensible Nutzerdaten zugreifen."
    }
    if ($s -match "private information|personal information") {
        return "Eine App oder ein Angreifer kann unter Umständen private Informationen offenlegen."
    }
    if ($s -match "location information|precise location|user location") {
        return "Eine App kann unter Umständen Standortinformationen offenlegen."
    }
    if ($s -match "contacts|photos|calendar|microphone|camera") {
        return "Eine App kann unter Umständen auf Kontakte, Fotos, den Kalender oder Mikrofon-/Kamera-Daten zugreifen."
    }
    if ($s -match "fingerprinting|tracking") {
        return "Eine App oder ein Webinhalt kann unter Umständen Nutzer wiedererkennen oder verfolgen."
    }
    if ($s -match "spoofing|spoofed") {
        return "Eine bösartige Komponente kann unter Umständen eine Identität oder Quelle vortäuschen."
    }
    if ($s -match "denial of service|denial-of-service") {
        return "Manipulierte Inhalte können unter Umständen einen Denial-of-Service auslösen."
    }
    if ($s -match "unexpected app termination|unexpected system termination|app termination|system termination|app crash|system crash|device may restart") {
        return "Manipulierte Inhalte können unter Umständen einen unerwarteten App- oder Systemabbruch verursachen."
    }
    if ($s -match "memory corruption|corrupt process memory|out-of-bounds read|out-of-bounds write|use after free|integer overflow|integer underflow") {
        return "Speicherfehler können unter Umständen sicherheitsrelevante Auswirkungen haben."
    }
    if ($s -match "local network") {
        return "Ein Angreifer im lokalen Netzwerk kann unter Umständen sicherheitsrelevante Auswirkungen erzielen."
    }
    if ($s -match "physical access") {
        return "Ein Angreifer mit physischem Zugriff kann unter Umständen sicherheitsrelevante Auswirkungen erzielen."
    }

    return ""
}

function New-RiskQuality {
    param(
        [string]$Impact,
        [string]$Description
    )

    $s = "$Impact $Description"

    $special = Get-SpecialAppleQuality -Text $s
    if ($special) {
        return $special
    }

    if (
        $s -match "arbitrary code execution|execute arbitrary code|code execution|kernel privileges|root privileges|gain root|kernel memory|sandbox escape|escape its sandbox|break out of its sandbox|break out of web content sandbox|bypass Pointer Authentication|bypass.*PAC|bypass Gatekeeper|Gatekeeper checks|file quarantine bypass|bypass signature validation"
    ) {
        return "sehr relevant"
    }
    if (
        $s -match "elevate privileges|elevated privileges|privilege escalation|increase privileges|local attacker.*elevate|elevate their privileges|sensitive user data|sensitive user information|access sensitive|sensitive information|disclose sensitive|user-sensitive data|access user-sensitive data|enumerate.*installed apps|installed apps|leak sensitive kernel state|restricted content from the lock screen|lock screen|App Privacy Report logging|circumvent.*Privacy Report|Content Security Policy|CSP|maliciously crafted website.*leak sensitive data|website may leak sensitive data|malicious iframe.*download settings|iframe.*download settings|remote images.*Mail.*Lockdown Mode|Lockdown Mode.*remote images|private information|personal information|location information|precise location|user location|contacts|photos|calendar|microphone|camera|fingerprinting|tracking|spoofing|spoofed"
    ) {
        return "relevant"
    }
    if ($s -match "denial of service|denial-of-service") {
        return "mittel"
    }
    if ($s -match "unexpected Safari crash|unexpected process crash|process crash|terminate the process") {
        return "mittel"
    }
    if ($s -match "unexpected app termination|unexpected system termination|app termination|system termination|app crash|system crash|device may restart") {
        return "mittel"
    }
    if ($s -match "memory corruption|corrupt process memory|out-of-bounds read|out-of-bounds write|use after free|integer overflow|integer underflow") {
        return "mittel"
    }
    if ($s -match "local network") {
        return "mittel"
    }
    if ($s -match "physical access") {
        return "mittel"
    }

    return "prüfen"
}

function New-AppleEntry {
    param(
        [hashtable]$Context,
        [string]$AppleUrl,
        [string]$Component,
        [string]$Impact,
        [string]$Description,
        [array]$Cves
    )

    if (-not $Component -or -not $Impact) {
        return $null
    }

    return [pscustomobject]@{
        LsiId                = $Context.LsiId
        LsiTitel             = $Context.LsiTitel
        LsiRisiko            = $Context.LsiRisiko
        Exploit              = $Context.Exploit
        NoPatch              = $Context.NoPatch
        LsiInitialdatum      = $Context.LsiInitialdatum
        LsiStand             = $Context.LsiStand
        BetroffeneVersionen  = $Context.BetroffeneVersionen
        BehobenDurch         = $Context.BehobenDurch
        MinFixVersions       = $Context.MinFixVersions
        MinFixIosLinie18     = $Context.MinFixIosLinie18
        MinFixIosLinie26     = $Context.MinFixIosLinie26
        MinFixIpadOsLinie18  = $Context.MinFixIpadOsLinie18
        MinFixIpadOsLinie26  = $Context.MinFixIpadOsLinie26
        QuelleDeutsch        = "Apple Security Advisory"
        AppleUrl             = $AppleUrl
        Komponente           = $Component
        ImpactOriginal       = $Impact
        DescriptionOriginal  = $Description
        CVEs                 = ($Cves | Sort-Object -Unique) -join ", "
        Qualitaet            = New-RiskQuality -Impact $Impact -Description $Description
        KurzbeschreibungDE   = New-GermanSummary -Impact $Impact -Description $Description
    }
}

function Get-AppleAdvisoryEntries {
    param(
        [string]$Url,
        [hashtable]$Context
    )

    try {
        $html = Invoke-WebRequest -Uri $Url -UseBasicParsing -ErrorAction Stop
    }
    catch {
        throw "Apple-Seite konnte nicht geladen werden: $Url`n$($_.Exception.Message)"
    }

    $text = $html.Content
    $text = $text -replace "<br\s*/?>", "`n"
    $text = $text -replace "</p>", "`n"
    $text = $text -replace "</h3>", "`n"
    $text = $text -replace "</h2>", "`n"
    $text = $text -replace "</li>", "`n"
    $text = $text -replace "<[^>]+>", ""
    $text = [System.Net.WebUtility]::HtmlDecode($text)

    $lines = $text -split "`n" |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ }

    $localEntries = @()
    $currentComponent = $null
    $currentImpact = $null
    $currentDescription = $null
    $currentCves = @()

    foreach ($line in $lines) {
        if (
            $line -match "^[A-Za-z0-9 /()._-]{2,60}$" -and
            $line -notmatch "^(Impact|Description|Available for|CVE-|Released|About|This document|Entry added|Entry updated|Published Date|Helpful\?)"
        ) {
            $entry = New-AppleEntry -Context $Context -AppleUrl $Url -Component $currentComponent -Impact $currentImpact -Description $currentDescription -Cves $currentCves
            if ($entry) {
                $localEntries += $entry
            }

            $currentComponent = $line
            $currentImpact = $null
            $currentDescription = $null
            $currentCves = @()
            continue
        }

        if ($line -match "^Impact:\s*(.+)$") {
            $currentImpact = $Matches[1]
            continue
        }

        if ($line -match "^Description:\s*(.+)$") {
            $currentDescription = $Matches[1]
            continue
        }

        if ($line -match "CVE-\d{4}-\d{4,7}") {
            $cveMatches = [regex]::Matches($line, "CVE-\d{4}-\d{4,7}")
            foreach ($m in $cveMatches) {
                $currentCves += $m.Value
            }
            continue
        }
    }

    $entry = New-AppleEntry -Context $Context -AppleUrl $Url -Component $currentComponent -Impact $currentImpact -Description $currentDescription -Cves $currentCves
    if ($entry) {
        $localEntries += $entry
    }

    return $localEntries
}

function Get-WidCandidateAdvisories {
    param(
        [int]$DaysBack,
        [int]$MaxAdvisories,
        [bool]$OnlySubscribed,
        [string[]]$Classifications,
        [string]$TitleRegex,
        [int]$PageSize
    )

    $fromDate = (Get-Date).AddDays(-1 * $DaysBack).ToString("yyyy-MM-ddT00:00:00.000zzz")
    $encodedFrom = [uri]::EscapeDataString($fromDate)
    $abo = if ($OnlySubscribed) { "true" } else { "false" }

    $page = 0
    $candidates = @()
    $limitReached = $false

    Write-Host "Suche WID Security Advisories..."
    Write-Host "Zeitraum ab: $fromDate"
    Write-Host "OnlySubscribed: $OnlySubscribed"
    Write-Host "Risiko: $($Classifications -join ', ')"
    Write-Host "Titel-RegEx: $TitleRegex"
    Write-Host "MaxAdvisories: $MaxAdvisories"
    Write-Host ""

    do {
        $uri = "https://wid.lsi.bayern.de/content/public/securityAdvisory?sort=published%2Cdesc&size=$PageSize&page=$page&aboFilter=$abo&publishedFromFilter=$encodedFrom"

        $data = Invoke-WidApi -Uri $uri

        foreach ($item in $data.content) {
            $classificationOk = $Classifications -contains $item.classification
            $titleOk = $item.title -match $TitleRegex

            if ($classificationOk -and $titleOk) {
                $candidates += [pscustomobject]@{
                    LsiId          = $item.name
                    Uuid           = $item.uuid
                    Published      = $item.published
                    Classification = $item.classification
                    Title          = $item.title
                    TemporalScore  = $item.temporalscore
                    Status         = $item.status
                    NoPatch        = $item.noPatch
                    Exploit        = $item.exploit
                }

                if ($candidates.Count -ge $MaxAdvisories) {
                    $limitReached = $true
                    break
                }
            }
        }

        Write-Host "Seite $page / $($data.totalPages - 1): Kandidaten bisher $($candidates.Count)"

        if ($limitReached) {
            break
        }

        $page++
    } while ($page -lt $data.totalPages)

    return @($candidates | Sort-Object Published -Descending | Select-Object -First $MaxAdvisories)
}

function Get-LsiAppleEntries {
    param(
        [pscustomobject]$Candidate
    )

    $LsiName = $Candidate.LsiId
    $Uuid    = $Candidate.Uuid

    if (-not $Uuid) {
        $encodedName = [uri]::EscapeDataString($LsiName)
        $uuidUri = "https://wid.lsi.bayern.de/content/public/securityAdvisory/uuid-by-name/$encodedName"
        $Uuid = Invoke-WidApi -Uri $uuidUri
    }

    $detailUri = "https://wid.lsi.bayern.de/content/public/content/$Uuid"
    $lsi = Invoke-WidApi -Uri $detailUri

    $rawJsonPath = Join-Path $outDir "$LsiName.json"
    if ($KeepRawJson) {
        $lsi | ConvertTo-Json -Depth 100 | Out-File $rawJsonPath -Encoding utf8
    }

    $lsiId = $lsi.properties.idKuerzel
    $lsiTitel = $lsi.properties.title
    $lsiRisiko = $lsi.properties.risiko
    $lsiInitialdatum = $lsi.properties.initialreleasedate
    $lsiStand = $lsi.properties.currentreleasedate

    if (-not $lsiId) {
        throw "LSI-ID konnte nicht aus den geladenen Detaildaten gelesen werden: $LsiName"
    }

    $productRefs = $lsi.children |
        Where-Object { $_.name -eq "productReferenceListe" } |
        Select-Object -ExpandProperty children

    $betroffeneVersionenRaw = $productRefs |
        Where-Object { $_.properties.name -match "<" } |
        ForEach-Object { $_.properties.name } |
        Sort-Object -Unique

    $behobenDurchRaw = $productRefs |
        Where-Object { $_.properties.id -match "-fixed$" } |
        ForEach-Object { $_.properties.name } |
        Sort-Object -Unique

    $appleUrls = $lsi.children |
        Where-Object { $_.name -eq "documentReferenceListe" } |
        Select-Object -ExpandProperty children |
        Where-Object { $_.properties.url -match "support\.apple\.com" } |
        ForEach-Object { $_.properties.url } |
        Sort-Object -Unique

    if (-not $appleUrls -or $appleUrls.Count -eq 0) {
        throw "Keine Apple-Support-URLs in der LSI-Meldung gefunden: $LsiName"
    }

    $minFix = Get-MinFixBreakdown -FixedNames $behobenDurchRaw

    # v5.0: Versionsstrings in Apple-RAW-Texten normalisieren
    $betroffeneVersionen = ConvertTo-NormalizedAppleVersions -Text (($betroffeneVersionenRaw -join " | "))
    $behobenDurch        = ConvertTo-NormalizedAppleVersions -Text (($behobenDurchRaw -join " | "))

    $context = @{
        LsiId               = $lsiId
        LsiTitel            = $lsiTitel
        LsiRisiko           = $lsiRisiko
        Exploit             = $Candidate.Exploit
        NoPatch             = $Candidate.NoPatch
        LsiInitialdatum     = $lsiInitialdatum
        LsiStand            = $lsiStand
        BetroffeneVersionen = $betroffeneVersionen
        BehobenDurch        = $behobenDurch
        MinFixVersions      = $minFix.Compact
        MinFixIosLinie18    = $minFix.IosLinie18
        MinFixIosLinie26    = $minFix.IosLinie26
        MinFixIpadOsLinie18 = $minFix.IpadOsLinie18
        MinFixIpadOsLinie26 = $minFix.IpadOsLinie26
    }

    Write-Host ""
    Write-Host "LSI-ID: $lsiId"
    Write-Host "Titel: $lsiTitel"
    Write-Host "Risiko: $lsiRisiko"
    if ($KeepRawJson) {
        Write-Host "Rohdaten gespeichert: $rawJsonPath"
    }
    else {
        Write-Host "Rohdaten: nicht gespeichert (-KeepRawJson nicht gesetzt)"
    }
    Write-Host "Apple-URLs:"
    $appleUrls | ForEach-Object { Write-Host "  $_" }
    Write-Host ""

    $entriesForThisLsi = @()

    foreach ($url in $appleUrls) {
        Write-Host "Lese Apple-Seite:"
        Write-Host $url

        $appleEntries = Get-AppleAdvisoryEntries -Url $url -Context $context
        foreach ($entry in $appleEntries) {
            $entriesForThisLsi += $entry
        }

        Write-Host "Einträge aus dieser Apple-Seite: $($appleEntries.Count)"
        Write-Host ""
    }

    if ($entriesForThisLsi.Count -eq 0) {
        throw "Es wurden keine Apple-Schwachstelleneinträge erkannt: $LsiName"
    }

    $beforeDedup = $entriesForThisLsi.Count
    $entriesForThisLsi = Merge-DuplicateEntries -Entries $entriesForThisLsi
    $afterDedup = $entriesForThisLsi.Count

    if ($beforeDedup -ne $afterDedup) {
        Write-Host "Deduplikation: $beforeDedup → $afterDedup Einträge (mehrere Apple-Branches zusammengeführt)"
        Write-Host ""
    }

    if ($KeepPerAdvisoryCsv) {
        $timestamp = Get-Date -Format "yyyy-MM-dd"
        $singleCsv = Join-Path $outDir "$($lsiId)_Apple-Auswertung_$timestamp.csv"
        $entriesForThisLsi |
            Select-Object $OutputColumns |
            Export-Csv -Path $singleCsv -NoTypeInformation -Encoding UTF8 -Delimiter ";"

        Write-Host "Einzel-CSV geschrieben:"
        Write-Host $singleCsv
    }
    else {
        Write-Host "Einzel-CSV: nicht gespeichert (-KeepPerAdvisoryCsv nicht gesetzt)"
    }
    Write-Host ""

    return $entriesForThisLsi
}

function Get-UniqueCves {
    param([array]$Rows)

    $cves = New-Object System.Collections.Generic.List[string]

    foreach ($row in $Rows) {
        if ($row.CVEs) {
            $cveMatches = [regex]::Matches($row.CVEs, "CVE-\d{4}-\d{4,7}")
            foreach ($m in $cveMatches) {
                $cves.Add($m.Value)
            }
        }
    }

    return @($cves | Sort-Object -Unique)
}

function Get-ImpactThemes {
    param([array]$Rows)

    $text = (($Rows | ForEach-Object { "$($_.KurzbeschreibungDE) $($_.ImpactOriginal) $($_.DescriptionOriginal)" }) -join " ").ToLowerInvariant()
    $themes = New-Object System.Collections.Generic.List[string]

    if ($text -match "schadcode|codeausführung|arbitrary code|execute arbitrary code") {
        $themes.Add("Schadcodeausführung")
    }
    if ($text -match "systemrechte|root|rechte|privileg|privilege|kernel privileges") {
        $themes.Add("Rechteausweitung")
    }
    if ($text -match "sandbox|gatekeeper|quarantäne|schutzmechanismus|security|same-origin|csp|pointer authentication") {
        $themes.Add("Umgehung von Schutzmechanismen")
    }
    if ($text -match "nutzerdaten|private information|sensitive|informationen|keychain|standort|location|dns|network traffic|mail") {
        $themes.Add("Informationsabfluss / Datenschutz")
    }
    if ($text -match "denial|absturz|crash|termination|speicherfehler|memory corruption") {
        $themes.Add("Absturz / Denial of Service")
    }
    if ($text -match "webkit|webinhalt|website|safari|cross-site") {
        $themes.Add("Web/Safari/WebKit")
    }
    if ($text -match "lokalen netzwerk|local network|network") {
        $themes.Add("Netzwerk")
    }

    return @($themes | Sort-Object -Unique)
}

function New-ShortConclusion {
    param(
        [string]$LsiRisiko,
        [string]$BetroffeneVersionen,
        [string]$BehobenDurch,
        [int]$SehrRelevant,
        [int]$Relevant,
        [int]$Mittel,
        [int]$Pruefen,
        [array]$Themes
    )

    $themeText = if ($Themes -and $Themes.Count -gt 0) {
        ($Themes -join ", ")
    }
    else {
        "mehrere unterschiedliche Schwachstellenarten"
    }

    $reviewText = if ($Pruefen -gt 0) {
        " $Pruefen Einträge müssen fachlich nachgeprüft werden."
    }
    else {
        ""
    }

    return "Die Meldung ist vom LSI als '$LsiRisiko' eingestuft und betrifft $BetroffeneVersionen. Behoben durch: $BehobenDurch. Enthalten sind $SehrRelevant sehr relevante, $Relevant relevante und $Mittel mittlere Schwachstelleneinträge. Schwerpunkte: $themeText.$reviewText"
}

function Export-ManagementReport {
    param(
        [array]$Rows
    )

    if (-not $Rows -or $Rows.Count -eq 0) {
        return $null
    }

    $reportRows = @()
    $groups = $Rows | Group-Object LsiId | Sort-Object Name

    foreach ($group in $groups) {
        $r = @($group.Group)
        $first = $r[0]

        $urls = @(
            $r |
                ForEach-Object { $_.AppleUrl -split "\s*\|\s*" } |
                Where-Object { $_ } |
                Sort-Object -Unique
        )
        $cves = Get-UniqueCves -Rows $r

        $sehrRelevant = @($r | Where-Object { $_.Qualitaet -eq "sehr relevant" }).Count
        $relevant = @($r | Where-Object { $_.Qualitaet -eq "relevant" }).Count
        $mittel = @($r | Where-Object { $_.Qualitaet -eq "mittel" }).Count
        $pruefen = @($r | Where-Object { $_.Qualitaet -eq "prüfen" }).Count

        $themes = Get-ImpactThemes -Rows $r

        $kritischeKurztexte = @(
            $r |
                Where-Object { $_.Qualitaet -eq "sehr relevant" } |
                Select-Object -ExpandProperty KurzbeschreibungDE -Unique |
                Select-Object -First 5
        )

        $reportRows += [pscustomobject]@{
            LsiId                  = $first.LsiId
            LsiTitel               = $first.LsiTitel
            LsiRisiko              = $first.LsiRisiko
            LsiInitialdatum        = $first.LsiInitialdatum
            LsiStand               = $first.LsiStand
            BetroffeneVersionen    = $first.BetroffeneVersionen
            BehobenDurch           = $first.BehobenDurch
            AppleUrlAnzahl         = $urls.Count
            AppleUrls              = ($urls -join " | ")
            CveAnzahl              = $cves.Count
            EintraegeGesamt        = $r.Count
            SehrRelevant           = $sehrRelevant
            Relevant               = $relevant
            Mittel                 = $mittel
            Pruefen                = $pruefen
            Schwerpunkte           = ($themes -join " | ")
            SehrRelevanteBeispiele = ($kritischeKurztexte -join " | ")
            Kurzfazit              = New-ShortConclusion -LsiRisiko $first.LsiRisiko -BetroffeneVersionen $first.BetroffeneVersionen -BehobenDurch $first.BehobenDurch -SehrRelevant $sehrRelevant -Relevant $relevant -Mittel $mittel -Pruefen $pruefen -Themes $themes
        }
    }

    $existingReportFile = $null
    if (-not $script:IsFirstRunForOutput) {
        $existingReportFile = Get-LatestExistingManagementReportCsv -Directory $outDir
    }

    if ($existingReportFile) {
        $reportCsv = $existingReportFile.FullName
    }
    else {
        $timestamp = Get-Date -Format "yyyy-MM-dd"
        $reportCsv = Join-Path $outDir "LSI-Apple-Managementreport_$timestamp.csv"
    }

    $reportRows |
        Export-Csv -Path $reportCsv -NoTypeInformation -Encoding UTF8 -Delimiter ";"

    return $reportCsv
}

# --------------------------------------------------------------------
# Hauptlauf — v5.2 inkrementelles Betriebsmodell
# --------------------------------------------------------------------

# 1) Vorhandene Gesamtauswertung suchen
$existingFile = $null
$existingRange = $null
$isFirstRun = $true

if (-not $ForceFullRun) {
    $existingFile = Get-LatestExistingGesamtCsv -Directory $outDir
    if ($existingFile) {
        $existingRange = Get-ExistingDateRange -CsvPath $existingFile.FullName
        if ($existingRange -and $existingRange.RowCount -gt 0) {
            $isFirstRun = $false
        }
    }
}

# 2) Effektive Parameter bestimmen
$effectiveDaysBack    = $DaysBack
$effectiveMaxAdvisories = $MaxAdvisories

if ($isFirstRun) {
    # Erstlauf-Deckel auf 100 anheben, wenn Parameter darunter liegt
    if ($effectiveMaxAdvisories -lt 100) {
        $effectiveMaxAdvisories = 100
    }
    Write-Host "Modus: ERSTLAUF (keine vorhandene Gesamtauswertung im Skript-Ordner)"
    Write-Host "Deckel angehoben auf: $effectiveMaxAdvisories"
}
else {
    Write-Host "Modus: FOLGELAUF"
    Write-Host "Vorhandene Datei : $($existingFile.Name)"
    Write-Host "Einträge bestand  : $($existingRange.RowCount)"
    Write-Host "Neuester LsiStand: $($existingRange.Newest.ToString('yyyy-MM-dd'))"

    # Datumsbasiertes Inkrement: ab neuestem LsiStand + Sicherheitspuffer
    $daysSinceNewest = [int]([Math]::Ceiling(([DateTime]::Now - $existingRange.Newest).TotalDays))
    $bufferDays = 7
    $autoDaysBack = $daysSinceNewest + $bufferDays

    if ($autoDaysBack -lt $effectiveDaysBack) {
        Write-Host "DaysBack reduziert auf inkrementelles Fenster: $autoDaysBack (war $effectiveDaysBack)"
        $effectiveDaysBack = $autoDaysBack
    }
    else {
        Write-Host "DaysBack bleibt: $effectiveDaysBack (Inkrementfenster $autoDaysBack größer)"
    }
}

# Merker für Exportfunktionen: Folgeläufe aktualisieren vorhandene Dateien.
$script:IsFirstRunForOutput = $isFirstRun

Write-Host ""

# 3) RELEVANT_VERSIONS dokumentieren
Write-Host "RELEVANT_VERSIONS: $($script:RELEVANT_VERSIONS -join ', ')"
Write-Host ""

# 4) WID-Abfrage starten
$candidates = Get-WidCandidateAdvisories `
    -DaysBack $effectiveDaysBack `
    -MaxAdvisories $effectiveMaxAdvisories `
    -OnlySubscribed $OnlySubscribed `
    -Classifications $Classifications `
    -TitleRegex $TitleRegex `
    -PageSize $PageSize

$timestamp = Get-Date -Format "yyyy-MM-dd"

if (-not $candidates -or $candidates.Count -eq 0) {
    Write-Host "Keine passenden WID-Advisories im abgefragten Fenster gefunden."
    if (-not $isFirstRun -and $existingRange) {
        Write-Host "Vorhandene Daten werden trotzdem auf RELEVANT_VERSIONS bereinigt..."
    }
    else {
        throw "Erstlauf: keine WID-Advisories gefunden und keine bestehende Datei. Abbruch."
    }
    $candidates = @()
}

if ($candidates.Count -gt 0) {
    Write-Host "Gefundene LSI-Meldungen:"
    $candidates | Select-Object LsiId, Published, Classification, Title | Format-Table -AutoSize
    Write-Host ""
}

# 5) LSI-Details verarbeiten
$newEntries = @()
$failed = @()

foreach ($candidate in $candidates) {
    Write-Host "============================================================"
    Write-Host "Verarbeite:"
    Write-Host "$($candidate.LsiId) - $($candidate.Title)"
    Write-Host "============================================================"

    try {
        $entries = Get-LsiAppleEntries -Candidate $candidate
        foreach ($entry in $entries) {
            $newEntries += $entry
        }
    }
    catch {
        $failed += [pscustomobject]@{
            LsiId = $candidate.LsiId
            Title = $candidate.Title
            Error = $_.Exception.Message
        }

        Write-Host "FEHLER bei $($candidate.LsiId)"
        Write-Host $_.Exception.Message
        Write-Host ""
        continue
    }
}

# 6) Mit Bestand mergen (im Folgelauf)
$allEntries = @()

if ($isFirstRun) {
    $allEntries = $newEntries
}
else {
    $existingRows = @($existingRange.Rows)
    Write-Host "Merge: $($existingRows.Count) bestehende + $($newEntries.Count) neue Einträge"
    $allEntries = Merge-WithExistingRows -ExistingRows $existingRows -NewRows $newEntries
    Write-Host "Nach Merge: $($allEntries.Count) Einträge"
    Write-Host ""
}

# 7) Bereinigung anhand RELEVANT_VERSIONS
$beforePrune = $allEntries.Count
$allEntries = @($allEntries | Where-Object {
    Test-IsRelevantEntry -BetroffeneVersionen $_.BetroffeneVersionen -BehobenDurch $_.BehobenDurch
})
$afterPrune = $allEntries.Count

if ($beforePrune -ne $afterPrune) {
    Write-Host "Bereinigung: $beforePrune → $afterPrune Einträge"
    Write-Host "Entfernt: $($beforePrune - $afterPrune) Einträge ohne Treffer in RELEVANT_VERSIONS"
    Write-Host ""
}

# 8) Ausgaben schreiben
if ($allEntries.Count -gt 0) {
    if (-not $isFirstRun -and $existingFile) {
        $gesamtCsv = $existingFile.FullName
    }
    else {
        $gesamtCsv = Join-Path $outDir "LSI-Apple-Gesamtauswertung_$timestamp.csv"
    }

    $allEntries |
        Select-Object $OutputColumns |
        Export-Csv -Path $gesamtCsv -NoTypeInformation -Encoding UTF8 -Delimiter ";"

    Write-Host ""
    Write-Host "Gesamt-CSV geschrieben:"
    Write-Host $gesamtCsv
    Write-Host ""

    Write-Host "Anzahl Einträge gesamt: $($allEntries.Count)"
    Write-Host ""

    Write-Host "Qualitätsverteilung gesamt:"
    $allEntries | Group-Object Qualitaet | Sort-Object Name | Format-Table Name, Count -AutoSize

    Write-Host ""
    Write-Host "LSI-Verteilung:"
    $allEntries | Group-Object LsiId | Sort-Object Name | Format-Table Name, Count -AutoSize

    Write-Host ""
    Write-Host "Prüffälle gesamt:"
    $prueffaelle = $allEntries | Where-Object { $_.Qualitaet -eq "prüfen" }
    if ($prueffaelle.Count -eq 0) {
        Write-Host "Keine"
    }
    else {
        $prueffaelle | Select-Object LsiId, AppleUrl, Komponente, ImpactOriginal, DescriptionOriginal, CVEs | Format-Table -AutoSize
    }

    $reportCsv = Export-ManagementReport -Rows $allEntries
    if ($reportCsv) {
        Write-Host ""
        Write-Host "Managementreport geschrieben:"
        Write-Host $reportCsv
    }
}
else {
    Write-Host "Keine Einträge nach Verarbeitung und Bereinigung übrig."
}

if ($failed.Count -gt 0) {
    Write-Host ""
    Write-Host "Fehlgeschlagene LSI-IDs:"
    $failed | Format-Table LsiId, Title, Error -AutoSize

    $failedCsv = Join-Path $outDir "LSI-Apple-Gesamtauswertung_Fehler_$timestamp.csv"
    $failed | Export-Csv -Path $failedCsv -NoTypeInformation -Encoding UTF8 -Delimiter ";"

    Write-Host ""
    Write-Host "Fehler-CSV geschrieben:"
    Write-Host $failedCsv
}

Write-Host ""
Write-Host "Fertig."
