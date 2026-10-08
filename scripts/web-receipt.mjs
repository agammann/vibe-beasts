import fs from 'node:fs';
import crypto from 'node:crypto';
const sha=path=>crypto.createHash('sha256').update(fs.readFileSync(path)).digest('hex');
const version=/^#define VIBE_VERSION "(\d+\.\d+\.\d+)"$/m.exec(fs.readFileSync('src/version.h','utf8'))?.[1];
if(!version)throw Error('Missing stable source version');
const receipt={version,emscripten:'4.0.15',inputs:Object.fromEntries(['src/game.cpp','src/game.h','src/roster.inc'].map(path=>[path,sha(path)])),outputs:Object.fromEntries(['dist/core.js','dist/core.wasm'].map(path=>[path,sha(path)]))};
if(process.argv[2]==='--verify'){
 const actual=JSON.parse(fs.readFileSync('dist/BUILD.json','utf8'));
 if(JSON.stringify(actual)!==JSON.stringify(receipt))throw Error('Committed browser core or compiled source differs from its build receipt');
 console.log('PASS: browser core receipt matches exact compiled inputs and actual JS/WASM');
}else fs.writeFileSync('dist/BUILD.json',JSON.stringify(receipt,null,2)+'\n');
