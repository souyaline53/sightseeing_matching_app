'use strict';
// Read-only by default. --apply creates only missing records, with a backup and exists:false preconditions.
const fs = require('node:fs');
const path = require('node:path');
const { gunzipSync } = require('node:zlib');
const { FieldValue } = require('firebase-admin/firestore');
const { context } = require('./production_transport_context.cjs');
const samples = [
  { id: '札幌駅', legacyId: 'sapporo', address: '北海道札幌市北区北6条西4丁目1番1号', names: ['札幌駅','札幌駅前','札幌駅北口'] },
  { id: '新千歳空港', legacyId: 'chitose', address: '北海道千歳市美々987番地22', names: ['新千歳空港','新千歳空港国内線','新千歳空港国際線','新千歳空港２８番','新千歳空港１番','新千歳空港・国際線'] },
  { id: '旭川駅', legacyId: 'asahikawa', address: '北海道旭川市宮下通8丁目3番1号', names: ['旭川駅','旭川駅前'] },
  { id: '小樽駅', legacyId: 'otaru', address: '北海道小樽市稲穂2丁目22番15号', names: ['小樽駅','小樽駅前'] },
];
async function main() {
  const { db, bucket, projectId } = context();
  const existing = await db.collection('departure_places').get();
  const manual = (await db.collection('transport_stops').get()).docs.map(d=>({id:d.id,...d.data()}));
  const feeds = (await db.collection('transport_feeds').get()).docs;
  const stops = [...manual];
  for (const doc of feeds) {
    const feed = doc.data();
    if (!feed.activeVersionId) continue;
    if (feed.distribution?.formatVersion === 2) {
      const prefix = `transport_data/${doc.id}/${feed.activeVersionId}`;
      const [bytes] = await bucket.file(`${prefix}/stop-names.json.gz`).download();
      const rows = JSON.parse(gunzipSync(bytes)).stops ?? [];
      stops.push(...rows.map(s=>({...s,sourceType:'gtfs',verificationStatus:'unverified'})));
    } else {
      const rows = await doc.ref.collection('versions').doc(feed.activeVersionId).collection('transport_stops').get();
      stops.push(...rows.docs.map(d=>({id:d.id,...d.data(),sourceType:'gtfs',verificationStatus:'unverified'})));
    }
  }
  const records = [];
  for (const sample of samples) {
    if (existing.docs.some(d=>d.id === sample.id)) continue;
    const matches = [...new Map(stops.filter(s => s.isActive !== false &&
      (sample.names.includes(s.name) || s.departurePlaceId === sample.legacyId)).map(s=>[s.id,s])).values()];
    if (matches.length > 30) throw Error(`${sample.id}: more than 30 access stops; review required`);
    const url = new URL('https://msearch.gsi.go.jp/address-search/AddressSearch');
    url.searchParams.set('q',sample.address);
    const response = await fetch(url,{signal:AbortSignal.timeout(10000)});
    if (!response.ok) throw Error('geocode HTTP '+response.status);
    const found = await response.json();
    if (found.length !== 1) throw Error(`${sample.id}: ambiguous geocode (${found.length})`);
    const [longitude,latitude] = found[0].geometry.coordinates;
    if (!Number.isFinite(latitude) || !Number.isFinite(longitude) || Math.abs(latitude)>90 || Math.abs(longitude)>180) throw Error('invalid coordinates');
    const accessStops = matches.map(s=>({
      stopId:s.id,stopName:s.name,stopDestinations:s.stopDestinations ?? [],
      ...(s.platformCode != null ? {platformCode:s.platformCode} : {}),
      walkingMinutes:null,walkingDistanceMeters:null,isPrimary:false,isActive:true,
      sourceType:'manual', verificationStatus:'unverified',
    }));
    records.push({id:sample.id,address:sample.address,latitude,longitude,accessStops});
  }
  console.log(JSON.stringify({projectId,existing:existing.docs.map(d=>d.id),records},null,2));
  if (!process.argv.includes('--apply') || !records.length) return;
  const dir = path.resolve('.local-backups/departures');fs.mkdirSync(dir,{recursive:true,mode:0o700});
  const backup = path.join(dir,`${new Date().toISOString().replaceAll(':','-')}.json`);
  fs.writeFileSync(backup,JSON.stringify({projectId,existing:existing.docs.map(d=>({id:d.id,data:d.data()})),legacyStops:manual,records},null,2),{mode:0o600,flag:'wx'});
  const batch = db.batch();
  for (const {id,...data} of records) batch.create(db.collection('departure_places').doc(id),{
    ...data,createdAt:FieldValue.serverTimestamp(),updatedAt:FieldValue.serverTimestamp(),
  });
  await batch.commit();
  for (const record of records) {
    const doc = await db.collection('departure_places').doc(record.id).get();
    const data = doc.data();
    if (data?.address !== record.address || data.latitude !== record.latitude || data.longitude !== record.longitude || JSON.stringify(data.accessStops.map(s=>s.stopId).sort()) !== JSON.stringify(record.accessStops.map(s=>s.stopId).sort())) throw Error('verification failed');
  }
  console.log(JSON.stringify({created:records.map(r=>r.id),verified:true,backup}));
}
main().catch(error=>{console.error(error.message);process.exitCode=1;});
