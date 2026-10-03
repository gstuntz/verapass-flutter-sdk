import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../errors.dart';
import '../flow/ports.dart';
import '../flow/verification_controller.dart';
import '../options.dart';
import '../result.dart';
import 'default_dependencies.dart';

/// How a verification ended: a [result], or the [error] the user saw (code `cancelled` when
/// they simply closed it).
class FaceVerificationOutcome {
  const FaceVerificationOutcome.result(FaceVerificationResult this.result) : error = null;
  const FaceVerificationOutcome.error(FaceVerificationException this.error) : result = null;
  final FaceVerificationResult? result;
  final FaceVerificationException? error;
}

/// The complete verification screen, to embed in your own route or layout. For a
/// one-call, full-screen flow use [FaceVerification.start].
///
/// Pass either a [clientToken] (one session; no retry after a result) or a
/// [clientTokenProvider] (called for each new attempt, so the user can retry).
///
/// One view is one verification: its settings are read once, when it is first shown. To start
/// a new verification in the same place in your widget tree, give it a new [key].
class FaceVerificationView extends StatefulWidget {
  const FaceVerificationView({
    super.key,
    required this.apiUrl,
    this.clientToken,
    this.clientTokenProvider,
    this.options = const FaceVerificationOptions(),
    this.onResult,
    this.onError,
    required this.onClose,
  }) : assert((clientToken == null) != (clientTokenProvider == null), 'Pass exactly one of clientToken and clientTokenProvider');

  /// Base URL of the Face Platform API, e.g. https://api.example.com.
  final Uri apiUrl;
  final String? clientToken;
  final Future<String> Function()? clientTokenProvider;
  final FaceVerificationOptions options;

  /// A result was shown (each attempt). Not proof: confirm it on your server.
  final ValueChanged<FaceVerificationResult>? onResult;

  /// An error was shown.
  final ValueChanged<FaceVerificationException>? onError;

  /// The user left; the camera and speech are already released.
  final ValueChanged<FaceVerificationOutcome> onClose;

  @override
  State<FaceVerificationView> createState() => _FaceVerificationViewState();
}

/// Replaces the platform pieces (camera, detector, speech, JPEG encoding) for tests. Not
/// part of the public API; exposed through `package:facera/testing.dart`.
FlowDependencies? debugFlowDependenciesOverride;

class _FaceVerificationViewState extends State<FaceVerificationView> with WidgetsBindingObserver {
  late final VerificationController _controller;
  FlowPhase? _reportedPhase;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _controller = VerificationController(
      apiUrl: widget.apiUrl,
      clientToken: widget.clientToken,
      clientTokenProvider: widget.clientTokenProvider,
      options: widget.options,
      dependencies: debugFlowDependenciesOverride ?? defaultFlowDependencies,
    )..addListener(_onChange);
    WidgetsBinding.instance.addPostFrameCallback((_) => _controller.startIfNoIntro());
  }

  void _onChange() {
    final phase = _controller.phase;
    if (phase != _reportedPhase) {
      _reportedPhase = phase;
      if (phase == FlowPhase.result) widget.onResult?.call(_controller.result!);
      if (phase == FlowPhase.error) widget.onError?.call(_controller.error!);
      if (phase == FlowPhase.closed) _finish();
    }
    if (mounted) setState(() {});
  }

  void _finish() {
    if (_closed) return;
    _closed = true;
    // Synchronous: the outcome is known the moment the flow closes.
    final result = _controller.closedResult;
    widget.onClose(result != null ? FaceVerificationOutcome.result(result) : FaceVerificationOutcome.error(_controller.closedError!));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The camera must be released when the app is not in the foreground (and iOS stops it
    // anyway); the interrupted step restarts when the user comes back.
    switch (state) {
      case AppLifecycleState.inactive:
        _controller.pause(backgrounded: false); // ignored during a camera-permission prompt
      case AppLifecycleState.paused || AppLifecycleState.hidden:
        _controller.pause();
      case AppLifecycleState.resumed:
        _controller.resume();
      case AppLifecycleState.detached:
        _controller.close();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setPreferredOrientations(const []);
    _controller
      ..removeListener(_onChange)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final t = widget.options.theme;
    final brightness = t.brightness ?? base.brightness;
    final scheme = (t.brightness == null ? base.colorScheme : ColorScheme.fromSeed(seedColor: t.accentColor ?? base.colorScheme.primary, brightness: brightness)).copyWith(
      primary: t.accentColor,
      surface: t.backgroundColor,
      onSurface: t.textColor,
    );
    return Theme(
      data: base.copyWith(colorScheme: scheme, brightness: brightness),
      child: Builder(
        builder: (context) => PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _controller.close();
          },
          child: Material(
            color: Theme.of(context).colorScheme.surface,
            child: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Header(title: _controller.messages.title, closeLabel: _controller.messages.close, onClose: _controller.close),
                        Expanded(child: _body(context)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final c = _controller;
    final m = c.messages;
    return switch (c.phase) {
      FlowPhase.intro => _Intro(controller: c),
      FlowPhase.starting || FlowPhase.submitting => _Busy(text: c.busyText),
      FlowPhase.capturing || FlowPhase.paused => _Capture(controller: c, showText: widget.options.instructions),
      FlowPhase.result => _Outcome(
        success: c.result!.passed,
        title: c.result!.passed ? m.successTitle : m.failureTitle,
        body: c.result!.passed ? m.successBody : (m.failure[c.result!.failureCode ?? FaceFailureCode.failed] ?? m.failure[FaceFailureCode.failed]!),
        primary: c.result!.passed ? (m.done, c.close) : (c.canRetry ? (m.tryAgain, c.retry) : (m.close, c.close)),
        secondary: !c.result!.passed && c.canRetry ? (m.close, c.close) : null,
      ),
      FlowPhase.error => _Outcome(
        success: false,
        title: m.errorTitle,
        body: m.errors[c.error!.code] ?? m.errorTitle,
        primary: c.canRetry ? (m.tryAgain, c.retry) : (m.close, c.close),
        secondary: c.canRetry ? (m.close, c.close) : null,
      ),
      FlowPhase.closed => const SizedBox.shrink(),
    };
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.closeLabel, required this.onClose});
  final String title;
  final String closeLabel;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(Icons.verified_user_outlined, size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(title, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant), overflow: TextOverflow.ellipsis),
        ),
        IconButton(onPressed: onClose, tooltip: closeLabel, icon: const Icon(Icons.close)),
      ],
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro({required this.controller});
  final VerificationController controller;

  @override
  Widget build(BuildContext context) {
    final m = controller.messages;
    final theme = Theme.of(context);
    const icons = [Icons.wb_sunny_outlined, Icons.face_retouching_off_outlined, Icons.person_outline];
    return ListView(
      padding: const EdgeInsets.only(top: 16, bottom: 16),
      children: [
        Semantics(header: true, child: Text(m.title, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600))),
        const SizedBox(height: 8),
        Text(m.introBody, style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 20),
        for (final (i, tip) in m.introTips.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(10)),
                  child: Icon(icons[i % icons.length], size: 20, color: theme.colorScheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(tip, style: theme.textTheme.bodyLarge)),
              ],
            ),
          ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.lock_outline, size: 18, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(child: Text(m.privacyNote, style: theme.textTheme.bodySmall)),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _PrimaryButton(label: m.start, onPressed: controller.begin, autofocus: true),
        const SizedBox(height: 8),
        _SecondaryButton(label: m.cancel, onPressed: controller.close),
      ],
    );
  }
}

class _Busy extends StatelessWidget {
  const _Busy({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Semantics(
      liveRegion: true,
      label: text,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 44, height: 44, child: CircularProgressIndicator(strokeWidth: 4)),
          const SizedBox(height: 16),
          ExcludeSemantics(child: Text(text, style: Theme.of(context).textTheme.bodyLarge)),
        ],
      ),
    ),
  );
}

class _Capture extends StatelessWidget {
  const _Capture({required this.controller, required this.showText});
  final VerificationController controller;
  final bool showText;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final theme = Theme.of(context);
    final source = c.frameSource;
    final paused = c.phase == FlowPhase.paused;
    return Column(
      children: [
        const SizedBox(height: 8),
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: 3 / 4,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const ColoredBox(color: Color(0xFF0B0D12)),
                    if (source != null && !paused) ExcludeSemantics(child: _CoverPreview(source: source)),
                    CustomPaint(
                      painter: _OvalOverlay(
                        progress: c.progress,
                        good: c.guidanceGood,
                        accent: theme.colorScheme.primary,
                        success: Colors.green.shade600,
                        mask: theme.colorScheme.surface.withValues(alpha: 0.72),
                      ),
                    ),
                    if (c.arrow != null && !paused) _TurnArrow(side: c.arrow!, color: theme.colorScheme.primary),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        ExcludeSemantics(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < c.totalSteps; i++)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: 28,
                  height: 4,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    color: c.completedSteps.contains(i)
                        ? Colors.green.shade600
                        : i == c.step
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outlineVariant,
                  ),
                ),
            ],
          ),
        ),
        if (c.totalSteps > 0 && showText)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              c.messages.stepOf(math.min(c.step + 1, c.totalSteps), c.totalSteps),
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        const SizedBox(height: 8),
        // Spoken by screen readers even when on-screen hints are off.
        Semantics(
          liveRegion: true,
          label: c.guidance,
          child: ExcludeSemantics(
            child: SizedBox(
              height: 64,
              child: Center(
                child: showText
                    ? Text(
                        c.guidance,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                        maxLines: 2,
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ),
        ),
        _SecondaryButton(label: c.messages.cancel, onPressed: c.close),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// The camera preview filling its box (cropping, never stretching).
class _CoverPreview extends StatelessWidget {
  const _CoverPreview({required this.source});
  final FrameSource source;

  @override
  Widget build(BuildContext context) {
    final aspect = source.previewAspectRatio;
    if (aspect == null) return const SizedBox.expand();
    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(width: 1000 * aspect, height: 1000, child: source.buildPreview(context)),
    );
  }
}

class _OvalOverlay extends CustomPainter {
  _OvalOverlay({required this.progress, required this.good, required this.accent, required this.success, required this.mask});
  final double progress;
  final bool good;
  final Color accent;
  final Color success;
  final Color mask;

  @override
  void paint(Canvas canvas, Size size) {
    final oval = Rect.fromCenter(center: Offset(size.width / 2, size.height * 0.47), width: size.width * 0.64, height: size.height * 0.67);
    final hole = Path()..addOval(oval);
    canvas.drawPath(Path.combine(PathOperation.difference, Path()..addRect(Offset.zero & size), hole), Paint()..color = mask);
    canvas.drawOval(oval, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = good ? success : Colors.white.withValues(alpha: 0.85));
    if (progress > 0) {
      canvas.drawArc(oval, -math.pi / 2, 2 * math.pi * progress, false, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..color = accent);
    }
  }

  @override
  bool shouldRepaint(_OvalOverlay old) => old.progress != progress || old.good != good || old.accent != accent || old.mask != mask;
}

class _TurnArrow extends StatelessWidget {
  const _TurnArrow({required this.side, required this.color});
  final ArrowSide side;
  final Color color;

  @override
  Widget build(BuildContext context) => Align(
    alignment: side == ArrowSide.left ? Alignment.centerLeft : Alignment.centerRight,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: ExcludeSemantics(
        child: CircleAvatar(
          radius: 24,
          backgroundColor: color,
          child: Icon(side == ArrowSide.left ? Icons.arrow_back : Icons.arrow_forward, color: Theme.of(context).colorScheme.onPrimary),
        ),
      ),
    ),
  );
}

class _Outcome extends StatelessWidget {
  const _Outcome({required this.success, required this.title, required this.body, required this.primary, this.secondary});
  final bool success;
  final String title;
  final String body;
  final (String, VoidCallback) primary;
  final (String, VoidCallback)? secondary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = success ? Colors.green.shade600 : theme.colorScheme.error;
    return Column(
      children: [
        const Spacer(),
        Semantics(
          liveRegion: true,
          label: '$title. $body',
          child: ExcludeSemantics(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 36,
                  backgroundColor: color.withValues(alpha: 0.12),
                  child: Icon(success ? Icons.check_rounded : Icons.error_outline_rounded, color: color, size: 40),
                ),
                const SizedBox(height: 16),
                Text(title, textAlign: TextAlign.center, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text(body, textAlign: TextAlign.center, style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ),
        const Spacer(),
        _PrimaryButton(label: primary.$1, onPressed: primary.$2, autofocus: true),
        if (secondary != null) ...[const SizedBox(height: 8), _SecondaryButton(label: secondary!.$1, onPressed: secondary!.$2)],
        const SizedBox(height: 8),
      ],
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.onPressed, this.autofocus = false});
  final String label;
  final VoidCallback onPressed;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: FilledButton(
      autofocus: autofocus,
      onPressed: onPressed,
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      child: Text(label),
    ),
  );
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      child: Text(label),
    ),
  );
}
