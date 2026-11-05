## 0.3.1

* Docs: create a free account at https://app.verapass.app/signup to get an API key.

## 0.3.0

* Liveness video for review: when the session asks for it (`record_video`, set by projects that keep photos and video), the SDK records a short, low-bitrate clip (about 250 kbps) of the head-turn steps and sends it with the photos. It never affects the result, and nothing is recorded otherwise.
* Accepts the new `vpct_` client tokens (and still `fpct_` ones), and refuses the new `vp_live_` API keys like the old `fpk_` ones.

## 0.2.2

* Each verification reports which SDK version and platform completed it, so the dashboard can show where every session was done.

## 0.2.1

* Docs: strictness presets (Standard, Strict, Very strict), what they mean for your users, and how to read a rejection.

## 0.2.0

* Verification checks: sessions verify liveness, face match, or both, as chosen by your server. The SDK captures only what the session needs: no head turns without liveness, and no reference is required without face match.
* New `FaceVerificationOptions.checks` to refuse sessions that skip a check your app expects (`FaceVerificationErrorCode.checksMismatch`).
* `FaceVerificationResult.checks` reports what the session verified.
* `FaceVerificationOptions.liveness` is deprecated; the session's checks decide.
* Homepage is now https://verapass.app/ (create a free account there to get an API key).

## 0.1.0

* Initial release: full-screen and embeddable face verification with on-device guidance, head-turn liveness, spoken instructions, and en/es/fr messages.
