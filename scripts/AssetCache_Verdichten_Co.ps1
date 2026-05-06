# AssetCache_Verdichten_Co.ps1
# Verdichtet AssetCache_Co_alle_Standorte.csv von 15-Minuten-Werten
# auf Stunden-Werte. Ergebnis: ca. 75 % weniger Zeilen, Verlauf bleibt erhalten.
#
# Aggregation pro Feld:
# - ServedDelta, OriginDelta: Summe (Delta-Werte addieren sich zum Stunden-Delta)
# - ClientsCnt (aktiv/gesamt): Maximum aktiv, gesamt unverändert
# - CachePr: Mittelwert
# - AppleTTFB, WiFiSNR: Mittelwert
# - DNSRes, AppleReach: Minimum (Ausfall in der Stunde sichtbar)
# - iOSUpdates, iOSBytes, CacheUsed: letzter Wert (kategorial / Bestand)
# - PeerCnt: Mittelwert
#
# Eingabe: AssetCache_Co_alle_Standorte.csv
# Ausgabe: AssetCache_Co_alle_Standorte_Stunden.csv

$input_file  = ".\AssetCache_Co_alle_Standorte.csv"
$output_file = ".\AssetCache_Co_alle_Standorte_Stunden.csv"

if (-not (Test-Path $input_file)) {
    Write-Host "Datei nicht gefunden: $input_file"
    exit 1
}

Write-Host "Lese: $input_file"
$data = Import-Csv -Path $input_file -Encoding UTF8

Write-Host "Verarbeite $($data.Count) Zeilen..."

# Hilfsfunktion: ClientsCnt "aktiv/gesamt" parsen
function Parse-ClientsCnt($value) {
    if ($value -match '^(\d+)/(\d+)$') {
        return @{ Aktiv = [int]$matches[1]; Gesamt = [int]$matches[2] }
    }
    return @{ Aktiv = 0; Gesamt = 0 }
}

# Hilfsfunktion: sicheres Konvertieren in Zahl (leerer String -> 0)
function ToNum($v) {
    if ([string]::IsNullOrWhiteSpace($v)) { return 0 }
    try { return [double]$v } catch { return 0 }
}

# Gruppierung: SiteCode + Stunde (yyyy-MM-ddTHH)
$grouped = $data | Group-Object -Property {
    $ts = [datetime]::Parse($_.Timestamp)
    "$($_.SiteCode)|$($ts.ToString('yyyy-MM-ddTHH'))"
}

Write-Host "Gruppen: $($grouped.Count) (Standort-Stunden-Kombinationen)"

$result = foreach ($group in $grouped) {
    $rows = $group.Group
    $first = $rows[0]
    $last  = $rows[-1]

    # ClientsCnt: Maximum aktiv, gesamt aus erstem Eintrag (konstant pro Standort)
    $maxAktiv = 0
    $gesamt   = 0
    foreach ($row in $rows) {
        $cc = Parse-ClientsCnt $row.ClientsCnt
        if ($cc.Aktiv -gt $maxAktiv) { $maxAktiv = $cc.Aktiv }
        if ($cc.Gesamt -gt 0) { $gesamt = $cc.Gesamt }
    }

    # Numerische Aggregationen
    $servedSum   = ($rows | ForEach-Object { ToNum $_.ServedDelta }   | Measure-Object -Sum).Sum
    $originSum   = ($rows | ForEach-Object { ToNum $_.OriginDelta }   | Measure-Object -Sum).Sum
    $cachePrAvg  = ($rows | ForEach-Object { ToNum $_.CachePr }       | Measure-Object -Average).Average
    $ttfbAvg     = ($rows | ForEach-Object { ToNum $_.AppleTTFB }     | Measure-Object -Average).Average
    $snrAvg      = ($rows | ForEach-Object { ToNum $_.WiFiSNR }       | Measure-Object -Average).Average
    $peerAvg     = ($rows | ForEach-Object { ToNum $_.PeerCnt }       | Measure-Object -Average).Average
    $dnsMin      = ($rows | ForEach-Object { ToNum $_.DNSRes }        | Measure-Object -Minimum).Minimum
    $reachMin    = ($rows | ForEach-Object { ToNum $_.AppleReach }    | Measure-Object -Minimum).Minimum

    [PSCustomObject]@{
        SiteCode    = $first.SiteCode
        Timestamp   = ([datetime]::Parse($first.Timestamp)).ToString('yyyy-MM-ddTHH:00:00')
        PeerCnt     = [math]::Round($peerAvg, 1)
        ClientsCnt  = "$maxAktiv/$gesamt"
        iOSUpdates  = $last.iOSUpdates
        iOSBytes    = $last.iOSBytes
        ServedDelta = [int64]$servedSum
        OriginDelta = [int64]$originSum
        CacheUsed   = $last.CacheUsed
        CachePr     = [math]::Round($cachePrAvg, 1)
        DNSRes      = [int]$dnsMin
        AppleReach  = [int]$reachMin
        AppleTTFB   = [int][math]::Round($ttfbAvg, 0)
        WiFiSNR     = [int][math]::Round($snrAvg, 0)
    }
}

# Sortieren nach Standort, dann Zeit
$result = $result | Sort-Object SiteCode, Timestamp

$result | Export-Csv -Path $output_file -NoTypeInformation -Encoding UTF8

Write-Host "Fertig: $output_file"
Write-Host "  Eingabe:  $($data.Count) Zeilen (15-Minuten-Werte)"
Write-Host "  Ausgabe:  $($result.Count) Zeilen (Stunden-Werte)"
Write-Host "  Reduktion: $([math]::Round((1 - $result.Count / $data.Count) * 100, 1)) %"