import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'design.dart';

/// The v3 control set, shared by the settings window and the layout editor.
/// Every duration comes from FzMotion; every radius from FzRadius.

/// The one frame every text input wears, so a field cannot look different in the settings
/// window than it does in the editor: field fill, hairline that goes hot on hover, accent plus
/// the double focus ring while focused. The ring is two outward strokes (1px gap, 2px ink) and
/// both strokes and border animate - on their own tokens, 120ms for focus and 150ms for hover.
class FzFieldFrame extends StatefulWidget {
  const FzFieldFrame({
    super.key,
    required this.focusNode,
    required this.child,
    this.enabled = true,
    this.width,
    this.height = FzMetrics.control,
    this.padding = const EdgeInsets.symmetric(horizontal: 12),
  });

  final FocusNode focusNode;
  final Widget child;
  final bool enabled;
  final double? width;
  final double height;
  final EdgeInsetsGeometry padding;

  @override
  State<FzFieldFrame> createState() => _FzFieldFrameState();
}

class _FzFieldFrameState extends State<FzFieldFrame> {
  bool _hover = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant FzFieldFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_onFocusChange);
      widget.focusNode.addListener(_onFocusChange);
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final FzColors c = context.fz;
    final bool enabled = widget.enabled;
    final bool focused = enabled && widget.focusNode.hasFocus;
    final Color edge = !enabled
        ? c.cardBorder
        : focused
        ? c.accent
        : _hover
        ? c.fieldBorderHot
        : c.fieldBorder;

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.text : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: AnimatedContainer(
          // The ring rides the focus token; the fill and hairline ride hover underneath it.
          duration: FzMotion.focus,
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(FzRadius.base),
            boxShadow: <BoxShadow>[
              // One pixel of ink, no gap stroke: the double ring read as a heavy frame around
              // a 32px field. The colour fades in rather than starting from transparent black,
              // so mid-animation it is not grey.
              BoxShadow(
                color: focused ? c.focusA : fade(c.focusA),
                spreadRadius: 1,
              ),
            ],
          ),
          child: AnimatedContainer(
            duration: FzMotion.hover,
            curve: Curves.easeOutCubic,
            padding: widget.padding,
            decoration: BoxDecoration(
              color: c.field,
              borderRadius: BorderRadius.circular(FzRadius.base),
              border: Border.all(color: edge, width: 1),
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// A [TextField] stripped of its own decoration: [FzFieldFrame] draws the chrome, and the
/// caller owns the [FocusNode] so committing on blur stays in one place.
class FzFieldText extends StatelessWidget {
  const FzFieldText({
    super.key,
    required this.focusNode,
    required this.controller,
    required this.enabled,
    this.style,
    this.hintText = '',
    this.hintStyle,
    this.textAlign = TextAlign.start,
    this.textAlignVertical = TextAlignVertical.center,
    this.keyboardType,
    this.maxLines = 1,
    this.expands = false,
    this.onChanged,
    this.onSubmitted,
  });

  final FocusNode focusNode;
  final TextEditingController controller;
  final bool enabled;
  final TextStyle? style;
  final String hintText;
  final TextStyle? hintStyle;
  final TextAlign textAlign;

  /// The frame gives the field a fixed height, so the text has to be told where to sit in it.
  final TextAlignVertical textAlignVertical;
  final TextInputType? keyboardType;
  final int? maxLines;
  final bool expands;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      style: style,
      textAlign: textAlign,
      textAlignVertical: textAlignVertical,
      keyboardType: keyboardType,
      maxLines: maxLines,
      expands: expands,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      cursorColor: context.fz.accent,
      decoration: InputDecoration(
        isDense: true,
        border: InputBorder.none,
        enabled: enabled,
        hintText: hintText.isEmpty ? null : hintText,
        hintStyle: hintStyle,
        // The frame owns the padding; the text needs none of its own.
        contentPadding: EdgeInsets.zero,
        filled: false,
      ),
    );
  }
}

/// The scrolling area inside the window. The 16px gutter is applied *outside* the clip rather
/// than as scroll padding - inside, a bottom inset only shows up once the list reaches its end,
/// so mid-scroll the cards ran straight into the frame while the sides kept their gap. The clip
/// gives the scrolling content the window's own 8px corners.
/// A number field that has both the caret and the pointer over it owns the wheel. `Listener`
/// callbacks do not consume a `PointerScrollEvent` — the ancestor `Scrollable` hears it too — so
/// without handing the wheel to one owner the page scrolls while the value steps.
class FzWheelOwnership {
  FzWheelOwnership._();

  static final ValueNotifier<int> claimants = ValueNotifier<int>(0);

  static void claim(bool on) {
    claimants.value += on ? 1 : -1;
  }

  static bool get held => claimants.value > 0;
}

class FzViewport extends StatelessWidget {
  const FzViewport({
    super.key,
    required this.children,
    this.controller,
    this.top = 8,
    this.listKey,
  });

  final List<Widget> children;
  final ScrollController? controller;
  final double top;

  /// Passed to the ListView so an AnimatedSwitcher can tell the pages apart.
  final Key? listKey;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        FzMetrics.pagePadX,
        top,
        FzMetrics.pagePadX,
        FzMetrics.pagePadX,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(FzRadius.base),
        child: ValueListenableBuilder<int>(
          valueListenable: FzWheelOwnership.claimants,
          builder: (BuildContext context, int claims, Widget? child) => Scrollbar(
            controller: controller,
            child: ListView(
              key: listKey,
              controller: controller,
              padding: EdgeInsets.zero,
              // Only while a field is spinning the wheel: dragging and scrolling come back the
              // moment the caret leaves.
              physics: claims > 0
                  ? const NeverScrollableScrollPhysics()
                  : null,
              children: children,
            ),
          ),
        ),
      ),
    );
  }
}

/// The specimen's `cardIn`: a list item fades up 6px and settles at full size, each one starting
/// a step behind its neighbour. This is the only place `--d-enter` is allowed - the tile grid and
/// the quick-switch row, where the eye needs the sequence to read a set as assembled, not pasted.
class FzEnter extends StatefulWidget {
  const FzEnter({
    super.key,
    required this.index,
    required this.child,
    this.step = const Duration(milliseconds: 26),
  });

  final int index;
  final Duration step;
  final Widget child;

  @override
  State<FzEnter> createState() => _FzEnterState();
}

class _FzEnterState extends State<FzEnter> {
  bool _on = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(widget.step * widget.index, () {
      if (mounted) {
        setState(() => _on = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: _on ? 1 : 0),
      duration: FzMotion.enter,
      curve: Curves.fastOutSlowIn, // cubic-bezier(0, 0, .2, 1)
      builder: (BuildContext context, double t, Widget? child) => Opacity(
        // Transforms only: the layout is settled before the first frame, so a staggered row
        // never reflows while it plays.
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 6),
          child: Transform.scale(scale: 0.985 + 0.015 * t, child: child),
        ),
      ),
      child: widget.child,
    );
  }
}

/// Reports pointer hover to a builder, so a control can animate its hairline without
/// reimplementing the MouseRegion pair. The caller still owns the animation widget - keep it
/// inside the builder, not around it, or the cursor chip repaints the whole subtree.
class FzHoverBuilder extends StatefulWidget {
  const FzHoverBuilder({
    super.key,
    required this.builder,
    this.enabled = true,
    this.clickable = true,
  });

  final Widget Function(BuildContext context, bool hovering) builder;
  final bool enabled;
  final bool clickable;

  @override
  State<FzHoverBuilder> createState() => _FzHoverBuilderState();
}

class _FzHoverBuilderState extends State<FzHoverBuilder> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: !widget.enabled
          ? SystemMouseCursors.basic
          : widget.clickable
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: widget.enabled ? (_) => setState(() => _hover = true) : null,
      onExit: widget.enabled ? (_) => setState(() => _hover = false) : null,
      child: widget.builder(context, widget.enabled && _hover),
    );
  }
}

class FzChip extends StatelessWidget {
  const FzChip({super.key, required this.text, this.accent = false});
  final String text;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final FzColors c = context.fz;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: accent ? c.accentSoft : c.field,
        borderRadius: BorderRadius.circular(FzRadius.small),
        border: Border.all(color: accent ? c.accent : c.fieldBorder, width: 1),
      ),
      child: Text(
        text,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: accent ? c.accent : c.ink2,
          fontSize: 10.5,
          height: 1.4,
        ),
      ),
    );
  }
}

class FzToggle extends StatelessWidget {
  const FzToggle({super.key, required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final FzColors c = context.fz;
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: FzMotion.check,
          curve: Curves.easeOutCubic,
          width: FzMetrics.toggleW,
          height: FzMetrics.toggleH,
          decoration: BoxDecoration(
            color: value ? c.accent : c.field,
            borderRadius: BorderRadius.circular(FzRadius.pill),
            border: Border.all(
              color: value ? c.accent : c.fieldBorder,
              width: 1,
            ),
          ),
          child: AnimatedAlign(
            duration: FzMotion.check,
            curve: Curves.easeOutCubic,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Container(
                width: FzMetrics.toggleKnob,
                height: FzMetrics.toggleKnob,
                decoration: BoxDecoration(
                  color: value ? c.accentInk : c.ink2,
                  borderRadius: BorderRadius.circular(FzRadius.pill),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One container, one sliding thumb, one row of labels. The thumb is a single animated rect
/// rather than a background per cell, so switching sections slides it across instead of
/// cross-fading two fills.
class FzSegmented extends StatelessWidget {
  const FzSegmented({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
    this.width = FzMetrics.fieldWidth,
  });

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;
  final double width;

  // Everything below is measured inside the container's own box: the 1px hairline is drawn in
  // that box, so the child area is (width - 2) x (32 - 2), and the thumb sits 3px inside it.
  static const double _pad = 3;
  static const double _gap = 2;

  @override
  Widget build(BuildContext context) {
    final FzColors c = context.fz;
    final double innerWidth = width - 2;
    final double innerHeight = FzMetrics.control - 2;
    final double cellWidth =
        (innerWidth - 2 * _pad - _gap * (labels.length - 1)) / labels.length;
    final double cellHeight = innerHeight - 2 * _pad;

    return Container(
      width: width,
      height: FzMetrics.control,
      decoration: BoxDecoration(
        color: c.field,
        borderRadius: BorderRadius.circular(FzRadius.base),
        border: Border.all(color: c.fieldBorder, width: 1),
      ),
      child: Stack(
        children: <Widget>[
          AnimatedPositioned(
            duration: FzMotion.seg,
            curve: Curves.easeOutCubic,
            left: _pad + index * (cellWidth + _gap),
            top: _pad,
            width: cellWidth,
            height: cellHeight,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: c.card,
                borderRadius: BorderRadius.circular(FzRadius.thumb),
                border: Border.all(color: c.fieldBorder, width: 1),
              ),
            ),
          ),
          Positioned.fill(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: List<Widget>.generate(labels.length, (int i) {
                return Padding(
                  padding: EdgeInsets.only(left: i == 0 ? 0 : _gap),
                  child: SizedBox(
                    width: cellWidth,
                    height: cellHeight,
                    child: _SegmentCell(
                      label: labels[i],
                      selected: i == index,
                      onTap: () => onChanged(i),
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class _SegmentCell extends StatefulWidget {
  const _SegmentCell({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_SegmentCell> createState() => _SegmentCellState();
}

class _SegmentCellState extends State<_SegmentCell> {
  @override
  Widget build(BuildContext context) {
    final FzColors c = context.fz;
    return GestureDetector(
      onTap: widget.onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          alignment: Alignment.center,
          // No hover fill: the sliding thumb is the only thing that marks a cell, and a grey
          // band under the pointer read as a second selection.
          child: Text(
            widget.label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: widget.selected ? c.ink : c.ink2,
              fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

class FzButton extends StatefulWidget {
  const FzButton({
    super.key,
    required this.label,
    this.onTap,
    this.width,
    this.primary = false,
    this.enabled = true,
    this.dangerOnHover = false,
  });

  final String label;
  final VoidCallback? onTap;
  final double? width;
  final bool primary;
  final bool enabled;

  /// For a button that destroys something: it is a normal secondary button until the pointer
  /// comes over it, and then the hairline, the label and a one-pixel ring all go red.
  final bool dangerOnHover;

  @override
  State<FzButton> createState() => _FzButtonState();
}

class _FzButtonState extends State<FzButton> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final FzColors c = context.fz;
    final bool on = widget.enabled;
    // A primary button keeps its accent fill all the way through the press - the specimen only
    // shifts it down a pixel - while a secondary one drops to the press colour.
    final Color fill = !on
        ? fade(c.field)
        : widget.primary
        ? (_hover ? c.accentHot : c.accent)
        : (_down ? c.press : (_hover ? c.hover : c.field));
    final Color border = !on
        ? c.cardBorder
        : widget.primary
        ? c.accent
        : (widget.dangerOnHover && _hover)
        ? c.danger
        : (_hover ? c.fieldBorderHot : c.fieldBorder);
    final Color ink = !on
        ? c.ink3
        : widget.primary
        ? c.accentInk
        : (widget.dangerOnHover && _hover)
        ? c.danger
        : c.ink;
    // One shadow slot that is always there, so the red ring fades in instead of appearing.
    final Color ring =
        (widget.dangerOnHover && _hover && on)
        ? c.danger.withValues(alpha: 0.35)
        : fade(c.danger);

    return GestureDetector(
      onTapDown: on ? (_) => setState(() => _down = true) : null,
      onTapUp: on ? (_) => setState(() => _down = false) : null,
      onTapCancel: on ? () => setState(() => _down = false) : null,
      onTap: on ? () => widget.onTap?.call() : null,
      child: MouseRegion(
        cursor: on ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: on ? (_) => setState(() => _hover = true) : null,
        onExit: on ? (_) => setState(() => _hover = false) : null,
        child: AnimatedContainer(
          duration: _down ? FzMotion.press : FzMotion.hover,
          curve: Curves.easeOutCubic,
          transform: Matrix4.translationValues(0, _down && on ? 1 : 0, 0),
          width: widget.width,
          height: FzMetrics.control,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(FzRadius.base),
            border: Border.all(color: border, width: 1),
            boxShadow: <BoxShadow>[
              BoxShadow(color: ring, blurRadius: 0, spreadRadius: ring.a > 0 ? 1 : 0),
            ],
          ),
          child: Text(
            widget.label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: ink,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// Like the native one: a flag-backed choice stores a bool, so index 1 means true.
/// A choice with more than three options: the v3 field plus a popup this app draws itself.
///
/// `MenuAnchor` was the obvious starting point, but its transition is not configurable and the
/// spec wants a panel to arrive and leave on the same durations as everything else - so the
/// entry and the exit are animated here, over an overlay that anchors to the field.
class FzChoice extends StatelessWidget {
  const FzChoice({
    super.key,
    required this.labels,
    required this.index,
    required this.segmented,
    required this.onChanged,
  });

  final List<String> labels;
  final int index;
  final bool segmented;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    if (segmented) {
      return FzSegmented(labels: labels, index: index, onChanged: onChanged);
    }
    return FzDropdown(labels: labels, index: index, onChanged: onChanged);
  }
}

/// Lets the owner ask an open popup to play its exit. The popup registers itself here, so the
/// entry is removed when that animation ends rather than the moment the request is made.
class FzPopupHandle {
  VoidCallback? dismiss;
}

class FzDropdown extends StatefulWidget {
  const FzDropdown({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
  });

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  State<FzDropdown> createState() => _FzDropdownState();
}

class _FzDropdownState extends State<FzDropdown> {
  final LayerLink _link = LayerLink();
  final FzPopupHandle _handle = FzPopupHandle();
  OverlayEntry? _entry;

  bool get _open => _entry != null;

  static double panelHeight(int items) =>
      items * FzMetrics.control + 2 * FzMetrics.menuPad;

  @override
  void dispose() {
    _entry?.remove();
    super.dispose();
  }

  void _toggle() {
    if (_open) {
      _handle.dismiss?.call();
      return;
    }
    _show();
  }

  void _show() {
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box == null) {
      return;
    }
    final Offset anchor = box.localToGlobal(Offset.zero);
    final Size screen = MediaQuery.sizeOf(context);
    final double needed = panelHeight(widget.labels.length);
    final bool dropUp =
        anchor.dy + FzMetrics.control + FzMetrics.menuGap + needed >
        screen.height;

    _entry = OverlayEntry(
      builder: (BuildContext context) => _FzPopup(
        link: _link,
        handle: _handle,
        labels: widget.labels,
        index: widget.index,
        dropUp: dropUp,
        needed: needed,
        onPick: (int i) {
          widget.onChanged(i);
          _handle.dismiss?.call();
        },
        onFinished: _remove,
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(_entry!);
    setState(() {});
  }

  void _remove() {
    _entry?.remove();
    _entry = null;
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: _ChoiceField(
        label: widget.labels[widget.index],
        open: _open,
        onTap: _toggle,
      ),
    );
  }
}

class _FzPopup extends StatefulWidget {
  const _FzPopup({
    required this.link,
    required this.handle,
    required this.labels,
    required this.index,
    required this.dropUp,
    required this.needed,
    required this.onPick,
    required this.onFinished,
  });

  final LayerLink link;
  final FzPopupHandle handle;
  final List<String> labels;
  final int index;
  final bool dropUp;
  final double needed;
  final ValueChanged<int> onPick;
  final VoidCallback onFinished;

  @override
  State<_FzPopup> createState() => _FzPopupState();
}

class _FzPopupState extends State<_FzPopup>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    duration: FzMotion.page,
    reverseDuration: FzMotion.select,
    vsync: this,
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.fastOutSlowIn,
  );
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    widget.handle.dismiss = _dismiss;
    _controller.forward();
  }

  @override
  void dispose() {
    widget.handle.dismiss = null;
    _controller.dispose();
    super.dispose();
  }

  void _dismiss() {
    if (_closing) {
      return;
    }
    setState(() => _closing = true);
    _controller.reverse().whenComplete(widget.onFinished);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      _dismiss();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final FzColors c = context.fz;
    return Stack(
      children: <Widget>[
        // The barrier only has to swallow the tap that closes the panel; it paints nothing, so
        // the window behind it stays exactly as it was.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _dismiss,
            child: const SizedBox.expand(),
          ),
        ),
        CompositedTransformFollower(
          link: widget.link,
          showWhenUnlinked: false,
          offset: Offset(
            0,
            widget.dropUp
                ? -(widget.needed + FzMetrics.menuGap)
                : FzMetrics.control + FzMetrics.menuGap,
          ),
          child: FadeTransition(
            opacity: _curve,
            // A small slide along the axis it opened from: 12% of the panel's own height.
            child: SlideTransition(
              position: Tween<Offset>(
                begin: Offset(0, widget.dropUp ? 0.12 : -0.12),
                end: Offset.zero,
              ).animate(_curve),
              child: Focus(
                autofocus: true,
                onKeyEvent: _onKey,
                child: SizedBox(
                  width: FzMetrics.fieldWidth,
                  child: Material(
                    elevation: 0,
                    color: c.menu,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(FzRadius.base),
                      side: BorderSide(color: c.menuBorder),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Padding(
                      padding: const EdgeInsets.all(FzMetrics.menuPad),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        // Without this every item sizes itself to its own label, so the bands
                        // come out different widths and the text looks centred.
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: List<Widget>.generate(
                          widget.labels.length,
                          (int i) => _PopupItem(
                            label: widget.labels[i],
                            selected: i == widget.index,
                            onTap: () => widget.onPick(i),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PopupItem extends StatefulWidget {
  const _PopupItem({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_PopupItem> createState() => _PopupItemState();
}

class _PopupItemState extends State<_PopupItem> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final FzColors c = context.fz;
    final Color fill = _down
        ? c.press
        : _hover
        ? c.hover
        : widget.selected
        ? c.accentSoft
        : fade(c.hover);
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: AnimatedContainer(
          duration: FzMotion.hover,
          curve: Curves.easeOutCubic,
          height: FzMetrics.control,
          // The band is a fixed 32 tall and the label is 12, so without this the text sits on the
          // top of its own row.
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(FzRadius.small),
          ),
          child: Text(
            widget.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: c.ink,
              fontSize: 12,
              fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

/// The dropdown's field: hairline goes hot on hover, accent while the popup is open, and the
/// caret turns over on the select duration instead of swapping icons.
class _ChoiceField extends StatefulWidget {
  const _ChoiceField({
    required this.label,
    required this.open,
    required this.onTap,
  });

  final String label;
  final bool open;
  final VoidCallback onTap;

  @override
  State<_ChoiceField> createState() => _ChoiceFieldState();
}

class _ChoiceFieldState extends State<_ChoiceField> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final FzColors c = context.fz;
    return GestureDetector(
      onTap: widget.onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: AnimatedContainer(
          duration: FzMotion.hover,
          curve: Curves.easeOutCubic,
          width: FzMetrics.fieldWidth,
          height: FzMetrics.control,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: c.field,
            borderRadius: BorderRadius.circular(FzRadius.base),
            border: Border.all(
              color: widget.open
                  ? c.accent
                  : _hover
                  ? c.fieldBorderHot
                  : c.fieldBorder,
              width: 1,
            ),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  widget.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: c.ink, fontSize: 12),
                ),
              ),
              AnimatedRotation(
                turns: widget.open ? 0.5 : 0,
                duration: FzMotion.select,
                curve: Curves.easeOutCubic,
                child: CustomPaint(
                  size: const Size(6, 4),
                  painter: _CaretPainter(color: c.ink2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CaretPainter extends CustomPainter {
  const _CaretPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    canvas.drawPath(
      Path()
        ..moveTo(0, 0)
        ..lineTo(size.width / 2, size.height)
        ..lineTo(size.width, 0),
      stroke,
    );
  }

  @override
  bool shouldRepaint(_CaretPainter old) => old.color != color;
}

/// Commits on blur or Enter, never on every keystroke: each write makes the engine re-read the
/// whole settings file, so the native window does the same (OnEditLostFocus).
/// [onChanged] fires live, for fields that only drive local state (the editor's zone count).
class FzNumberField extends StatefulWidget {
  const FzNumberField({
    super.key,
    required this.value,
    this.onCommit,
    this.onChanged,
    this.width = FzMetrics.numberWidth,
    this.enabled = true,
    this.min,
    this.max,
  });

  final int value;
  final ValueChanged<int>? onCommit;
  final ValueChanged<int>? onChanged;
  final double width;
  final bool enabled;

  /// The same bounds the engine applies to the row. A field that lets you wheel past them shows a
  /// value the file would not keep.
  final int? min;
  final int? max;

  @override
  State<FzNumberField> createState() => _FzNumberFieldState();
}

class _FzNumberFieldState extends State<FzNumberField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value.toString(),
  );
  final FocusNode _focus = FocusNode();

  /// Where the wheel has got to. Kept locally because the parent's `value` only comes back after a
  /// write and a reload, which is slower than a flick of the wheel.
  int? _spinning;

  bool _over = false;
  bool _claiming = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    _updateClaim();
    if (!_focus.hasFocus) {
      _spinning = null;
      _commit();
    }
  }

  /// The wheel belongs to a focused field only while the pointer is over it; everywhere else the
  /// list keeps its scroll.
  void _updateClaim() {
    final bool want = _over && _focus.hasFocus && widget.enabled;
    if (want == _claiming) {
      return;
    }
    _claiming = want;
    FzWheelOwnership.claim(want);
  }

  @override
  void didUpdateWidget(covariant FzNumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateClaim();
    if (widget.value != oldWidget.value) {
      _spinning = null;
      if (!_focus.hasFocus) {
        _controller.text = widget.value.toString();
      }
    }
  }

  @override
  void dispose() {
    if (_claiming) {
      FzWheelOwnership.claim(false);
      _claiming = false;
    }
    _focus.removeListener(_onFocusChange);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  int _clamp(int v) {
    final int? lo = widget.min;
    final int? hi = widget.max;
    if (lo != null && v < lo) {
      return lo;
    }
    if (hi != null && v > hi) {
      return hi;
    }
    return v;
  }

  void _commit() {
    final int? parsed = int.tryParse(_controller.text.trim());
    if (parsed == null) {
      return;
    }
    final int bounded = _clamp(parsed);
    if (bounded != widget.value) {
      widget.onCommit?.call(bounded);
    }
  }

  /// A notch of the wheel over a focused field steps the number, the way a native spinner does.
  /// Gated on the caret being in the box, so a wheel over the list still scrolls the list.
  void _onPointerSignal(PointerSignalEvent event) {
    if (!widget.enabled || !_focus.hasFocus) {
      return;
    }
    if (event is! PointerScrollEvent || event.scrollDelta.dy == 0) {
      return;
    }
    final int next = _clamp((_spinning ?? widget.value) + (event.scrollDelta.dy > 0 ? -1 : 1));
    if (next == _spinning) {
      return;  // already at the end of the range; do not fire a write that changes nothing
    }
    setState(() {
      _spinning = next;
      _controller.text = next.toString();
    });
    widget.onChanged?.call(next);
    widget.onCommit?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    final FzColors c = context.fz;
    return MouseRegion(
      onEnter: (_) {
        setState(() => _over = true);
        _updateClaim();
      },
      onExit: (_) {
        setState(() => _over = false);
        _updateClaim();
      },
      child: Listener(
        onPointerSignal: _onPointerSignal,
        child: FzFieldFrame(
          focusNode: _focus,
          enabled: widget.enabled,
          width: widget.width,
          child: FzFieldText(
            focusNode: _focus,
            controller: _controller,
            enabled: widget.enabled,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            style: TextStyle(color: widget.enabled ? c.ink : c.ink3, fontSize: 12),
            onChanged: (String s) {
              final int? parsed = int.tryParse(s.trim());
              if (parsed != null) {
                _spinning = parsed;
                widget.onChanged?.call(parsed);
              }
            },
            onSubmitted: (_) {
              _spinning = null;
              _commit();
            },
          ),
        ),
      ),
    );
  }
}
