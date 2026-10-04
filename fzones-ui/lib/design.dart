import 'package:flutter/material.dart';

/// Review controls for the POC; the shipped app reads ui-settings.json instead.
enum FzThemeMode { system, light, dark }

enum FzLangMode { system, en, zh }

/// Design tokens ported from FZones/FZonesTheme.cpp and
/// documents/designs/fzones_design_system.md. Keep in sync with the C++.
class FzRadius {
  static const double base = 8; // frame, card, field, button, menu, tile
  static const double thumb = 5; // segmented thumb = 8 - 3
  static const double small = 4; // menu item, keycap, zone, badge
  static const double grip = 2; // canvas selection handle
  static const double pill = 999; // closed list: toggle, scrollbar
}

class FzMetrics {
  static const double bar = 48;
  static const double captionButton = 46;
  static const double frameStroke = 1;

  /// The invisible band along the window's own edge that hands a drag to the system resize loop.
  static const double grabBand = 6;

  /// The dropdown panel's own inner padding, and the gap it opens by.
  static const double menuPad = 4;
  static const double menuGap = 4;

  /// How far the row highlight sits inside the card's content box, and how far the row's own
  /// content sits inside that. The content is inset further than the band, so the band breathes
  /// evenly around the label and the control instead of running under them.
  static const EdgeInsets rowInset = EdgeInsets.fromLTRB(6, 3, 6, 3);
  static const EdgeInsets rowContentInset = EdgeInsets.symmetric(
    horizontal: 12,
  );
  static const double row = 44;
  static const double control = 32;
  static const double header = 36;
  static const double tab = 36;
  static const double section = 18;
  static const double cardPadX = 16;
  static const double pagePadX = 16;

  /// 320 + the 280 control column + the slack between them, all inside the row's content inset.
  /// The card's content box is 636 wide, so a 340 label column left no room to inset the row.
  static const double labelWidth = 320;
  static const double fieldWidth = 280;
  static const double numberWidth = 84;
  static const double toggleW = 40;
  static const double toggleH = 20;
  static const double toggleKnob = 12;
}

/// Every duration the app may use, nothing else (v3 §7.3).
class FzMotion {
  static const Duration hover = Duration(milliseconds: 150);
  static const Duration press = Duration(milliseconds: 90);
  static const Duration check = Duration(milliseconds: 180);
  static const Duration seg = Duration(milliseconds: 180);
  static const Duration focus = Duration(milliseconds: 120);
  static const Duration select = Duration(milliseconds: 150);
  static const Duration bar = Duration(milliseconds: 140);
  static const Duration page = Duration(milliseconds: 200);
  static const Duration theme = Duration(milliseconds: 240);
  static const Duration collapse = Duration(milliseconds: 220);
  static const Duration enter = Duration(milliseconds: 260);
}

@immutable
class FzColors {
  const FzColors({
    required this.accent,
    required this.accentInk,
    required this.accentSoft,
    required this.win,
    required this.card,
    required this.cardBorder,
    required this.frame,
    required this.field,
    required this.fieldBorder,
    required this.fieldBorderHot,
    required this.hover,
    required this.press,
    required this.ink,
    required this.ink2,
    required this.ink3,
    required this.menu,
    required this.menuBorder,
    required this.scroll,
    required this.danger,
    required this.focusA,
    required this.focusB,
  });

  final Color accent;
  final Color accentInk;
  final Color accentSoft;
  final Color win;
  final Color card;
  final Color cardBorder;
  final Color frame;
  final Color field;
  final Color fieldBorder;
  final Color fieldBorderHot;
  final Color hover;
  final Color press;
  final Color ink;
  final Color ink2;
  final Color ink3;
  final Color menu;
  final Color menuBorder;
  final Color scroll;

  /// The close button's hover fill, and the only colour in the palette that does not change
  /// with the theme.
  final Color danger;
  final Color focusA;
  final Color focusB;

  /// A primary button's hover fill. Derived rather than tabulated - 88% accent, 12% ink, which
  /// is `color-mix(in srgb, accent 88%, ink)` in the specimen - so it still reads correctly
  /// mid-crossfade, when the palette itself is a lerp.
  Color get accentHot => Color.lerp(accent, ink, 0.12)!;

  static const FzColors light = FzColors(
    accent: Color(0xFF0F6CBD),
    accentInk: Color(0xFFFFFFFF),
    accentSoft: Color(0x1F0F6CBD),
    win: Color(0xFFF3F3F3),
    card: Color(0xFFFBFBFB),
    cardBorder: Color(0xFFE6E6E6),
    frame: Color(0xFFD7D7D7),
    field: Color(0xFFFFFFFF),
    fieldBorder: Color(0xFFCFCFCF),
    fieldBorderHot: Color(0xFF8A8A8A),
    hover: Color(0xFFF4F4F4),
    press: Color(0xFFECECEC),
    ink: Color(0xFF1A1A1A),
    ink2: Color(0xFF5C5C5C),
    ink3: Color(0xFF9A9A9A),
    menu: Color(0xFFF9F9F9),
    menuBorder: Color(0xFFE0E0E0),
    scroll: Color(0xFFB0B0B0),
    danger: Color(0xFFC42B1C),
    focusA: Color(0xFF0B0B0B),
    focusB: Color(0xFFFFFFFF),
  );

  static const FzColors dark = FzColors(
    accent: Color(0xFF4CC2FF),
    accentInk: Color(0xFF0B2340),
    accentSoft: Color(0x294CC2FF),
    win: Color(0xFF202020),
    card: Color(0xFF2B2B2B),
    cardBorder: Color(0xFF383838),
    frame: Color(0xFF3D3D3D),
    field: Color(0xFF323232),
    fieldBorder: Color(0xFF4D4D4D),
    fieldBorderHot: Color(0xFF7A7A7A),
    hover: Color(0xFF353535),
    press: Color(0xFF3F3F3F),
    ink: Color(0xFFFFFFFF),
    ink2: Color(0xFFC9C9C9),
    ink3: Color(0xFF7E7E7E),
    menu: Color(0xFF2C2C2C),
    menuBorder: Color(0xFF3A3A3A),
    scroll: Color(0xFF5C5C5C),
    danger: Color(0xFFC42B1C),
    focusA: Color(0xFFFFFFFF),
    focusB: Color(0xFF000000),
  );

  /// Lets Flutter's theme animation interpolate the whole palette, which is the 240ms
  /// crossfade the native side implements by hand in Theme::AdvanceTheme.
  static FzColors lerp(FzColors a, FzColors b, double t) {
    Color m(Color x, Color y) => Color.lerp(x, y, t)!;
    return FzColors(
      accent: m(a.accent, b.accent),
      accentInk: m(a.accentInk, b.accentInk),
      accentSoft: m(a.accentSoft, b.accentSoft),
      win: m(a.win, b.win),
      card: m(a.card, b.card),
      cardBorder: m(a.cardBorder, b.cardBorder),
      frame: m(a.frame, b.frame),
      field: m(a.field, b.field),
      fieldBorder: m(a.fieldBorder, b.fieldBorder),
      fieldBorderHot: m(a.fieldBorderHot, b.fieldBorderHot),
      hover: m(a.hover, b.hover),
      press: m(a.press, b.press),
      ink: m(a.ink, b.ink),
      ink2: m(a.ink2, b.ink2),
      ink3: m(a.ink3, b.ink3),
      menu: m(a.menu, b.menu),
      menuBorder: m(a.menuBorder, b.menuBorder),
      scroll: m(a.scroll, b.scroll),
      danger: m(a.danger, b.danger),
      focusA: m(a.focusA, b.focusA),
      focusB: m(a.focusB, b.focusB),
    );
  }
}

class FzTheme extends ThemeExtension<FzTheme> {
  const FzTheme(this.colors);
  final FzColors colors;

  @override
  FzTheme copyWith({FzColors? colors}) => FzTheme(colors ?? this.colors);

  @override
  FzTheme lerp(ThemeExtension<FzTheme>? other, double t) =>
      other is FzTheme ? FzTheme(FzColors.lerp(colors, other.colors, t)) : this;
}

extension FzContext on BuildContext {
  FzColors get fz => Theme.of(this).extension<FzTheme>()!.colors;
}

/// The "off" end of a colour transition: the same hue at zero alpha.
///
/// Animating from [Colors.transparent] instead lerps through transparent *black*, so a pale
/// hover band passes through mid-grey on its way in - which is what made a row highlight read
/// as both too dark and, with two rows mid-fade at once, as two bands.
Color fade(Color c) => c.withValues(alpha: 0);

/// The UI face follows the resolved language, exactly like Theme::CreateUiFont does:
/// Segoe UI Variable Text for Latin, Microsoft YaHei UI once the strings are Chinese.
String fzFontFamily(bool chinese) =>
    chinese ? 'Microsoft YaHei UI' : 'Segoe UI Variable Text';

ThemeData buildFzTheme(FzColors c, bool chinese) {
  final ThemeData base = ThemeData(
    useMaterial3: true,
    brightness: c == FzColors.dark ? Brightness.dark : Brightness.light,
    fontFamily: fzFontFamily(chinese),
    fontFamilyFallback: const ['Microsoft YaHei UI', 'Segoe UI', 'sans-serif'],
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    extensions: [FzTheme(c)],
  );

  return base.copyWith(
    scaffoldBackgroundColor: c.win,
    canvasColor: c.card,
    colorScheme: base.colorScheme.copyWith(
      primary: c.accent,
      onPrimary: c.accentInk,
      surface: c.card,
      onSurface: c.ink,
      outline: c.fieldBorder,
    ),
    textTheme: base.textTheme.apply(bodyColor: c.ink, displayColor: c.ink),
    dividerColor: c.cardBorder,
    focusColor: c.focusA,
  );
}
