import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:verapass/verapass.dart';
import 'package:verapass/src/api/client_api.dart';
import 'package:verapass/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// --- Fakes ----------------------------------------------------------------------------------

/// "follow": does what the screen says (after a human reaction time). "stuck": turns once
/// and stays turned. Others are fixed scenes.
enum Scene { follow, stuck, none, two, frozen }

class FakeCamera implements FrameSource {
  FakeCamera(this.log, {this.openError, this.openDelay = Duration.zero});
  final List<String> log;
  final Object? openError;

  /// How long opening takes, e.g. while the system permission prompt is up.
  final Duration openDelay;
  final _frames = StreamController<CameraFrame>.broadcast();
  Timer? _timer;
  bool closed = false;
  static final _frame = CameraFrame(width: 2, height: 2, format: FrameFormat.rgb888, planes: [FramePlane(Uint8List(12), bytesPerRow: 6, bytesPerPixel: 3)]);

  @override
  Future<void> open() async {
    log.add('open');
    await Future<void>.delayed(openDelay);
    if (openError != null) throw openError!;
    // A fresh frame object every 33 ms, like a 30 fps camera.
    _timer = Timer.periodic(const Duration(milliseconds: 33), (_) => _frames.add(CameraFrame(width: 2, height: 2, format: FrameFormat.rgb888, planes: _frame.planes)));
  }

  @override
  Stream<CameraFrame> get frames => _frames.stream;
  @override
  Widget buildPreview(BuildContext context) => const ColoredBox(color: Colors.black);
  @override
  bool get previewMirrored => true;
  @override
  double? get previewAspectRatio => 9 / 16;

  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    log.add('close');
    _timer?.cancel();
    unawaited(_frames.close());
  }
}

String _onScreen() => find.byType(Text).evaluate().map((e) => (e.widget as Text).data ?? '').join(' | ');

class FakeUser implements FaceDetector {
  FakeUser(this.scene);
  final Scene scene;
  String pose = 'frontal';
  String _seen = '';
  DateTime _since = DateTime(2000);

  ObservedFace _face(String p) {
    final yaw = switch (p) { 'left' => 0.4, 'right' => -0.4, _ => 0.0 };
    return ObservedFace(
      box: const NormalizedBox(0.3, 0.3, 0.4, 0.3),
      score: 0.95,
      eyeA: const NormalizedPoint(0.45, 0.4),
      eyeB: const NormalizedPoint(0.55, 0.4),
      nose: NormalizedPoint(0.5 + yaw * 0.1, 0.45),
    );
  }

  /// Takes the pose the screen asks for, ~300 ms after the instruction appears.
  void _react() {
    final text = _onScreen();
    final now = clock.now();
    if (text != _seen) {
      _seen = text;
      _since = now;
    }
    if (now.difference(_since) < const Duration(milliseconds: 300)) return;
    if (scene == Scene.stuck && pose != 'frontal') return;
    // Understands the English and Spanish instructions.
    if (RegExp(r'look (back|directly)|mira directamente|vuelve a mirar', caseSensitive: false).hasMatch(text)) pose = 'frontal';
    if (RegExp('to the left|hacia la izquierda').hasMatch(text)) pose = 'left';
    if (RegExp('to the right|hacia la derecha').hasMatch(text)) pose = 'right';
  }

  @override
  Future<List<ObservedFace>> detect(CameraFrame frame) async {
    switch (scene) {
      case Scene.none:
        return const [];
      case Scene.two:
        return [_face('frontal'), _face('frontal')];
      case Scene.frozen:
        return [_face('frontal')];
      case Scene.follow || Scene.stuck:
        _react();
        return [_face(pose)];
    }
  }

  @override
  void close() {}
}

/// A speech engine that never answers (seen on an Android emulator).
class HangingSpeaker extends FakeSpeaker {
  HangingSpeaker() : super(true);
  @override
  Future<void> say(String text, {bool instruction = false}) => Completer<void>().future;
  @override
  Future<void> stop() => Completer<void>().future;
}

class FakeSpeaker implements Speaker {
  FakeSpeaker(this.enabled);
  @override
  final bool enabled;
  final spoken = <String>[];
  int stops = 0;

  @override
  Future<void> say(String text, {bool instruction = false}) async {
    if (!enabled) return;
    spoken.add(text);
    await Future<void>.delayed(Duration(milliseconds: text.length * 40)); // speaking takes time
  }

  @override
  Future<void> stop() async => stops++;
}

/// The client-token endpoints, in memory.
class FakeServer {
  FakeServer({this.challenge = const ['turn_left', 'turn_right'], this.referenceReady = true, this.checks});
  final List<String> challenge;
  final List<String>? checks; // null: an older server that doesn't report checks
  final bool referenceReady;
  String status = 'created';
  String verifyStatus = 'verification_passed';
  String? failureCode;
  int? verifyError;
  final posts = <(String token, List<String> fields)>[];
  final tokensSeen = <String>[];

  Map<String, Object?> _session() => {
    'id': 'session-1',
    'status': status,
    'checks': ?checks,
    'challenge': challenge.isEmpty ? null : challenge,
    'expires_at': null,
    'completed_at': null,
    'reference_ready': referenceReady,
    'failure_code': failureCode,
    'failure_frame': null,
  };

  http.Client client() => MockClient((request) async {
    final token = request.headers['X-Client-Token'] ?? '';
    tokensSeen.add(token);
    if (!token.startsWith('fpct_')) return http.Response('{"detail":"Invalid or missing client token"}', 401);
    if (request.method == 'POST') {
      final fields = RegExp(r'name="(\w+)"').allMatches(utf8.decode(request.bodyBytes, allowMalformed: true)).map((m) => m.group(1)!).toList();
      posts.add((token, fields));
      if (verifyError != null) return http.Response('{"detail":"boom"}', verifyError!);
      status = verifyStatus;
    }
    return http.Response(jsonEncode(_session()), 200);
  });
}

class Harness {
  Harness({this.scene = Scene.follow, Object? cameraError, bool hangingSpeech = false, Duration cameraOpenDelay = Duration.zero, FakeServer? server})
    : server = server ?? FakeServer() {
    user = FakeUser(scene);
    faceVerificationDependencies = FlowDependencies(
      frameSource: (_) {
        final camera = FakeCamera(cameraLog, openError: cameraError, openDelay: cameraOpenDelay);
        cameras.add(camera);
        return camera;
      },
      detector: () async => user,
      speaker: (enabled, _) => speaker = hangingSpeech ? HangingSpeaker() : FakeSpeaker(enabled),
      encodeJpeg: (frame) async => Uint8List.fromList([1, 2, 3]),
      api: (url, token) => ClientApi(url, token, client: this.server.client()),
    );
  }

  final Scene scene;
  final FakeServer server;
  late final FakeUser user;
  late FakeSpeaker speaker;
  final cameraLog = <String>[];
  final cameras = <FakeCamera>[];
  final results = <FaceVerificationResult>[];
  final errors = <FaceVerificationException>[];
  FaceVerificationOutcome? outcome;

  Widget view({String? token = 'fpct_token1', Future<String> Function()? provider, FaceVerificationOptions options = const FaceVerificationOptions()}) => MaterialApp(
    home: FaceVerificationView(
      apiUrl: Uri.parse('https://api.test'),
      clientToken: provider == null ? token : null,
      clientTokenProvider: provider,
      options: options,
      onResult: results.add,
      onError: errors.add,
      onClose: (o) => outcome = o,
    ),
  );
}

/// Shows the view and taps Start on the intro screen.
Future<void> open(WidgetTester tester, Widget view) async {
  await tester.pumpWidget(view);
  await tester.pump();
  await tester.tap(find.byType(FilledButton)); // Start, in any language
  await tester.pump();
}

/// Removes the view mid-flow and lets its last timers run out.
Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 2));
}

Future<void> advance(WidgetTester tester, Duration total) async {
  const step = Duration(milliseconds: 50);
  for (var t = Duration.zero; t < total; t += step) {
    await tester.pump(step);
  }
}

// --- Tests ----------------------------------------------------------------------------------

void main() {
  tearDown(() => faceVerificationDependencies = null);

  testWidgets('success: guides through each step, submits the photos in order, cleans up', (tester) async {
    final h = Harness();
    await open(tester, h.view());
    await advance(tester, const Duration(seconds: 15));

    expect(find.text('Verification complete'), findsOneWidget);
    expect(h.server.posts.single.$2, ['frames', 'frames', 'frames']);
    expect(h.cameraLog, ['open', 'close']); // camera released before submitting
    expect(h.results.single.passed, isTrue);

    await tester.tap(find.text('Done'));
    await tester.pump();
    expect(h.outcome!.result!.passed, isTrue);
  });

  testWidgets('one probe photo for sessions without a liveness challenge', (tester) async {
    final h = Harness(server: FakeServer(challenge: const []));
    await open(tester, h.view());
    await advance(tester, const Duration(seconds: 8));

    expect(h.server.posts.single.$2, ['probe']);
  });

  testWidgets('face_match only: one probe photo, reported in the result', (tester) async {
    final h = Harness(server: FakeServer(checks: const ['face_match'], challenge: const []));
    await open(tester, h.view());
    await advance(tester, const Duration(seconds: 8));

    expect(h.server.posts.single.$2, ['probe']);
    expect(h.results.single.checks, {FaceCheck.faceMatch});
  });

  testWidgets('liveness only: head-turn photos, no reference needed', (tester) async {
    final h = Harness(server: FakeServer(checks: const ['liveness'], referenceReady: false));
    await open(tester, h.view());
    await advance(tester, const Duration(seconds: 15));

    expect(find.text('Verification complete'), findsOneWidget);
    expect(h.server.posts.single.$2, ['frames', 'frames', 'frames']);
    expect(h.results.single.checks, {FaceCheck.liveness});
  });

  testWidgets('face_match sessions still need the reference', (tester) async {
    final h = Harness(server: FakeServer(checks: const ['liveness', 'face_match'], referenceReady: false));
    await open(tester, h.view());
    await advance(tester, const Duration(milliseconds: 500));

    expect(find.textContaining("isn't ready yet"), findsOneWidget);
    expect(h.server.posts, isEmpty);
  });

  testWidgets('refuses a session that skips a check the app expects', (tester) async {
    final h = Harness(server: FakeServer(checks: const ['face_match'], challenge: const []));
    await open(tester, h.view(options: const FaceVerificationOptions(checks: {FaceCheck.liveness, FaceCheck.faceMatch})));
    await advance(tester, const Duration(milliseconds: 500));

    expect(find.textContaining("isn't set up correctly"), findsOneWidget);
    expect(h.server.posts, isEmpty);
    expect(h.cameras.every((c) => c.closed), isTrue);
  });

  testWidgets('intro screen first when instructions are on', (tester) async {
    final h = Harness();
    await tester.pumpWidget(h.view(options: const FaceVerificationOptions()));
    await tester.pump();
    expect(find.text('Verify your identity'), findsWidgets);
    expect(find.text('Be the only person in view'), findsOneWidget);
    expect(h.cameraLog, isEmpty);

    await tester.tap(find.text('Start'));
    await advance(tester, const Duration(seconds: 15));
    expect(find.text('Verification complete'), findsOneWidget);
  });

  testWidgets('instructions off: no intro, no on-screen hints, screen readers still get them', (tester) async {
    final handle = tester.ensureSemantics();
    final h = Harness(scene: Scene.none);
    await tester.pumpWidget(h.view(options: const FaceVerificationOptions(instructions: false)));
    await advance(tester, const Duration(seconds: 3));

    expect(find.text('Start'), findsNothing);
    expect(find.text('Position your face in the oval.'), findsNothing);
    expect(find.bySemanticsLabel('Position your face in the oval.'), findsOneWidget);
    handle.dispose();
    await unmount(tester);
  });

  testWidgets('permission denied: explains, retry works once allowed', (tester) async {
    final h = Harness(cameraError: const FaceVerificationException(FaceVerificationErrorCode.cameraDenied, 'denied'));
    await open(tester, h.view());
    await advance(tester, const Duration(milliseconds: 500));

    expect(find.textContaining('Camera access is off'), findsOneWidget);
    expect(h.errors.single.code, FaceVerificationErrorCode.cameraDenied);

    await tester.tap(find.text('Close'));
    await tester.pump();
    expect(h.outcome!.error!.code, FaceVerificationErrorCode.cameraDenied);
  });

  testWidgets('no face: asks to position the face, times out, submits nothing', (tester) async {
    final h = Harness(scene: Scene.none);
    await open(tester, h.view(options: const FaceVerificationOptions(stepTimeout: Duration(seconds: 6))));
    await advance(tester, const Duration(seconds: 3));
    expect(find.text('Position your face in the oval.'), findsOneWidget);

    await advance(tester, const Duration(seconds: 5));
    expect(find.textContaining('That took too long'), findsOneWidget);
    expect(h.server.posts, isEmpty);
  });

  testWidgets('multiple faces: asks for only one person, captures nothing', (tester) async {
    final h = Harness(scene: Scene.two);
    await open(tester, h.view());
    await advance(tester, const Duration(seconds: 3));

    expect(find.text('Make sure only you are in view.'), findsOneWidget);
    expect(h.server.posts, isEmpty);
    await unmount(tester);
  });

  testWidgets('liveness: a face that never turns cannot pass the turn step', (tester) async {
    final h = Harness(scene: Scene.frozen);
    await open(tester, h.view(options: const FaceVerificationOptions(stepTimeout: Duration(seconds: 8))));
    await advance(tester, const Duration(seconds: 5));
    expect(find.text('Turn your head to the left.'), findsOneWidget);

    await advance(tester, const Duration(seconds: 8));
    expect(find.textContaining('That took too long'), findsOneWidget);
    expect(h.server.posts, isEmpty);
  });

  testWidgets('liveness failure from the server: shown, no retry with a single token', (tester) async {
    final h = Harness();
    h.server
      ..verifyStatus = 'liveness_failed'
      ..failureCode = 'liveness_failed';
    await open(tester, h.view());
    await advance(tester, const Duration(seconds: 15));

    expect(find.text("We couldn't confirm a live person was present."), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
    expect(h.results.single.status, FaceSessionStatus.livenessFailed);
  });

  testWidgets('verification failure: retry asks the provider for a fresh session', (tester) async {
    final h = Harness();
    h.server
      ..verifyStatus = 'verification_failed'
      ..failureCode = 'not_matched';
    final tokens = ['fpct_first', 'fpct_second'];
    await open(tester, h.view(provider: () async => tokens.removeAt(0)));
    await advance(tester, const Duration(seconds: 15));
    expect(find.text("Your face didn't match our records."), findsOneWidget);

    h.server
      ..status = 'created'
      ..verifyStatus = 'verification_passed'
      ..failureCode = null;
    await tester.tap(find.text('Try again'));
    await advance(tester, const Duration(seconds: 15));

    expect(find.text('Verification complete'), findsOneWidget);
    expect(h.server.posts.map((p) => p.$1), ['fpct_first', 'fpct_second']);
  });

  testWidgets('two turns the same way need a look back in between; a stuck user cannot pass', (tester) async {
    final h = Harness(scene: Scene.stuck, server: FakeServer(challenge: const ['turn_left', 'turn_left']));
    await open(tester, h.view(options: const FaceVerificationOptions(stepTimeout: Duration(seconds: 10))));
    await advance(tester, const Duration(seconds: 8));

    expect(find.text('Now look back at the camera.'), findsOneWidget);
    await advance(tester, const Duration(seconds: 10));
    expect(h.server.posts, isEmpty);
  });

  testWidgets('voice on: speaks each instruction and the result', (tester) async {
    final h = Harness();
    await open(tester, h.view(options: const FaceVerificationOptions(voice: true)));
    await advance(tester, const Duration(seconds: 25));

    expect(h.speaker.spoken, containsAll(['Look directly at the camera.', 'Turn your head to the left.', 'Now look back at the camera.', 'Turn your head to the right.', 'Verification complete']));
  });

  testWidgets('a speech engine that never answers cannot block the verification', (tester) async {
    final h = Harness(hangingSpeech: true);
    await open(tester, h.view(options: const FaceVerificationOptions(voice: true)));
    await advance(tester, const Duration(seconds: 60));

    expect(find.text('Verification complete'), findsOneWidget);
    await unmount(tester);
    await tester.pump(const Duration(seconds: 10)); // the speech backstop timers run out
  });

  testWidgets('voice off: never speaks', (tester) async {
    final h = Harness();
    await open(tester, h.view(options: const FaceVerificationOptions(voice: false)));
    await advance(tester, const Duration(seconds: 15));

    expect(find.text('Verification complete'), findsOneWidget);
    expect(h.speaker.spoken, isEmpty);
  });

  testWidgets('Spanish: text and voice', (tester) async {
    final h = Harness();
    await open(tester, h.view(options: const FaceVerificationOptions(voice: true, language: 'es-MX')));
    await advance(tester, const Duration(seconds: 25));

    expect(find.text('Verificación completada'), findsOneWidget);
    expect(h.speaker.spoken, contains('Mira directamente a la cámara.'));
  });

  testWidgets('lifecycle: backgrounding releases the camera; returning redoes only the interrupted step', (tester) async {
    final h = Harness();
    await open(tester, h.view());
    await advance(tester, const Duration(seconds: 4)); // first photo taken, on the second step
    expect(find.text('Step 2 of 3'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await advance(tester, const Duration(milliseconds: 300));
    expect(h.cameraLog, ['open', 'close']);
    expect(find.text('Paused. Return to the app to continue.'), findsOneWidget);
    expect(h.speaker.stops, greaterThan(0));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await advance(tester, const Duration(seconds: 15));

    expect(h.cameraLog, ['open', 'close', 'open', 'close']);
    expect(find.text('Verification complete'), findsOneWidget);
    expect(h.server.posts.single.$2, hasLength(3)); // the first photo was kept, nothing doubled
  });

  testWidgets('a permission prompt (app inactive while the camera opens) does not interrupt', (tester) async {
    final h = Harness(cameraOpenDelay: const Duration(seconds: 2)); // the prompt is up for 2 s
    await open(tester, h.view());
    // The system prompt appears while the camera is opening, then the user answers.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump(const Duration(milliseconds: 1500));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await advance(tester, const Duration(seconds: 15));

    expect(h.cameraLog, ['open', 'close']); // opened once, never re-requested
    expect(find.text('Verification complete'), findsOneWidget);
  });

  testWidgets('cleanup: closing mid-capture releases the camera and speech, submits nothing', (tester) async {
    final h = Harness(scene: Scene.frozen);
    await open(tester, h.view(options: const FaceVerificationOptions(voice: true)));
    await advance(tester, const Duration(seconds: 3));

    await tester.tap(find.byTooltip('Close'));
    await advance(tester, const Duration(seconds: 10));

    expect(h.cameras.every((c) => c.closed), isTrue);
    expect(h.speaker.stops, greaterThan(0));
    expect(h.outcome!.error!.code, FaceVerificationErrorCode.cancelled);
    expect(h.server.posts, isEmpty);
  });

  testWidgets('a lost response: retry shows the stored result instead of capturing again', (tester) async {
    final h = Harness();
    h.server.verifyError = 503;
    await open(tester, h.view());
    await advance(tester, const Duration(seconds: 15));
    expect(find.textContaining('temporarily unavailable'), findsOneWidget);

    h.server
      ..verifyError = null
      ..status = 'verification_passed'; // it did finish on the server
    await tester.tap(find.text('Try again'));
    await advance(tester, const Duration(seconds: 2));

    expect(find.text('Verification complete'), findsOneWidget);
    expect(h.cameraLog.where((e) => e == 'open'), hasLength(2)); // opened, then released at once
  });

  testWidgets('session without a reference: reported, camera released', (tester) async {
    final h = Harness(server: FakeServer(referenceReady: false));
    await open(tester, h.view());
    await advance(tester, const Duration(milliseconds: 500));

    expect(find.textContaining("isn't ready yet"), findsOneWidget);
    expect(h.cameras.every((c) => c.closed), isTrue);
  });

  testWidgets('an API key instead of a client token is refused, never sent', (tester) async {
    final h = Harness();
    await open(tester, h.view(token: 'fpk_abcdefgh_secret'));
    await advance(tester, const Duration(milliseconds: 300));

    expect(find.textContaining("isn't set up correctly"), findsOneWidget);
    expect(h.server.tokensSeen, isEmpty);
  });

  test('FaceVerification.start refuses API keys before opening anything', () {
    expect(
      () => FaceVerification.start(_NoContext(), apiUrl: Uri.parse('https://a'), clientToken: 'fpk_x_y'),
      throwsA(isA<FaceVerificationException>().having((e) => e.code, 'code', FaceVerificationErrorCode.configurationError)),
    );
  });
}

class _NoContext extends Fake implements BuildContext {}
