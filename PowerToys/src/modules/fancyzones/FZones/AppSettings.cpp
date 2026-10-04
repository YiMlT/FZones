#include "pch.h"
#include "AppSettings.h"

#include <common/SettingsAPI/FileWatcher.h>
#include <common/SettingsAPI/settings_helpers.h>
#include <common/utils/json.h>

#include <FancyZonesLib/ModuleConstants.h>

namespace
{
    constexpr wchar_t FILE_NAME[] = L"\\ui-settings.json";
    constexpr wchar_t THEME_KEY[] = L"theme";
    constexpr wchar_t LANGUAGE_KEY[] = L"language";
    constexpr wchar_t RUN_KEY[] = L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
    constexpr wchar_t RUN_VALUE[] = L"FZones";

    struct State
    {
        ThemeMode theme = ThemeMode::System;
        Language language = Language::System;
    };

    State state;

    // Lives here rather than in the caller because this module owns the file: the settings page is
    // a separate process, so watching it is the only way a language or theme change reaches an
    // engine that is already running.
    std::optional<FileWatcher> settingsWatcher;

    std::wstring FilePath()
    {
        return PTSettingsHelper::get_module_save_folder_location(NonLocalizable::ModuleKey) + FILE_NAME;
    }

    int ReadInt(const json::JsonObject& root, const wchar_t* key, int fallback)
    {
        if (!json::has(root, key, json::JsonValueType::Number))
        {
            return fallback;
        }
        return static_cast<int>(root.GetNamedNumber(key));
    }

    void WriteName(const json::JsonObject& root, const wchar_t* key, const wchar_t* name)
    {
        root.SetNamedValue(key, json::JsonValue::CreateStringValue(name));
    }

    // The Flutter UI owns this file's shape: it stores the enum *names*, not their numbers. Reading
    // only integers made every value the UI wrote fall back to "system", which is why the tray menu
    // never followed a language change - and why a theme set from the settings page looked ignored.
    // Accept both forms, name first, so a file written by either side reads the same.
    int ReadChoice(const json::JsonObject& root,
                   const wchar_t* key,
                   const std::pair<const wchar_t*, int> (&names)[3],
                   int fallback)
    {
        if (json::has(root, key, json::JsonValueType::String))
        {
            const std::wstring value = root.GetNamedString(key).c_str();
            for (const auto& [name, number] : names)
            {
                if (value == name)
                {
                    return number;
                }
            }
            return fallback;
        }
        return ReadInt(root, key, fallback);
    }

    constexpr std::pair<const wchar_t*, int> THEME_NAMES[] = {
        { L"system", static_cast<int>(ThemeMode::System) },
        { L"light", static_cast<int>(ThemeMode::Light) },
        { L"dark", static_cast<int>(ThemeMode::Dark) },
    };

    constexpr std::pair<const wchar_t*, int> LANGUAGE_NAMES[] = {
        { L"system", static_cast<int>(Language::System) },
        { L"en", static_cast<int>(Language::English) },
        { L"zh", static_cast<int>(Language::Chinese) },
    };

    const wchar_t* ThemeName(ThemeMode mode)
    {
        for (const auto& [name, number] : THEME_NAMES)
        {
            if (number == static_cast<int>(mode))
            {
                return name;
            }
        }
        return L"system";
    }

    const wchar_t* LanguageName(Language language)
    {
        for (const auto& [name, number] : LANGUAGE_NAMES)
        {
            if (number == static_cast<int>(language))
            {
                return name;
            }
        }
        return L"system";
    }

    void Persist()
    {
        json::JsonObject root;
        WriteName(root, THEME_KEY, ThemeName(state.theme));
        WriteName(root, LANGUAGE_KEY, LanguageName(state.language));
        json::to_file(FilePath(), root);
    }
}

namespace AppSettings
{
    void Load()
    {
        const auto loaded = json::from_file(FilePath());
        if (loaded.has_value())
        {
            state.theme = static_cast<ThemeMode>(ReadChoice(*loaded, THEME_KEY, THEME_NAMES, static_cast<int>(ThemeMode::System)));
            state.language = static_cast<Language>(ReadChoice(*loaded, LANGUAGE_KEY, LANGUAGE_NAMES, static_cast<int>(Language::System)));
        }

        Loc::SetLanguage(state.language);
    }

    void Watch()
    {
        settingsWatcher.emplace(FilePath(), [] { Load(); });
    }

    ThemeMode Theme()
    {
        return state.theme;
    }

    void SetTheme(ThemeMode mode)
    {
        state.theme = mode;
        Persist();
    }

    Language LanguageSetting()
    {
        return state.language;
    }

    void SetLanguageSetting(Language language)
    {
        state.language = language;
        Loc::SetLanguage(language);
        Persist();
    }

    bool AutostartEnabled()
    {
        DWORD size = 0;
        return RegGetValueW(HKEY_CURRENT_USER, RUN_KEY, RUN_VALUE, RRF_RT_REG_SZ, nullptr, nullptr, &size) == ERROR_SUCCESS;
    }

    bool SetAutostartEnabled(bool enabled)
    {
        HKEY key = nullptr;
        if (RegOpenKeyExW(HKEY_CURRENT_USER, RUN_KEY, 0, KEY_SET_VALUE, &key) != ERROR_SUCCESS)
        {
            return false;
        }

        LSTATUS status = ERROR_SUCCESS;
        if (enabled)
        {
            wchar_t path[MAX_PATH] = L"";
            if (GetModuleFileNameW(NULL, path, ARRAYSIZE(path)) == 0)
            {
                status = GetLastError();
            }
            else
            {
                const std::wstring quoted = L"\"" + std::wstring{ path } + L"\"";
                status = RegSetValueExW(key, RUN_VALUE, 0, REG_SZ, reinterpret_cast<const BYTE*>(quoted.c_str()), static_cast<DWORD>((quoted.size() + 1) * sizeof(wchar_t)));
            }
        }
        else
        {
            status = RegDeleteValueW(key, RUN_VALUE);
            if (status == ERROR_FILE_NOT_FOUND)
            {
                status = ERROR_SUCCESS;
            }
        }

        RegCloseKey(key);
        return status == ERROR_SUCCESS;
    }

    bool SystemPrefersDark()
    {
        DWORD value = 1;
        DWORD size = sizeof(value);
        DWORD type = REG_DWORD;
        if (RegGetValueW(HKEY_CURRENT_USER,
                         L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
                         L"AppsUseLightTheme",
                         RRF_RT_DWORD,
                         &type,
                         &value,
                         &size) != ERROR_SUCCESS)
        {
            return false;
        }

        return value == 0;
    }

    bool UsesDarkTheme()
    {
        switch (state.theme)
        {
        case ThemeMode::Light:
            return false;
        case ThemeMode::Dark:
            return true;
        default:
            return SystemPrefersDark();
        }
    }
}
