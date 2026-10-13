# Role architecture — Nazorat AAT

Three inspectorates use the same app — plant quarantine, veterinary and the
sanitary-epidemiological service — and a fourth is expected. They share the
login, the profile, the map and the location handling, and diverge in almost
everything else.

**Read this file first whenever a request names an inspectorate** ("this is for
the veterinary role", "karantin uchun"). It says where that code goes and how
it is wired, so one inspectorate's logic can never run for another.

> **Scope.** This file records the boundary and the procedures. It does not
> duplicate Dart code: the repository is the source of truth, and two copies of
> a tab list would drift apart within a week.

---

## The inspectorates

| Inspectorate | `InspectorRole` | Folder | Module | Label key |
|---|---|---|---|---|
| Plant quarantine | `karantin` | `lib/features/karantin/` | `KarantinModule` | `roleKarantinInspector` |
| Veterinary | `veterinary` | `lib/features/veterinary/` | `VeterinaryModule` | `roleVetInspector` |
| Sanitary-epidemiological | `ses` | `lib/features/ses/` | `SesModule` | `roleSesInspector` |
| *role code not recognised* | `null` | — | `SharedOnlyModule` | `roleInspector` |

The role is **never chosen by hand**. It is derived from the `roles` claim in
the access token, so a password login, OneID, Karantin ID and Face ID all land
on the same answer. The backend codes that map onto each inspectorate are in
`kInspectorRoleCodes` (`lib/features/auth/domain/entities/inspector_role.dart`)
— that table is the source of truth; add a new code there rather than relying
on the keyword fallback below it.

`null` is a real case, not a placeholder: `resolveInspectorRole` returns null
instead of guessing, and an inspector in the field cannot wait for the backend
to be fixed. They get the shared screens.

---

## The two rules

**1. Role-specific code lives only in its own folder.** From outside, only its
module may be imported, and only by `lib/core/roles/role_registry.dart`. No
inspectorate ever imports another one.

**2. Shared code never names an inspectorate.** It asks what the user *may do*
(their module, later a capability), never who they are. `InspectorRole` as a
type is fine; `InspectorRole.karantin` in a shared file is not.

Three files are exempt from rule 2, because naming the inspectorates is their
job: `inspector_role.dart` (defines them), `role_registry.dart` (picks the
module, deliberately exhaustive) and `role_badge.dart` (one colour, icon and
label per inspectorate).

Both rules are enforced by `test/role_boundary_test.dart`, which fails with the
offending file name. They are not advice.

---

## How the composition works

```
lib/core/roles/
  role_module.dart        RoleModule contract, RoleTab, RoleShell, ShellLayout
  role_registry.dart      moduleFor(InspectorRole?) — exhaustive switch
  role_controller.dart    the live role, a ValueNotifier
  role_scope.dart         InheritedNotifier above the router
  shared_tabs.dart        weather, map (docked), settings
  shared_only_module.dart fallback for an unrecognised role code
```

`MainPage` (`lib/features/home/presentation/pages/main_page.dart`) is the shell
every inspector lands in. It knows nothing about any inspectorate: it reads the
role, asks `moduleFor` for a module, and builds the navigation from
`module.tabs`. A role whose screens differ needs **no edit there**.

### The role is settled before the first frame

A widget cannot await, so the role is never resolved inside the shell. It is
written to `RoleController` by whoever already knows it, and `RoleScope` —
an `InheritedNotifier` above the router — hands it down synchronously:

| Writer | When |
|---|---|
| `AppRouter._redirect` → `resolveFrom(authRepository)` | cold start, in the `/splash` redirect, next to `hasValidToken()` |
| `LoginPage`'s `AuthAuthenticated` listener | a login, which does not pass through the splash |
| `ProfileCubit.onChange` | `/users/me` answering, and a logout emitting null |

The token is already on disk, so reading it costs nothing on the splash screen
that waits 1.5 s anyway. `resolveFrom` swallows a storage failure on purpose:
the splash is the worst place to throw, an unresolved role means the shared
shell, and `/users/me` corrects it a moment later. `ValueNotifier` ignores a
write that changes nothing, so the usual case — the token and the server
agreeing — costs no rebuild.

`moduleFor` is a `switch` rather than a lookup map on purpose: adding a fourth
value to `InspectorRole` stops compiling until its module exists, instead of
silently dropping that inspector into the shared shell, where nobody would
notice for weeks.

`ShellLayout` holds the index arithmetic. The bar and the `IndexedStack` do not
share an index — the docked tab sits behind the notch and has no bar item — so
bar item 1 can mean tab 2. It is a plain class so the mapping is tested without
a widget tree (`test/role_module_test.dart`).

---

## Procedure: a feature for one inspectorate

Example: a vaccination journal for the veterinary inspector.

1. **Put it in the inspectorate's folder**, structured like any other feature:
   ```
   lib/features/veterinary/
     data/{datasources,models,repositories}/
     domain/{entities,repositories,usecases}/
     presentation/{bloc,pages,widgets}/
     veterinary_module.dart
   ```
2. **Wire it through the module** — this is the only line the navigation needs:
   ```dart
   @override
   List<RoleTab> get tabs => const [vaccinationTab, mapTab, settingsTab];
   ```
   `tabs.first` must not be docked (the shell opens on it) and at most one tab
   may be docked (the bar has one notch).
3. **Translations.** Add every new key to all three of
   `assets/translations/{uz,ru,en}.json`, prefixed with the inspectorate:
   `vetVaccinationTitle`, `karantinActTitle`, `sesSampleTitle`. Keep the keys
   **flat** — `inspector_role_test.dart` compares the top-level key sets of the
   three files, and nesting would hide a missing inner key from it.
4. **Register dependencies** in `lib/core/di/injection.dart` as usual (see the
   role-scope step below for where this is heading).
5. **Never** add a role check to a shared screen to make it fit. If a shared
   screen needs to behave differently, that is step 4 of the plan below — a
   capability — not an `if`.

## Procedure: a shared feature

Only if it is genuinely true for **every** inspectorate, including the
unrecognised-role case. It goes in its own feature folder as today, and if it
needs a tab, into `shared_tabs.dart` so every module can spread it in.

### Deciding which one it is

| Question | Shared | Role-specific |
|---|---|---|
| Would an inspector of another inspectorate open this screen? | yes | no |
| Does the backend endpoint differ per inspectorate? | no | yes |
| Does the form carry different fields per inspectorate? | no | yes |
| Is it about the device — location, map tiles, connection, updates? | yes | — |
| Is it about *who is signed in* rather than *what they inspect*? | yes | — |

When in doubt, start role-specific. Moving one inspectorate's screen into the
shared folder later is an import change; untangling a shared screen that three
inspectorates have grown branches in is not.

---

## What is shared today

| Area | Path |
|---|---|
| Login (password, OneID, Karantin ID, Face ID) | `lib/features/auth/` |
| Profile, settings | `lib/features/profile/`, `lib/features/settings/` |
| Map, location, field drawing | `lib/features/home/`, `lib/features/fields/`, `lib/core/map/` |
| Reference catalogue | `lib/features/reference/` |
| Offline sync | `lib/features/sync/`, `lib/core/storage/` |
| Weather | `lib/features/weather/` |
| Push, updates, downloads, diagnostics | `lib/core/{notifications,update,download,observability}/` |

Step 3 below moves these under `lib/features/shared/`; until then, "not in a
role folder" means shared.

---

## Adding a fourth inspectorate

1. Add the value to `InspectorRole` with its label key, and its backend codes
   to `kInspectorRoleCodes`.
2. Add the label to all three translation files, plus a colour and an icon in
   `role_badge.dart` (`inspector_role_test.dart` requires both to be distinct).
3. Create `lib/features/<name>/<name>_module.dart`.
4. Add the one line to `moduleFor`. The build is broken until you do — that is
   the point.
5. Add the folder name to `_folderFor` in `test/role_boundary_test.dart`.

---

## Where the work stands

| Step | State |
|---|---|
| 1. `RoleModule` skeleton, registry, generic `MainPage` | ✅ done 2026-10-13 — behaviour unchanged, all four modules still declare the same three tabs |
| 2. `RoleController` + `RoleScope`, role resolved in the `/splash` redirect | ✅ done 2026-10-13 |
| 3. Move shared features to `lib/features/shared/`, GetIt role scope | ⏳ next |
| 4. `Capability` enum + role-specific `go_router` routes behind a guard | ⏳ |

**Steps 1 and 2 are what had to land before the inspectorates' tab lists
diverge**, and they have. From here, giving an inspectorate its own screens is
the procedure above and nothing else — no shell change, and no frame with the
wrong navigation on it. `ShellLayout.clamp` still guards the one case the
controller cannot prevent: `/users/me` correcting the role while a tab further
down a shorter module's list is open.

Step 3 also closes a real leak: role-specific blocs registered as global lazy
singletons would survive a logout, so the next inspector to sign in on that
phone could see the previous one's state. The fix is a GetIt scope pushed after
login and popped on logout.

Step 4 is what shared screens use instead of role checks: a capability set on
the module, asked as `context.can(Capability.labSampling)`. It matters because
the backend can give one user several role codes, and `role == ses || role ==
vet` repeated in twenty places is exactly what this architecture exists to
prevent.

---

## Invariants

- `moduleFor` is exhaustive — never a `Map`, never a `default`.
- The role is settled before the shell builds. A fourth place that learns the
  role writes it to `RoleController`; the shell never resolves it itself.
- A module's `tabs.first` is not docked; at most one tab is docked.
- No inspectorate imports another; nothing but the registry imports a module.
- No shared file names an individual inspectorate.
- Every tab's `labelKey` exists, filled, in uz, ru and en.

## The gate

```bash
dart format lib test packages/karantin_face_sdk/lib packages/karantin_face_sdk/test
flutter analyze --fatal-infos
flutter test
```

The role-specific tests are `test/role_module_test.dart` (module and layout
invariants), `test/role_boundary_test.dart` (the two rules) and
`test/role_scope_test.dart` (resolution and hand-down). `ProfileCubit`'s own
test covers the correction path from `/users/me`.
