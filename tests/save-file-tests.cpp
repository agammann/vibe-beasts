#ifdef NDEBUG
#undef NDEBUG
#endif
#include "../src/save-file.h"
#include <cassert>
#include <fstream>
#include <iostream>
#include <thread>
#include <chrono>
#ifndef _WIN32
#include <sys/stat.h>
#endif

namespace fs = std::filesystem;
static std::string read(const fs::path& path) {
    std::ifstream input(path, std::ios::binary);
    return {std::istreambuf_iterator<char>(input), {}};
}
int main() {
    const auto root = fs::current_path() / "build" / ("save-file-test-" + std::to_string(std::chrono::steady_clock::now().time_since_epoch().count()));
    fs::create_directories(root);
    const auto save = root / "partner.save";
    std::string loaded = "previous bytes";
    assert(vb::desktop::readSave(root / "absent.save", loaded) == vb::desktop::ReadSaveResult::missing);
    assert(loaded.empty());
    assert(vb::desktop::writeSave(save, "first good save\n"));
    assert(vb::desktop::writeSave(save, "second good save\n"));
    assert(read(save) == "second good save\n");
    assert(vb::desktop::readSave(save, loaded) == vb::desktop::ReadSaveResult::valid);
    assert(loaded == "second good save\n");
    const auto boundary = root / "bounded.save";
    assert(vb::desktop::writeSave(boundary, std::string(vb::desktop::SaveLimit, 'x')));
    assert(vb::desktop::readSave(boundary, loaded) == vb::desktop::ReadSaveResult::valid);
    assert(loaded.size() == vb::desktop::SaveLimit);
    assert(!vb::desktop::writeSave(boundary, std::string(vb::desktop::SaveLimit + 1, 'y')));
    assert(read(boundary) == std::string(vb::desktop::SaveLimit, 'x'));
    { std::ofstream output(boundary, std::ios::binary | std::ios::trunc); output << std::string(1024 * 1024, 'z'); }
    assert(vb::desktop::readSave(boundary, loaded) == vb::desktop::ReadSaveResult::invalid);
    assert(loaded.empty());
    const auto unicode = root / fs::u8path("partner-\u00e9.save");
    assert(vb::desktop::writeSave(unicode, "unicode path"));
    assert(vb::desktop::readSave(unicode, loaded) == vb::desktop::ReadSaveResult::valid);
    assert(loaded == "unicode path");
    auto longPath = root;
    while (fs::absolute(longPath).native().size() < 310) longPath /= std::string(45, 'l');
    longPath /= "long-path.save";
    assert(vb::desktop::writeSave(longPath, "long path progress"));
    assert(vb::desktop::readSave(longPath, loaded) == vb::desktop::ReadSaveResult::valid);
    assert(loaded == "long path progress");
    const auto external = root / "external.save";
    { std::ofstream output(external); output << "external progress"; }
    const auto linked = root / "linked.save";
    std::error_code linkError;
    fs::create_symlink(fs::absolute(external), linked, linkError);
    if (!linkError) {
        assert(vb::desktop::readSave(linked, loaded) == vb::desktop::ReadSaveResult::invalid);
        assert(loaded.empty());
        assert(vb::desktop::writeSave(linked, "new selected save"));
        assert(read(external) == "external progress");
        assert(!fs::is_symlink(linked));
    } else std::cout << "SKIP: file symlink creation unavailable on this account\n";
    const auto hardlink = root / "hardlink.save";
    fs::create_hard_link(external, hardlink);
    assert(vb::desktop::writeSave(hardlink, "new hardlink save"));
    assert(read(external) == "external progress");
    const auto concurrent = root / "concurrent.save";
    assert(vb::desktop::writeSave(concurrent, "initial"));
    std::thread one([&] { for (int i = 0; i < 40; ++i) vb::desktop::writeSave(concurrent, "first writer"); });
    std::thread two([&] { for (int i = 0; i < 40; ++i) vb::desktop::writeSave(concurrent, "second writer"); });
    for (int i = 0; i < 100; ++i) {
        assert(vb::desktop::readSave(concurrent, loaded) == vb::desktop::ReadSaveResult::valid);
        assert(loaded == "initial" || loaded == "first writer" || loaded == "second writer");
    }
    one.join(); two.join();
#ifndef _WIN32
    const auto fifo = root / "not-a-save.fifo";
    assert(mkfifo(fifo.c_str(), 0600) == 0);
    assert(vb::desktop::readSave(fifo, loaded) == vb::desktop::ReadSaveResult::invalid);
#endif
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
    assert(vb::desktop::readSave(directory, loaded) == vb::desktop::ReadSaveResult::invalid);
    { std::ofstream marker(directory / "keep.txt"); marker << "keep"; }
    assert(!vb::desktop::writeSave(directory, "must not remove folder"));
    assert(read(directory / "keep.txt") == "keep");
    for (const auto& entry : fs::directory_iterator(root)) {
        assert(entry.path().filename().string().find(".tmp-") == std::string::npos);
        assert(entry.path().filename().string().find(".save-tmp-") == std::string::npos);
    }
    std::cout << "PASS: bounded regular-file reads, concurrent atomic saves, failed writes preserve old data, and staged files are cleaned\n";
}
