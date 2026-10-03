import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

import '../api/client_api.dart';
import '../detection/face.dart';
import '../detection/frame.dart';
import '../errors.dart';
import '../guidance/pose.dart';
import '../l10n/messages.dart';
import '../options.dart';
import '../result.dart';
import 'ports.dart';

const _holdTime = Duration(milliseconds: 700); // a pose must be held this long before capture
const _recenterHoldTime = Duration(milliseconds: 400); // facing the camera again between turns
const _instructionMinTime = Duration(milliseconds: 1200); // an instruction shows this long before capture can start
const _confirmTime = Duration(milliseconds: 900); // "Got it" pause after each capture
const _guidanceSettle = Duration(milliseconds: 250); // a new hint must persist this long to replace the old one
const _detectInterval = Duration(milliseconds: 60);
const _countdownSeconds = 3; // per step, when on-device detection is unavailable

enum FlowPhase { intro, starting, capturing, paused, submitting, result, error, closed }

/// Which side of the screen the turn arrow points to.
enum ArrowSide { left, right }

/// Runs one verification: session, camera, guided capture, submission, result. The view
/// renders its state; it never talks to the camera or API itself.
class VerificationController extends ChangeNotifier {
  VerificationController({
    required this.apiUrl,
    required this.options,
    required this.dependencies,
    String? clientToken,
    Future<String> Function()? clientTokenProvider,
  }) : assert((clientToken == null) != (clientTokenProvider == null), 'Pass exactly one of clientToken and clientTokenProvider'),
       _fixedToken = clientToken,
       _tokenProvider = clientTokenProvider,
       messages = options.resolvedMessages {
    _speaker = _BoundedSpeaker(dependencies.speaker(options.voice, messages.speechLocale));
    phase = options.instructions ? FlowPhase.intro : FlowPhase.starting;
  }

  final Uri apiUrl;
  final FaceVerificationOptions options;
  final FlowDependencies dependencies;
  final FaceVerificationMessages messages;
  final String? _fixedToken;
  final Future<String> Function()? _tokenProvider;

  late final Speaker _speaker;
  Future<FaceDetector?>? _detectorFuture;
  FaceDetector? _detector;

  // --- View state ------------------------------------------------------------------------------
  late FlowPhase phase;
  int step = 0;
  int totalSteps = 0;
  final Set<int> completedSteps = {};
  String guidance = '';
  bool guidanceGood = false;
  ArrowSide? arrow;
  double progress = 0;
  String busyText = '';
  FaceVerificationResult? result;
  FaceVerificationException? error;

  /// The camera, while it is open (for the preview).
  FrameSource? get frameSource => _source;

  /// How it ended, set synchronously when the flow closes (before listeners are notified):
  /// the last result, or the error the user saw (code `cancelled` if none).
  FaceVerificationResult? closedResult;
  FaceVerificationException? closedError;

  // --- Internals -------------------------------------------------------------------------------
  _Run? _run;
  String? _token;
  ClientApi? _api;
  ClientSession? _session;
  List<StepPose> _poses = const [];
  final List<Uint8List> _photos = [];
  FrameSource? _source;
  StreamSubscription<CameraFrame>? _frameSub;
  CameraFrame? _latestFrame;
  bool _disposed = false;

  /// Starts the flow when there is no intro screen; call from the view once it's mounted.
  void startIfNoIntro() {
    if (phase == FlowPhase.starting && _run == null) unawaited(_attempt());
  }

  /// The intro's Start button.
  void begin() => unawaited(_attempt());

  /// "Try again": the same session after a retryable error, else a fresh session.
  void retry() {
    final needsNewSession = error == null || const {FaceVerificationErrorCode.sessionUsed, FaceVerificationErrorCode.sessionExpired, FaceVerificationErrorCode.invalidToken}.contains(error!.code);
    if (needsNewSession) {
      _token = null;
      _session = null;
    }
    unawaited(_attempt());
  }

  bool get canRetry {
    final e = error;
    final canRefresh = _tokenProvider != null;
    if (phase == FlowPhase.result) return canRefresh;
    if (e == null) return false;
    final needsNewSession = const {FaceVerificationErrorCode.sessionUsed, FaceVerificationErrorCode.sessionExpired, FaceVerificationErrorCode.invalidToken}.contains(e.code);
    return needsNewSession ? canRefresh : e.retryable;
  }

  /// The app went to the background (or another app took the camera): release the camera
  /// and stop speaking. Photos already taken are kept.
  ///
  /// [backgrounded] is false for "inactive", which is also what the system camera-permission
  /// prompt causes: while the camera is being opened that is expected, so it's ignored
  /// (pausing would cancel the request and prompt the user again).
  void pause({bool backgrounded = true}) {
    if (phase != FlowPhase.capturing && phase != FlowPhase.starting) return;
    if (!backgrounded && phase == FlowPhase.starting) return;
    _run?.cancel();
    _run = null;
    unawaited(_speaker.stop());
    unawaited(_closeCamera());
    phase = FlowPhase.paused;
    guidance = messages.paused;
    _notify();
  }

  /// Back in the foreground: reopen the camera and redo the step that was interrupted.
  void resume() {
    if (phase != FlowPhase.paused) return;
    unawaited(_attempt(resume: _session != null));
  }

  /// Leave (close button, back gesture, Done). Settles [done]; safe to call twice.
  void close() {
    if (phase == FlowPhase.closed) return;
    _run?.cancel();
    _run = null;
    unawaited(_speaker.stop());
    unawaited(_closeCamera());
    closedResult = result;
    closedError = result != null ? null : (error ?? const FaceVerificationException(FaceVerificationErrorCode.cancelled, 'The user closed the verification'));
    phase = FlowPhase.closed;
    _notify();
  }

  @override
  void dispose() {
    close();
    _detector?.close();
    _api?.close();
    _disposed = true;
    super.dispose();
  }

  // --- Flow ------------------------------------------------------------------------------------

  Future<void> _attempt({bool resume = false}) async {
    _run?.cancel();
    final run = _run = _Run();
    _detectorFuture ??= dependencies.detector().catchError((Object e) {
      debugPrint('[facera] Face detection unavailable, using timed capture: $e');
      return null;
    });
    error = null;
    result = null;
    if (!resume) {
      _photos.clear();
      completedSteps.clear();
      step = 0;
    }
    _setBusy(FlowPhase.starting, messages.starting);
    try {
      if (!resume || _session == null) {
        await _prepareSession(run);
        if (phase == FlowPhase.result) return; // the session had already finished
      } else {
        await _openCamera();
        run.check();
      }
      await _capture(run);
      await _closeCamera();
      run.check();
      _setBusy(FlowPhase.submitting, messages.submitting);
      unawaited(_speaker.say(messages.submitting, instruction: true));
      final finished = await _api!.verify(List.of(_photos), liveness: _poses.length > 1);
      run.check();
      _showResult(finished.toResult());
    } on _Cancelled {
      // paused or closed; whoever cancelled owns the state
    } on FaceVerificationException catch (e) {
      if (!run.cancelled) _showError(e);
    } catch (e) {
      if (!run.cancelled) _showError(FaceVerificationException(FaceVerificationErrorCode.serviceUnavailable, '$e', e));
    } finally {
      if (identical(_run, run)) {
        _run = null;
        if (phase != FlowPhase.capturing) await _closeCamera();
      }
    }
  }

  Future<void> _prepareSession(_Run run) async {
    final token = await _getToken();
    run.check();
    _api?.close();
    final api = _api = dependencies.api(apiUrl, token);
    final sessionFuture = api.getSession();
    final cameraFuture = _openCamera().then<Object?>((_) => null, onError: (Object e) => e);
    ClientSession session;
    try {
      session = await sessionFuture;
    } finally {
      await cameraFuture; // never leave the camera opening unobserved
    }
    final cameraError = await cameraFuture;
    run.check();
    // The server is the source of truth: e.g. retrying after a lost response shows the
    // stored result instead of capturing again.
    if (session.status.isFinal) {
      await _closeCamera();
      _showResult(session.toResult());
      return;
    }
    if (session.status != FaceSessionStatus.created) {
      throw FaceVerificationException(FaceVerificationErrorCode.sessionUsed, 'Session is ${session.status.name}');
    }
    if (cameraError != null) throw cameraError;
    if (!session.referenceReady) {
      throw const FaceVerificationException(FaceVerificationErrorCode.referenceMissing, 'The session has no reference photo yet');
    }
    if (!options.liveness && session.challenge.isNotEmpty) {
      debugPrint('[facera] This session requires liveness; `liveness: false` is ignored.');
    }
    _session = session;
    _poses = [StepPose.frontal, ...session.challenge.map(StepPose.fromAction)];
    totalSteps = _poses.length;
  }

  /// One step at a time: (after a turn) look back -> instruction -> hold -> capture -> "Got it".
  Future<void> _capture(_Run run) async {
    final detector = _detector = await _detectorFuture;
    run.check();
    phase = FlowPhase.capturing;
    _notify();
    for (; step < _poses.length; step++) {
      final pose = _poses[step];
      final deadline = clock.now().add(options.stepTimeout);
      final afterTurn = step > 0 && _poses[step - 1] != StepPose.frontal;
      CameraFrame frame;
      if (detector != null) {
        if (afterTurn) {
          final spoken = _instruct(messages.lookBack, null);
          await _holdPose(run, StepPose.frontal, detector, deadline, _recenterHoldTime, messages.lookBack);
          await spoken;
          run.check();
        }
        await Future.wait([_instruct(_instructionFor(pose), _arrowFor(pose)), Future<void>.delayed(_instructionMinTime)]);
        run.check();
        frame = await _holdPose(run, pose, detector, deadline, _holdTime, _instructionFor(pose));
      } else {
        if (afterTurn) {
          await Future.wait([_instruct(messages.lookBack, null), Future<void>.delayed(const Duration(milliseconds: 1500))]);
          run.check();
        }
        frame = await _countdown(run, pose);
      }
      _photos.add(await dependencies.encodeJpeg(frame));
      run.check();
      completedSteps.add(step);
      _setGuidance(messages.captured, good: true, arrow: null);
      progress = 1;
      _notify();
      await Future.wait([_speaker.say(messages.captured, instruction: true), Future<void>.delayed(_confirmTime)]);
      run.check();
    }
  }

  Future<void> _instruct(String text, ArrowSide? arrowSide) {
    _setGuidance(text, good: false, arrow: arrowSide);
    progress = 0;
    _notify();
    return _speaker.say(text, instruction: true);
  }

  /// Waits until [pose] is held for [hold]; returns the frame that completed it.
  Future<CameraFrame> _holdPose(_Run run, StepPose pose, FaceDetector detector, DateTime deadline, Duration hold, String instruction) async {
    final tracker = HoldTracker(hold);
    final requested = requestedGuidance(pose);
    var shown = requested;
    (Guidance, DateTime)? pending;
    CameraFrame? analyzed;
    final start = clock.now();
    while (true) {
      run.check();
      final now = clock.now();
      if (now.isAfter(deadline)) {
        throw FaceVerificationException(FaceVerificationErrorCode.stepTimeout, 'Step ${pose.name} was not completed in time');
      }
      final frame = _latestFrame;
      if (frame == null || identical(frame, analyzed)) {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        continue;
      }
      analyzed = frame;
      final List<ObservedFace> faces;
      faces = await detector.detect(frame);
      run.check();
      final verdict = evaluateFrame(faces, pose);
      final at = clock.now();
      if (verdict != shown) {
        if (pending == null || pending.$1 != verdict) pending = (verdict, at);
        if (verdict == Guidance.holdStill || at.difference(pending.$2) >= _guidanceSettle) {
          shown = verdict;
          pending = null;
          final text = verdict == requested ? instruction : messages.guidance[verdict]!;
          _setGuidance(text, good: verdict == Guidance.holdStill, arrow: verdict == Guidance.holdStill ? null : _arrowFor(_poseOf(verdict) ?? pose));
          if (verdict != Guidance.holdStill) unawaited(_speaker.say(text)); // a hint never talks over an instruction
        }
      }
      final held = tracker.update(verdict == Guidance.holdStill, at.difference(start));
      progress = tracker.progress(at.difference(start));
      _notify();
      if (held) return frame;
      await Future<void>.delayed(_detectInterval);
    }
  }

  /// Without on-device detection: show the instruction, count down, capture. The server checks it.
  Future<CameraFrame> _countdown(_Run run, StepPose pose) async {
    final instruction = _instructionFor(pose);
    unawaited(_speaker.say(instruction, instruction: true));
    for (var s = _countdownSeconds; s > 0; s--) {
      _setGuidance('$instruction $s…', good: false, arrow: _arrowFor(pose));
      progress = (_countdownSeconds - s) / _countdownSeconds;
      _notify();
      await Future<void>.delayed(const Duration(seconds: 1));
      run.check();
    }
    while (_latestFrame == null) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      run.check();
    }
    return _latestFrame!;
  }

  // --- Outcomes --------------------------------------------------------------------------------

  void _showResult(FaceVerificationResult outcome) {
    result = outcome;
    error = null;
    phase = FlowPhase.result;
    _notify();
    unawaited(_speaker.say(outcome.passed ? messages.successTitle : messages.failureTitle, instruction: true));
  }

  void _showError(FaceVerificationException e) {
    if (e.code == FaceVerificationErrorCode.cancelled) return;
    error = e;
    phase = FlowPhase.error;
    _notify();
    unawaited(_speaker.say(messages.errors[e.code] ?? messages.errorTitle, instruction: true));
  }

  // --- Resources -------------------------------------------------------------------------------

  Future<void> _openCamera() async {
    if (_source != null) return;
    final source = _source = dependencies.frameSource(options.camera);
    try {
      await source.open();
    } catch (e) {
      if (identical(_source, source)) _source = null;
      await source.close();
      rethrow;
    }
    _frameSub = source.frames.listen((frame) => _latestFrame = frame);
    _notify(); // the preview can show now
  }

  Future<void> _closeCamera() async {
    // Take ownership synchronously, so overlapping calls never release the same camera twice.
    final source = _source, subscription = _frameSub;
    _source = null;
    _frameSub = null;
    _latestFrame = null;
    // Not awaited: cancelling a broadcast-stream subscription can stay pending, and a plain
    // listener holds nothing that needs releasing.
    unawaited(subscription?.cancel());
    if (source != null) await source.close();
  }

  Future<String> _getToken() async {
    final existing = _token;
    if (existing != null) return existing;
    final String token;
    if (_fixedToken != null) {
      token = _fixedToken;
      _checkToken(token);
    } else {
      try {
        token = await _tokenProvider!();
      } catch (e) {
        throw FaceVerificationException(FaceVerificationErrorCode.sessionUnavailable, 'clientTokenProvider failed: $e', e);
      }
      _checkToken(token);
    }
    return _token = token;
  }

  /// Throws for anything but a session client token (e.g. an API key passed by mistake).
  static void checkToken(String token) => _checkToken(token);

  static void _checkToken(String token) {
    if (token.startsWith('fpk_') || !token.startsWith(clientTokenPrefix)) {
      throw const FaceVerificationException(
        FaceVerificationErrorCode.configurationError,
        'Never put an API key in an app. Create a session on your server and pass its client_token (fpct_...).',
      );
    }
  }

  // --- Helpers ---------------------------------------------------------------------------------

  String _instructionFor(StepPose pose) => messages.guidance[requestedGuidance(pose)]!;

  StepPose? _poseOf(Guidance g) => switch (g) {
    Guidance.turnLeft => StepPose.turnLeft,
    Guidance.turnRight => StepPose.turnRight,
    _ => null,
  };

  /// Turns are the person's own left/right; in a mirrored selfie preview their left is on
  /// the screen's left.
  ArrowSide? _arrowFor(StepPose pose) {
    if (pose == StepPose.frontal) return null;
    final mirrored = _source?.previewMirrored ?? options.camera.lens == FaceCameraLens.front;
    final personLeft = pose == StepPose.turnLeft;
    return personLeft == mirrored ? ArrowSide.left : ArrowSide.right;
  }

  void _setGuidance(String text, {required bool good, required ArrowSide? arrow}) {
    guidance = text;
    guidanceGood = good;
    this.arrow = arrow;
  }

  void _setBusy(FlowPhase next, String text) {
    phase = next;
    busyText = text;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }
}

/// Whatever a speaker does, the flow waits at most [_maxSpeech] for it: speech is a nicety
/// and must never block a verification.
class _BoundedSpeaker implements Speaker {
  _BoundedSpeaker(this._inner);
  static const _maxSpeech = Duration(seconds: 8);
  final Speaker _inner;

  @override
  bool get enabled => _inner.enabled;

  @override
  Future<void> say(String text, {bool instruction = false}) =>
      _inner.say(text, instruction: instruction).timeout(_maxSpeech, onTimeout: () {}).catchError((Object _) {});

  @override
  Future<void> stop() => _inner.stop().timeout(const Duration(seconds: 2), onTimeout: () {}).catchError((Object _) {});
}

class _Run {
  bool cancelled = false;
  void cancel() => cancelled = true;
  void check() {
    if (cancelled) throw const _Cancelled();
  }
}

class _Cancelled implements Exception {
  const _Cancelled();
}
