# Launch the development executable without changing the caller's environment.
# Optional overrides: VLC_BUILD_DIRECTORY and VLC_QT_DIRECTORY (Qt prefix).
$ErrorActionPreference = 'Stop'

$buildDirectory = if ($env:VLC_BUILD_DIRECTORY) {
    $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($env:VLC_BUILD_DIRECTORY)
} else {
    Join-Path $PSScriptRoot 'build-ucrt'
}
$executable = Join-Path $buildDirectory 'bin\vlc-redesign.exe'
if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) {
    throw "Development executable not found: $executable. Run .\build-vlc.ps1 first."
}

if ($env:VLC_QT_DIRECTORY) {
    $qtPaths = Join-Path $env:VLC_QT_DIRECTORY 'bin\qtpaths6.exe'
    if (-not (Test-Path -LiteralPath $qtPaths)) {
        $qtPaths = Join-Path $env:VLC_QT_DIRECTORY 'bin\qtpaths.exe'
    }
} else {
    $qtPathsCommand = Get-Command qtpaths6.exe, qtpaths.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $qtPathsCommand) {
        throw 'Put the Qt toolchain bin directory on PATH, or set VLC_QT_DIRECTORY to its prefix.'
    }
    $qtPaths = $qtPathsCommand.Source
}
if (-not (Test-Path -LiteralPath $qtPaths -PathType Leaf)) {
    throw "Qt path query tool not found: $qtPaths"
}

function Get-QtPath([string] $Name) {
    $result = & $qtPaths --query $Name
    if ($LASTEXITCODE -ne 0 -or -not $result -or -not (Test-Path -LiteralPath $result -PathType Container)) {
        throw "Cannot resolve Qt directory $Name using $qtPaths."
    }
    return $result
}

# ProcessStartInfo.Arguments is used for Windows PowerShell 5.1 compatibility.
# Quote each argument independently, including embedded quotes and trailing slashes.
function ConvertTo-WindowsArgument([string] $Value) {
    $escaped = [regex]::Replace($Value, '(\\*)"', '$1$1\"')
    return '"' + [regex]::Replace($escaped, '(\\+)$', '$1$1') + '"'
}

$bootstrapSource = Join-Path $PSScriptRoot 'extras\package\win32\launch-redesign.cs'
$bootstrap = Join-Path $buildDirectory 'bin\launch-vlc-redesign.exe'
if (-not (Test-Path -LiteralPath $bootstrap) -or
    (Get-Item -LiteralPath $bootstrapSource).LastWriteTimeUtc -gt (Get-Item -LiteralPath $bootstrap).LastWriteTimeUtc) {
    Add-Type -Path $bootstrapSource -OutputAssembly $bootstrap -OutputType WindowsApplication
}
[System.IO.File]::WriteAllLines((Join-Path $buildDirectory 'bin\launch-vlc-redesign.paths'), [string[]]@(
    $buildDirectory, $PSScriptRoot, (Get-QtPath 'QT_INSTALL_BINS'),
    (Get-QtPath 'QT_INSTALL_PLUGINS'), (Get-QtPath 'QT_INSTALL_QML')
), (New-Object System.Text.UTF8Encoding($false)))
if ($env:VLC_LAUNCH_PREPARE_ONLY -eq '1') {
    Write-Output $bootstrap
    return
}

$startInfo = New-Object System.Diagnostics.ProcessStartInfo
$startInfo.FileName = $bootstrap
$startInfo.WorkingDirectory = (Get-Location).ProviderPath
$startInfo.UseShellExecute = $false
$startInfo.Arguments = (@($args) | ForEach-Object { ConvertTo-WindowsArgument $_ }) -join ' '

$process = [System.Diagnostics.Process]::Start($startInfo)
try {
    $process.WaitForExit()
    exit $process.ExitCode
} finally {
    $process.Dispose()
}
