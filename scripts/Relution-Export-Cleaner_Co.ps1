# Relution-Export-Cleaner_Co.ps1
# Bereinigt den Relution-Export:
# - entfernt Spalte "name" (Gerätename / Schülername)
# - kürzt organizationName auf Standortkürzel (Inhalt der ersten Klammer)

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
