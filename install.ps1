$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Repo = if ($env:HEXEL_REPO) { $env:HEXEL_REPO } else { "Zokker1/hexel-releases" }
$Version = if ($env:HEXEL_VERSION) { $env:HEXEL_VERSION } else { "latest" }
$InstallDir = if ($env:HEXEL_INSTALL_DIR) { $env:HEXEL_INSTALL_DIR } else { Join-Path $env:USERPROFILE ".local\bin" }

if ([Environment]::Is64BitOperatingSystem -eq $false) {
    throw "Hexel currently requires 64-bit Windows."
}

$Asset = "hexel-windows-x64.zip"
if ($Version -eq "latest") {
    $BaseUrl = "https://github.com/$Repo/releases/latest/download"
} else {
    $BaseUrl = "https://github.com/$Repo/releases/download/$Version"
}

$TmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("hexel-install-" + [System.Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $TmpDir -Force | Out-Null

try {
    $ZipPath = Join-Path $TmpDir $Asset
    $SumsPath = Join-Path $TmpDir "SHA256SUMS.txt"

    Write-Host "Downloading $Asset from $Repo ($Version)..."
    Invoke-WebRequest -Uri "$BaseUrl/$Asset" -OutFile $ZipPath -UseBasicParsing

    try {
        Invoke-WebRequest -Uri "$BaseUrl/SHA256SUMS.txt" -OutFile $SumsPath -UseBasicParsing
        $SumsLines = Get-Content -Path $SumsPath
        $ExpectedHash = $null
        foreach ($line in $SumsLines) {
            if ($line -match '^\s*([0-9a-fA-F]{64})\s+\*?(.+?)\s*$') {
                if ($Matches[2] -eq $Asset) {
                    $ExpectedHash = $Matches[1].ToLowerInvariant()
                    break
                }
            }
        }
        if ($ExpectedHash) {
            $ActualHash = (Get-FileHash -Path $ZipPath -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($ActualHash -ne $ExpectedHash) {
                throw "Checksum mismatch for ${Asset}: expected $ExpectedHash, got $ActualHash"
            }
        }
    } catch {
        if ($_.Exception.Message -like "Checksum mismatch*") {
            throw
        }
    }

    $ExtractDir = Join-Path $TmpDir "extract"
    Expand-Archive -Path $ZipPath -DestinationPath $ExtractDir -Force

    $BuiltExe = Join-Path $ExtractDir "hexel.exe"
    if (-not (Test-Path $BuiltExe)) {
        throw "Extracted archive did not contain hexel.exe"
    }

    if (-not (Test-Path $InstallDir)) {
        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    }

    $TargetExe = Join-Path $InstallDir "hexel.exe"
    Copy-Item -Path $BuiltExe -Destination $TargetExe -Force
    Unblock-File -Path $TargetExe -ErrorAction SilentlyContinue
    Write-Host "Installed: $TargetExe"

    $UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $Entries = @()
    if ($UserPath) {
        $Entries = $UserPath -split ';' | Where-Object { $_.Trim() -ne "" }
    }
    $NormInstall = $InstallDir.TrimEnd('\')
    $AlreadyInUserPath = $Entries | Where-Object { $_.TrimEnd('\').Equals($NormInstall, [StringComparison]::OrdinalIgnoreCase) }

    if (-not $AlreadyInUserPath) {
        $NewUserPath = (@($Entries) + $InstallDir) -join ';'
        [Environment]::SetEnvironmentVariable("Path", $NewUserPath, "User")
        Write-Host "Added $InstallDir to User PATH. Open a new terminal window if 'hexel' is not found in other shells."
    } else {
        Write-Host "$InstallDir is already on User PATH."
    }

    $SessionEntries = ($env:Path -split ';') | Where-Object { $_.Trim() -ne "" }
    $InCurrentSession = $SessionEntries | Where-Object { $_.TrimEnd('\').Equals($NormInstall, [StringComparison]::OrdinalIgnoreCase) }
    if (-not $InCurrentSession) {
        $env:Path = "$InstallDir;$env:Path"
    }

    & $TargetExe --version
    Write-Host "Done. Run 'hexel' from any project folder to start."
} finally {
    Remove-Item -Path $TmpDir -Recurse -Force -ErrorAction SilentlyContinue
}
