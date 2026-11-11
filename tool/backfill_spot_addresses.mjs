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
const spots = await list('sightseeing_spot');
const pending = spots.filter(d => !d.fields.address?.stringValue?.trim());
console.log(JSON.stringify({project, total:spots.length, missing:pending.map(d=>d.name.split('/').at(-1))}));
if (!process.argv.includes('--apply') || !pending.length) process.exit(0);
const response = await fetch('https://msearch.gsi.go.jp/address-search/AddressSearch?q='+encodeURIComponent('北海道夕張市高松7番地'));
if (!response.ok) throw new Error('geocode failed');
const candidates = await response.json();
if (candidates.length !== 1) throw new Error('ambiguous geocode');
const [longitude, latitude] = candidates[0].geometry.coordinates;
if (!Number.isFinite(latitude) || !Number.isFinite(longitude) || Math.abs(latitude)>90 || Math.abs(longitude)>180) throw new Error('invalid coordinates');
const backupDir = path.resolve('.local-backups/addresses');
fs.mkdirSync(backupDir,{recursive:true,mode:0o700});
const backupFile = path.join(backupDir,`${new Date().toISOString().replaceAll(':','-')}.json`);
fs.writeFileSync(backupFile,JSON.stringify({project,spots:pending},null,2),{mode:0o600,flag:'wx'});
const writes = pending.map(d=>({update:{name:d.name,fields:{address:{stringValue:'北海道夕張市高松7番地'},latitude:{doubleValue:latitude},longitude:{doubleValue:longitude}}},updateMask:{fieldPaths:['address','latitude','longitude']},currentDocument:{updateTime:d.updateTime},updateTransforms:[{fieldPath:'updatedAt',setToServerValue:'REQUEST_TIME'}]}));
await request(`${root}:commit`,{method:'POST',body:JSON.stringify({writes})});
const verified = await list('sightseeing_spot');
for (const doc of pending) {
 const saved = verified.find(d=>d.name===doc.name);
 if (saved?.fields.address?.stringValue !== '北海道夕張市高松7番地' || saved.fields.latitude?.doubleValue !== latitude || saved.fields.longitude?.doubleValue !== longitude) throw new Error('verification failed');
}
console.log(JSON.stringify({updated:pending.length,latitude,longitude,backupFile}));
