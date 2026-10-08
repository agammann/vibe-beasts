#pragma once
#include <filesystem>
#include <string>

namespace vb::desktop {
// A failed write never removes the previous save.
bool writeSave(const std::filesystem::path& path, const std::string& data);
std::filesystem::path executableDirectory();
}
