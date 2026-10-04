import 'package:flutter/material.dart';

import 'design.dart';
import 'widgets.dart';

/// The colour picker behind a row's "..." button: a saturation/value field over a hue bar, a hex
/// field that stays editable, and 取消 / 确定.
///
/// It is a panel inside this window, not a native dialog - the frame, the radius ladder, the
/// dark palette and the transitions all have to be the app's own.

String? parseHex(String text) {
  final String t = text.trim().replaceFirst('#', '');
  if (t.length != 6) {
    return null;
  }
  final int? value = int.tryParse(t, radix: 16);
  if (value == null) {
    return null;
  }
  return '#${value.toRadixString(16).toUpperCase().padLeft(6, '0')}';
}

Future<String?> showFzColorPicker(
  BuildContext context, {
  required String hex,
  required String title,
  required String cancelLabel,
  required String okLabel,
}) {
  return showDialog<String>(
    context: context,
    builder: (BuildContext context) => FzColorPicker(
      initial: hex,
      title: title,
      cancelLabel: cancelLabel,
      okLabel: okLabel,
    ),
  );
}

class FzColorPicker extends StatefulWidget {
  const FzColorPicker({
    super.key,
    required this.initial,
    required this.title,
    required this.cancelLabel,
    required this.okLabel,
  });

  final String initial;
  final String title;
  final String cancelLabel;
  final String okLabel;

  @override
  State<FzColorPicker> createState() => _FzColorPickerState();
}

class _FzColorPickerState extends State<FzColorPicker> {
  late HSLColor _hsl = _hslFrom(widget.initial);
  bool _shown = false;
  bool _closing = false;
  late final TextEditingController _hex = TextEditingController(
    text: widget.initial.toUpperCase(),
  );
  final FocusNode _hexFocus = FocusNode();

  static HSLColor _hslFrom(String hex) {
    final int? value = int.tryParse(hex.replaceFirst('#', ''), radix: 16);
    final Color color = value == null
        ? const Color(0xFF008CFF)
        : Color(0xFF000000 | value);
    return HSLColor.fromColor(color);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() => _shown = true);
      }
    });
  }

  @override
  void dispose() {
    _hex.dispose();
    _hexFocus.dispose();
    super.dispose();
  }

  /// One way out, so the panel never just vanishes: the buttons, Esc and the barrier all come
  /// through here, and the pop waits for the exit to finish.
  void _exit([String? result]) {
    if (_closing) {
      return;
    }
    setState(() => _closing = true);
    Future<void>.delayed(FzMotion.select, () {
      if (mounted) {
        Navigator.of(context).pop(result);
      }
    });
  }

  void _set(HSLColor next) {
    setState(() {
      _hsl = next;
      _hex.text = _toHex(next);
    });
  }

  static String _toHex(HSLColor h) {
    final Color c = h.toColor();
    String two(double v) => (v * 255)
        .round()
        .clamp(0, 255)
        .toRadixString(16)
        .padLeft(2, '0')
        .toUpperCase();
    return '#${two(c.r)}${two(c.g)}${two(c.b)}';
  }

  void _commitHex(String text) {
    final String? parsed = parseHex(text);
    if (parsed != null) {
      _set(_hslFrom(parsed));
    } else {
      _hex.text = _toHex(_hsl);
    }
  }

  @override
  Widget build(BuildContext context) {
    final FzColors c = context.fz;
    final bool up = _shown && !_closing;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (!didPop) {
          _exit();
        }
      },
      child: AnimatedScale(
        scale: up ? 1 : 0.96,
        duration: _closing ? FzMotion.select : FzMotion.page,
        curve: Curves.fastOutSlowIn,
        child: AnimatedOpacity(
          opacity: up ? 1 : 0,
          duration: _closing ? FzMotion.select : FzMotion.page,
          child: Dialog(
            backgroundColor: c.card,
            elevation: 0,
            insetPadding: const EdgeInsets.all(24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(FzRadius.base),
              side: BorderSide(color: c.cardBorder),
            ),
            child: SizedBox(
              width: 320,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(
                      widget.title,
                      style: TextStyle(
                        color: c.ink,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _SaturationValueField(
                      hsl: _hsl,
                      onChanged: (double s, double l) => _set(
                        _hsl
                            .withSaturation(s.clamp(0.0, 1.0))
                            .withLightness(l.clamp(0.0, 1.0)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _HueBar(
                      hue: _hsl.hue,
                      onChanged: (double h) => _set(_hsl.withHue(h)),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: FzFieldFrame(
                            focusNode: _hexFocus,
                            child: FzFieldText(
                              focusNode: _hexFocus,
                              controller: _hex,
                              enabled: true,
                              onSubmitted: _commitHex,
                              style: TextStyle(
                                color: c.ink,
                                fontSize: 11,
                                fontFamily: 'Consolas',
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        AnimatedContainer(
                          duration: FzMotion.hover,
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: _hsl.toColor(),
                            borderRadius: BorderRadius.circular(FzRadius.base),
                            border: Border.all(color: c.fieldBorder),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: <Widget>[
                        const Spacer(),
                        FzButton(
                          label: widget.cancelLabel,
                          width: 90,
                          onTap: () => _exit(),
                        ),
                        const SizedBox(width: 8),
                        FzButton(
                          label: widget.okLabel,
                          width: 90,
                          primary: true,
                          onTap: () => _exit(_toHex(_hsl)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Saturation runs left to right, lightness top to bottom; the field itself is the pure hue.
class _SaturationValueField extends StatelessWidget {
  const _SaturationValueField({required this.hsl, required this.onChanged});

  static const double height = 150;

  final HSLColor hsl;
  final void Function(double saturation, double lightness) onChanged;

  @override
  Widget build(BuildContext context) {
    final FzColors c = context.fz;
    // The height is pinned here: inside a min-size Column the incoming main-axis constraints are
    // unbounded, and the Stack inside cannot size itself to infinity.
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints box) {
          final Size size = Size(box.maxWidth, box.maxHeight);
          return GestureDetector(
            onPanStart: (DragStartDetails d) => _pick(d.localPosition, size),
            onPanUpdate: (DragUpdateDetails d) => _pick(d.localPosition, size),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(FzRadius.small),
                border: Border.all(color: c.fieldBorder),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(FzRadius.small),
                child: Stack(
                  children: <Widget>[
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _SaturationValuePainter(hsl.hue),
                      ),
                    ),
                    Positioned(
                      left: _clampX(hsl.saturation * size.width, size),
                      top: _clampX((1 - hsl.lightness) * size.height, size) - 6,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: hsl.toColor(),
                          border: Border.all(color: c.ink, width: 1.5),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  static double _clampX(double v, Size size) => v.clamp(6.0, size.width - 6.0);

  void _pick(Offset at, Size size) {
    if (size.width == 0 || size.height == 0) {
      return;
    }
    onChanged(at.dx / size.width, 1 - at.dy / size.height);
  }
}

class _SaturationValuePainter extends CustomPainter {
  const _SaturationValuePainter(this.hue);

  final double hue;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()..color = HSLColor.fromAHSL(1, hue, 1, 0.5).toColor(),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: <Color>[Color(0xFFFFFFFF), Color(0x00FFFFFF)],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Color(0x00000000), Color(0xFF000000)],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_SaturationValuePainter old) => old.hue != hue;
}

class _HueBar extends StatelessWidget {
  const _HueBar({required this.hue, required this.onChanged});

  final double hue;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final FzColors c = context.fz;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        return GestureDetector(
          onPanStart: (DragStartDetails d) =>
              _pick(d.localPosition, box.maxWidth),
          onPanUpdate: (DragUpdateDetails d) =>
              _pick(d.localPosition, box.maxWidth),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(FzRadius.small),
            child: Container(
              height: 14,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: <Color>[
                    Color(0xFFFF0000),
                    Color(0xFFFFFF00),
                    Color(0xFF00FF00),
                    Color(0xFF00FFFF),
                    Color(0xFF0000FF),
                    Color(0xFFFF00FF),
                    Color(0xFFFF0000),
                  ],
                ),
              ),
              child: Stack(
                children: <Widget>[
                  Positioned(
                    left: (hue / 360 * box.maxWidth - 2).clamp(
                      0.0,
                      box.maxWidth - 4,
                    ),
                    child: Container(
                      width: 4,
                      height: 14,
                      decoration: BoxDecoration(
                        color: c.field,
                        border: Border.all(color: c.ink, width: 1),
                        borderRadius: BorderRadius.circular(FzRadius.grip),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _pick(Offset at, double width) {
    if (width == 0) {
      return;
    }
    onChanged((at.dx / width).clamp(0.0, 1.0) * 360);
  }
}
