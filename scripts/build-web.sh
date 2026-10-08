#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
em++ --version | grep -F '4.0.15' >/dev/null
em++ src/game.cpp -std=c++17 -O2 --no-entry -sMODULARIZE=1 -sEXPORT_ES6=1 -sEXPORT_NAME=createVibeCore -sENVIRONMENT=web,node -sALLOW_MEMORY_GROWTH=1 '-sEXPORTED_FUNCTIONS=["_vb_get","_vb_pet","_vb_species","_vb_name","_vb_message","_vb_tick","_vb_action","_vb_save","_vb_load"]' '-sEXPORTED_RUNTIME_METHODS=["cwrap"]' -o dist/core.js
node scripts/web-receipt.mjs
node scripts/make-service-worker.mjs
