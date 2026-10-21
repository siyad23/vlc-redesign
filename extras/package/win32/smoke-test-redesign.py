#!/usr/bin/env python3
"""Exercise the real Qt interface offscreen with isolated VLC preferences."""
import argparse
import os
from pathlib import Path
import re
import subprocess
import wave


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build-directory", type=Path, default=Path("build-ucrt"))
    parser.add_argument("--qt-prefix", type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[3]
    build = args.build_directory.resolve()
    qt = args.qt_prefix.resolve()
    output = build / "redesign-smoke"
    output.mkdir(exist_ok=True)
    media = output / "silence with spaces.wav"
    with wave.open(str(media), "wb") as wav:
        wav.setparams((1, 2, 8000, 0, "NONE", "not compressed"))
        wav.writeframes(bytes(8000 * 2 * 4))

    environment = dict(os.environ)
    environment.update({
        "PATH": os.pathsep.join(map(str, (build / "src", build / "lib", qt / "bin")))
                + os.pathsep + os.environ.get("PATH", ""),
        "VLC_DEVELOPMENT_DLL_DIRECTORY": str(qt / "bin"),
        "VLC_PLUGIN_PATH": str(build / "modules"),
        "VLC_LIBEXEC_PATH": str(build / "bin"),
        "VLC_DATA_PATH": str(root / "share"),
        "VLC_LOCALE_PATH": str(build / "po"),
        "QT_QPA_PLATFORM": "offscreen",
        "QT_QUICK_BACKEND": "software",
    })
    # Query Qt rather than relying on one vendor's directory layout.
    qtpaths = next(p for p in (qt / "bin/qtpaths6.exe", qt / "bin/qtpaths.exe") if p.is_file())
    for variable, query in (("QT_PLUGIN_PATH", "QT_INSTALL_PLUGINS"),
                            ("QML2_IMPORT_PATH", "QT_INSTALL_QML")):
        environment[variable] = subprocess.check_output(
            [str(qtpaths), "--query", query], text=True).strip()

    variants = {
        "onboarding": ["--qt-privacy-ask", "--no-media-library"],
        "minimal": ["--no-qt-privacy-ask", "--qt-minimal-view", "--no-media-library"],
        "pinned": ["--no-qt-privacy-ask", "--qt-pin-controls", "--no-media-library"],
        "media-library": ["--no-qt-privacy-ask", "--media-library"],
    }
    qml_errors = re.compile(
        r"ReferenceError|TypeError|Required property .*not initialized|"
        r"Cannot assign|Unable to assign|is not a type|failed to load component",
        re.IGNORECASE)
    for name, options in variants.items():
        profile = output / name
        profile.mkdir(exist_ok=True)
        child_environment = dict(environment, VLC_CONFIG_PATH=str(profile),
                                 VLC_CACHE_PATH=str(profile), VLC_USERDATA_PATH=str(profile))
        command = [str(build / "bin/vlc-redesign.exe"), "-I", "qt", "-vv",
                   "--ignore-config", "--no-one-instance", "--no-plugins-cache",
                   "--no-metadata-network-access", "--qt-compositor=dummy",
                   "--aout=dummy", "--vout=dummy", "--play-and-exit",
                   *options, str(media)]
        with (profile / "stdout.log").open("wb") as stdout, (profile / "stderr.log").open("wb") as stderr:
            completed = subprocess.run(command, cwd=root, env=child_environment,
                                       stdout=stdout, stderr=stderr, timeout=45)
        log = (profile / "stderr.log").read_text(encoding="utf-8", errors="replace")
        errors = [line for line in log.splitlines() if qml_errors.search(line)]
        if completed.returncode or errors or 'using interface module "qt"' not in log:
            raise RuntimeError(f"{name}: exit={completed.returncode}; QML errors={errors}; see {profile}")
        if name == "media-library" and 'using medialibrary module "medialibrary"' not in log:
            raise RuntimeError(f"Media-library backend did not initialize; see {profile}")
        print(f"PASS {name}")


if __name__ == "__main__":
    main()
