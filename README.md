# veraPass (Flutter)

Face verification for Flutter apps on iOS and Android: camera, on-device guidance, the head-turn
liveness check, spoken instructions, and the result. It uses the same API and flow as the web SDK.

## Get an API key

To get an API key, visit [verapass.app](https://verapass.app/) and create a free account.
Create a project, then an API key under **API keys**. Keep the key on your server: the app
never holds it.

## How it fits together

There's no API key in the app. Anything shipped inside an app can be extracted, so the app only
ever gets a **session client token**.

```
your server ──API key──► POST /api/v1/sessions {checks} (+ /reference)  → client_token (fpct_…)
your app    ──────────► FaceVerification.start(clientTokenProvider: …)   camera, guidance, liveness
your server ──API key──► GET /api/v1/sessions/{id}                       the result you act on
```

## Checks: liveness, face match, or both

Each session verifies `liveness` (head-turn challenge and anti-spoofing), `face_match`
(compare with the reference photo your server uploaded), or both. Your server picks them when
it creates the session (`{"checks": ["liveness"]}`), within what its API key allows (set per
key in the dashboard). Omit `checks` to run every check the key allows. The SDK follows the
session:

| Session checks | What the user does | Reference needed |
|---|---|---|
| `liveness` + `face_match` | Look at the camera, then turn their head as asked | Yes |
| `liveness` | Look at the camera, then turn their head as asked | No |
| `face_match` | One photo looking at the camera | Yes |

The app can't change a session's checks. To make sure it never runs a session weaker than you
expect, set `FaceVerificationOptions(checks: {FaceCheck.liveness, FaceCheck.faceMatch})`: a
session that skips any of them fails with `checksMismatch`.

## Strictness: how sure the check must be

Each project chooses how strict face match and liveness are: **Standard** (default),
**Strict**, or **Very strict** (Dashboard → Projects → your project). Your server can raise
it for one session, for example before a large payout:

```json
{"checks": ["liveness", "face_match"], "match_strictness": "very_strict"}
```

| Level | Face match | Liveness |
|---|---|---|
| Standard | Balanced; recommended for most sign-ups | Stops printed photos and most screen replays |
| Strict | Needs a closer match; more retries with old or low-quality reference photos | Every photo must look clearly live; more retries in poor lighting |
| Very strict | For high-risk actions; noticeably more retries | Rejects anything not unmistakably live; good lighting matters |

Stricter settings reject more impostors and spoofs, and ask more real people to try again.
They can only make checks harder to pass than the defaults, never easier, and can't be
lowered for a session.

**What changes in the SDK:** nothing in the flow. The user takes the same photos; a strict
session is just more likely to end with `not_matched` or `liveness_failed`. The on-screen
messages stay the same (they never reveal scores or thresholds). If many of your users
retry, check the session details in the dashboard: each session shows the strictness and
threshold that decided it. Advise users to face a window or lamp, remove hats and glasses,
and hold still.

## Usage

```dart
import 'package:verapass/verapass.dart';

final result = await FaceVerification.start(
  context,
  apiUrl: Uri.parse('https://api.example.com'),
  // Called for each attempt (so the user can retry). Your server returns a client token.
  clientTokenProvider: () => myBackend.startFaceVerification(),
  options: const FaceVerificationOptions(voice: true),
);
if (result.passed) await myBackend.confirmFaceVerification(result.sessionId); // confirm server-side
```

`start` opens a full-screen verification and completes when the user closes it. It throws
`FaceVerificationException` if they leave without a result: code `cancelled`, or the error they saw
(for example `cameraDenied`).

To place the screen in your own layout or route, embed the view instead:

```dart
FaceVerificationView(
  apiUrl: Uri.parse('https://api.example.com'),
  clientTokenProvider: myBackend.startFaceVerification,
  onResult: (result) {/* each attempt's result, shown to the user */},
  onClose: (outcome) {/* outcome.result or outcome.error; camera and speech already released */},
)
```

One view is one verification. To start a new one in the same place, give it a new `key`
(for example `UniqueKey()`), otherwise Flutter keeps the existing screen.

### Public API

| | |
|---|---|
| `FaceVerification.start(context, apiUrl:, clientToken: \| clientTokenProvider:, options:)` | Full-screen flow. Returns a `FaceVerificationResult`. |
| `FaceVerificationView(...)` | The same screen as a widget, with `onResult`, `onError`, and `onClose`. |
| `FaceVerificationResult` | `sessionId`, `passed`, `status` (`FaceSessionStatus`), `checks` (`Set<FaceCheck>`), `failureCode` (`FaceFailureCode`), `failureFrame`. **Not proof**: confirm on your server. |
| `FaceVerificationException` | `code` (`FaceVerificationErrorCode`), `message`, `retryable`. |
| `FaceVerificationOptions` | See below. |
| `FaceVerificationMessages` | All user-facing text. `.en`, `.es`, `.fr`, or your own (`copyWith`). |

Use `clientToken: 'fpct_…'` for a single session (no retry after a result), or
`clientTokenProvider` to allow retries. An API key (`fpk_…`) is refused.

### Options

| Option | Default | |
|---|---|---|
| `voice` | `false` | Spoken instructions with the device's own text-to-speech (no network voice service). |
| `instructions` | `true` | Intro screen and on-screen hints. When off, screen readers still announce the hints. |
| `checks` | session's | Checks your app expects (`FaceCheck.liveness`, `FaceCheck.faceMatch`). What's captured follows the session; a session missing one fails with `checksMismatch`. |
| `liveness` | `true` | Deprecated: the session's checks decide. `false` is ignored with a debug warning. |
| `language` | `'en'` | `en`, `es`, or `fr` (regional tags like `es-MX` work); others fall back to English. |
| `messages` | | Your own text, replacing the built-in language. |
| `theme` | follows app | `FaceVerificationTheme(brightness:, accentColor:, backgroundColor:, textColor:)`. |
| `camera` | front, 720p | `FaceCameraOptions(lens: front \| back, resolution: medium \| high \| veryHigh)`. |
| `stepTimeout` | 30 s | Time per step before the user is offered a retry. |

## Platform requirements

| | |
|---|---|
| Flutter / Dart | Flutter 3.44+, Dart 3.12+ |
| iOS | 15.0+ (real device for the camera; the Simulator has no camera) |
| Android | minSdk 24 (Android 7.0+) |

### iOS setup

Add to `ios/Runner/Info.plist`:

```xml
<key>NSCameraUsageDescription</key>
<string>The camera is used to verify your identity with a few photos of your face.</string>
```

The SDK never records audio, so it never asks for the microphone, and
`NSMicrophoneUsageDescription` isn't needed. The camera plugin does contain audio-capture code,
though. If App Store Connect ever reports a missing microphone purpose string (ITMS-90683), add the
key with a truthful description (for example "Not used").

### Android setup

The `camera` plugin declares the camera permission for you. It also declares microphone and
legacy-storage permissions for video recording, which this SDK never does. Remove them in
`android/app/src/main/AndroidManifest.xml`:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools">
    <uses-permission android:name="android.permission.RECORD_AUDIO" tools:node="remove" />
    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" tools:node="remove" />
```

**Known issue:** `tflite_flutter` 0.12 sets Java 11 while current Android Gradle Plugin versions
compile Kotlin for 17. Until it's fixed, add this to `android/gradle.properties`:

```
kotlin.jvm.target.validation.mode=warning
```

### Permissions

| Permission | Platform | Asked | Why |
|---|---|---|---|
| Camera | iOS, Android | When the verification opens the camera | Photos of the face |
| Internet | Android (declared) | Never (install-time) | The API |
| Microphone | Neither | Never | Not used (`enableAudio: false`) |
| Storage, location, contacts, … | Neither | Never | Not used |

If the user denies the camera, the screen explains how to enable it in Settings, and
`FaceVerificationErrorCode.cameraDenied` is reported. The system permission prompt doesn't
interrupt the flow.

## Behaviour

- **One step at a time.** Look at the camera, then turn your head one way, look back, and turn
  the other way. Each instruction is shown (and spoken) before capture can start, followed by a
  "Got it" pause.
- **On-device guidance.** MediaPipe's BlazeFace model, the same one the web SDK uses, runs on the
  open-source TensorFlow Lite runtime. Images never leave the device for detection, and nothing is
  sent to Google: no ML Kit, no telemetry. The server re-checks every photo.
- **Photos.** The submitted photos are the exact camera frames that passed guidance, made upright
  and un-mirrored (the server's convention), encoded as JPEG in a background isolate. Nothing is
  stored on the device.
- **Lifecycle.** Going to the background releases the camera and pauses. Photos already taken are
  kept, and the interrupted step restarts when the user returns.
- **Speech.** Speech never blocks the flow, even on devices with a missing or unresponsive speech
  engine.
- **Orientation.** The screen is held in portrait while it's open. Your app's settings are restored
  afterwards.

## Package structure

```
lib/
  verapass.dart             public API (everything else is internal)
  testing.dart              test hooks: replace the camera, detector, and speech in tests
  src/
    face_verification.dart  FaceVerification.start
    options.dart, result.dart, errors.dart, l10n/messages.dart
    ui/                     the verification screen (FaceVerificationView)
    flow/                   VerificationController (state machine), ports (interfaces)
    detection/              BlazeFace decoder, camera frame conversion (rotation, mirroring, JPEG)
    guidance/               pose and hint rules, the same as the web SDK
    api/                    client-token API client
    platform/               camera plugin, TensorFlow Lite, text-to-speech implementations
assets/blaze_face_short_range.tflite   (230 KB, Apache 2.0)
example/                    "Demo Bank" app + on-device integration tests
test/                       unit and flow tests (decoder against reference outputs, full flow)
```

## Testing

```bash
flutter test                                    # unit + flow tests
cd example
flutter test integration_test/sdk_test.dart -d <device> \
  --dart-define=DEMO_SERVER=http://10.0.2.2:5181     # Android emulator (iOS simulator: http://localhost:5181)
```

The integration tests run the real SDK on the device against the real API. They use real
TensorFlow Lite detection, speech, and encoding, with recorded frames standing in for the camera.
They need the demo server (`web-sdk/demo/server.mjs`) running on your computer.
