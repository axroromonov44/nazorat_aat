# Karantin ID login

Face login against `id.karantin.uz`, replacing the webview flow. The scan,
the capture and the OAuth dance all happen natively; the only thing the app
takes out of it is the authorization `code`, which the Dala backend then
exchanges for a session.

Two hosts are involved, and keeping them apart matters: `id.karantin.uz`
issues the code, `dala.efito.uz` turns it into tokens. Nothing in the app
ever sends a password or a face image to Dala.

## Where the requests are sent from

| Class | File | Talks to |
| --- | --- | --- |
| `KarantinFaceRemoteDataSource` | `packages/karantin_face_sdk/lib/src/karantin_face_remote_datasource.dart` | `id.karantin.uz/app` — every Karantin ID request |
| `KarantinFaceAuthPage` | `packages/karantin_face_sdk/lib/src/karantin_face_auth_page.dart` | orchestrates the data source; sends nothing itself |
| `KarantinDeviceData` | `packages/karantin_face_sdk/lib/src/karantin_device_data.dart` | builds the device fields every submit carries |
| `AuthRemoteDataSource.loginKarantin` | `lib/features/auth/data/datasources/auth_remote_datasource.dart` | `dala.efito.uz/api/v1` — the code exchange |

`KarantinFaceRemoteDataSource` is the single place that reaches Karantin ID.
If a request needs to change, it changes there and nowhere else.

## Configuration

- `KarantinIdConfig` — `lib/core/constants/karantin_config.dart`: the client
  id (`dala_nazorat_muucpk`), the scope and the redirect URI
  (`https://dala.efito.uz/api/v1/auth/one-id/callback`). The app's own values.
- `KarantinFaceConfig` — `packages/karantin_face_sdk/lib/src/karantin_face_config.dart`:
  the SDK's side of the same parameters, plus `baseUrl`
  (`https://id.karantin.uz`), the accent colour and the Uzbek strings. The API
  lives under `$baseUrl/app`, which is what `apiBaseUrl` returns.

The package is reusable, so it holds no Dala constants — the caller passes
them in. `login_form.dart` is where the two meet.

## The endpoints

All paths are relative to `https://id.karantin.uz/app`.

| Method | Path | Called by | Purpose |
| --- | --- | --- | --- |
| `GET` | `/project/oauth/authorize` | `startSession()` | Opens the OAuth session. Answers with a 302 whose `Location` is an SPA route; the route decides the flow and carries `token`/`name` (login, verify-document) or `code`/`state` (register). |
| `POST` | `/project/notify/login/` | `notifyLogin()` | Tells the backend which identifier is about to be used. Best-effort — a failure here must not block the scan. |
| `POST` | `/project/oauth/login` | `submitLogin()` | The face submit. Multipart: `token`, `pinfl` or `passport_number`, `face_image`, up to four `check_image1..4`, plus the device fields. |
| `POST` | `/project/oauth/register` | `submitRegister()` | Same multipart body, with `one_code` instead of the identifier. |
| `POST` | `/project/oauth/verify-doc` | `submitVerifyDocument()` | Same again, with `token` only. |

Each submit answers with `redirect_to`, not with a code. `followToCode()`
then walks the `Location` chain — at most ten hops — until a URL starts with
the configured `redirectUri`, and reads `?code=` off it. Ten is a stop, not a
target: without it a redirect loop would hang the dialog forever.

## Two Dio clients, one cookie jar

`KarantinFaceRemoteDataSource` holds two clients on purpose:

- `_dio` — base URL `$baseUrl/app`, 30s timeouts, `Accept-Language: uz`. The
  normal calls.
- `_redirectDio` — `followRedirects: false`, and `validateStatus` accepts
  3xx. The flow *is* the redirects, so they have to arrive as responses
  instead of being resolved away by Dio.

Both share one `CookieJar`. The OAuth session lives in that cookie: if the
redirect walk used a jar of its own, `authorize` and the submit would be two
unrelated sessions and the code would never be issued.

## Device fields

`KarantinDeviceData` sends `device_id`, `finger_print`, `device`, `browser`,
`network` and, when a location is known, `latitude` and `longitude`. The id
and the fingerprint are generated once and persisted under
`karantin_device_id` / `karantin_device_fingerprint`, because a device that
reports a new identity on every login looks to the backend like a new device
every time.

## After the code

```
login_form.dart  KarantinFace.authenticate(...)      -> code
      |
AuthBloc          AuthKarantinLoginRequested(code)
      |
KarantinLoginUseCase -> AuthRepositoryImpl.loginWithKarantinCode
      |
AuthRemoteDataSource.loginKarantin
      |
GET https://dala.efito.uz/api/v1/users/login/karantin?code=...
```

`/users/login/karantin` is listed in `_isAuthEndpoint`
(`lib/core/network/dio_service.dart`), so the interceptor attaches no
`Authorization` header and does not try to refresh on a 401 — at this point
there is no session yet to refresh.

## Testing notes

- There is no staging Karantin ID. Every run authenticates against production
  with a real passport or PINFL.
- `debugLogging` on `KarantinFaceConfig` logs request and response bodies; it
  is wired to `kDebugMode` in `login_form.dart` so release builds stay quiet.
- The capture is still un-mirrored while the preview is mirrored, which is the
  one known open item in this flow.
