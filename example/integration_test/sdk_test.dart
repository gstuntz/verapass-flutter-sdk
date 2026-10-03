// On-device tests: the real SDK (UI, flow, TensorFlow Lite face detection, text-to-speech,
// JPEG encoding) against the real API, with recorded frames standing in for the camera
// (simulators have no camera). The demo server (web-sdk/demo/server.mjs) must be running on
// this computer, holding a project API key; it creates the sessions.
//
//   flutter test integration_test/sdk_test.dart -d <device> \
//     --dart-define=DEMO_SERVER=http://10.0.2.2:5181   (Android emulator; iOS simulator: localhost)
//     --dart-define=REAL_CAMERA=notFound|denied           (what the real camera plugin should report)

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:facera/facera.dart';
import 'package:facera/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';

const api = String.fromEnvironment('API_URL', defaultValue: 'https://api.ridafleet.com');
const demoServer = String.fromEnvironment('DEMO_SERVER', defaultValue: 'http://localhost:5181');
const realCamera = String.fromEnvironment('REAL_CAMERA');

/// Plays recorded frames like a camera: each image for [segment], looping.
class RecordedCamera implements FrameSource {
  RecordedCamera(this.names, {this.segment = const Duration(milliseconds: 2500)});
  final List<String> names;
  final Duration segment;
  final _frames = StreamController<CameraFrame>.broadcast();
  final _decoded = <(CameraFrame, Uint8List)>[];
  Timer? _timer;
  bool closed = false;
  int _shown = 0;

  static final _cache = <String, (CameraFrame, Uint8List)>{};

  static Future<(CameraFrame, Uint8List)> _load(String name) async {
    final cached = _cache[name];
    if (cached != null) return cached;
    final jpeg = (await rootBundle.load('assets/test_frames/$name.jpg')).buffer.asUint8List();
    final image = img.decodeJpg(jpeg)!.convert(numChannels: 3);
    final rgb = image.getBytes(order: img.ChannelOrder.rgb);
    final frame = CameraFrame(width: image.width, height: image.height, format: FrameFormat.rgb888, planes: [FramePlane(rgb, bytesPerRow: image.width * 3, bytesPerPixel: 3)]);
    return _cache[name] = (frame, jpeg);
  }

  @override
  Future<void> open() async {
    for (final name in names) {
      _decoded.add(await _load(name));
    }
    final start = DateTime.now();
    _timer = Timer.periodic(const Duration(milliseconds: 66), (_) {
      final index = (DateTime.now().difference(start).inMilliseconds ~/ segment.inMilliseconds) % _decoded.length;
      _shown = index;
      final (f, _) = _decoded[index];
      // A new object each tick, like a camera delivering a new frame.
      _frames.add(CameraFrame(width: f.width, height: f.height, format: f.format, planes: f.planes));
    });
  }

  @override
  Stream<CameraFrame> get frames => _frames.stream;
  @override
  Widget buildPreview(BuildContext context) => _decoded.isEmpty ? const SizedBox() : Image.memory(_decoded[_shown].$2, gaplessPlayback: true, fit: BoxFit.cover);
  @override
  bool get previewMirrored => true;
  @override
  double? get previewAspectRatio => 9 / 16;

  @override
  Future<void> close() async {
    closed = true;
    _timer?.cancel();
    unawaited(_frames.close());
  }
}

/// The device's real text-to-speech, recording what it was asked to say.
class RecordingSpeaker implements Speaker {
  RecordingSpeaker(this._inner);
  final Speaker _inner;
  final said = <String>[];
  @override
  bool get enabled => _inner.enabled;
  @override
  Future<void> say(String text, {bool instruction = false}) {
    if (enabled) said.add(text);
    return _inner.say(text, instruction: instruction);
  }

  @override
  Future<void> stop() => _inner.stop();
}

class Run {
  Run(List<String> frames, {this.reference = 'bolden', bool realCameraPlugin = false}) {
    faceVerificationDependencies = FlowDependencies(
      frameSource: (options) {
        if (realCameraPlugin) return defaultDependencies.frameSource(options);
        return camera = RecordedCamera(frames);
      },
      detector: defaultDependencies.detector, // real TensorFlow Lite on the device
      speaker: (enabled, locale) => speaker = RecordingSpeaker(defaultDependencies.speaker(enabled, locale)),
      encodeJpeg: defaultDependencies.encodeJpeg,
    );
  }

  final String reference;
  RecordedCamera? camera;
  RecordingSpeaker? speaker;
  final sessions = <String>[];
  FaceVerificationOutcome? outcome;
  FaceVerificationResult? result;

  Future<String> token() async {
    final response = await http.post(Uri.parse('$demoServer/demo/session?reference=$reference'));
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    sessions.add(body['sessionId'] as String);
    return body['clientToken'] as String;
  }

  Widget view({FaceVerificationOptions options = const FaceVerificationOptions()}) => MaterialApp(
    key: UniqueKey(), // a fresh app tree per test: nothing carries over from the previous one
    home: FaceVerificationView(
      key: UniqueKey(), // a new verification, never the previous test's screen
      apiUrl: Uri.parse(api),
      clientTokenProvider: token,
      options: options,
      onResult: (r) => result = r,
      onClose: (o) => outcome = o,
    ),
  );

  /// The authoritative result, read by the demo server with its API key.
  Future<Map<String, dynamic>> serverView() async =>
      jsonDecode((await http.get(Uri.parse('$demoServer/demo/result/${sessions.last}'))).body) as Map<String, dynamic>;
}

Future<void> start(WidgetTester tester, Widget view) async {
  await tester.pumpWidget(view);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.byType(FilledButton));
}

/// Pumps in real time until [finder] matches.
Future<void> waitFor(WidgetTester tester, Finder finder, {Duration timeout = const Duration(seconds: 60)}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) return;
  }
  throw TestFailure('Timed out waiting for $finder. On screen: ${find.byType(Text).evaluate().map((e) => (e.widget as Text).data).join(' | ')}');
}

Future<void> settle(WidgetTester tester, Duration duration) async {
  final end = DateTime.now().add(duration);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

const person = ['frontal', 'left', 'right'];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => faceVerificationDependencies = null);

  testWidgets('success: real detection, real API, verification_passed (voice on)', (tester) async {
    final run = Run(person);
    await start(tester, run.view(options: const FaceVerificationOptions(voice: true)));
    await waitFor(tester, find.text('Verification complete'), timeout: const Duration(seconds: 90));

    final server = await run.serverView();
    expect(server['status'], 'verification_passed');
    expect(run.speaker!.said, containsAll(['Look directly at the camera.', 'Now look back at the camera.', 'Verification complete']));
    expect(run.camera!.closed, isTrue);
    await tester.tap(find.text('Done'));
    await settle(tester, const Duration(milliseconds: 500));
    expect(run.outcome!.result!.passed, isTrue);
  });

  testWidgets('verification failure: a different person on file', (tester) async {
    final run = Run(person, reference: 'kelly');
    await start(tester, run.view());
    await waitFor(tester, find.text("Your face didn't match our records."), timeout: const Duration(seconds: 90));
    expect((await run.serverView())['status'], 'verification_failed');
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('liveness failure: the first photo is a screen replay (server rejects it)', (tester) async {
    final run = Run(['spoof_frontal', 'left', 'right']);
    await start(tester, run.view());
    await waitFor(tester, find.text("We couldn't confirm a live person was present."), timeout: const Duration(seconds: 90));
    final server = await run.serverView();
    expect(server['status'], 'liveness_failed');
    expect(server['failure_reason'], contains('spoof_suspected'));
  });

  testWidgets('no face: guidance, then a timeout; nothing submitted', (tester) async {
    final run = Run(['empty']);
    await start(tester, run.view(options: const FaceVerificationOptions(stepTimeout: Duration(seconds: 6))));
    await waitFor(tester, find.text('Position your face in the oval.'));
    await waitFor(tester, find.textContaining('That took too long'));
    expect((await run.serverView())['status'], 'created');
  });

  testWidgets('multiple faces: asks for one person; nothing captured', (tester) async {
    final run = Run(['pair']);
    await start(tester, run.view(options: const FaceVerificationOptions(stepTimeout: Duration(seconds: 6))));
    await waitFor(tester, find.text('Make sure only you are in view.'));
    await waitFor(tester, find.textContaining('That took too long'));
    expect((await run.serverView())['status'], 'created');
  });

  testWidgets('voice off: nothing spoken, flow completes', (tester) async {
    final run = Run(person);
    await start(tester, run.view(options: const FaceVerificationOptions(voice: false)));
    await waitFor(tester, find.text('Verification complete'), timeout: const Duration(seconds: 90));
    expect(run.speaker!.said, isEmpty);
  });

  testWidgets('lifecycle: interrupted mid-capture, resumes and completes', (tester) async {
    final run = Run(person);
    await start(tester, run.view());
    await waitFor(tester, find.text('Step 2 of 3'), timeout: const Duration(seconds: 30));

    // Leaving the app goes inactive (app switcher, a call, Control Center), then paused.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await waitFor(tester, find.text('Paused. Return to the app to continue.'));
    expect(run.camera!.closed, isTrue);
    final firstCamera = run.camera;
    // While paused Flutter draws no frames, so wait without pumping.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await Future<void>.delayed(const Duration(seconds: 2));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await waitFor(tester, find.text('Verification complete'), timeout: const Duration(seconds: 90));
    expect(run.camera, isNot(same(firstCamera))); // the camera was reopened
    expect((await run.serverView())['status'], 'verification_passed');
  });

  testWidgets('cleanup: closing mid-capture releases the camera; nothing submitted', (tester) async {
    final run = Run(person);
    await start(tester, run.view(options: const FaceVerificationOptions(voice: true)));
    await waitFor(tester, find.text('Step 1 of 3'));
    await settle(tester, const Duration(seconds: 1));
    await tester.tap(find.byTooltip('Close'));
    await settle(tester, const Duration(seconds: 2));

    expect(run.camera!.closed, isTrue);
    expect(run.outcome!.error!.code, FaceVerificationErrorCode.cancelled);
    expect((await run.serverView())['status'], 'created');
  });

  testWidgets('real camera plugin: permission or availability is reported ($realCamera)', (tester) async {
    if (realCamera.isEmpty) return markTestSkipped('Pass --dart-define=REAL_CAMERA=notFound|denied');
    final run = Run(const [], realCameraPlugin: true);
    // Time for the test script to set the permission state (adb) after the app installs.
    await Future<void>.delayed(const Duration(seconds: 8));
    await start(tester, run.view());
    final message = realCamera == 'denied' ? 'Camera access is off' : 'No camera was found';
    await waitFor(tester, find.textContaining(message), timeout: const Duration(seconds: 20));
    await tester.tap(find.text('Close'));
    await settle(tester, const Duration(milliseconds: 500));
    expect(run.outcome!.error!.code, realCamera == 'denied' ? FaceVerificationErrorCode.cameraDenied : FaceVerificationErrorCode.cameraNotFound);
  }, skip: !Platform.isIOS && !Platform.isAndroid);
}
