param([string]$Emcc = 'em++')
$ErrorActionPreference = 'Stop'
Push-Location (Join-Path $PSScriptRoot '..')
try {
  $compilerVersion = (& $Emcc --version) -join "`n"
  if ($LASTEXITCODE -ne 0 -or $compilerVersion -notmatch '4\.0\.15') { throw 'This release requires Emscripten 4.0.15.' }
  $exports = '["_vb_get","_vb_pet","_vb_species","_vb_name","_vb_message","_vb_tick","_vb_action","_vb_save","_vb_load"]'
  & $Emcc src/game.cpp -std=c++17 -O2 --no-entry -sMODULARIZE=1 -sEXPORT_ES6=1 -sEXPORT_NAME=createVibeCore '-sENVIRONMENT=web,node' -sALLOW_MEMORY_GROWTH=1 "-sEXPORTED_FUNCTIONS=$exports" '-sEXPORTED_RUNTIME_METHODS=["cwrap"]' -o dist/core.js
  if ($LASTEXITCODE -ne 0) { throw 'WebAssembly build failed' }
  node scripts/web-receipt.mjs
  if ($LASTEXITCODE -ne 0) { throw 'Browser core receipt failed' }
  node scripts/make-service-worker.mjs
  if ($LASTEXITCODE -ne 0) { throw 'Offline manifest generation failed' }
} finally { Pop-Location }
