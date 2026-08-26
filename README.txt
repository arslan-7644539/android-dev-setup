ANDROID DEV SETUP
=================

ZIP NAME
--------
android-dev-setup.zip

INSTALL
-------
1. Put the required vendor packages in the packages folder:
   - Java17-Setup.exe
   - commandlinetools-win.zip
2. Keep the tools\Clean-AndroidEnv.ps1 file next to INSTALL.bat.
3. Right-click INSTALL.bat.
4. Select Run as administrator.
5. The installer clearly explains what it will change.
6. Press Y to start or N to cancel.
7. From there it runs fully unattended (silent Java install,
   command line tools setup, package installation, env vars).

CLEAN + FRESH BEHAVIOR
----------------------
The installer removes/resets the Android setup it owns:
- C:\Android
- ANDROID_HOME / ANDROID_SDK_ROOT (both User and Machine scope)
- Any old SDK folder those variables pointed to (e.g. a previous
  Android Studio SDK install, or a wrong/leftover setup), via
  tools\Clean-AndroidEnv.ps1
- Android-related User PATH entries

It does NOT uninstall Java.
It does NOT remove Node.js/npm, Git, project files outside C:\Android,
or unrelated PATH entries.

JAVA LOGIC
----------
- Java 17 or newer detected: keep the existing Java installation.
- Java missing: install packages\Java17-Setup.exe silently (/s, no
  clicks needed). If silent install can't be confirmed, the installer
  is reopened once for manual completion.
- Bundled Java installer missing when Java is required: stop with a clear error.

ANDROID COMPONENTS
-------------------
C:\Android
- Command Line Tools
- Platform Tools / ADB
- Android platform 36
- Build Tools 36.0.0
- NDK 27.1.12297006
- CMake 3.22.1

No emulator or Android system image is installed.

IMPORTANT
---------
The ZIP contains the installer and package placeholders, not the actual
Java/Android binaries. Add the official packages before running it.
