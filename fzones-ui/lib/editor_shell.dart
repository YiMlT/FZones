import 'package:flutter/material.dart';

import 'design.dart';
import 'widgets.dart';

/// Chrome shared by the three editor pages (browse, grid, canvas) so they cannot drift apart.

class FzEditorShell extends StatelessWidget {
  const FzEditorShell({
    super.key,
    required this.colors,
    required this.bar,
    required this.body,
  });

  final FzColors colors;
  final List<Widget> bar;
  final List<Widget> body;

  @override
  Widget build(BuildContext context) {
    final FzColors c = colors;
    return FzViewport(
      top: 12,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(FzRadius.base),
          ),
          // A foreground stroke, so the hairline costs the content no width.
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(FzRadius.base),
            border: Border.all(color: c.cardBorder, width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(children: bar),
              const SizedBox(height: 12),
              ...body,
            ],
          ),
        ),
      ],
    );
  }
}

class FzFieldLabel extends StatelessWidget {
  const FzFieldLabel({super.key, required this.colors, required this.text});
  final FzColors colors;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Text(text, style: TextStyle(color: colors.ink, fontSize: 12)),
      );
}

/// The editor's plain text input: same frame as every other field in the app, so the name box
/// on the grid page cannot drift away from the hex field on the settings page.
class FzTextField extends StatefulWidget {
  const FzTextField({
    super.key,
    required this.colors,
    required this.controller,
    this.hint = '',
    this.width,
  });

  final FzColors colors;
  final TextEditingController controller;
  final String hint;
  final double? width;

  @override
  State<FzTextField> createState() => _FzTextFieldState();
}

class _FzTextFieldState extends State<FzTextField> {
  final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final FzColors c = widget.colors;
    return FzFieldFrame(
      focusNode: _focus,
      width: widget.width,
      child: FzFieldText(
        focusNode: _focus,
        controller: widget.controller,
        enabled: true,
        hintText: widget.hint,
        hintStyle: TextStyle(color: c.ink3, fontSize: 12),
        style: TextStyle(color: c.ink, fontSize: 12),
      ),
    );
  }
}
