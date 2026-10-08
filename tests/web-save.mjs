import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
import createVibeCore from '../dist/core.js';

// Execute the application and its actual WASM core with a small DOM/storage host.
// Browser lifecycle, rendered recovery and downloads are checked separately.
const source=readFileSync(new URL('../dist/app.js',import.meta.url),'utf8')
  .replace("import createVibeCore from './core.js';",'');
const key='vibe-beasts-save-v1', corrupt='VIBE_BEASTS 2\nunreadable recovery fixture';
async function session(){
  const nodes=new Map(), events=new Map(), storage=new Map([[key,corrupt]]);
  const node=selector=>{
    if(!nodes.has(selector))nodes.set(selector,{innerHTML:'',textContent:'',open:false,
      showModal(){this.open=true;},close(){this.open=false;},contains(){return false;}});
    return nodes.get(selector);
  };
  const on=(name,callback)=>events.set(name,callback);
  const document={hidden:false,querySelector:node,querySelectorAll:()=>[],addEventListener:on};
  await runInNewContext(`(async()=>{${source}\n})()`,{
    createVibeCore,document,window:{addEventListener:on},navigator:{},setInterval(){},
    localStorage:{getItem:k=>storage.get(k)||null,setItem:(k,v)=>storage.set(k,v)},
    console:{error(error){throw error;}}
  });
  return {nodes,node,events,storage,document};
}

const start=await session();
assert.match(start.node('#dialog-body').innerHTML,/Your save needs attention/);
start.document.hidden=true;
start.events.get('visibilitychange')();
start.events.get('pagehide')();
assert.equal(start.storage.get(key),corrupt,'Lifecycle saves must preserve unreadable progress');
start.document.hidden=false;
start.events.get('visibilitychange')();
await start.events.get('click')({target:{closest:()=>({dataset:{action:'0',arg:'1'}})}});
assert.notEqual(start.storage.get(key),corrupt,'Choosing a new partner replaces the unreadable save');
const fresh=await createVibeCore();
assert.equal(fresh.cwrap('vb_load','number',['string'])(start.storage.get(key)),1);
assert.equal(fresh._vb_get(0),4);
assert.equal(fresh._vb_get(15),1);
await start.events.get('change')({target:{id:'partner-select',value:'2'}});
start.events.get('pagehide')();
assert.equal(fresh.cwrap('vb_load','number',['string'])(start.storage.get(key)),1);
assert.equal(fresh._vb_get(0),7,'The partner dropdown keeps saving after explicit recovery');

const unreadableFile=await session();
await unreadableFile.events.get('change')({target:{id:'save-file',files:[{size:100,text:async()=>{throw new Error('File read failed');}}]}});
assert.match(unreadableFile.node('#dialog-body').innerHTML,/Could not read that file/);
assert.equal(unreadableFile.storage.get(key),corrupt,'A failed file read must preserve the stored save');

const restore=await session();
const backup=start.storage.get(key);
await restore.events.get('change')({target:{id:'save-file',files:[{size:backup.length,text:async()=>backup}]}});
restore.node('#confirm-import').onclick();
restore.events.get('pagehide')();
assert.notEqual(restore.storage.get(key),corrupt,'A valid confirmed import restores normal saving');
assert.equal(fresh.cwrap('vb_load','number',['string'])(restore.storage.get(key)),1);
assert.equal(fresh._vb_get(0),7);
console.log('PASS: unreadable saves survive lifecycle events; explicit new game and valid import resume saving');
