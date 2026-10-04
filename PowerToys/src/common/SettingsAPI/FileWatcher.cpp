#include "pch.h"
#include "FileWatcher.h"
#include <utils/winapi_error.h>

std::optional<FILETIME> FileWatcher::MyFileTime()
{
    HANDLE hFile = CreateFileW(m_path.c_str(), FILE_READ_ATTRIBUTES, FILE_SHARE_DELETE | FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_EXISTING, 0, nullptr);
    std::optional<FILETIME> result;
    if (hFile != INVALID_HANDLE_VALUE)
    {
        FILETIME lastWrite;
        if (GetFileTime(hFile, nullptr, nullptr, &lastWrite))
        {
            result = lastWrite;
        }

        CloseHandle(hFile);
    }

    return result;
}

FileWatcher::FileWatcher(const std::wstring& path, std::function<void()> callback) :
    m_path(path),
    m_callback(callback)
{
    std::filesystem::path fsPath(path);
    m_file_name = fsPath.filename();
    std::transform(m_file_name.begin(), m_file_name.end(), m_file_name.begin(), ::towlower);
    // Prime the timestamp. Without this the first notification after construction only fills
    // the cache, so the change that notification announced was silently dropped.
    m_lastWrite = MyFileTime();

    // LastWriteTime alone is not enough: a writer that replaces the file atomically (write a
    // temp file, then rename it over the target) produces a *name* change on the directory, not
    // a last-write change on the existing file, so the notification never arrived. Watching
    // FileName as well is what makes atomic writers visible; the name filter below still keeps
    // every other file in the folder out.
    m_folder_change_reader = wil::make_folder_change_reader_nothrow(
        fsPath.parent_path().c_str(),
        false,
        static_cast<wil::FolderChangeEvents>(
            static_cast<DWORD>(wil::FolderChangeEvents::LastWriteTime) |
            static_cast<DWORD>(wil::FolderChangeEvents::FileName)),
        [this](wil::FolderChangeEvent, PCWSTR fileName) {
            std::wstring lowerFileName(fileName);
            std::transform(lowerFileName.begin(), lowerFileName.end(), lowerFileName.begin(), ::towlower);

            // m_file_name is lowercased, so the comparison has to use the lowercased copy too.
            if (m_file_name == lowerFileName)
            {
                auto lastWrite = MyFileTime();
                if (!m_lastWrite.has_value())
                {
                    // The file did not exist when this watcher was built - which is every watcher
                    // on a first run, and the applied-layouts one after its folder has been cleared.
                    // The event that announced the file's creation is the change we care about, so
                    // it must not be swallowed by priming the cache: without this, the first apply
                    // after startup was written to disk and never read back.
                    m_lastWrite = lastWrite;
                    if (lastWrite.has_value())
                    {
                        m_callback();
                    }
                }
                else if (lastWrite.has_value())
                {
                    if (m_lastWrite->dwHighDateTime != lastWrite->dwHighDateTime ||
                        m_lastWrite->dwLowDateTime != lastWrite->dwLowDateTime)
                    {
                        m_lastWrite = lastWrite;
                        m_callback();
                    }
                }
            }
        });

    if (!m_folder_change_reader)
    {
        Logger::error(L"Failed to start folder change reader for path {}. {}", path, get_last_error_or_default(GetLastError()));
    }
}

FileWatcher::~FileWatcher()
{
    m_folder_change_reader.reset();
}
