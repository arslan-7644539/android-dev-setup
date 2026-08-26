# Android Dev Setup

Unattended Android SDK installer for Windows — clean, fresh `C:\Android` setup with Java, command line tools, platform, build tools, NDK, and CMake.

## Zip name

`android-dev-setup.zip`

## Install

1. Put the required vendor packages in the `packages` folder:
   - `Java17-Setup.exe`
   - `commandlinetools-win.zip`
2. Keep `tools\Clean-AndroidEnv.ps1` and `lib\Console.ps1` next to `Install.ps1` and `INSTALL.bat` (folder layout must stay intact).
3. Right-click `INSTALL.bat`.
4. Select **Run as administrator**.
5. The installer clearly explains what it will change.
6. Press `Y` to start or `N` to cancel.
7. From there it runs fully unattended (silent Java install, command line tools setup, package installation, env vars).

## Flags

`INSTALL.bat` forwards any arguments straight to `Install.ps1`. Run these from an elevated (Administrator) terminal in this folder:

| Flag | Effect |
|---|---|
| `INSTALL.bat -DryRun` | Preview every step (Java, cleanup, package install, env vars) without deleting, installing, or changing anything on the system. |
| `INSTALL.bat -Check` | Skip setup entirely and just report whether Java + the Android components already match `config.json`. |
| `INSTALL.bat -Yes` | Skip the Y/N confirmation prompt (for unattended/CI runs). |
| `INSTALL.bat -Config path\to\other-config.json` | Use a different config file instead of the default `config.json`. |
| `INSTALL.bat -NoColor` | Plain text output, no ANSI colors (useful when piping output). |

Flags can be combined, e.g. `INSTALL.bat -DryRun -NoColor`

## Versions (`config.json`)

Component versions are no longer hardcoded in the script. Edit `config.json` in this folder to change them:

| Key | Meaning | Default |
|---|---|---|
| `installRoot` | Where the SDK is installed | `C:\Android` |
| `androidPlatform` | Android platform level | `36` |
| `buildTools` | Build Tools version | `36.0.0` |
| `ndk` | NDK version | `27.1.12297006` |
| `cmake` | CMake version | `3.22.1` |

## Logs

Every run (including `-DryRun` and `-Check`) writes a plain-text transcript to `logs\install-<timestamp>.log` for troubleshooting.

## Clean + fresh behavior

The installer removes/resets the Android setup it owns:

- The configured `installRoot` (default `C:\Android`)
- `ANDROID_HOME` / `ANDROID_SDK_ROOT` (both User and Machine scope)
- Any old SDK folder those variables pointed to (e.g. a previous Android Studio SDK install, or a wrong/leftover setup), via `tools\Clean-AndroidEnv.ps1`
- Android-related User PATH entries

It does **NOT** uninstall Java.
It does **NOT** remove Node.js/npm, Git, project files outside the install root, or unrelated PATH entries.

## Java logic

- Java 17 or newer detected: keep the existing Java installation.
- Java missing: install `packages\Java17-Setup.exe` silently (`/s`, no clicks needed). If silent install can't be confirmed, the installer is reopened once for manual completion.
- Bundled Java installer missing when Java is required: stop with a clear error.

## Android components

Default install root: `C:\Android`

- Command Line Tools
- Platform Tools / ADB
- Android platform 36
- Build Tools 36.0.0
- NDK 27.1.12297006
- CMake 3.22.1

No emulator or Android system image is installed.

## Important

The ZIP contains the installer and package placeholders, not the actual Java/Android binaries. Add the official packages before running it.
