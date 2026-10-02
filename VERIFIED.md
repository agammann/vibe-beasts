# Release verification

## Browser save recovery — 2026-10-02

- An unreadable stored save stayed intact after a failed import, navigation away and reload in the rendered browser app. Confirming a valid native save restored the active battle and resumed normal saving. The automated persistence regression uses the actual WebAssembly core with a small DOM/storage test host; it also checks explicit new-partner selection.
- A fresh browser session completed a real 30-second hatch, ten training actions, a complete battle and its 20 XP reward. Field-guide search, manual pause across reload, export download and offline cached reload passed. Screenshots at 1440, 390 and 320 pixels were inspected; no horizontal overflow, page exceptions or external asset requests were observed.
- Native C++ tests were compiled with LLVM MinGW 20260922 and passed 1,580 simulated battles and the evolution/save checks. The committed WebAssembly module passed interoperability checks against the freshly generated native save fixtures.
- The published Windows `v1.1.0` ZIP matched its release SHA-256. Its existing executable passed the built-in window/render/save smoke test with all 151 sprites, and the snapshot was inspected. The Windows renderer was not rebuilt or manually played through for this browser-only fix.

These checks used Windows 11 and desktop Edge, with phone-sized viewports rather than physical phones. The earlier release evidence below remains separately scoped.

## v1.1 evolution update

- All 70 evolving species passed tests immediately below and at their level and cumulative time requirements. All 79 families share one 72-hour full-chain timeline per partner, including hatching; three-form families have a 36-hour intermediate milestone. Late evolution and older saves preserve cumulative time and earned levels.
- Native C++ regression tests completed 1,580 simulated battles. A separate local progression check earned its XP through 1,467 completed battles (1,465 wins, 2 losses), reached all 151 forms and 72 evolution branches, and checked all four routes. Time was simulated for testing; no accelerated play mode is shipped.
- The actual WebAssembly build rejected below-level and below-time saves, evolved Charmander at level 16 / 36 total hours, preserved its level and clock, and accepted a converted Eevee branch at level 36 / 72 hours.
- Local browser UI at `localhost:4178`: imported a level-15 fixture and verified disabled evolution; imported level 16 / 36 hours, clicked Evolve, and verified Charmeleon with 36 / 72 hours and level 16 / 36 toward Charizard. Desktop and 390-pixel phone viewport screenshots inspected; no horizontal overflow or relevant console errors observed.
- Windows native rendering/resource/save smoke test passed with 151 sprites. Its new total-hours and evolution-level indicators were visually inspected. Sprite provenance and JavaScript syntax checks passed.

The progression check does not represent 72 real elapsed hours of manual play. Physical-phone installation remains untested. Earlier broader release checks are recorded below.

## Tested locally

- C++17 engine compiled and its regression suite passed: egg/clock gating; 30-second hatching; cumulative evolution boundaries; level gating; care-independent evolution; sleeping, paused and suspended timers; all three Eevee branches; invalid action rejection; deterministic battle rewards; malformed-save rejection; save round trips; **1,580 complete simulated battles** over all 79 partner families and four routes.
- Actual Emscripten WebAssembly build passed timer, hatch, sleep/pause, invalid-import and **native-to-WebAssembly save compatibility** checks.
- Windows x64 native app linked statically, created its OpenGL window, loaded all **151 sprites**, rendered and saved successfully. Native screenshot inspected, including Windows high-DPI rendering.
- Browser UI: chose a starter, set clock, hatched in real elapsed time, trained, completed a battle using type burst/guard/tackle, received XP, and imported a native save through the file picker. Used a prepared 72-hour test fixture to check Eevee choice and evolution reveal; this did not require waiting 72 real hours.
- Responsive interface visually inspected at desktop and 390-pixel phone width; 320-pixel layout checked for horizontal overflow.
- All 151 source sprite hashes, dimensions, filenames and allowed Yellow paths verified. All 151 species are reachable through playable families/evolution and were encountered in a deterministic League simulation.
- Early ten-family preview saves successfully import into the expanded Vibe Beasts format.
- Offline browser proof: stopped the local server, evolved Eevee into Vaporeon, then reloaded from the cache with saved progress intact.
- Windows installer tested in isolated local folders: Vibe Beasts shortcut, identical executable hash, 151 sprites, and the installed copy passed its native smoke test.

## Scope

The Windows renderer and browser UI are separate interfaces over the same C++ rules. The native smoke test validates rendering/resources and save startup; it is not a complete manual playthrough of every Windows button. Phone checks use browser viewport emulation, not a physical Android/iPhone. Safari installation and OS download/reputation prompts were not independently tested. macOS/Linux native runtime behavior is not claimed verified.

The game intentionally uses local single-player saves without cloud synchronization, multiplayer, anti-cheat, official Pokémon battle fidelity or official game mechanics.

CI configuration is in [build.yml](.github/workflows/build.yml). See the repository's Actions tab for the current run rather than treating this document as a live CI status indicator.
