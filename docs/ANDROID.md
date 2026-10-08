# Android build and device testing

Garden Table is a Godot **4.7.2** project using the Compatibility renderer. The `Android Debug` export preset builds an APK with package ID `com.akhilesh.gardentable`, ARM64 and x86_64 support, Android 7.0/API 24 minimum, and API 36 target. Portrait orientation is set in `project.godot`. This offline game requests vibration for optional haptics; it has no online service requirement.

## Build from Godot on your computer

1. Install Godot 4.7.2 (standard edition, not .NET), import `project.godot`, and allow the initial asset import to finish.
2. Install the **4.7.2 export templates** through **Editor → Manage Export Templates**.
3. Install OpenJDK 17 or 21 and Android Studio's SDK, including **Android SDK Platform 36**, **Build-Tools 36.1.0**, and **Platform-Tools**. Accept the SDK terms in Android Studio when prompted.
4. In **Editor Settings → Export → Android**, set the Java SDK path and Android SDK path. Godot can generate its development debug keystore. Keep your release signing keys outside the repository.
5. Open **Project → Export → Android Debug**, choose **Export Project**, leave **Export With Debug** enabled, and save an APK. The preset uses standard APK templates; a Gradle build or Android plugin is not required. Enable **Runnable** in the preset if you want Godot's one-click device toolbar; it is initially disabled to support headless cloud builds without ADB device discovery.
6. On an Android device, enable USB debugging, connect it, and approve the computer. Install using `adb install -r garden-table-debug.apk` or copy the APK to the device and allow installation from that source.

For the editor-only playtest, no Android tools are needed: open `project.godot` and press **F6/F5** to run the current/main scene.

## Reproduce the Linux cloud build

Python 3.11+, Bash, ripgrep, OpenJDK 17/21, and ordinary Godot desktop system libraries are required. The helper downloads the pinned official engine, checks Godot's published SHA-512 digests, and verifies the Android archive checksums from Google's official repository metadata. It writes tooling beside the checkout, never into project content.

```bash
# Install the engine and Android tooling. About 2 GB of downloads on the first run.
bash tools/setup_environment.sh --android
source ../garden-table-tools/environment.sh

# Import and validate the project.
bash tools/run_checks.sh

# This must run with the setup environment above, so editor settings/templates resolve.
mkdir -p builds
"$GODOT_BIN" --headless --path . --export-debug "Android Debug" builds/garden-table-debug.apk
"$ANDROID_HOME/build-tools/36.1.0/apksigner" verify --verbose builds/garden-table-debug.apk
```

Set `FOOD_SORTING_TOOLS_DIR` to choose another tools directory before running the setup helper. Its generated `environment.sh` exposes `GODOT_BIN`, Android/Java paths and isolated XDG paths. Source that file for every new terminal session. On this cloud machine the tooling directory is `/workspace/tools`, so use `source /workspace/tools/environment.sh`.

The helper makes a local **development-only** debug key with Android's standard debug credentials. Keys, SDK packages, engine binaries and generated APKs are excluded from the Git repository. For Play Store distribution, create a separate release preset and configure private signing credentials; the debug preset is for testing.

## Device acceptance pass

Use a physical device for final touch, performance and safe-area checks:

- Start in portrait; inspect narrow/tall phone layouts and tap target sizes.
- Tap a food then an empty destination, and repeat using drag and drop.
- Make a triple, check the reveal animation and any order-ticket progress, then undo.
- Suspend and resume the app; force close and relaunch during a level and verify progress recovery.
- Test sound/music/haptics settings, mute switches, reduced motion, and high readability.
- Complete and replay a level; progress rewards should only be granted once.
- Test airplane mode and the Android back button. No purchase, ad, analytics or account connection is needed.

Successful APK export and signature verification establish package buildability, not physical-device rendering or touch performance. The cloud checks use the production resolver and desktop/headless runtime. Device-only checks remain a local acceptance step.
