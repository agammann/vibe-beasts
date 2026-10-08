# Rebuild Vibe Beasts

Ready-to-play downloads are linked in [README.md](README.md). Playing the Windows ZIP needs no compiler. Developers can rebuild the same C++17 core for Windows and the browser.

## Tools

- Windows x64 LLVM MinGW UCRT **20260922**, including `clang++.exe` and `windres.exe`.
- The static Windows MinGW package of **raylib 5.5**.
- **Emscripten 4.0.15** for WebAssembly.
- **Node.js 22 or later** for the local server and browser checks; release CI uses 24.19.0.
- Git for creating release archives. A downloaded source ZIP builds without Git.

Download and extract [LLVM MinGW](https://github.com/mstorsjo/llvm-mingw/releases/tag/20260922) and [raylib 5.5](https://github.com/raysan5/raylib/releases/tag/5.5). Windows CI checks the compiler archive's SHA-256 and uses the identified raylib 5.5 MinGW asset. The native build receipt records the linked raylib archive's hash.

## Windows

From the source folder, run:

```powershell
.\scripts\build-windows.ps1 -Compiler 'C:\tools\llvm-mingw\bin\clang++.exe' -Raylib 'C:\tools\raylib-5.5_win64_mingw-w64'
.\build\windows\Play.cmd
```

The script runs the C++ rules and save-file tests, builds in a separate staging folder and creates `build/windows/` with the executable, all 151 sprites, notices and launchers. It checks the executable's version against `src/version.h`. A failed compiler or test leaves the previous output folder intact. A successful rebuild keeps an existing output folder under `build/previous-*`.

To check actual rendering without touching normal player progress:

```powershell
.\build\windows\VibeBeasts.exe --save build\verification.save --snapshot build\native-preview.png
.\build\windows\VibeBeasts.exe --version
```

Snapshot mode loads all sprites, renders eight frames, saves to the explicit isolated path and exits. `--smoke-test` does the same without a screenshot. Without `--save`, these modes use `build/smoke.save` beside the executable. Ordinary `--save FILE` launches a separate save for development checks. Malformed options and failed snapshot/save writes return a nonzero exit code. The window requires an OpenGL 3.3 graphics driver.

## Browser

Install and activate [Emscripten 4.0.15](https://emscripten.org/docs/getting_started/downloads.html), then enter its configured shell. Ensure `node` is on PATH:

```powershell
.\scripts\build-web.ps1
node tests/web-core.mjs
node tests/web-save.mjs
node tests/assets.mjs
node scripts/serve.mjs
```

Open http://localhost:4173. The native core tests write the fixtures expected by `tests/web-core.mjs`, which loads the actual WebAssembly module. Build Windows first to create those fixtures. On Linux/macOS an Emscripten-enabled shell can run `bash scripts/build-web.sh`; the corresponding native core fixture can be generated with `c++ -std=c++17 src/game.cpp tests/core-tests.cpp -o build/core-tests` and `./build/core-tests` after creating `build/`.

Do not open `dist/index.html` through `file://`. Browsers require HTTP/HTTPS for WebAssembly loading and service workers. The bundle contains every runtime asset locally. Run `node scripts/make-service-worker.mjs` after changing browser assets to refresh the offline cache. `dist/BUILD.json` records the core's exact source hashes and JS/WASM hashes; `node scripts/web-receipt.mjs --verify` checks it.

## Release packages

From a clean, committed Git checkout with both editions built:

```powershell
.\scripts\package-release.ps1
.\scripts\check-release.ps1 -Compiler 'C:\tools\llvm-mingw\bin\clang++.exe' -Raylib 'C:\tools\raylib-5.5_win64_mingw-w64' -Out 'C:\temp\vibe-consumer' -VerifyWindow
```

Use a new consumer folder. The checker verifies all three package checksums, source Git blobs, matching identities, the native files/version and browser files. It rebuilds the delivered Windows source and checks the delivered actual WASM. `-VerifyWindow` additionally runs the delivered executable's render/save/snapshot test on a machine with OpenGL 3.3. CI performs the package and source checks; the real Windows renderer and browser playthrough are checked separately on a Windows desktop before release.

The [pinned workflow](.github/workflows/build.yml) rebuilds Windows and WebAssembly, requires the rebuilt browser core/cache to match committed files, and consumes all three ZIPs. A main push publishes the new stable version only after that job succeeds, with matching tag, source commit and seven verified assets. An already published version remains unchanged. Update the source version, Windows resource, package version, browser footer/download links and changelog together for a later release.

## Hosting and other native platforms

Any static HTTPS host can serve `dist/`; set `.wasm` to `application/wasm`. For ChatGPT Sites, use your own identity in `.openai/hosting.json`. Do not reuse this project's Site identity.

The optional CMake layout uses a pinned raylib 5.5 source revision. Native Linux needs raylib's X11/OpenGL development dependencies. Copy `assets/` and `icon-192.png` from `dist/` into the executable's folder and run from that folder on other native platforms. Native macOS/Linux runtime and physical-phone installation are outside this Windows/Chromium release's verified scope.

MIT permissions cover original code and documentation. Pokémon artwork, names and trademarks retain their separate rights; see [CREDITS.md](CREDITS.md).
