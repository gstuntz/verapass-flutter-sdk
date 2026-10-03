import 'package:flutter/material.dart';

import 'l10n/messages.dart';

/// Which camera to use. The front camera is the default (a selfie flow); the back camera is
/// for an operator verifying someone else.
enum FaceCameraLens { front, back }

/// Capture resolution: [high] (720p) is a good balance of detail and speed on phones.
enum FaceCameraResolution { medium, high, veryHigh }

class FaceCameraOptions {
  const FaceCameraOptions({this.lens = FaceCameraLens.front, this.resolution = FaceCameraResolution.high});
  final FaceCameraLens lens;
  final FaceCameraResolution resolution;
}

/// Colors of the verification screen. Defaults follow the app's [ThemeData]
/// (light or dark), so the screen matches the host app without configuration.
class FaceVerificationTheme {
  const FaceVerificationTheme({this.brightness, this.accentColor, this.backgroundColor, this.textColor});

  /// Force light or dark; null follows the host app's theme.
  final Brightness? brightness;
  final Color? accentColor;
  final Color? backgroundColor;
  final Color? textColor;
}

class FaceVerificationOptions {
  const FaceVerificationOptions({
    this.voice = false,
    this.instructions = true,
    this.liveness = true,
    this.language = 'en',
    this.messages,
    this.theme = const FaceVerificationTheme(),
    this.camera = const FaceCameraOptions(),
    this.stepTimeout = const Duration(seconds: 30),
  });

  /// Speak instructions with the device's built-in text-to-speech. No network voice service.
  final bool voice;

  /// Show the intro screen and on-screen hints. Screen readers always get the hints.
  final bool instructions;

  /// Perform the head-turn liveness challenge when the session has one. The server decides
  /// whether a session requires liveness; when it does, `false` can't skip it.
  final bool liveness;

  /// "en", "es", or "fr" (regional tags like "es-MX" work). Others fall back to English.
  final String language;

  /// Your own text, replacing the built-in messages for [language].
  final FaceVerificationMessages? messages;

  final FaceVerificationTheme theme;
  final FaceCameraOptions camera;

  /// Time allowed for each step before the user is offered a retry.
  final Duration stepTimeout;

  FaceVerificationMessages get resolvedMessages => messages ?? FaceVerificationMessages.forLanguage(language);
}
