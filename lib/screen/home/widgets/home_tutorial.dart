import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HomeTutorial extends StatefulWidget {
  const HomeTutorial({
    super.key,
    required this.child,
    required this.navigationKey,
    required this.ready,
  });

  final Widget child;
  final GlobalKey navigationKey;
  final bool ready;

  static VoidCallback? startOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_TutorialScope>()?.start;

  @override
  State<HomeTutorial> createState() => _HomeTutorialState();
}

class _HomeTutorialState extends State<HomeTutorial> {
  static const _seenKey = 'home_tutorial_seen_v1';
  static const _messages = [
    '1. スワイプで行きたい観光地決めます！',
    '2. 旅程作成で保存した中からルートを作ります！',
    '3. しおりでは作成した旅を確認できます！',
  ];
  static const _tabs = [1, 3, 2];
  final _preferences = SharedPreferencesAsync();
  Timer? _timer;
  bool _checked = false;
  bool _seen = true;
  int? _step;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      _seen = await _preferences.getBool(_seenKey) ?? false;
    } catch (_) {
      _seen = false;
    }
    if (!mounted) return;
    _checked = true;
    _startIfReady();
  }

  @override
  void didUpdateWidget(HomeTutorial oldWidget) {
    super.didUpdateWidget(oldWidget);
    _startIfReady();
  }

  void _startIfReady() {
    if (!_checked || _seen || !widget.ready || _step != null) return;
    _seen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _start();
    });
  }

  void _start() {
    _timer?.cancel();
    setState(() => _step = 0);
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (_step == 2) {
        _finish();
      } else {
        setState(() => _step = _step! + 1);
      }
    });
  }

  void _finish() {
    _timer?.cancel();
    setState(() => _step = null);
    unawaited(_saveSeen());
  }

  Future<void> _saveSeen() async {
    try {
      await _preferences.setBool(_seenKey, true);
    } catch (_) {
      // Keep the tutorial available even when local storage is unavailable.
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _TutorialScope(
    start: _start,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final step = _step;
        final navigation =
            widget.navigationKey.currentContext?.findRenderObject()
                as RenderBox?;
        final height =
            navigation?.size.height ??
            (80 + MediaQuery.paddingOf(context).bottom);
        final anchor = step == null ? 0.5 : (_tabs[step] + 0.5) / 5;
        return Stack(
          fit: StackFit.expand,
          children: [
            widget.child,
            if (step != null) ...[
              const Positioned.fill(
                child: ModalBarrier(
                  dismissible: false,
                  color: Color(0x99000000),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: height + 18,
                child: Semantics(
                  liveRegion: true,
                  child: Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    elevation: 8,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 12, 12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _messages[step],
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('${step + 1} / 3'),
                              TextButton(
                                onPressed: _finish,
                                child: const Text('閉じる'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: constraints.maxWidth * anchor - 12,
                bottom: height,
                child: CustomPaint(
                  size: const Size(24, 18),
                  painter: _BubbleTail(),
                ),
              ),
            ],
          ],
        );
      },
    ),
  );
}

class _TutorialScope extends InheritedWidget {
  const _TutorialScope({required this.start, required super.child});
  final VoidCallback start;

  @override
  bool updateShouldNotify(_TutorialScope oldWidget) => start != oldWidget.start;
}

class _BubbleTail extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Path()
        ..lineTo(size.width, 0)
        ..lineTo(size.width / 2, size.height)
        ..close(),
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_BubbleTail oldDelegate) => false;
}
