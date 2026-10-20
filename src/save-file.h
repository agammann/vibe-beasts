#pragma once
#include <cstddef>
#include <filesystem>
#include <string>

namespace vb::desktop {
constexpr std::size_t SaveLimit = 16000;
enum class ReadSaveResult { missing, valid, invalid };
// Only bounded bytes from one regular-file handle are returned. Links are rejected.
ReadSaveResult readSave(const std::filesystem::path& path, std::string& data);
// A failed write never removes the previous save.
bool writeSave(const std::filesystem::path& path, const std::string& data);
std::filesystem::path executableDirectory();
}
