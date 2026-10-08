#ifdef NDEBUG
#undef NDEBUG
#endif
#include "../src/save-file.h"
#include <cassert>
#include <fstream>
#include <iostream>

namespace fs = std::filesystem;
static std::string read(const fs::path& path) {
    std::ifstream input(path, std::ios::binary);
    return {std::istreambuf_iterator<char>(input), {}};
}
int main() {
    const auto root = fs::current_path() / "build" / "save-file-test";
    fs::create_directories(root);
    const auto save = root / "partner.save";
    assert(vb::desktop::writeSave(save, "first good save\n"));
    assert(vb::desktop::writeSave(save, "second good save\n"));
    assert(read(save) == "second good save\n");
    const auto blocked = root / "not-a-directory";
    { std::ofstream output(blocked); output << "parent must remain a file"; }
    assert(!vb::desktop::writeSave(blocked / "partner.save", "must fail"));
    assert(read(blocked) == "parent must remain a file");
#ifdef _WIN32
    fs::permissions(save, fs::perms::owner_read, fs::perm_options::replace);
    assert(!vb::desktop::writeSave(save, "must not replace readonly save"));
    assert(read(save) == "second good save\n");
    fs::permissions(save, fs::perms::owner_all, fs::perm_options::replace);
#endif
    const auto directory = root / "save-is-a-folder";
    fs::create_directories(directory);
    { std::ofstream marker(directory / "keep.txt"); marker << "keep"; }
    assert(!vb::desktop::writeSave(directory, "must not remove folder"));
    assert(read(directory / "keep.txt") == "keep");
    for (const auto& entry : fs::directory_iterator(root)) assert(entry.path().filename().string().find(".tmp-") == std::string::npos);
    std::cout << "PASS: atomic save replacement, failed writes preserve old data, and staged files are cleaned\n";
}
