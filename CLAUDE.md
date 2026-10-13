# Nazorat AAT

An offline-first Flutter app for quarantine, veterinary and sanitary
inspectors. Inspectors work in the field where the connection is weak or
absent, so being offline is not the exception — it is the normal case.

## Roles

Three inspectorates — quarantine, veterinary and SES — share one app, and a
fourth is expected. **Whenever a request names an inspectorate ("this is for
the veterinary role", "karantin uchun"), read
[`docs/ROLES.md`](docs/ROLES.md) first and follow the procedure there.** It
says which folder the code belongs in and how it is wired, so one
inspectorate's logic cannot run for another.

Two rules, both enforced by `test/role_boundary_test.dart`:

- Role-specific code lives only in `lib/features/<role>/`; from outside, only
  its module is imported, and only by `lib/core/roles/role_registry.dart`.
- Shared code never names an inspectorate. It asks what the user may do — the
  module, later a capability — not who they are.

## Releases and infrastructure

**Whenever the subject is shipping a build, CI, Crashlytics, push, or the
update policy, read [`docs/DEVOPS.md`](docs/DEVOPS.md) first and follow the
procedure there.** It holds the release commands, the workflows, the list of
secrets and the invariants that must not be broken.

`docs/DEVOPS.md` also records **where the work was left off** — what is done,
what was deliberately skipped, and the next steps in order. Start there when
picking the work back up.

In short, a test build is:

```bash
tool/bump_build.sh              # build number only: 1.0.1+19 -> 1.0.1+20
git commit -am "chore: build 1.0.1+20" && git push origin main
gh workflow run release.yml
```

**Bump the build number and nothing else unless a new version name was
actually asked for.** The build number is what the stores order releases by;
the version name is what users read. Raising the name for an ordinary test
build puts a number in the store that stands for no change anyone would
notice.

A release that *does* carry a new version name goes out by tag instead:

```bash
tool/bump_build.sh 1.1.0
git commit -am "chore: release 1.1.0"
git tag v1.1.0 && git push origin main v1.1.0
```

CI refuses to build when a `v*` tag and the version in `pubspec.yaml`
disagree, which is why a build-only release is dispatched rather than tagged —
its tag would already exist. `docs/DEVOPS.md` has the table.

## Working rules

After any change, before handing it over:

```bash
dart format lib test packages/karantin_face_sdk/lib packages/karantin_face_sdk/test
flutter analyze --fatal-infos
flutter test
```

CI runs exactly this gate (`--fatal-infos`, so info-level lints fail too);
anything that does not pass locally will not pass there either.

When native code, a plugin or `pubspec.yaml` changes, also run
`flutter build apk --debug` — `flutter analyze` does not see Gradle or
CocoaPods problems.

## Things worth knowing about this project

- **The folder and the package disagree.** The Dart package, the GitHub repo
  and the app are all `nazorat_aat` / `Nazorat AAT` / `com.nazorat.aat.uz`;
  only the local directory is still `dala_nazorati`, left that way on purpose
  because tooling keys off its absolute path. This paragraph is the only place
  in the repository that still spells the old name, so `git grep` for it should
  return these lines and nothing else.

- **There is no staging backend.** Every build talks to production
  (`dala.efito.uz`, `datahub.karantin.uz`, `id.karantin.uz`). Keep that in
  mind when testing anything that writes data.
- **The repository is public.** `google-services.json`,
  `GoogleService-Info.plist` and `android/key.properties` are all gitignored.
  Never put a secret in the source.
- **Three languages:** `assets/translations/{uz,ru,en}.json`. A new key must
  be added to all three — `test/inspector_role_test.dart` checks this.
- **iOS permission strings** live in English in `Info.plist` with
  `uz`/`ru` localizations under `ios/Runner/*.lproj/InfoPlist.strings`.
  Adding a permission means editing all four files.
- **Shorebird** is configured: a Dart-only fix can ship with
  `shorebird patch`, without the stores.
- **Diagnostics.** `lib/core/observability/diagnostics_log.dart` records every
  network request and sync step to disk and attaches them to crash reports —
  this is how offline failures become visible.

## Code style

Comments are written in **English**, and they explain *why* rather than
*what*. Follow the surrounding code: not "added a timeout", but "without a
timeout Dio waits forever and the dialog spins indefinitely".
