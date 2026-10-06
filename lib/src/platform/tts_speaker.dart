import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../flow/ports.dart';

/// Spoken instructions with the device's own text-to-speech (AVSpeechSynthesizer on iOS,
/// TextToSpeech on Android): free, on-device voices, no network service.
class TtsSpeaker implements Speaker {
  TtsSpeaker._(this._tts, this._locale);

  /// A speaker for [locale], or a silent one when voice is off.
  static Speaker create(bool enabled, String locale) => enabled ? TtsSpeaker._(FlutterTts(), locale) : const SilentSpeaker();

  final FlutterTts _tts;
  final String _locale;
  Future<void>? _setup;
  bool _instructionPlaying = false;
  String _last = '';
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  bool get enabled => true;

  /// Platform speech engines can be missing or never answer (some Android devices and
  /// emulators). Every call is time-limited so speech can never stall a verification.
  static Future<void> _limited(Future<dynamic> call, Duration limit) =>
      call.then((_) {}).timeout(limit, onTimeout: () {}).catchError((Object e) => debugPrint('[verapass] Text-to-speech: $e'));

  Future<void> _ensureSetup() => _setup ??= () async {
    const limit = Duration(seconds: 2);
    await _limited(_tts.awaitSpeakCompletion(true), limit);
    final available = await _tts.isLanguageAvailable(_locale).timeout(limit, onTimeout: () => false).catchError((_) => false);
    if (available == true) await _limited(_tts.setLanguage(_locale), limit);
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      // Play instructions even with the ring/silent switch on, mixed with other audio.
      await _limited(_tts.setIosAudioCategory(IosTextToSpeechAudioCategory.playback, [IosTextToSpeechAudioCategoryOptions.mixWithOthers]), limit);
    }
  }();

  @override
  Future<void> say(String text, {bool instruction = false}) async {
    final now = DateTime.now();
    if (!instruction && (_instructionPlaying || (text == _last && now.difference(_lastAt) < const Duration(seconds: 4)))) return;
    _last = text;
    _lastAt = now;
    try {
      await _ensureSetup();
      await _limited(_tts.stop(), const Duration(seconds: 1));
      _instructionPlaying = instruction;
      // Completes when speech ends (or after a generous estimate of its length).
      await _limited(_tts.speak(text), Duration(milliseconds: 1500 + text.length * 90));
    } finally {
      if (instruction) _instructionPlaying = false;
    }
  }

  @override
  Future<void> stop() async {
    _instructionPlaying = false;
    await _limited(_tts.stop(), const Duration(seconds: 1));
  }
}

class SilentSpeaker implements Speaker {
  const SilentSpeaker();

  @override
  bool get enabled => false;

  @override
  Future<void> say(String text, {bool instruction = false}) async {}

  @override
  Future<void> stop() async {}
}
