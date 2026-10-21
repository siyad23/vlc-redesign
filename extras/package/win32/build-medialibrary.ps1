param([Parameter(Mandatory = $true)][string] $BuildDirectory)
$ErrorActionPreference = 'Stop'
$sourceRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$rules = Get-Content -LiteralPath (Join-Path $sourceRoot 'contrib\src\medialibrary\rules.mak') -Raw
$version = [regex]::Match($rules, 'MEDIALIBRARY_VERSION\s*:=\s*(\S+)').Groups[1].Value
if (-not $version) { throw 'Cannot read the pinned media-library version.' }
$archiveName = "medialibrary-$version.tar.bz2"
$dependencyDirectory = Join-Path $BuildDirectory 'deps'
$prefix = Join-Path $dependencyDirectory 'install'
$archive = Join-Path $dependencyDirectory $archiveName
New-Item -ItemType Directory -Force -Path $dependencyDirectory | Out-Null
if (-not (Test-Path -LiteralPath $archive)) {
    Invoke-WebRequest -UseBasicParsing -Uri "https://code.videolan.org/videolan/medialibrary/-/archive/$version/$archiveName" -OutFile $archive
}
$checksums = Get-Content -LiteralPath (Join-Path $sourceRoot 'contrib\src\medialibrary\SHA512SUMS')
$checksumLine = $checksums | Where-Object { $_ -match ('\s' + [regex]::Escape($archiveName) + '$') }
$expectedHash = ($checksumLine -split '\s+')[0]
if (-not $expectedHash -or (Get-FileHash -LiteralPath $archive -Algorithm SHA512).Hash -ne $expectedHash) {
    throw "Checksum verification failed: $archive"
}
$source = Join-Path $dependencyDirectory "medialibrary-$version"
if (-not (Test-Path -LiteralPath $source)) {
    & tar.exe -xf $archive -C $dependencyDirectory
    if ($LASTEXITCODE -ne 0) { throw 'Media-library extraction failed.' }
}
$dependencyBuild = Join-Path $dependencyDirectory 'medialibrary-build'
$setup = @('setup')
if (Test-Path -LiteralPath (Join-Path $dependencyBuild 'meson-private\coredata.dat')) {
    $setup += '--reconfigure'
}
& meson.exe @setup $dependencyBuild $source --prefix $prefix --libdir lib -Dlibvlc=disabled -Dtests=disabled -Ddefault_library=static
if ($LASTEXITCODE -ne 0) { throw 'Media-library configuration failed.' }
& meson.exe compile -C $dependencyBuild
if ($LASTEXITCODE -ne 0) { throw 'Media-library build failed.' }
& meson.exe install -C $dependencyBuild --no-rebuild
if ($LASTEXITCODE -ne 0) { throw 'Media-library installation failed.' }
