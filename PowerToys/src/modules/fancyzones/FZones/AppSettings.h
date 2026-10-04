#pragma once

#include "FZonesStrings.h"

enum class ThemeMode
{
    System = 0,
    Light = 1,
    Dark = 2,
};

// UI preferences that belong to this app, not to the zone engine's settings.json. They live in
// ui-settings.json, which the Flutter settings page writes and this process watches: the two are
// separate exes, so the file is the whole protocol between them. It is deliberately NOT the
// engine's settings.json, whose FileWatcher would reload the zone engine on a theme change.
namespace AppSettings
{
    void Load();

    /// Start following the file. Without this a language or theme change only lands at the next
    /// start of the engine.
    void Watch();

    ThemeMode Theme();
    void SetTheme(ThemeMode mode);

    Language LanguageSetting();
    void SetLanguageSetting(Language language);

    bool AutostartEnabled();
    bool SetAutostartEnabled(bool enabled);

    bool SystemPrefersDark();
    bool UsesDarkTheme();
}
