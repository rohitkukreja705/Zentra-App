# Zentra - rebuilt project

## What this actually is

Your original APK (`app-release-1.apk`, package `com.wearables.app`) is a
Flutter app. Flutter compiles all Dart code - every screen, every line of
business logic - into native machine code (`libapp.so`). There is no
decompiler that turns that back into source, the way there is for Java/
Kotlin. So this is **not** a recovery of your original files. It's a fresh
project, same package name and app identity, with the QRing ring
integration done correctly (including the permission fix from earlier in
this conversation) and a navigation shell matching the tabs your APK's
strings revealed (Home / Activity / Devices / Profile).

**What's real and functional:**
- The QRing SDK wiring end to end - scan, connect, live heart rate - via a
  Kotlin platform channel (`QRingBridge.kt`) that mirrors the vendor's own
  sample app's exact method signatures and init sequence.
- The Bluetooth permission gate (`lib/core/permissions.dart`) that was the
  actual fix for your crash, applied at every entry point that touches BLE.
- Your real app icon and adaptive-icon foreground, pulled straight out of
  the APK's resources (these aren't compiled like the Dart code is, so
  they came out byte-identical).
- A working live-HR chart and a foreground-service-backed workout screen.
- A "Sync ring data" button on Devices that pulls today's step count,
  calories, distance, and total sleep straight off the ring (via
  `BleOperateManager.getTodayStepTotal`) and feeds the Home tab's cards.
  This is a pull, not a live stream - the ring counts steps on its own
  hardware and holds the running total; there's no push API for it in the
  SDK the way there is for heart rate, so it needs a manual sync each time
  you want a fresh number.
- A live Stress reading on Home, alongside heart rate - it rides in the
  same sensor response frame as heart rate (a real byte from the ring's
  own firmware), so it shows up automatically during a live Activity
  session, no separate sync needed.

**Deliberately NOT built - blood pressure:** the SDK's blood pressure
value is generated with `Math.random()` app-side (confirmed in
`CalcBloodPressureByHeart.java` and `manualModePressure` in the
decompiled SDK) - not read from any real sensor. I built it, then found
this, then removed it. Don't re-add it without a real data source behind
it; displaying it would mean showing users a fabricated number as their
blood pressure.

Known gap: `sleepMinutes` in the steps sync is usually 0 - confirmed via
a screen recording of the reference app (QWatch Pro / ring model
H59MAX_F104) that sleep isn't in the "today totals" bucket at all; it
lives in a day-indexed historical record (`ReadSleepDetailsReq` in the
SDK). Not wired up yet.

**What's simplified, on purpose, for reliability:**
- No Firebase. Push notifications and cloud sync were in your manifest but
  wiring Firebase back in needs your live project's `google-services.json`
  - I don't have it and a fake one would just break the build. Say the
    word and I'll add it back in once you can get me that file.
- Plain `setState` instead of riverpod, and no sqflite/local database yet.
  Both are easy to layer in; I skipped them here because I can't compile-
  test this project (no Flutter SDK or pub.dev access in my sandbox), so
  I kept the dependency surface small to maximize the odds this builds
  clean on the first CI run.
- Only English strings, no localization - your original shipped 24
  languages.
- Home, Activity, Devices, Profile - the deeper tabs your APK had (Sleep,
  Recovery, Coach, Challenges, Rewards, Friends, Habits, Inbox, Settings...)
  aren't rebuilt yet. Tell me which ones matter most and I'll build them
  out next.

## Layout

```
pubspec.yaml              - dependencies (deliberately minimal, see above)
lib/                       - the actual app
  core/
    theme.dart              - dark theme
    permissions.dart        - THE fix: gates every BLE call on real grants
    ble_channel.dart         - Dart side of the platform channel
  features/
    shell/main_shell.dart    - bottom nav
    home/home_tab.dart
    devices/devices_tab.dart - scan + pair, permission-gated
    activity/live_workout_screen.dart - start/stop workout + live HR chart
    profile/profile_tab.dart - placeholder
assets/icon/                - your real icon, extracted from the APK
android_overlay/            - NOT a real android/ folder - files the CI
                               workflow copies on top of a freshly
                               generated one (see below for why)
.github/workflows/build-apk.yml
```

`android/` and `ios/` don't exist in this repo and are gitignored. The
workflow runs `flutter create --platforms=android .` on every build to
generate a fresh, correctly-versioned Android project (matching whatever
Flutter/Gradle/AGP is current), then copies the three files in
`android_overlay/` on top of it: the manifest, the Kotlin bridge, and the
QRing AAR. This avoids me hand-pinning a Gradle/AGP version number that
could go stale.

## Pushing this to GitHub

Same constraint as last time: pushing `.github/workflows/build-apk.yml`
through the Contents API needs a fine-grained PAT with **Workflows: Read
and write**, not just Contents. Everything else only needs Contents R/W.

The QRing AAR (`android_overlay/app/libs/qring_sdk_1.0.0.27.aar`) is a
1.1 MB binary - push it as base64 content via the Contents API like any
other file, same as the icon PNGs.

If you'd rather I push this directly: give me the repo name and a
short-lived fine-grained PAT (Contents: R/W, Workflows: R/W) and I'll do
it from here.

## First build

Expect the first Actions run to be the actual first real compile of this
code - I couldn't run `flutter pub get` or `flutter build apk` locally
(no Flutter SDK, and pub.dev isn't reachable from my sandbox), so this
hasn't been compile-verified. The dependency versions in `pubspec.yaml`
are caret ranges (`^x.y.z`) specifically so pub's resolver has room to
pick a compatible current release even if an exact patch number I guessed
is off. If a run fails, paste me the Actions log and I'll fix it fast -
most likely failure mode is a single dependency version constraint.
