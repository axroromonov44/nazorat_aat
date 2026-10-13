# DevOps runbook — Nazorat AAT

This file does two jobs:

1. **Operations manual.** When asked to "ship to test", follow
   [Release procedure](#release-procedure) — nothing else needs to be
   consulted.
2. **Infrastructure record.** What each file is for, and which invariants
   must not be broken.

> **About copied code.** The **configuration** here is complete (CI/CD YAML,
> Gradle, manifest, plists) — it is easy to lose and tedious to reconstruct.
> **Dart code is not duplicated**: only its path and its invariants are
> recorded. Keeping 800 lines in two places guarantees they drift apart, and
> at that point nobody knows which copy is right. The repository is the source
> of truth.

---

## Current state

| | |
|---|---|
| CI (analyze + test + build) | ✅ working, gates `main` and `develop` |
| Firebase project `nazorat-aat` | ✅ created, Android + iOS apps registered |
| Crashlytics | ✅ wired, config files in place |
| Diagnostics log | ✅ working |
| Remote Config update policy | ✅ parameters published |
| Push (FCM) | ✅ working, verified on a real device |
| CD — Android half | ✅ proven end to end — latest is 1.0.2+29 on the internal track (run 38380695009) |
| CD — iOS half | ✅ proven end to end — 1.0.2+29 reached TestFlight (run 38380695009) |
| Dispatching from `develop` | ✅ proven — 1.0.2+29 shipped from the branch; `main` stays at 1.0.2+26 |
| Release signing | ✅ verified locally — `flutter build appbundle --release` produces a signed 79 MB AAB |
| Branch protection on `main` | ⛔ deliberately not enabled |
| Shorebird code push | ✅ configured (`shorebird.yaml`) |
| Apple certificate + profile | ⏳ both expire **2027-10-07** — see [expiry](#when-the-apple-credentials-expire) |

The ⚠️ row depends on [Preparing the Apple credentials](#preparing-the-apple-credentials).

---

## Release procedure

### What "ship to test" means

```bash
# 1. Gate, locally, before anything is pushed
dart format --output=none --set-exit-if-changed \
  lib test packages/karantin_face_sdk/lib packages/karantin_face_sdk/test
flutter analyze --fatal-infos
(cd packages/karantin_face_sdk && flutter analyze --fatal-infos)
flutter test
(cd packages/karantin_face_sdk && flutter test)

# 2. Bump the build number, and ONLY the build number unless a new version
#    name was actually asked for. This is the default; see below.
tool/bump_build.sh           # 1.0.1+19 -> 1.0.1+20   (build only — the default)

# 3. Commit and push, then start the run by hand
git commit -am "chore: build $(grep '^version:' pubspec.yaml | sed 's/version: //')"
git push origin develop
gh workflow run release.yml --ref develop
```

**The build number is the only thing a test build needs.** Both stores order
releases by it and reject an upload that does not raise it; the version name is
what users read, and it changes when the release means something to them, not
once per upload.

#### Why a build-only release is dispatched, not tagged

`verify` refuses to continue when a `v*` tag does not match the version name in
`pubspec.yaml` — that catches tagging without bumping, before a 40-minute build
ends in a store rejection. But it also means a build-only bump has no tag it can
use: `1.0.1+19 -> 1.0.1+20` still wants `v1.0.1`, which already exists and
cannot be moved.

So the two paths differ, and the first one is the usual one:

| | build only | new version name |
|---|---|---|
| bump | `tool/bump_build.sh` | `tool/bump_build.sh 1.1.0` |
| branch | `develop` | `main` |
| start the run | `gh workflow run release.yml --ref develop` | `git tag v1.1.0 && git push origin main v1.1.0` |
| tag check | skipped (no `v*` ref) | enforced |

#### Which branch a build comes from

`develop` is the branch work lands on, and test builds are dispatched straight
from it. Merging it into `main` to ship a test build would carry whatever is
still unfinished into main's history, which is hard to unpick afterwards; a
dispatch reaches the same testers and leaves main alone. `release.yml` makes no
assumption about the branch — its only `ref` check is
`if: startsWith(github.ref, 'refs/tags/v')`.

`main` is for releases that carry a version name. Those go out by tag, which
means `develop` is merged into `main` first, deliberately, as its own decision.

CI gates both branches (`push: branches: [main, develop]`), so nothing is
dispatched from an unverified commit.

The dispatch path is not a workaround. `release.yml` declares
`workflow_dispatch` precisely so a build can ship without inventing a version
number for it, and the tag check is written `if: startsWith(github.ref,
'refs/tags/v')` so it stays out of the way when there is no tag.

> **This has been got wrong once.** Asked for "+1 on the build", `1.0.1+19`
> went out as **`1.0.2+20`** — the version name was raised only because the
> tag path was the one written down here, and `v1.0.1` was taken. Nothing
> broke, but the store now shows a version number that stands for no change
> an inspector would notice. Reach for `gh workflow run release.yml`.

### Choosing the version name

| change | example |
|---|---|
| bug fix | `1.0.0` → `1.0.1` |
| new feature | `1.0.1` → `1.1.0` |
| breaking change or large rewrite | `1.1.0` → `2.0.0` |

The build number is independent and only ever goes up by one. A test build
that is not one of the rows above does not get a new version name — it gets a
new build number and a dispatched run.

### When only Dart changed

No need to wait for the stores — a Shorebird patch reaches devices in minutes:

```bash
shorebird patch --platforms=android,ios
```

A patch **cannot** carry changes to native code, plugins, `pubspec.yaml` or
assets. Those need a full release.

### Knowing which patch a device is on

`lib/core/update/shorebird_update_service.dart` downloads patches without ever
telling the inspector, which is right — a patch applies on the next launch and
there is nothing to decide — but it means a silent failure would otherwise be
invisible. So the service reports itself:

- **Crashlytics custom key `shorebird_patch`** — the running patch number, or
  `0` for the release as the stores shipped it, or `unknown` when the number
  could not be read. Two crashes with identical stack traces are usually the
  same bug on different patches, and this is the only thing that tells them
  apart. Filter on it before concluding a patch fixed anything.
- **The diagnostics log**, under the `shorebird` tag, for every step: the
  running patch, whether one was available, and why a download did not happen.

The failure reasons are deliberately split. A download that fails because the
inspector is standing in a field with no signal is logged as a warning and
goes no further; only a patch that downloaded and then refused to install
reaches Crashlytics as a non-fatal. Treating both as defects would bury the
one that is.

`UpdateStatus.restartRequired` is not an error either — it means a patch is
already waiting and the app has to be reopened. Nothing can hurry that.

### Rolling back

Halt the internal-track release in Play Console; expire the build in
TestFlight. A Shorebird patch is undone by publishing the previous one again.

---

## CI — `.github/workflows/ci.yml`

Three jobs run in parallel on every push and pull request. The repository is
public, so even the macOS runner is free.

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
  workflow_dispatch:

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

env:
  FLUTTER_VERSION: "3.47.1"

jobs:
  analyze:
    name: Analyze & test
    runs-on: ubuntu-latest
    timeout-minutes: 20
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: ${{ env.FLUTTER_VERSION }}
          channel: stable
          cache: true
      - name: Dependencies
        run: |
          flutter pub get
          flutter pub get -C packages/karantin_face_sdk
      - name: Format
        run: |
          dart format --output=none --set-exit-if-changed \
            lib test packages/karantin_face_sdk/lib packages/karantin_face_sdk/test
      - name: Analyze (app)
        run: flutter analyze --fatal-infos
      - name: Analyze (karantin_face_sdk)
        run: flutter analyze --fatal-infos
        working-directory: packages/karantin_face_sdk
      - name: Test (app)
        run: flutter test --coverage
      - name: Test (karantin_face_sdk)
        run: flutter test
        working-directory: packages/karantin_face_sdk
      - name: Coverage report
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: coverage
          path: coverage/lcov.info
          if-no-files-found: ignore

  build-android:
    name: Android build
    runs-on: ubuntu-latest
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: "17"
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: ${{ env.FLUTTER_VERSION }}
          channel: stable
          cache: true
      - run: flutter pub get
      - run: flutter build apk --debug

  build-ios:
    name: iOS build
    runs-on: macos-latest
    timeout-minutes: 40
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: ${{ env.FLUTTER_VERSION }}
          channel: stable
          cache: true
      - run: flutter pub get
      - run: flutter build ios --debug --no-codesign
```

**Why the build jobs exist:** `flutter analyze` only reads Dart. A Gradle
plugin clash, a CocoaPods problem or missing desugaring shows up only in a
real build — which is exactly what happened in this project when
`flutter_local_notifications` turned out to need core library desugaring.

**Bump `FLUTTER_VERSION` together with the local SDK.** Otherwise CI checks
against a different one and "works on my machine" becomes possible again.

---

## CD — `.github/workflows/release.yml`

The full workflow lives in the repository. Shape: `verify` (version guard +
analyze + test) → `android` and `ios` in parallel.

### Secrets it needs

GitHub → Settings → Secrets and variables → Actions:

| secret | what | how to get it |
|---|---|---|
| `ANDROID_KEYSTORE_BASE64` | signing key | `base64 -i android/keystore.jks \| pbcopy` |
| `ANDROID_KEY_PROPERTIES` | key passwords | `base64 -i android/key.properties \| pbcopy` |
| `ANDROID_GOOGLE_SERVICES_JSON` | Firebase (Android) | `base64 -i android/app/google-services.json \| pbcopy` |
| `GOOGLE_PLAY_SERVICE_ACCOUNT` | Play API | Google Cloud service account JSON, **plain text, not base64** — see [CD secrets](#cd-secrets) |
| `IOS_GOOGLE_SERVICE_INFO_PLIST` | Firebase (iOS) | `base64 -i ios/Runner/GoogleService-Info.plist \| pbcopy` |
| `IOS_CERTIFICATE_P12` | distribution certificate | Keychain → export .p12 → base64 |
| `IOS_CERTIFICATE_PASSWORD` | .p12 password | chosen during export |
| `IOS_PROVISIONING_PROFILE` | profile | Apple Developer → Profiles → base64 |
| `APPSTORE_KEY_ID` | ASC API key | App Store Connect → Users → Integrations → Keys |
| `APPSTORE_ISSUER_ID` | ASC issuer | same page |
| `APPSTORE_PRIVATE_KEY` | contents of the `.p8` | downloaded once, at key creation |

> **No Apple ID password is used** — two-factor auth makes it useless in CI.
> Only the App Store Connect API key (`.p8`).

`ios/ExportOptions.plist` is in the repository with `teamID = PTV6284A36`,
which must match `DEVELOPMENT_TEAM` on the Runner target.

---

## Firebase

Project **`nazorat-aat`** (console:
`https://console.firebase.google.com/project/nazorat-aat`), created with the
CLI together with both apps:

| | id |
|---|---|
| Android | `1:980297703068:android:e70382e0cf0ed4aceb9759` |
| iOS | `1:980297703068:ios:03f2183c045a5bd9eb9759` |

Config files are gitignored (the repository is public). To fetch them again:

```bash
firebase apps:sdkconfig ANDROID 1:980297703068:android:e70382e0cf0ed4aceb9759 \
  --project nazorat-aat --out android/app/google-services.json
firebase apps:sdkconfig IOS 1:980297703068:ios:03f2183c045a5bd9eb9759 \
  --project nazorat-aat --out ios/Runner/GoogleService-Info.plist
```

> **Invariant:** `GoogleService-Info.plist` is registered in
> `project.pbxproj` under the Runner target's *Copy Bundle Resources* phase.
> Dropping the file into `ios/Runner/` is not enough — without that entry it
> never reaches the app bundle and Firebase stays dead on iOS.
>
> The flip side: because it is a declared build input, Xcode refuses to build
> at all when the file is absent. The file is gitignored, so CI would fail on
> every run. The CI job therefore writes a placeholder before building — it
> only compiles, never launches the app — while the release workflow restores
> the real file from `IOS_GOOGLE_SERVICE_INFO_PLIST`. Android solves the same
> problem differently, by applying its Gradle plugins conditionally, because
> there the plugin is what demands the file.

### Gradle plugins are conditional

`android/app/build.gradle.kts`. `google-services.json` is gitignored, so the
plugin is applied only when the file exists — otherwise CI and a fresh clone
would not build:

```kotlin
val googleServicesFile = file("google-services.json")
if (googleServicesFile.exists()) {
    apply(plugin = "com.google.gms.google-services")
    apply(plugin = "com.google.firebase.crashlytics")
} else {
    logger.lifecycle(
        "google-services.json not found - Crashlytics is disabled for this " +
            "build. Download it from the Firebase console into android/app/."
    )
}
```

The trap is that this is a log line, not an error: a release build on a machine
without the file succeeds and produces an AAB with no Crashlytics and no push.
CI is safe — it writes the file from `ANDROID_GOOGLE_SERVICES_JSON` first — but
a hand-built AAB is only as good as what is in `android/app/`.

`android/settings.gradle.kts`:

```kotlin
id("com.google.gms.google-services") version "4.4.2" apply false
id("com.google.firebase.crashlytics") version "3.0.2" apply false
```

This mirrors the `hasReleaseSigning` pattern already used for signing.

---

## Observability

The problem: the app works offline, so a failure stays **on the inspector's
phone**. Three layers close that gap.

### 1. Crashlytics — crashes

`lib/core/observability/crash_reporting.dart`

- `FlutterError.onError` and `PlatformDispatcher.instance.onError` are wired
- collection is **off in debug** (`setCrashlyticsCollectionEnabled(!kDebugMode)`)
- `Firebase.initializeApp()` is called **without options**, inside `try/catch`

> **Do not change:** `firebase_options.dart` is deliberately unused. It would
> have to be generated for the code to compile at all, binding the whole
> project to one Firebase project. Reading the native config files instead
> means a missing file degrades to "no crash reporting" rather than "no build".

### 2. Diagnostics log — failures that are not crashes

`lib/core/observability/diagnostics_log.dart` and
`lib/core/network/diagnostics_interceptor.dart`

Crashlytics catches crashes. "I could not sign in", "the sync never
finished", "the image did not load" are not crashes. So a ring buffer is kept
on disk:

- the last **1000 lines** live in Hive and survive a restart
- every line also becomes a Crashlytics breadcrumb, so it travels with a crash
- flushed to disk when the app leaves the foreground
  (`DiagnosticsLifecycleObserver`)

What it looks like:

```
2026-10-06T14:22:08 INFO  [http] POST /auth/login 401 820ms
2026-10-06T14:23:15 ERROR [http] GET /reference/pests/ FAILED connectionTimeout 15004ms
2026-10-06T14:23:15 INFO  [sync] pests -> error
```

The first line is a wrong password, the second a dead connection. Previously
both looked like "it did not work".

> **Do not change:**
> - Response bodies are **not** logged — catalog responses run to megabytes
>   and may carry personal data.
> - Only `uri.path` is logged; a full URL may carry a token in its query.
> - The interceptor is attached **only** to `DioService` and
>   `ReferenceRemoteDataSource`. Do not attach it to the map tile or reference
>   image clients: 1255 requests would bury the log.

**How it reaches the developer:** automatically (alongside any crash or
non-fatal report), or on demand — Profile → **"Send diagnostics log"**, which
shares the file over Telegram.

### 3. Non-fatal reports

Failures that do not stop the app but are worth knowing about:

| where | what is reported |
|---|---|
| `reference_repository_impl.dart` | a catalog step failed |
| `app_download_controller.dart` | offline map download failed |
| `remote_config_service.dart` | Remote Config unavailable |
| `push_service.dart` | push service did not start |

---

## Update policy (Remote Config)

`lib/core/update/app_version.dart` · `remote_config_service.dart` ·
`update_prompt.dart`

Parameters are version-controlled in `remoteconfig.template.json` and
published with:

```bash
firebase deploy --only remoteconfig --project nazorat-aat
```

| key | example | effect |
|---|---|---|
| `min_supported_version` | `1.2.0` | below this — **forced** update, dialog cannot be dismissed |
| `latest_version` | `1.5.0` | below this — **optional**, with a "Later" button |
| `update_message` | text | replaces the built-in copy when set |
| `store_url_android` | Play link | falls back to a built-in link when empty |
| `store_url_ios` | App Store link | the button stays hidden when empty |

No new build is needed to block an old version: change the value in the
console (or the template file) and devices pick it up on their next launch
(`minimumFetchInterval` is one hour).

> **`store_url_ios` is still empty,** so the update dialog on iOS shows no
> button at all. TestFlight has builds but there is no public App Store page
> to point at yet; fill this in the day the app is approved, or an iOS user
> told to update has nowhere to go.

> **Do not change:** `resolveUpdateRequirement` returns
> `UpdateRequirement.none` for anything unparseable. Typing `v1.2.0` instead
> of `1.2.0` in the console must lock **nobody** out. `test/app_version_test.dart`
> guards this with 14 tests, including the `"1.10.0"` vs `"1.9.0"` case where
> a text comparison would place `1.10.0` lower.

---

## Push notifications (FCM)

`lib/core/notifications/push_service.dart`

All four states are handled: foreground (`onMessage` → local notification),
background (the system), terminated (`getInitialMessage`), and tapped
(`onMessageOpenedApp`).

> **Do not change:**
> - The background handler is a **top-level function** annotated with
>   `@pragma('vm:entry-point')`. Without it, tree shaking removes it from
>   release builds and background messages silently stop working.
> - The channel id `nazorat_default` appears in **three places**:
>   `PushService._channel`, the `AndroidManifest.xml` meta-data, and
>   `_showForeground`. If they disagree, nothing appears on Android 8+.

### Native configuration

`android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
...
<meta-data
    android:name="com.google.firebase.messaging.default_notification_channel_id"
    android:value="nazorat_default" />
<meta-data
    android:name="com.google.firebase.messaging.default_notification_icon"
    android:resource="@mipmap/ic_launcher" />
```

`android/app/build.gradle.kts` — required by `flutter_local_notifications`:

```kotlin
compileOptions {
    isCoreLibraryDesugaringEnabled = true
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
```

`ios/Runner/AppDelegate.swift`:

```swift
if #available(iOS 10.0, *) {
  UNUserNotificationCenter.current().delegate = self
}
application.registerForRemoteNotifications()
```

`ios/Runner/Runner.entitlements` (wired into all three build configurations
through `CODE_SIGN_ENTITLEMENTS`):

```xml
<key>aps-environment</key>
<string>development</string>
```

Xcode rewrites this to `production` on App Store export, so `development` is
the correct value to keep in the file.

`ios/Runner/Info.plist`:

```xml
<key>UIBackgroundModes</key>
<array>
    <string>remote-notification</string>
</array>
```

### APNs

An APNs **authentication key** is uploaded to Firebase (Key ID `WDL4G34DNC`,
Team ID `PTV6284A36`). One key covers both development and production, never
expires, and serves every app on the account.

The "APNs Certificates" section in the Firebase console is deliberately empty:
certificates are the legacy alternative to the key, not a companion to it, and
they would have to be renewed yearly.

The Runner target carries the *Push Notifications* capability; the
`aps-environment` entitlement is wired through
`CODE_SIGN_ENTITLEMENTS` in all three build configurations.

---

## Permissions

### Android

Declared in `android/app/src/main/AndroidManifest.xml`: internet, fine /
coarse / background location, camera, microphone, media and legacy storage
reads, and `POST_NOTIFICATIONS` for Android 13+.

### iOS

`Info.plist` holds the **English** usage descriptions, which is what App
Store review reads. Inspectors still see their own language because the
strings are localized:

```
ios/Runner/en.lproj/InfoPlist.strings
ios/Runner/uz.lproj/InfoPlist.strings
ios/Runner/ru.lproj/InfoPlist.strings
```

> **Do not change:** the three files form a `PBXVariantGroup` in
> `project.pbxproj` and `uz`/`ru` are listed in `knownRegions`. A language
> missing from `knownRegions` is not built at all, and a variant group missing
> from *Copy Bundle Resources* never reaches the bundle — in both cases the
> prompts silently fall back to English. Verify after changing:
> `ls build/ios/iphoneos/Runner.app/*.lproj`.

Adding a new permission means editing four files: `Info.plist` (English) plus
the three `InfoPlist.strings`.

---

## File map

| file | purpose |
|---|---|
| `.github/workflows/ci.yml` | analyze · test · android/ios build |
| `.github/workflows/release.yml` | tag → Play internal + TestFlight |
| `tool/bump_build.sh` | increments the build number in pubspec.yaml |
| `firebase.json` · `remoteconfig.template.json` | Remote Config as code |
| `ios/ExportOptions.plist` | IPA export settings (teamID, dSYM upload) |
| `lib/core/observability/crash_reporting.dart` | Crashlytics wiring |
| `lib/core/observability/diagnostics_log.dart` | on-disk ring buffer |
| `lib/core/observability/analytics_service.dart` | Analytics wrapper |
| `lib/core/network/diagnostics_interceptor.dart` | logs every request |
| `lib/core/notifications/push_service.dart` | FCM |
| `lib/core/update/app_version.dart` | version comparison (pure logic) |
| `lib/core/update/remote_config_service.dart` | reads the update policy |
| `lib/core/update/update_prompt.dart` | forced / optional dialog |
| `test/app_version_test.dart` | 14 tests guarding the forced update |

---

## Where this was left off

Last updated 2026-10-07. Everything below is the state of the repository as it
actually stands, not a plan.

### Done and verified

- `main` carries the whole pipeline; CI passes there (analyze, tests, real
  Android and iOS builds).
- Firebase project `nazorat-aat` with both apps registered; Crashlytics,
  Analytics, Remote Config and FCM are wired.
- Remote Config parameters are published from `remoteconfig.template.json`.
- Push notifications were tested end to end on a real device.
- `flutter build appbundle --release` produces a signed bundle, so the signing
  configuration itself is known good.
- **The Android pipeline has run for real,** twice. `v1.0.1` shipped
  1.0.1+19 and `v1.0.2` shipped 1.0.2+20; the internal track reports both
  `completed`. Nothing on that side is theoretical any more.
- 1.0.2 should have been 1.0.1+20. The version name was raised only because
  the tag path was the one documented — see
  [What "ship to test" means](#what-ship-to-test-means), now corrected.

### Deliberately skipped

Branch protection on `main` is **not** enabled. CI runs on every push and pull
request but does not block a merge. This was a conscious choice, not an
oversight — do not "fix" it without being asked.

### CD secrets

Already set — the whole Android half, the App Store Connect API key and the
distribution certificate:

```
ANDROID_KEYSTORE_BASE64
ANDROID_KEY_PROPERTIES
ANDROID_GOOGLE_SERVICES_JSON
GOOGLE_PLAY_SERVICE_ACCOUNT
IOS_GOOGLE_SERVICE_INFO_PLIST
APPSTORE_KEY_ID
APPSTORE_ISSUER_ID
APPSTORE_PRIVATE_KEY
IOS_CERTIFICATE_P12
IOS_CERTIFICATE_PASSWORD
IOS_PROVISIONING_PROFILE
```

The ASC key is `L2B3479S8C`. Do not confuse it with `WDL4G34DNC`, the APNs key
in Firebase: both are `AuthKey_<id>.p8` files holding an EC private key, so
only the console they came from tells them apart — an ASC key comes from
App Store Connect → Users and Access → Integrations → Keys, never from
Apple Developer → Keys. `release.yml` writes the secret to
`AuthKey_$KEY_ID.p8`, so `APPSTORE_KEY_ID` must be the id of the key the
`.p8` actually belongs to.

`GOOGLE_PLAY_SERVICE_ACCOUNT` is the `play-release-ci@nazorat-aat` service
account, created in the `nazorat-aat` Google Cloud project — a Firebase project
*is* a Cloud project, so no second one was made. It carries **no Cloud IAM
role**; the upload right comes from the Play Console invitation, not from
Cloud. The old "Play Console → Setup → API access" route no longer exists:

1. Cloud Console → enable `Google Play Android Developer API`
2. IAM & Admin → Service Accounts → create, skip the role step → Keys → JSON
3. Play Console → **Users and permissions → Invite new users** → that service
   account's email → `com.nazorat.aat.uz` → *View app information* and
   *Release to testing tracks*

The key goes in as **plain text** (`serviceAccountJsonPlainText`), unlike every
other secret here, which is base64. Access can be checked without spending a
40-minute build on it — this returns HTTP 200 once the invitation has landed:

```bash
gcloud auth activate-service-account --key-file=<key>.json
curl -X POST -H "Authorization: Bearer $(gcloud auth print-access-token \
  --scopes=https://www.googleapis.com/auth/androidpublisher)" \
  -H "Content-Length: 0" \
  https://androidpublisher.googleapis.com/androidpublisher/v3/applications/com.nazorat.aat.uz/edits
```

Nothing is missing any more. The release has still never run end to end on
the iOS side, so the first run is where the remaining problems show up.

> `gh secret set X < ~/Downloads/file` fails with `Operation not permitted`
> when it runs from an agent or a tool: macOS guards `~/Downloads` and
> `~/Desktop` per application, and moving the file between those two changes
> nothing. `~/Documents` is not guarded, so moving the file there is the
> simplest fix; otherwise run it from Terminal.app, which asks once.

### Preparing the Apple credentials

All of this is done — kept as the record of how, since a certificate expires
in a year and a profile with it. Every step runs through Apple's consoles.

Two things must exist first, or the run builds an IPA and then fails on the
last step:

- `com.nazorat.aat.uz` registered under Apple Developer → **Identifiers**
- an App Store Connect app record for that same bundle id

**The certificate** — ✅ done:
`Apple Distribution: Shokhrukh Shodiev (PTV6284A36)`, valid until 2027-10-07.
How it was obtained: Keychain Access → Certificate Assistant → *Request a Certificate from a
Certificate Authority* → save the CSR. Apple Developer → Certificates → **+** →
**Apple Distribution** → upload the CSR → download the `.cer` → double-click to
install. Keychain Access → **My Certificates** → right-click the
`Apple Distribution:` entry → **Export** as `.p12`, choosing a password.

**The profile** — ✅ done: `Nazorat AAT`, UUID
`8d8aeb14-c271-47eb-9eb1-b42d5615e774`, valid until 2027-10-07. How it was
obtained: Apple Developer → **Profiles** → **+** → **App Store** (Apple now
labels it *App Store Connect*) → App ID `com.nazorat.aat.uz` → that
certificate → download the `.mobileprovision`.

A profile is worth checking before trusting it, since every way of getting it
wrong fails the same way later:

```bash
security cms -D -i Nazorat_AAT.mobileprovision > /tmp/p.plist
/usr/libexec/PlistBuddy -c 'Print :Name' /tmp/p.plist
/usr/libexec/PlistBuddy -c 'Print :Entitlements:application-identifier' /tmp/p.plist
/usr/libexec/PlistBuddy -c 'Print :ProvisionedDevices' /tmp/p.plist
```

`Name` is what `ExportOptions.plist` needs and it is not the file name — here
`Nazorat AAT` against `Nazorat_AAT.mobileprovision`. A `ProvisionedDevices`
array means an Ad Hoc profile, which cannot reach TestFlight. The certificate
embedded in the profile must be the same one the `.p12` holds; comparing SHA-1
fingerprints proves it:

```bash
python3 -c "import plistlib,hashlib;print(hashlib.sha1(plistlib.load(open('/tmp/p.plist','rb'))['DeveloperCertificates'][0]).hexdigest().upper())"
security find-identity -v -p codesigning | grep Distribution
```

**The API key** — ✅ done (`L2B3479S8C`). It came from App Store Connect →
Users and Access → Integrations → **Keys**, access role **App Manager**; a
lesser role cannot upload builds. The `.p8` downloads once; both IDs are on
that page.

```bash
base64 -i ~/Downloads/dist.p12            | gh secret set IOS_CERTIFICATE_P12
base64 -i ~/Downloads/app.mobileprovision | gh secret set IOS_PROVISIONING_PROFILE
```

Note the asymmetry: the `.p12` and the profile go in **base64**, while the
`.p8` went in as **plain text**, because the workflow writes it straight to a
file. Base64 there builds fine and fails at upload with nothing that points at
the cause.

Verifying the `.p12` locally with Homebrew's OpenSSL 3 fails on
`RC2-40-CBC : unsupported` — Apple exports with a cipher OpenSSL 3 retired, so
either add `-legacy` or use `/usr/bin/openssl` (LibreSSL). This says nothing
about the file: CI imports it with `apple-actions/import-codesign-certs`, which
goes through macOS `security`, the same tool that wrote it.

Re-running needs no new tag — `gh workflow run release.yml` replays it — but
it does need `tool/bump_build.sh` first once a run has reached a store. The
Android and iOS jobs are independent, so a run that failed on iOS has usually
already uploaded that build number to Play, and Play rejects it the second
time. Debugging the iOS half therefore costs a build number per attempt;
1.0.2+24 and +25 went that way.

### Signing: the archive and the export are two steps

`flutter build ipa` archives first and exports second, and **they are signed
from different places.** `ios/ExportOptions.plist` configures only the export.
The archive uses the Xcode project, so a correct `ExportOptions.plist` does
nothing for it — run 37590185220 failed with the certificate and the profile
both in place:

```
Error (Xcode): No Accounts: Add a new account in Accounts settings.
Error (Xcode): No profiles for 'com.nazorat.aat.uz' were found: Xcode couldn't
  find any iOS App Development provisioning profiles matching ...
```

Two causes, both in the project. The Runner target set no `CODE_SIGN_STYLE`,
which means automatic, and automatic signing wants an Apple ID that CI does
not have. And the project level pins
`CODE_SIGN_IDENTITY[sdk=iphoneos*] = "iPhone Developer"` — the Flutter
template's default — which is why it hunted for a *development* profile.

So the Runner target's **Release** configuration now carries:

```
CODE_SIGN_STYLE = Manual;
"CODE_SIGN_IDENTITY[sdk=iphoneos*]" = "Apple Distribution";
PROVISIONING_PROFILE_SPECIFIER = "Nazorat AAT";
```

Release only. Debug and Profile stay automatic, so `flutter run` on a device
still signs with whichever Apple ID the developer has. Checking it needs no
build:

```bash
cd ios && xcodebuild -project Runner.xcodeproj -target Runner \
  -configuration Release -showBuildSettings | grep CODE_SIGN
```

`PROVISIONING_PROFILE_SPECIFIER` is the profile's internal `Name`, not its
file name.

With that in place run 37592011891 went green on all three jobs, putting
1.0.2+25 on the Play internal track and in TestFlight. That is the first time
the iOS half completed.

> **Xcode puts it back.** Opening `Runner.xcworkspace` and touching anything
> under Signing & Capabilities rewrites the Release configuration to
> `CODE_SIGN_STYLE = Automatic`, `CODE_SIGN_IDENTITY = "Apple Development"`
> and an empty `PROVISIONING_PROFILE_SPECIFIER`, with no prompt and no diff
> anybody reads — `project.pbxproj` is not a file you review line by line.
>
> It happened during the Karantin ID work: run 38378882945 archived for five
> minutes and failed with the same two errors as above, after the certificate
> and the profile had both installed cleanly. Android had already uploaded, so
> the build number had to be burned and the release re-dispatched as
> 1.0.2+29.
>
> **After any visit to Xcode, run the `-showBuildSettings` check above before
> dispatching a release.** Three lines, no build, and it is the difference
> between a 12-minute failure and a green run. The three settings also carry a
> comment in `project.pbxproj` saying this, for whoever reads the file next.

### When the Apple credentials expire

**2027-10-07.** The distribution certificate and the profile expire the same
day, a year after they were made. After that every iOS release fails at
signing; Android keeps going, so the run turns red while Play still gets the
build.

A profile is bound to a certificate, so the order is fixed: certificate first,
then a new profile, even if only the profile looks expired. The steps are the
ones above — the walkthrough is kept for this day, not for history. Then reset
the three secrets (`IOS_CERTIFICATE_P12`, `IOS_CERTIFICATE_PASSWORD`,
`IOS_PROVISIONING_PROFILE`); the App Store Connect API key is unaffected,
since it never expires.

> **Keep the profile's name `Nazorat AAT`,** or two files have to change with
> it: `ios/ExportOptions.plist` and `PROVISIONING_PROFILE_SPECIFIER` in
> `ios/Runner.xcodeproj/project.pbxproj`. Beware that `Nazorat AAT` is also
> the app's display name in `Info.plist` and in three
> `INFOPLIST_KEY_CFBundleDisplayName` entries — a blind find-and-replace over
> the name either breaks signing or renames the app on the home screen.

Shorebird patches keep working regardless: a patch ships Dart, not a signed
binary.

The two halves are independent: the Android job releases on its own, without
waiting for any of the Apple credentials. Until they exist the iOS job fails
while Android still reaches Play — a red run is not a broken release.

### Next steps, in order

1. **Decide on the uncommitted working tree.** `lib/main.dart` has three
   comments deleted — the ones explaining why `main()` orders
   `CrashReporting.init()`, `DiagnosticsLog.init()` and `PushService.init()`
   the way it does. The code is untouched, so this is a style question, not a
   bug. `pubspec.lock` and `ios/Podfile.lock` also carry patch bumps
   (`intl 0.20.2 → 0.20.3`, `matcher 0.12.19 → 0.12.20`) that the local gate
   passed with but CI has never seen.
2. **Wire `onMessageOpened` to navigation.** The handler exists but goes
   nowhere, because which screen to open depends on what `data` the backend
   sends with a push. Needs a decision first, not code.
3. **Rotate the keystore passwords** in `android/key.properties`, then update
   `ANDROID_KEY_PROPERTIES`. Routine hygiene:
   ```bash
   keytool -storepasswd -keystore android/keystore.jks
   keytool -keypasswd -alias upload -keystore android/keystore.jks
   ```
   This changes only the passwords, not the key, so nothing breaks in Play
   Console.
4. **Backend conversations** (separate track, nothing here blocks on them):
   - Catalog images total **1.04 GB**. Thumbnails would cut that to roughly
     68 MB (WebP 1280px) or 17 MB (320px). Raise with the
     `datahub.karantin.uz` team.
   - There is no staging backend, so a clearly marked test inspector on
     production is needed — today `flutter run` writes to the real database.
   - `page_size` is ignored on `/reference/plants/`, so 184 plants cost 10
     sequential requests.

### The retired bundle id

`com.dala.nazorati.uz` is **dead**. It was the earlier id, it still had a Play
listing, and the release service account gets `403` on it — which reads like a
permissions problem and is not one. The live package is `com.nazorat.aat.uz`,
in `android/app/build.gradle.kts`, `release.yml` and the iOS target alike.

Related: SHA fingerprints come from the signing certificate, never from a
device or a package name, and under Play App Signing the certificate that
matters is Google's, not the local upload key. The one way to read the real
one without waiting for a Console page is to ask an installed build:

```bash
adb shell pm path com.nazorat.aat.uz          # then pull that base.apk
apksigner verify --print-certs base.apk
```

`CN=Android, O=Google Inc.` in the output means Play re-signed it, so those
digests are the production fingerprints. `CN=Android Debug` means the build
came from `flutter run` and its fingerprint is worth nothing to Firebase.

### Known, accepted, not a bug

Face capture sends frames **un-mirrored** (`karantin_face_scanner.dart` has no
flip) while the old webview flipped them horizontally. The flow was verified on
a device and works. If the backend ever starts rejecting face matches, this is
the first place to look.

## Keeping this file current

Update it whenever the infrastructure changes — a new workflow, a new secret,
a new observability layer. A stale runbook is worse than none, because people
trust it.
