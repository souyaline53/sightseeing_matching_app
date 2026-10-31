// Explicitly scoped maintenance: only legacy transit, sample_* masters and accessStops.
// Read-only by default. --apply uses a backup and Firestore preconditions in one commit.
import fs from 'node:fs';
import path from 'node:path';
import {createRequire} from 'node:module';
import {execFileSync} from 'node:child_process';
const project = 'sightseeing-matching-prototype';
const emulator=process.argv.includes('--emulator');
let accessToken;
if(!emulator) {
 const cli = fs.realpathSync(execFileSync('which',['firebase'],{encoding:'utf8'}).trim());
 const requireCli = createRequire(cli);
 const auth = requireCli('../auth.js');
 const account = auth.getProjectDefaultAccount(process.cwd());
 if (!account) throw new Error('firebase login を実行してください');
 const token = await auth.getAccessToken(account.tokens.refresh_token, ['https://www.googleapis.com/auth/cloud-platform']);
 accessToken=token.access_token;
} else {
 if(!/^127\.0\.0\.1:\d+$/.test(process.env.FIRESTORE_EMULATOR_HOST??'')) throw new Error('--emulatorにはローカルFIRESTORE_EMULATOR_HOSTが必要');
 accessToken='owner';
}
const root = emulator ? `http://${process.env.FIRESTORE_EMULATOR_HOST}/v1/projects/${project}/databases/(default)/documents` : `https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents`;
async function request(url, options={}) {
 const response=await fetch(url,{...options,headers:{Authorization:`Bearer ${accessToken}`,'Content-Type':'application/json'}});
 const body=await response.json();
 if(!response.ok) throw new Error(`Firestore ${response.status}: ${body.error?.message ?? 'request failed'}`);
 return body;
}
async function list(collection) {
 const docs=[]; let next='';
 do {
  const result=await request(`${root}/${collection}?pageSize=100${next ? `&pageToken=${encodeURIComponent(next)}` : ''}`);
  docs.push(...result.documents??[]);next=result.nextPageToken;
  if(docs.length>400) throw new Error(`${collection} が400件を超えるため中止しました`);
 } while(next);
 return docs;
}
function decode(v) {
 if('stringValue' in v) return v.stringValue;
 if('integerValue' in v) return Number(v.integerValue);
 if('booleanValue' in v) return v.booleanValue;
 if('nullValue' in v) return null;
 if('arrayValue' in v) return (v.arrayValue.values??[]).map(decode);
 if('mapValue' in v) return Object.fromEntries(Object.entries(v.mapValue.fields??{}).map(([k,v])=>[k,decode(v)]));
 return v;
}
function encode(v) {
 if(v===null) return {nullValue:null};
 if(typeof v==='string') return {stringValue:v};
 if(typeof v==='number') return Number.isInteger(v)?{integerValue:String(v)}:{doubleValue:v};
 if(typeof v==='boolean') return {booleanValue:v};
 if(Array.isArray(v)) return {arrayValue:{values:v.map(encode)}};
 return {mapValue:{fields:Object.fromEntries(Object.entries(v).map(([k,v])=>[k,encode(v)]))}};
}
const legacy=await list('transit');
const spots=await list('sightseeing_spot');
const masters={};
for(const c of ['transport_agencies','transport_stops','transport_routes','transport_services','transport_trips','transport_fares']) masters[c]=await list(c);
console.log(JSON.stringify({project,legacyCount:legacy.length,spots:spots.map(d=>({id:d.name.split('/').at(-1),title:decode(d.fields.title),accessStops:decode(d.fields.accessStops??{arrayValue:{}})})),masters:Object.fromEntries(Object.entries(masters).map(([c,docs])=>[c,docs.map(d=>d.name.split('/').at(-1))]))},null,2));
if(!process.argv.includes('--apply')) process.exit(0);
const fixture=JSON.parse(fs.readFileSync(new URL('../docs/transport/sample.json',import.meta.url),'utf8'));
if(Object.keys(fixture.transport_trips).length!==3) throw new Error('サンプル便は3件である必要があります');
const writes=[];
for(const [collection,docs] of Object.entries(masters)) {
 for(const [id,data] of Object.entries(fixture[collection])) {
  const existing=docs.find(d=>d.name.split('/').at(-1)===id);
  if(existing && decode(existing.fields.sourceType??{stringValue:''})!=='sample') throw new Error(`${collection}/${id} がサンプルと確認できないため中止`);
  const fields=Object.fromEntries(Object.entries({...data,id,createdAt:existing?.fields.createdAt?decode(existing.fields.createdAt):new Date().toISOString(),updatedAt:new Date().toISOString()}).map(([k,v])=>[k,encode(v)]));
  if(existing?.fields.createdAt) fields.createdAt=existing.fields.createdAt;
  writes.push({update:{name:`projects/${project}/databases/(default)/documents/${collection}/${id}`,fields},currentDocument:existing?{updateTime:existing.updateTime}:{exists:false}});
 }
}
// Optional explicit spot IDs, never implicitly attach fictitious stops to real spots.
const idsArg=process.argv.find(a=>a.startsWith('--spot-ids='));
if(idsArg) {
 const ids=idsArg.slice('--spot-ids='.length).split(',');
 if(ids.length!==3 || new Set(ids).size!==3) throw new Error('--spot-ids は異なる観光地IDを3つ指定');
 for(const [i,id] of ids.entries()) {
  const doc=spots.find(d=>d.name.split('/').at(-1)===id);
  if(!doc) throw new Error(`観光地 ${id} がありません`);
  const previous=decode(doc.fields.accessStops??{arrayValue:{}});
  const entry={stopId:`sample_${'bcd'[i]}`,walkingMinutes:null,walkingDistanceMeters:null,isPrimary:false,sourceType:'sample',verificationStatus:'sample',note:'画面確認専用の架空停留所。実際のアクセス情報ではありません。'};
  const entries=[...previous.filter(e=>e.stopId!==entry.stopId),entry];
  writes.push({update:{name:doc.name,fields:{accessStops:encode(entries)}},updateMask:{fieldPaths:['accessStops']},currentDocument:{updateTime:doc.updateTime}});
 }
}
for(const doc of legacy) writes.push({delete:doc.name,currentDocument:{updateTime:doc.updateTime}});
if(writes.length>450) throw new Error('変更が450件を超えるため中止');
const backupDir=path.resolve('.local-backups/transport');fs.mkdirSync(backupDir,{recursive:true,mode:0o700});
const backupFile=path.join(backupDir,`${new Date().toISOString().replaceAll(':','-')}.json`);
fs.writeFileSync(backupFile,JSON.stringify({project,legacy,spots,masters},null,2),{mode:0o600,flag:'wx'});
console.log(`Backup: ${backupFile}`);
await request(`${root}:commit`,{method:'POST',body:JSON.stringify({writes})});
const remaining=await list('transit');
const trips=await list('transport_trips');
if(remaining.length!==0 || !Object.keys(fixture.transport_trips).every(id=>trips.some(d=>d.name.endsWith(`/${id}`)))) throw new Error('書き込み後の確認に失敗');
console.log(JSON.stringify({deletedLegacy:legacy.length,registeredSampleTrips:Object.keys(fixture.transport_trips),spotLinks:idsArg?3:0}));
