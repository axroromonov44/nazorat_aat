# karantin_face_sdk

**Karantin ID uchun native Flutter Face ID kirish.** Webview ichidagi yuz
skanerini on-device kamera + ML Kit oqimi bilan almashtiradi: OAuth sessiyasini
ochadi, foydalanuvchini yuz skaneridan o'tkazadi, rasmlarni Karantin ID
backendiga yuboradi, redirect zanjirini kuzatadi va ilovaga avtorizatsiya
**`code`**ini qaytaradi.

- On-device yuz aniqlash (Google ML Kit) — yuz ma'lumoti rasmiy Karantin ID
  backendiga yuborilgan rasmlardan boshqa hech qayerga ketmaydi.
- Passiv liveness (tabiiy harakat / ko'z pirpirashi / bosh burchagi) —
  foydalanuvchidan **hech qachon** burilish yoki ko'z pirpiratishni so'ramaydi.
- Eng sifatli kadrni tanlash + rasm siqish (zaif internet uchun kichik yuklama).
- Qurilma bog'lanishi (device id, fingerprint, GPS) — inspektor anti-fraud uchun.
- Platformaga mos kamera-ruxsat dialoglari (iOS'da Cupertino, Android'da
  Material).

## O'rnatish

Paketni `pubspec.yaml`ga path (yoki git) dependency sifatida qo'shing:

```yaml
dependencies:
  karantin_face_sdk:
    path: packages/karantin_face_sdk
    # yoki git orqali:
    # git:
    #   url: https://github.com/axroromonov44/nazorat_aat.git
    #   path: packages/karantin_face_sdk
```

So'ng `flutter pub get`.

### Platforma sozlamalari

**Android** — `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.CAMERA"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
```

`minSdkVersion` **21+** bo'lishi shart.

**iOS** — `ios/Runner/Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>Yuzni tasdiqlash uchun kamera kerak</string>
<key>NSLocationWhenInUseUsageDescription</key>
<string>Tasdiqlash joyini qayd etish uchun joylashuv kerak</string>
```

## Foydalanish

```dart
import 'package:karantin_face_sdk/karantin_face_sdk.dart';

final code = await KarantinFace.authenticate(
  context,
  config: const KarantinFaceConfig(
    clientId: 'your_client_id',
    redirectUri: 'https://your.app/callback',
    // baseUrl: 'https://id.karantin.uz', // standart
    // authType: 'login',                 // standart
    primaryColor: Color(0xFF2E7D32),
    // Log va diagnostika sizniki: paket o'zi hech narsa yozmaydi.
    // interceptors: [MyLogInterceptor()],
  ),
);

if (code != null) {
  // `code`ni backendingizda tokenlarga almashtiring (webview redirectidagidek).
}
```

Yoki sahifani to'g'ridan-to'g'ri oching:

```dart
final code = await Navigator.of(context).push<String?>(
  MaterialPageRoute(
    builder: (_) => KarantinFaceAuthPage(config: config),
  ),
);
```

### Matnlarni tarjima qilish

Har bir matnning o'zbekcha standarti bor; `strings:` orqali o'zgartiring:

```dart
KarantinFaceConfig(
  clientId: '…',
  redirectUri: '…',
  strings: KarantinFaceStrings(
    formTitle: 'Yuz orqali kirish',
    continueButton: 'Davom etish',
  ),
)
```

## Qanday ishlaydi

1. `GET /app/project/oauth/authorize` → redirectdan `token`/`name` (yoki
   `code`/`state`) olinadi.
2. Passport / PNFL kiritiladi, so'ng yuz skaneri ishga tushadi.
3. `POST /app/project/oauth/{login,register,verify-doc}` — `face_image` +
   `check_image1..4` + qurilma maydonlari yuboriladi.
4. `redirect_to` kuzatilib `redirectUri?code=…` ga yetguncha boriladi va kod
   qaytariladi.

So'rovlar orasida bitta cookie jar ulashilади — OAuth sessiyasi brauzer
sessiyasidek ishlaydi.

## Litsenziya

Nazorat AAT / Karantin ID loyihasi uchun ichki foydalanish.
