#include "save-file.h"
#include <chrono>
#include <fstream>
#include <system_error>
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#endif

namespace fs = std::filesystem;
namespace vb::desktop {
bool writeSave(const fs::path& path, const std::string& data) {
    std::error_code ec;
    if (!path.parent_path().empty()) fs::create_directories(path.parent_path(), ec);
    if (ec) return false;
    auto temp = path;
    temp += ".tmp-" + std::to_string(std::chrono::steady_clock::now().time_since_epoch().count());
    {
        std::ofstream output(temp, std::ios::binary | std::ios::trunc);
        output.write(data.data(), static_cast<std::streamsize>(data.size()));
        output.flush();
        if (!output) { output.close(); fs::remove(temp, ec); return false; }
        output.close();
        if (!output) { fs::remove(temp, ec); return false; }
    }
#ifdef _WIN32
    const bool replaced = MoveFileExW(temp.c_str(), path.c_str(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH) != 0;
#else
    fs::rename(temp, path, ec);
    const bool replaced = !ec;
#endif
    if (!replaced) fs::remove(temp, ec);
    return replaced;
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
