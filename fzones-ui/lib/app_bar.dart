import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'design.dart';
import 'window_bridge.dart';

/// The window chrome: a 1px frame hairline on the same 8px radius as everything inside it, and
/// the 48px app bar the v3 spec calls for.
///
/// The Flutter view is a Win32 child window covering every pixel, so Windows never hit-tests the
/// parent: the drag band and the resize handles are Flutter widgets that hand the gesture back to
/// the system through [FzWindow].

/// The whole window, from the frame inwards. Pages are handed the area below the app bar.
class FzWindowFrame extends StatelessWidget {
  const FzWindowFrame({
    super.key,
    required this.title,
    required this.tooltips,
    required this.hasSettingsButton,
    required this.child,
  });

  final String title;
  final FzCaptionTooltips tooltips;

  /// The gear only appears on the editor - the settings window has nothing to open.
  final bool hasSettingsButton;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final FzColors c = context.fz;
    FzWindow.attach();

    final Widget surface = Material(
      type: MaterialType.canvas,
      color: c.win,
      child: Column(
        children: <Widget>[
          FzAppBar(
            title: title,
            tooltips: tooltips,
            hasSettingsButton: hasSettingsButton,
          ),
          Expanded(child: child),
        ],
      ),
    );

    return ValueListenableBuilder<bool>(
      valueListenable: FzWindow.maximized,
      child: surface,
      builder: (BuildContext context, bool maximized, Widget? inner) {
        return TweenAnimationBuilder<double>(
          // Maximized drops the radius: the window edge is the screen edge there.
          tween: Tween<double>(end: maximized ? 0 : FzRadius.base),
          duration: FzMotion.page,
          curve: Curves.easeOutCubic,
          child: inner,
          builder: (BuildContext context, double radius, Widget? body) {
            final BorderRadius corners = BorderRadius.circular(radius);
            return DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                borderRadius: corners,
                border: Border.all(
                    color: c.frame, width: FzMetrics.frameStroke),
              ),
              child: ClipRRect(
                borderRadius: corners,
                child: maximized
                    ? body
                    : Stack(children: <Widget>[
                        Positioned.fill(child: body!),
                        ..._grabZones(),
                      ]),
              ),
            );
          },
        );
      },
    );
  }

  /// The eight grab zones, each one handing its pointer-down to the system's resize loop.
  List<Widget> _grabZones() {
    const double b = FzMetrics.grabBand;
    return <Widget>[
      _handle(
          edge: FzWindowEdge.left,
          cursor: SystemMouseCursors.resizeLeft,
          left: 0,
          top: b,
          bottom: b,
          width: b),
      _handle(
          edge: FzWindowEdge.right,
          cursor: SystemMouseCursors.resizeRight,
          right: 0,
          top: b,
          bottom: b,
          width: b),
      _handle(
          edge: FzWindowEdge.top,
          cursor: SystemMouseCursors.resizeUp,
          top: 0,
          left: b,
          right: b,
          height: b),
      _handle(
          edge: FzWindowEdge.bottom,
          cursor: SystemMouseCursors.resizeDown,
          bottom: 0,
          left: b,
          right: b,
          height: b),
      _handle(
          edge: FzWindowEdge.topLeft,
          cursor: SystemMouseCursors.resizeUpLeft,
          top: 0,
          left: 0,
          width: b,
          height: b),
      _handle(
          edge: FzWindowEdge.topRight,
          cursor: SystemMouseCursors.resizeUpRight,
          top: 0,
          right: 0,
          width: b,
          height: b),
      _handle(
          edge: FzWindowEdge.bottomLeft,
          cursor: SystemMouseCursors.resizeDownLeft,
          bottom: 0,
          left: 0,
          width: b,
          height: b),
      _handle(
          edge: FzWindowEdge.bottomRight,
          cursor: SystemMouseCursors.resizeDownRight,
          bottom: 0,
          right: 0,
          width: b,
          height: b),
    ];
  }

  Widget _handle({
    required FzWindowEdge edge,
    required MouseCursor cursor,
    double? left,
    double? top,
    double? right,
    double? bottom,
    double? width,
    double? height,
  }) {
    return Positioned(
      left: left,
      top: top,
      right: right,
      bottom: bottom,
      width: width,
      height: height,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => FzWindow.startResize(edge),
        child: MouseRegion(cursor: cursor, child: const SizedBox.expand()),
      ),
    );
  }
}

class FzCaptionTooltips {
  const FzCaptionTooltips({
    required this.minimize,
    required this.close,
    this.settings,
  });

  final String minimize;
  final String close;
  final String? settings;
}

class FzAppBar extends StatelessWidget {
  const FzAppBar({
    super.key,
    required this.title,
    required this.tooltips,
    required this.hasSettingsButton,
  });

  final String title;
  final FzCaptionTooltips tooltips;
  final bool hasSettingsButton;

  @override
  Widget build(BuildContext context) {
    final FzColors c = context.fz;
    return SizedBox(
      height: FzMetrics.bar,
      child: Row(
        children: <Widget>[
          const SizedBox(width: FzMetrics.pagePadX),
          // Everything left of the buttons is the drag band. Expanded, not Flexible: a flex
          // child with a loose fit still takes its share of the free space, which pushed the
          // buttons a fifth of the way in from the right edge.
          Expanded(
            child: GestureDetector(
              key: const ValueKey<String>('fz-drag-band'),
              behavior: HitTestBehavior.opaque,
              onPanDown: (_) => FzWindow.startDrag(),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: c.ink,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.005),
                ),
              ),
            ),
          ),
          FzCaptionButton(
            glyph: FzCaptionGlyph.minimize,
            tooltip: tooltips.minimize,
            onTap: FzWindow.minimize,
          ),
          if (hasSettingsButton)
            FzCaptionButton(
              glyph: FzCaptionGlyph.settings,
              tooltip: tooltips.settings ?? '',
              onTap: FzWindow.openSettings,
            ),
          FzCaptionButton(
            glyph: FzCaptionGlyph.close,
            tooltip: tooltips.close,
            dangerOnHover: true,
            onTap: FzWindow.close,
          ),
          // The same 16 the page leaves on its right. Without it the close button sat on the
          // frame while everything below it had a gutter.
          const SizedBox(width: FzMetrics.pagePadX),
        ],
      ),
    );
  }
}

enum FzCaptionGlyph { minimize, settings, close }

/// 46x32 on radius 8, flush right, drawn with 1.4px strokes like the specimen's SVGs. Hover
/// takes 140ms; the close button fills the whole cell red rather than recolouring the glyph.
class FzCaptionButton extends StatefulWidget {
  const FzCaptionButton({
    super.key,
    required this.glyph,
    required this.tooltip,
    required this.onTap,
    this.dangerOnHover = false,
  });

  final FzCaptionGlyph glyph;
  final String tooltip;
  final VoidCallback onTap;
  final bool dangerOnHover;

  @override
  State<FzCaptionButton> createState() => _FzCaptionButtonState();
}

class _FzCaptionButtonState extends State<FzCaptionButton> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final FzColors c = context.fz;
    final bool danger = widget.dangerOnHover && _hover;
    final Color fill = danger
        ? c.danger
        : _down
            ? c.press
            : _hover
                ? c.hover
                : fade(c.hover);
    final Color ink = danger ? const Color(0xFFFFFFFF) : c.ink;

    final Widget button = GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: AnimatedContainer(
          duration: _down ? FzMotion.press : FzMotion.bar,
          curve: Curves.easeOutCubic,
          width: FzMetrics.captionButton,
          height: FzMetrics.control,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(FzRadius.base),
          ),
          child: CustomPaint(
            size: const Size(10, 10),
            painter: _CaptionGlyphPainter(glyph: widget.glyph, color: ink),
          ),
        ),
      ),
    );

    if (widget.tooltip.isEmpty) {
      return button;
    }
    return Tooltip(
      message: widget.tooltip,
      decoration: BoxDecoration(
        color: c.menu,
        borderRadius: BorderRadius.circular(FzRadius.small),
        border: Border.all(color: c.menuBorder),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      textStyle: TextStyle(color: c.ink, fontSize: 11),
      child: button,
    );
  }
}

class _CaptionGlyphPainter extends CustomPainter {
  const _CaptionGlyphPainter({required this.glyph, required this.color});

  final FzCaptionGlyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = glyph == FzCaptionGlyph.settings ? 1.1 : 1.4
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    final Offset center = Offset(size.width / 2, size.height / 2);

    switch (glyph) {
      case FzCaptionGlyph.minimize:
        canvas.drawLine(
            Offset(1, center.dy), Offset(size.width - 1, center.dy), stroke);
      case FzCaptionGlyph.close:
        canvas.drawLine(const Offset(1.5, 1.5), const Offset(8.5, 8.5), stroke);
        canvas.drawLine(const Offset(8.5, 1.5), const Offset(1.5, 8.5), stroke);
      case FzCaptionGlyph.settings:
        canvas.drawCircle(center, 1.9, stroke);
        for (int spoke = 0; spoke < 8; spoke++) {
          final double angle = spoke * math.pi / 4;
          final Offset unit = Offset(math.cos(angle), math.sin(angle));
          canvas.drawLine(center + unit * 3.1, center + unit * 4.3, stroke);
        }
    }
  }

  @override
  bool shouldRepaint(_CaptionGlyphPainter old) =>
      old.glyph != glyph || old.color != color;
}
