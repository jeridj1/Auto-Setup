[CmdletBinding()]
param(
    [string]$Repository = "jeridj1/Auto-Setup",
    [string]$Directory = (Join-Path (Get-Location).Path "NOMAD-E93z-Installer"),
    [bool]$IncludePrereleases = $true,
    [string]$ApiUrl = ""
)

$ErrorActionPreference = "Stop"
$BaseName = "NOMAD-Debian13.7-E93z.iso"
[System.IO.Directory]::CreateDirectory($Directory) | Out-Null
$Directory = [System.IO.Path]::GetFullPath($Directory)

$Handler = [System.Net.Http.HttpClientHandler]::new()
$Client = [System.Net.Http.HttpClient]::new($Handler)
$Client.Timeout = [System.Threading.Timeout]::InfiniteTimeSpan
$Client.DefaultRequestHeaders.UserAgent.ParseAdd("NOMAD-Release-Downloader/1.0")
$Client.DefaultRequestHeaders.Accept.ParseAdd("application/vnd.github+json")

function Get-ReleaseAsset([string]$Name) {
    $Asset = $Release.assets | Where-Object { $_.name -eq $Name } | Select-Object -First 1
    if (-not $Asset) { throw "Release is missing required asset: $Name" }
    return $Asset
}

function Get-ResumableAsset($Asset) {
    $Path = Join-Path $Directory $Asset.name
    $Expected = [int64]$Asset.size
    if ((Test-Path -LiteralPath $Path) -and ((Get-Item -LiteralPath $Path).Length -eq $Expected)) {
        Write-Host ("Already complete: {0} ({1:N0} bytes)" -f $Asset.name, $Expected)
        return $Path
    }
    if ((Test-Path -LiteralPath $Path) -and ((Get-Item -LiteralPath $Path).Length -gt $Expected)) {
        Remove-Item -LiteralPath $Path -Force
    }

    for ($Attempt = 1; $Attempt -le 20; $Attempt++) {
        $Current = if (Test-Path -LiteralPath $Path) { (Get-Item -LiteralPath $Path).Length } else { [int64]0 }
        if ($Current -eq $Expected) { return $Path }
        if ($Current -gt $Expected) {
            Remove-Item -LiteralPath $Path -Force
            $Current = 0
        }

        $Request = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Get, [string]$Asset.browser_download_url)
        if ($Current -gt 0) {
            $Request.Headers.Range = [System.Net.Http.Headers.RangeHeaderValue]::new($Current, $null)
        }

        $Response = $null
        $InputStream = $null
        $OutputStream = $null
        try {
            Write-Host ("Download {0}: resuming at {1:N0} of {2:N0} bytes (attempt {3}/20)" -f $Asset.name, $Current, $Expected, $Attempt)
            $Response = $Client.SendAsync($Request, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()

            if ($Response.StatusCode -eq [System.Net.HttpStatusCode]::RequestedRangeNotSatisfiable) {
                if ((Test-Path -LiteralPath $Path) -and ((Get-Item -LiteralPath $Path).Length -eq $Expected)) {
                    return $Path
                }
                throw "Server rejected the resume offset for $($Asset.name)."
            }
            $Response.EnsureSuccessStatusCode()

            $Append = $false
            if ($Response.StatusCode -eq [System.Net.HttpStatusCode]::PartialContent) {
                if ($Current -gt 0 -and $Response.Content.Headers.ContentRange.From -ne $Current) {
                    throw "Server returned an unexpected byte range for $($Asset.name)."
                }
                $Append = $Current -gt 0
            }
            elseif ($Response.StatusCode -eq [System.Net.HttpStatusCode]::OK) {
                # Server ignored the Range header. Safely restart this one asset.
                $Current = 0
                $Append = $false
            }
            else {
                throw "Unexpected HTTP response $([int]$Response.StatusCode) for $($Asset.name)."
            }

            $InputStream = $Response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
            if ($Append) {
                $OutputStream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
            }
            else {
                $OutputStream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
            }

            $Buffer = New-Object byte[] (4MB)
            $LastReport = [int64]$Current
            while (($Read = $InputStream.Read($Buffer, 0, $Buffer.Length)) -gt 0) {
                $OutputStream.Write($Buffer, 0, $Read)
                $Current += $Read
                if (($Current - $LastReport) -ge 33554432 -or $Current -eq $Expected) {
                    $Percent = if ($Expected -gt 0) { [math]::Min(100, [math]::Round(100 * $Current / $Expected, 1)) } else { 100 }
                    Write-Progress -Activity "Downloading N.O.M.A.D." -Status ("{0}: {1:N0}/{2:N0} bytes" -f $Asset.name, $Current, $Expected) -PercentComplete $Percent
                    $LastReport = $Current
                }
            }
            $OutputStream.Flush($true)
            $OutputStream.Dispose(); $OutputStream = $null
            $InputStream.Dispose(); $InputStream = $null
            $Response.Dispose(); $Response = $null
            $Request.Dispose()

            $Actual = if (Test-Path -LiteralPath $Path) { (Get-Item -LiteralPath $Path).Length } else { [int64]0 }
            if ($Actual -eq $Expected) {
                Write-Progress -Activity "Downloading N.O.M.A.D." -Completed
                Write-Host ("Complete: {0}" -f $Asset.name)
                return $Path
            }
            throw "Downloaded $Actual bytes, expected $Expected for $($Asset.name)."
        }
        catch {
            if ($OutputStream) { $OutputStream.Dispose() }
            if ($InputStream) { $InputStream.Dispose() }
            if ($Response) { $Response.Dispose() }
            $Request.Dispose()
            if ($Attempt -eq 20) { throw }
            Write-Warning ("Download interrupted: {0}. Partial data is retained for resume." -f $_.Exception.Message)
            Start-Sleep -Seconds ([Math]::Min(60, 5 * $Attempt))
        }
    }
}

try {
    Write-Host "Finding the latest N.O.M.A.D. E93z release..."
    $ApiUrl = if ([string]::IsNullOrWhiteSpace($ApiUrl)) { "https://api.github.com/repos/$Repository/releases?per_page=30" } else { $ApiUrl }
    $ApiResponse = $Client.GetAsync($ApiUrl).GetAwaiter().GetResult()
    $ApiResponse.EnsureSuccessStatusCode()
    $Releases = $ApiResponse.Content.ReadAsStringAsync().GetAwaiter().GetResult() | ConvertFrom-Json
    $ApiResponse.Dispose()

    $Candidates = @($Releases | Where-Object {
        $_.tag_name -like "nomad-e93z-*" -and -not $_.draft -and ($IncludePrereleases -or -not $_.prerelease)
    } | Sort-Object created_at -Descending)
    if ($Candidates.Count -eq 0) {
        throw "No published N.O.M.A.D. E93z release was found for $Repository."
    }
    $Release = $Candidates[0]
    Write-Host ("Selected release: {0}" -f $Release.tag_name)
    if ($Release.prerelease) {
        Write-Warning "This is a test candidate. It has automated tests but has not completed a physical installation test on the E93z."
    }

    $PartAssets = @($Release.assets | Where-Object { $_.name -match '^NOMAD-Debian13\.7-E93z\.iso\.part\d{2}$' } | Sort-Object name)
    if ($PartAssets.Count -lt 2) { throw "Release has an incomplete ISO segment set." }
    $ExpectedNames = for ($i=0; $i -lt $PartAssets.Count; $i++) { "{0}.part{1:D2}" -f $BaseName, $i }
    for ($i=0; $i -lt $PartAssets.Count; $i++) {
        if ($PartAssets[$i].name -ne $ExpectedNames[$i]) {
            throw "Release segment sequence is incomplete. Expected $($ExpectedNames[$i])."
        }
    }

    foreach ($Asset in $PartAssets) { Get-ResumableAsset $Asset | Out-Null }
    Get-ResumableAsset (Get-ReleaseAsset "$BaseName.sha512") | Out-Null
    Get-ResumableAsset (Get-ReleaseAsset "reassemble-nomad-iso.ps1") | Out-Null
    if ($Release.assets.name -contains "MANIFEST.txt") {
        Get-ResumableAsset (Get-ReleaseAsset "MANIFEST.txt") | Out-Null
    }

    Write-Host ""
    Write-Host "All release segments are present. Reassembling and verifying SHA-512..."
    $Reassembler = Join-Path $Directory "reassemble-nomad-iso.ps1"
    $OutputIso = Join-Path $Directory $BaseName
    try {
        & $Reassembler -Directory $Directory -OutputPath $OutputIso
        if (-not (Test-Path -LiteralPath $OutputIso)) { throw "Reassembler did not produce the ISO." }
    }
    catch {
        $Reason = $_.Exception.Message
        # A same-length corrupt segment would otherwise be trusted on every retry.
        # Discard all segments on a final SHA-512 failure so the next run fetches clean copies.
        foreach ($PartAsset in $PartAssets) {
            $PartPath = Join-Path $Directory $PartAsset.name
            if (Test-Path -LiteralPath $PartPath) {
                Remove-Item -LiteralPath $PartPath -Force
            }
        }
        $PartialIso = "$OutputIso.partial"
        if (Test-Path -LiteralPath $PartialIso) {
            Remove-Item -LiteralPath $PartialIso -Force
        }
        throw "ISO assembly or SHA-512 verification failed. The downloaded ISO segments have been discarded; run the downloader again to fetch clean copies. Original error: $Reason"
    }

    Write-Host ""
    Write-Host "N.O.M.A.D. installer is ready:"
    Write-Host $OutputIso
    Write-Host "Use Rufus or another image writer to write this ISO to a USB drive. That operation erases the selected USB drive."
}
finally {
    $Client.Dispose()
    $Handler.Dispose()
}
