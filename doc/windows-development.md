# Native Windows development

Use a consistent MSYS2 UCRT64 toolchain with GCC, Meson, Ninja, pkg-config,
Qt 6 (including Quick Controls, Quick Test and Shader Tools), gettext,
FreeType, HarfBuzz, and the multimedia libraries needed by your build.
Put that toolchain's `bin` directory first on `PATH`, followed by the MSYS2
`usr/bin` directory for gettext tools, flex, and bison. Avoid mixing compilers
from another MinGW installation.

From the repository root in PowerShell:

```powershell
.\rebuild-and-run.bat
```

This command finds the UCRT64 toolchain at `C:\msys64\ucrt64` (or
`VLC_QT_DIRECTORY`), closes any running VLC Redesign instance from this build,
rebuilds changed files, and launches the player after success. Installed VLC
can stay open. The console closes after launch; build failures stay visible.

The PowerShell script also accepts `-RunTests`, `-Reconfigure`, `-BuildOnly`,
`-WithoutMediaLibrary`, `-BuildDirectory`, and `-ToolchainDirectory`. Existing
Meson options are preserved unless you request reconfiguration. For example:

```powershell
.\rebuild-and-run.bat -RunTests
.\rebuild-and-run.bat "E:\Videos\a clip.mp4"
```

To configure the build explicitly and launch separately:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build-vlc.ps1 -RunTests
.\run-vlc.bat
```

The build enables the Qt interface, tests, translations, text shaping, and
media-library indexing. If the media-library dependency is missing, the script
downloads the version pinned in `contrib/src/medialibrary/rules.mak`, verifies
its SHA-512 checksum, and builds it under `build-ucrt/deps`. Nothing is installed
globally. Use `-WithoutMediaLibrary` for an intentionally smaller player;
onboarding then reports that indexing is unavailable.

`-RunTests` runs the Qt test suite. Build output and Meson test logs are under
`build-ucrt`. Other optional features, including Rust, Lua, and installer
generation, are independent of the redesign and follow Meson's configuration.

To check onboarding, minimal mode, pinned controls, and media-library startup
without a visible window or personal settings, run:

```powershell
python extras/package/win32/smoke-test-redesign.py --qt-prefix $env:VLC_QT_DIRECTORY
```

Set `VLC_QT_DIRECTORY` to your Qt/toolchain prefix for this command. The check
uses silent generated media and stores logs and test profiles under
`build-ucrt/redesign-smoke`.

The launcher discovers Qt with `qtpaths6.exe` or `qtpaths.exe`. Set
`VLC_QT_DIRECTORY` to the toolchain prefix if Qt is not on `PATH`. For another
build directory, pass `-BuildDirectory` to the build script and set
`VLC_BUILD_DIRECTORY` before launching. Media paths and other VLC arguments
are forwarded individually, including paths containing spaces.
The execution-policy option applies only to the child PowerShell process;
it does not change the machine's execution policy.

The launcher uses `vlc-redesign.exe`, displayed as **VLC Redesign**, with its own
Windows taskbar identity and settings under `build-ucrt/redesign-profile`.
Single-instance forwarding is disabled so it can run alongside installed VLC.
The script builds a small GUI bootstrapper, `bin/launch-vlc-redesign.exe`,
which explicitly opens VLC on the interactive `winsta0\default` desktop.
Its runtime paths are stored beside it in `launch-vlc-redesign.paths`.
The development executables accept `VLC_DEVELOPMENT_DLL_DIRECTORY`, registering that absolute
dependency directory with Windows. Runtime DLL loading excludes the current
directory and `PATH`; the installed executable retains its System32 policy.
`VLC_LOCALE_PATH` points at the build's generated gettext catalogs. The launcher
does not force onboarding to reappear or change the caller's environment.
