param(
    [Parameter(Mandatory=$true)]
    [string]$ClientRoot,

    [string]$OutputCsv = ".\00_Source_Inventory\client_inventory.csv"
)

$ErrorActionPreference = "Stop"

$resolvedRoot = (Resolve-Path -LiteralPath $ClientRoot).Path
$outDir = Split-Path -Parent $OutputCsv
if ($outDir -and -not (Test-Path -LiteralPath $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}

$rootPrefix = $resolvedRoot.TrimEnd('\') + '\'

$results = Get-ChildItem -LiteralPath $resolvedRoot -File -Recurse -Force |
    ForEach-Object {
        $file = $_
        $relative = $file.FullName
        if ($relative.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            $relative = $relative.Substring($rootPrefix.Length)
        }

        $hash = $null
        try {
            $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
        } catch {
            $hash = "HASH_ERROR: $($_.Exception.Message)"
        }

        [PSCustomObject]@{
            RelativePath     = $relative
            Extension        = $file.Extension.ToLowerInvariant()
            SizeBytes        = $file.Length
            LastWriteTimeUtc = $file.LastWriteTimeUtc.ToString("o")
            SHA256           = $hash
        }
    }

$results |
    Sort-Object RelativePath |
    Export-Csv -LiteralPath $OutputCsv -NoTypeInformation -Encoding UTF8

Write-Host "Inventory complete."
Write-Host "Client root: $resolvedRoot"
Write-Host "Files inventoried: $($results.Count)"
Write-Host "CSV: $((Resolve-Path -LiteralPath $OutputCsv).Path)"
