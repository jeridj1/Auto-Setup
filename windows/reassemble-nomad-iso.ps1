[CmdletBinding()]
param(
    [string]$Directory = (Get-Location).Path,
    [string]$OutputPath = (Join-Path (Get-Location).Path "NOMAD-Debian13.7-E93z.iso")
)

$ErrorActionPreference = "Stop"
$BaseName = "NOMAD-Debian13.7-E93z.iso"
$Pattern = "$BaseName.part*"
$Parts = @(Get-ChildItem -LiteralPath $Directory -File -Filter $Pattern | Sort-Object Name)

if ($Parts.Count -lt 2) {
    throw "Expected at least two files named $BaseName.part00, .part01, etc. Put every release part in one folder."
}

for ($i = 0; $i -lt $Parts.Count; $i++) {
    $Expected = "{0}.part{1:D2}" -f $BaseName, $i
    if ($Parts[$i].Name -ne $Expected) {
        throw "Missing or out-of-order ISO segment. Expected $Expected but found $($Parts[$i].Name)."
    }
}

$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
$OutputDirectory = [System.IO.Path]::GetDirectoryName($OutputPath)
[System.IO.Directory]::CreateDirectory($OutputDirectory) | Out-Null
$TempPath = "$OutputPath.partial"

if (Test-Path -LiteralPath $TempPath) {
    Remove-Item -LiteralPath $TempPath -Force
}

$Output = $null
try {
    $Output = [System.IO.File]::Open($TempPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    foreach ($Part in $Parts) {
        Write-Host ("Appending {0} ({1:N0} bytes)" -f $Part.Name, $Part.Length)
        $SourceStream = [System.IO.File]::OpenRead($Part.FullName)
        try {
            $SourceStream.CopyTo($Output, 4MB)
        }
        finally {
            $SourceStream.Dispose()
        }
    }
    $Output.Flush($true)
}
catch {
    if ($Output) { $Output.Dispose() }
    if (Test-Path -LiteralPath $TempPath) { Remove-Item -LiteralPath $TempPath -Force }
    throw
}
finally {
    if ($Output) { $Output.Dispose() }
}

$ChecksumPath = Join-Path $Directory "$BaseName.sha512"
if (-not (Test-Path -LiteralPath $ChecksumPath)) {
    Remove-Item -LiteralPath $TempPath -Force
    throw "Checksum file is missing: $ChecksumPath"
}
$ExpectedHash = ((Get-Content -LiteralPath $ChecksumPath -TotalCount 1).Trim() -split '\s+')[0].ToLowerInvariant()
if ($ExpectedHash -notmatch '^[0-9a-f]{128}$') {
    Remove-Item -LiteralPath $TempPath -Force
    throw "Checksum file does not contain a valid SHA-512 hash."
}

Write-Host "Verifying assembled ISO with SHA-512..."
$ActualHash = (Get-FileHash -LiteralPath $TempPath -Algorithm SHA512).Hash.ToLowerInvariant()
if ($ActualHash -ne $ExpectedHash) {
    Remove-Item -LiteralPath $TempPath -Force
    throw "SHA-512 mismatch. The ISO parts are incomplete, corrupted, or mixed between releases."
}

if (Test-Path -LiteralPath $OutputPath) {
    Remove-Item -LiteralPath $OutputPath -Force
}
Move-Item -LiteralPath $TempPath -Destination $OutputPath
Write-Host ""
Write-Host "N.O.M.A.D. ISO successfully reassembled and verified:"
Write-Host $OutputPath
Write-Host ("Size: {0:N0} bytes" -f (Get-Item -LiteralPath $OutputPath).Length)
Write-Host "SHA-512: $ActualHash"
