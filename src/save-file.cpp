#include "save-file.h"
#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstring>
#include <system_error>
#include <vector>
#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#else
#include <cerrno>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
#endif

namespace fs = std::filesystem;
namespace vb::desktop {
#ifdef _WIN32
static std::wstring windowsPath(const fs::path& path) {
    std::error_code ec;
    auto absolute = fs::absolute(path, ec);
    if (ec) return {};
    auto name = absolute.lexically_normal().make_preferred().native();
    if (name.rfind(L"\\\\?\\", 0) == 0) return name;
    if (name.rfind(L"\\\\", 0) == 0) return L"\\\\?\\UNC\\" + name.substr(2);
    return L"\\\\?\\" + name;
}
#endif
ReadSaveResult readSave(const fs::path& path, std::string& data) {
    data.clear();
    char bytes[SaveLimit + 1];
    std::size_t size = 0;
#ifdef _WIN32
    const auto filename = windowsPath(path);
    HANDLE file = CreateFileW(filename.c_str(), GENERIC_READ,
        FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr,
        OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT | FILE_FLAG_SEQUENTIAL_SCAN, nullptr);
    if (file == INVALID_HANDLE_VALUE) {
        const auto error = GetLastError();
        return error == ERROR_FILE_NOT_FOUND || error == ERROR_PATH_NOT_FOUND
            ? ReadSaveResult::missing : ReadSaveResult::invalid;
    }
    BY_HANDLE_FILE_INFORMATION info{};
    bool ok = GetFileType(file) == FILE_TYPE_DISK &&
        GetFileInformationByHandle(file, &info) &&
        !(info.dwFileAttributes & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_REPARSE_POINT)) &&
        info.nFileSizeHigh == 0 && info.nFileSizeLow <= SaveLimit;
    while (ok && size < sizeof(bytes)) {
        DWORD count = 0;
        ok = ReadFile(file, bytes + size, static_cast<DWORD>(sizeof(bytes) - size), &count, nullptr) != 0;
        if (!ok || count == 0) break;
        size += count;
    }
    CloseHandle(file);
#else
    const int file = open(path.c_str(), O_RDONLY | O_CLOEXEC | O_NONBLOCK | O_NOFOLLOW);
    if (file < 0) return errno == ENOENT ? ReadSaveResult::missing : ReadSaveResult::invalid;
    struct stat info{};
    bool ok = fstat(file, &info) == 0 && S_ISREG(info.st_mode) &&
        info.st_size >= 0 && static_cast<std::uintmax_t>(info.st_size) <= SaveLimit;
    while (ok && size < sizeof(bytes)) {
        const auto count = read(file, bytes + size, sizeof(bytes) - size);
        if (count < 0 && errno == EINTR) continue;
        if (count < 0) ok = false;
        if (count <= 0) break;
        size += static_cast<std::size_t>(count);
    }
    close(file);
#endif
    if (!ok || size > SaveLimit) return ReadSaveResult::invalid;
    data.assign(bytes, size);
    return ReadSaveResult::valid;
}

bool writeSave(const fs::path& path, const std::string& data) {
    if (data.size() > SaveLimit || path.filename().empty()) return false;
    std::error_code ec;
    if (!path.parent_path().empty()) {
#ifdef _WIN32
        fs::create_directories(fs::path(windowsPath(path.parent_path())), ec);
#else
        fs::create_directories(path.parent_path(), ec);
#endif
    }
    if (ec) return false;
    const auto destination = fs::absolute(path, ec);
    if (ec) return false;
    static std::atomic<unsigned long long> sequence{0};
    const auto suffix = std::to_string(std::chrono::steady_clock::now().time_since_epoch().count()) +
        "-" + std::to_string(sequence.fetch_add(1));
#ifdef _WIN32
    auto temporary = destination;
    temporary += ".tmp-" + suffix;
    // CREATE_NEW never opens a pre-existing file/link. Read-only sharing keeps
    // the staged object pinned until its handle-based rename or removal.
    const auto temporaryName = windowsPath(temporary);
    HANDLE file = CreateFileW(temporaryName.c_str(), GENERIC_WRITE | DELETE, FILE_SHARE_READ, nullptr,
        CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) return false;
    std::size_t offset = 0;
    bool ok = true;
    while (ok && offset < data.size()) {
        DWORD count = 0;
        ok = WriteFile(file, data.data() + offset, static_cast<DWORD>(data.size() - offset), &count, nullptr) != 0 && count != 0;
        offset += count;
    }
    ok = ok && FlushFileBuffers(file);
    if (ok) {
        const auto name = windowsPath(destination);
        const auto length = name.size() * sizeof(wchar_t);
        std::vector<unsigned char> storage(sizeof(FILE_RENAME_INFO) + length);
        auto* rename = reinterpret_cast<FILE_RENAME_INFO*>(storage.data());
        rename->ReplaceIfExists = TRUE;
        rename->RootDirectory = nullptr;
        rename->FileNameLength = static_cast<DWORD>(length);
        std::memcpy(rename->FileName, name.data(), length);
        ok = SetFileInformationByHandle(file, FileRenameInfo, rename,
            static_cast<DWORD>(storage.size())) != 0;
    }
    if (!ok) {
        FILE_DISPOSITION_INFO remove{TRUE};
        SetFileInformationByHandle(file, FileDispositionInfo, &remove, sizeof(remove));
    }
    CloseHandle(file);
    return ok;
#else
    const int parent = open(destination.parent_path().c_str(), O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    if (parent < 0) return false;
    const std::string staging = ".save-tmp-" + suffix;
    if (mkdirat(parent, staging.c_str(), 0700) != 0) { close(parent); return false; }
    const int directory = openat(parent, staging.c_str(), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (directory < 0) { close(parent); return false; }
    const int file = openat(directory, "save", O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
    bool ok = file >= 0;
    std::size_t offset = 0;
    while (ok && offset < data.size()) {
        const auto count = write(file, data.data() + offset, data.size() - offset);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) ok = false;
        else offset += static_cast<std::size_t>(count);
    }
    ok = ok && fsync(file) == 0;
    // Both directories are pinned. The source is inside a private staging
    // directory; the selected destination's parent remains the owner's choice.
    if (ok) ok = renameat(directory, "save", parent, destination.filename().c_str()) == 0;
    if (file >= 0) close(file);
    if (!ok) unlinkat(directory, "save", 0);
    struct stat owned{}, named{};
    const bool sameDirectory = fstat(directory, &owned) == 0 &&
        fstatat(parent, staging.c_str(), &named, AT_SYMLINK_NOFOLLOW) == 0 &&
        owned.st_dev == named.st_dev && owned.st_ino == named.st_ino;
    close(directory);
    if (sameDirectory) unlinkat(parent, staging.c_str(), AT_REMOVEDIR);
    close(parent);
    return ok;
#endif
}

fs::path executableDirectory() {
#ifdef _WIN32
    std::wstring name(32768, L'\0');
    const DWORD size = GetModuleFileNameW(nullptr, name.data(), static_cast<DWORD>(name.size()));
    if (size > 0 && size < name.size()) { name.resize(size); return fs::path(name).parent_path(); }
#endif
    return fs::current_path();
}
}
