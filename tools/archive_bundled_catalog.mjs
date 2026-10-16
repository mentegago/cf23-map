import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {gzipSync,gunzipSync} from 'node:zlib';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const read=name=>JSON.parse(fs.readFileSync(path.join(root,'data',name),'utf8'));
const catalog=read('catalog-initial.json'),fandoms=read('fandoms-initial.json'),version=read('last-updated-initial.json');
const snapshot={catalog,fandoms,version,manifest:{schemaVersion:'1.0.0',
  event:{id:catalog.event.id,name:catalog.event.name},catalog:'v1/catalog.json',fandomRegistry:'v1/fandoms.json'}};
const canonical=value=>Array.isArray(value)?value.map(canonical):value&&typeof value==='object'?
  Object.fromEntries(Object.keys(value).sort().map(k=>[k,canonical(value[k])])):value;
const body=JSON.stringify(canonical(snapshot));
const semantic=s=>JSON.stringify(canonical({catalog:{schemaVersion:s.catalog.schemaVersion,
  event:s.catalog.event,stats:s.catalog.stats,exhibitors:s.catalog.exhibitors},
  fandoms:{schemaVersion:s.fandoms.schemaVersion,fandoms:s.fandoms.fandoms},manifest:s.manifest}));
const folder=path.join(root,'data/analytics',catalog.event.id,String(version.creator_data_version));
const archive=path.join(folder,'snapshot.json.gz'),index=path.join(folder,'index.json');
if(fs.existsSync(archive)) {
  if(semantic(JSON.parse(gunzipSync(fs.readFileSync(archive)).toString()))!==semantic(snapshot))throw Error('Bundled analytics version conflict');
  const expected=JSON.parse(fs.readFileSync(index,'utf8')).archiveHash;
  if(createHash('sha256').update(fs.readFileSync(archive)).digest('hex')!==expected)throw Error('Archive integrity failure');
} else {
  if(process.argv.includes('--check'))throw Error('Missing bundled archive; run node tools/archive_bundled_catalog.mjs');
  fs.mkdirSync(folder,{recursive:true});const bytes=gzipSync(Buffer.from(body));
  fs.writeFileSync(archive,bytes,{flag:'wx'});
  fs.writeFileSync(index,JSON.stringify({schemaVersion:1,event:catalog.event.id,creatorDataVersion:version.creator_data_version,
    archiveHash:createHash('sha256').update(bytes).digest('hex')},null,2)+'\n',{flag:'wx'});
}
console.log(`Bundled analytics archive verified: ${catalog.event.id}/${version.creator_data_version}`);
