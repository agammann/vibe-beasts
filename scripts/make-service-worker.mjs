import {readdirSync,readFileSync,writeFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const files=['./','index.html','style.css','vibe.css','app.js','core.js','core.wasm','BUILD.json','manifest.webmanifest','icon-192.png','icon-512.png',...readdirSync('dist/assets').filter(x=>x.endsWith('.png')).map(x=>'assets/'+x)];
const hash=createHash('sha256');for(const f of files)if(f!=='./')hash.update(readFileSync('dist/'+f));const cache='vibe-beasts-'+hash.digest('hex').slice(0,12);
writeFileSync('dist/sw.js',`const CACHE=${JSON.stringify(cache)}, FILES=${JSON.stringify(files)};\nself.addEventListener('install',e=>{e.waitUntil(caches.open(CACHE).then(c=>c.addAll(FILES)).then(()=>self.skipWaiting()));});\nself.addEventListener('activate',e=>{e.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(k=>k.startsWith('vibe-beasts-')&&k!==CACHE).map(k=>caches.delete(k)))).then(()=>self.clients.claim()));});\nself.addEventListener('fetch',e=>{if(e.request.method!=='GET'||new URL(e.request.url).origin!==self.location.origin)return;e.respondWith(caches.match(e.request).then(hit=>hit||fetch(e.request)));});\n`);
console.log('Offline cache:',cache,files.length,'files');
