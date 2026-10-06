## 0.2.0

* Verification checks: sessions verify liveness, face match, or both, as chosen by your server. The SDK captures only what the session needs: no head turns without liveness, and no reference is required without face match.
* New `FaceVerificationOptions.checks` to refuse sessions that skip a check your app expects (`FaceVerificationErrorCode.checksMismatch`).
* `FaceVerificationResult.checks` reports what the session verified.
* `FaceVerificationOptions.liveness` is deprecated; the session's checks decide.
* Homepage is now https://verapass.app/ (create a free account there to get an API key).

## 0.1.0

* Initial release: full-screen and embeddable face verification with on-device guidance, head-turn liveness, spoken instructions, and en/es/fr messages.
