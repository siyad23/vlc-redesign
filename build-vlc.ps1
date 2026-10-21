# Build the native Windows development player with tests and text shaping.
param(
    [string] $BuildDirectory = (Join-Path $PSScriptRoot 'build-ucrt'),
    [switch] $WithoutMediaLibrary,
    [switch] $RunTests,
    [switch] $Incremental
)
$ErrorActionPreference = 'Stop'
$BuildDirectory = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($BuildDirectory)
$meson = (Get-Command meson.exe -ErrorAction Stop).Source
$originalPkgConfigPath = $env:PKG_CONFIG_PATH
$originalCcacheDirectory = $env:CCACHE_DIR
$originalQpaPlatform = $env:QT_QPA_PLATFORM
$env:CCACHE_DIR = Join-Path $BuildDirectory 'compiler-cache'
$localPkgConfig = Join-Path $BuildDirectory 'deps\install\lib\pkgconfig'
$env:PKG_CONFIG_PATH = (@($localPkgConfig, $originalPkgConfigPath) | Where-Object { $_ }) -join ';'
try {
    $configured = Test-Path -LiteralPath (Join-Path $BuildDirectory 'meson-private\coredata.dat')
    $needsSetup = -not $configured -or -not $Incremental -or $WithoutMediaLibrary
    if ($needsSetup -and -not $WithoutMediaLibrary) {
        & pkg-config.exe --exists 'medialibrary >= 0.13'
        if ($LASTEXITCODE -ne 0) {
            & (Join-Path $PSScriptRoot 'extras\package\win32\build-medialibrary.ps1') -BuildDirectory $BuildDirectory
        }
    }
    if ($needsSetup) {
        $setupArguments = @('setup')
        if ($configured) {
            $setupArguments += '--reconfigure'
        }
        $mediaLibrary = if ($WithoutMediaLibrary) { 'disabled' } else { 'enabled' }
        $setupArguments += @(
            $BuildDirectory, $PSScriptRoot,
            ('--pkg-config-path=' + ((@($localPkgConfig) + @($originalPkgConfigPath -split ';') | Where-Object { $_ }) -join ',')),
            '-Dqt=enabled', '-Dtests=enabled', '-Dnls=enabled', '-Dharfbuzz=enabled',
            "-Dmedialibrary=$mediaLibrary", '-Dbuildtype=debugoptimized',
            '-Dnsis=disabled', '-Dwix=disabled'
        )
        & $meson @setupArguments
        if ($LASTEXITCODE -ne 0) { throw 'Meson configuration failed.' }
    }
    & $meson compile -C $BuildDirectory
    if ($LASTEXITCODE -ne 0) { throw 'VLC build failed.' }
    if ($RunTests) {
        $env:QT_QPA_PLATFORM = 'offscreen'
        & $meson test -C $BuildDirectory --suite qt --print-errorlogs
        if ($LASTEXITCODE -ne 0) { throw 'Qt tests failed.' }
    }
} finally {
    $env:PKG_CONFIG_PATH = $originalPkgConfigPath
    $env:CCACHE_DIR = $originalCcacheDirectory
    $env:QT_QPA_PLATFORM = $originalQpaPlatform
}
