# Rebuild the project and launch VLC Redesign on the interactive desktop.
[CmdletBinding(PositionalBinding = $false)]
param(
    [string] $BuildDirectory,
    [string] $ToolchainDirectory = $(if ($env:VLC_QT_DIRECTORY) { $env:VLC_QT_DIRECTORY } else { 'C:\msys64\ucrt64' }),
    [switch] $RunTests,
    [switch] $Reconfigure,
    [switch] $WithoutMediaLibrary,
    [switch] $BuildOnly,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $VlcArguments = @()
)
$ErrorActionPreference = 'Stop'
if (-not $BuildDirectory) {
    $BuildDirectory = Join-Path $PSScriptRoot 'build-ucrt'
}

function ConvertTo-WindowsArgument([string] $Value) {
    $escaped = [regex]::Replace($Value, '(\\*)"', '$1$1\"')
    return '"' + [regex]::Replace($escaped, '(\\+)$', '$1$1') + '"'
}

$originalPath = $env:PATH
$originalQtDirectory = $env:VLC_QT_DIRECTORY
$originalBuildDirectory = $env:VLC_BUILD_DIRECTORY
$originalPrepareOnly = $env:VLC_LAUNCH_PREPARE_ONLY
try {
    $BuildDirectory = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($BuildDirectory)
    $ToolchainDirectory = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ToolchainDirectory)
    $toolchainBin = Join-Path $ToolchainDirectory 'bin'
    $msysBin = Join-Path (Split-Path $ToolchainDirectory -Parent) 'usr\bin'
    if (-not (Test-Path -LiteralPath $toolchainBin -PathType Container)) {
        throw "Toolchain not found: $toolchainBin. Set -ToolchainDirectory to your MSYS2 UCRT64 prefix."
    }
    $env:PATH = "$toolchainBin;$msysBin;$originalPath"
    $env:VLC_QT_DIRECTORY = $ToolchainDirectory
    $env:VLC_BUILD_DIRECTORY = $BuildDirectory
    foreach ($tool in @('meson.exe', 'ninja.exe', 'gcc.exe', 'pkg-config.exe')) {
        Get-Command $tool -ErrorAction Stop | Out-Null
    }

    # Windows cannot replace an executable or DLL while this build is running.
    # Match the complete executable path, never all VLC processes by name.
    $executable = Join-Path $BuildDirectory 'bin\vlc-redesign.exe'
    $players = @(Get-Process -Name 'vlc-redesign' -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -and [string]::Equals($_.Path, $executable, [StringComparison]::OrdinalIgnoreCase) })
    foreach ($player in $players) {
        Write-Host "Closing VLC Redesign from this build (PID $($player.Id))..."
        if (-not $player.HasExited) {
            $null = $player.CloseMainWindow()
            if (-not $player.WaitForExit(5000)) {
                # Closing VLC may only hide it in the tray. End this development
                # instance so its loaded DLLs can be rebuilt.
                Stop-Process -InputObject $player -ErrorAction Stop
                if (-not $player.WaitForExit(5000)) {
                    throw "VLC Redesign did not exit. Close it and try again."
                }
            }
        }
        $player.Dispose()
    }

    Write-Host 'Building VLC Redesign...'
    & (Join-Path $PSScriptRoot 'build-vlc.ps1') -BuildDirectory $BuildDirectory `
        -Incremental:(-not $Reconfigure) -WithoutMediaLibrary:$WithoutMediaLibrary -RunTests:$RunTests

    if ($BuildOnly) {
        Write-Host 'Build succeeded.'
        return
    }

    # Prepare the existing GUI bootstrapper, then start it without keeping this
    # console open for the player's lifetime. It targets winsta0\default.
    $env:VLC_LAUNCH_PREPARE_ONLY = '1'
    $bootstrap = & (Join-Path $PSScriptRoot 'launch-vlc.ps1')
    $env:VLC_LAUNCH_PREPARE_ONLY = $originalPrepareOnly
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $bootstrap
    $startInfo.WorkingDirectory = (Get-Location).ProviderPath
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.Arguments = (@($VlcArguments) | ForEach-Object { ConvertTo-WindowsArgument $_ }) -join ' '
    $launcher = [System.Diagnostics.Process]::Start($startInfo)
    try {
        if ($launcher.WaitForExit(1000) -and $launcher.ExitCode -ne 0) {
            throw "VLC Redesign launcher failed with exit code $($launcher.ExitCode)."
        }
    } finally {
        $launcher.Dispose()
    }
    Write-Host 'Build succeeded. VLC Redesign launched.'
} catch {
    Write-Error $_ -ErrorAction Continue
    exit 1
} finally {
    $env:PATH = $originalPath
    $env:VLC_QT_DIRECTORY = $originalQtDirectory
    $env:VLC_BUILD_DIRECTORY = $originalBuildDirectory
    $env:VLC_LAUNCH_PREPARE_ONLY = $originalPrepareOnly
}
