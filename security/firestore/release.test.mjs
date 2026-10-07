import { readFile } from 'node:fs/promises';
import { describe, test, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import { doc, collection, getDoc, getDocs, updateDoc, setDoc, writeBatch, query, where } from 'firebase/firestore';
const require = createRequire(new URL('../../functions/package.json', import.meta.url));
const { initializeApp, deleteApp } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { getFirestore, Timestamp } = require('firebase-admin/firestore');
const project = 'demo-gereja-rules';
for (const key of ['FIRESTORE_EMULATOR_HOST','FIREBASE_AUTH_EMULATOR_HOST']) {
  if (!/^(localhost|127\.0\.0\.1):\d+$/.test(process.env[key] || '')) throw Error(`Local ${key} is required`);
}
const actor = (role='user', extra={}) => ({ role, churchId:'a', jemaatId:'', isBlocked:false,
  isPengurus:false, kelompok:'AMKI', namaLengkap:'Nama', ...extra });
describe('Release rules and real authenticated callable approval flow', () => {
  let env, app, db;
  const contexts = new Map(), tokens = new Map();
  const user = uid => {
    if (!contexts.has(uid)) contexts.set(uid, env.authenticatedContext(uid).firestore());
    return contexts.get(uid);
  };
  async function call(uid, name, data) {
    const response = await fetch(`http://127.0.0.1:5001/${project}/us-central1/${name}`, {
      method:'POST', headers:{'Content-Type':'application/json', ...(uid ? {Authorization:`Bearer ${tokens.get(uid)}`} : {})},
      body:JSON.stringify({data}) });
    const body = await response.json();
    if (body.error) { const e=Error(body.error.message); e.code=body.error.status; throw e; }
    return body.result;
  }
  before(async () => {
    env = await initializeTestEnvironment({ projectId:project,
      firestore:{host:'127.0.0.1',port:8080,rules:await readFile('firestore.release.rules','utf8')} });
    app = initializeApp({projectId:project}, 'approval-tests'); db=getFirestore(app);
    for (const uid of ['u','v','new','admin','adminB','super','blocked','gembala','bpj']) {
      await getAuth(app).createUser({uid,email:`${uid}@demo.test`,password:'test-password-123'});
      const response = await fetch(`http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=fake-key`, {
        method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({email:`${uid}@demo.test`,password:'test-password-123',returnSecureToken:true})});
      const data=await response.json(); assert.ok(data.idToken); tokens.set(uid,data.idToken);
    }
  });
  beforeEach(async () => {
    await env.clearFirestore();
    const batch=db.batch();
    const fixtures={
      'churches/a':{namaGereja:'A',daerah:'Utara',kodeUndangan:'OLD123'},
      'churches/b':{namaGereja:'B',daerah:'Selatan',kodeUndangan:'OTHER'},
      'users/u':actor(), 'users/v':actor(), 'users/new':actor('user',{churchId:'',kelompok:'Umum'}),
      'users/admin':actor('admin'), 'users/adminB':actor('admin',{churchId:'b'}), 'users/super':actor('superadmin'),
      'users/blocked':actor('superadmin',{isBlocked:true}), 'users/gembala':actor('gembala'), 'users/bpj':actor('bpj'),
      'churches/a/jemaat/j':{nomorTelepon:'081234567890',tanggalLahir:'01-02-2000',namaLengkap:'Nama Jemaat',kelompok:'AMKI'},
      'prayers/private':{churchId:'a',uid:'v',isPrivat:true,isiDoa:'Private'},
      'prayers/public':{churchId:'a',uid:'v',isPrivat:false,isiDoa:'Public'},
      'prayers/legacy':{churchId:'a',uid:'v',isiDoa:'Legacy public'},
    };
    for (const [path,data] of Object.entries(fixtures)) batch.set(db.doc(path),data);
    await batch.commit();
  });
  after(async () => { await env?.cleanup(); if (app) await deleteApp(app); });
  test('private reads denied to other members/BPJ; owner/admin/gembala allowed', async () => {
    for (const uid of ['u','bpj','adminB','blocked']) await assertFails(getDoc(doc(user(uid),'prayers/private')));
    for (const uid of ['v','admin','gembala','super']) await assertSucceeds(getDoc(doc(user(uid),'prayers/private')));
  });
  test('new public/own queries allowed; old broad member query denied, privileged broad query allowed', async () => {
    const base=collection(user('u'),'prayers');
    const publicRows=await assertSucceeds(getDocs(query(base,where('churchId','==','a'),where('isPrivat','==',false))));
    assert.deepEqual(publicRows.docs.map(d=>d.id),['public']);
    await assertSucceeds(getDocs(query(base,where('churchId','==','a'),where('uid','==','u'))));
    await assertFails(getDocs(query(base,where('churchId','==','a'))));
    await assertSucceeds(getDocs(query(collection(user('gembala'),'prayers'),where('churchId','==','a'))));
  });
  test('direct membership/link and forged approval requests denied; profile edit remains supported', async () => {
    await assertFails(updateDoc(doc(user('new'),'users/new'),{churchId:'a',churchName:'A'}));
    const batch=writeBatch(user('u'));
    batch.update(doc(user('u'),'users/u'),{jemaatId:'j',kelompok:'AMKI'});
    batch.update(doc(user('u'),'churches/a/jemaat/j'),{uid:'u'});
    await assertFails(batch.commit());
    await assertFails(setDoc(doc(user('u'),'profile_requests/link_u'),{uid:'u',status:'approved',churchId:'a'}));
    await assertSucceeds(updateDoc(doc(user('u'),'users/u'),{namaLengkap:'Changed'}));
  });
  test('unauthenticated/blocked requests rejected and payload cannot impersonate another UID', async () => {
    await assert.rejects(call(null,'searchJemaatCandidate',{phone:'081234567890'}),e=>e.code==='UNAUTHENTICATED');
    await assert.rejects(call('blocked','searchJemaatCandidate',{phone:'081234567890'}),e=>e.code==='PERMISSION_DENIED');
    await call('u','requestJemaatLink',{uid:'v',jemaatId:'j',phone:'081234567890',year:'2000'});
    assert.equal((await db.doc('profile_requests/link_u').get()).data().uid,'u');
    assert.equal((await db.doc('profile_requests/link_v').get()).exists,false);
  });
  test('search returns masked name and never birthday/phone/full book', async () => {
    const candidate=await call('u','searchJemaatCandidate',{phone:'+6281234567890'});
    assert.deepEqual(Object.keys(candidate).sort(),['churchId','jemaatId','namaLengkap']);
    assert.equal(candidate.namaLengkap,'Nama J.');
  });
  test('link request pending/idempotent until church admin approves atomic ownership', async () => {
    const payload={jemaatId:'j',phone:'081234567890',year:'2000'};
    await call('u','requestJemaatLink',payload); await call('u','requestJemaatLink',payload);
    assert.equal((await db.doc('users/u').get()).data().jemaatId,'');
    assert.equal((await db.doc('churches/a/jemaat/j').get()).data().uid,undefined);
    await assertSucceeds(getDoc(doc(user('u'),'profile_requests/link_u')));
    await assertFails(getDoc(doc(user('v'),'profile_requests/link_u')));
    await assert.rejects(call('u','reviewProfileRequest',{requestId:'link_u',approve:true}),e=>e.code==='PERMISSION_DENIED');
    await assert.rejects(call('adminB','reviewProfileRequest',{requestId:'link_u',approve:true}),e=>e.code==='PERMISSION_DENIED');
    await call('admin','reviewProfileRequest',{requestId:'link_u',approve:true});
    assert.equal((await db.doc('users/u').get()).data().jemaatId,'j');
    assert.equal((await db.doc('churches/a/jemaat/j').get()).data().uid,'u');
    assert.equal((await db.doc('users/u').get()).data().role,'user');
    assert.equal((await call('u','requestJemaatLink',payload)).status,'approved');
  });
  test('membership code checked on server; admin approval preserves profile and privileges', async () => {
    await assert.rejects(call('new','requestChurchMembership',{code:'BAD'}));
    await call('new','requestChurchMembership',{code:'OLD123'});
    assert.equal((await db.doc('users/new').get()).data().churchId,'');
    await call('admin','reviewProfileRequest',{requestId:'membership_new',approve:true});
    const data=(await db.doc('users/new').get()).data();
    assert.equal(data.churchId,'a'); assert.equal(data.role,'user'); assert.equal(data.isPengurus,false);
    assert.equal(data.jemaatId,''); assert.equal(data.namaLengkap,'Nama');
    await assert.rejects(call('u','requestChurchMembership',{code:'OTHER'}));
  });
  test('wrong birth year/invalid date/claimed book rejected', async () => {
    await assert.rejects(call('u','requestJemaatLink',{jemaatId:'j',phone:'081234567890',year:'1999'}));
    await db.doc('churches/a/jemaat/j').update({tanggalLahir:'31-02-2000'});
    await assert.rejects(call('u','requestJemaatLink',{jemaatId:'j',phone:'081234567890',year:'2000'}));
    await db.doc('churches/a/jemaat/j').update({tanggalLahir:'2000',uid:'v'});
    await assert.rejects(call('u','requestJemaatLink',{jemaatId:'j',phone:'081234567890',year:'2000'}));
  });
  test('legacy numeric phones/Timestamp birthday accepted without rewriting book', async () => {
    await db.doc('churches/a/jemaat/j').update({nomorTelepon:81234567890,tanggalLahir:Timestamp.fromDate(new Date('2000-02-01T00:00:00Z'))});
    await call('u','requestJemaatLink',{jemaatId:'j',phone:'081234567890',year:'2000'});
    await call('admin','reviewProfileRequest',{requestId:'link_u',approve:true});
    assert.equal(typeof (await db.doc('churches/a/jemaat/j').get()).data().nomorTelepon,'number');
  });
  test('stale book or newly blocked applicant prevents approval without partial link', async () => {
    await call('u','requestJemaatLink',{jemaatId:'j',phone:'081234567890',year:'2000'});
    await db.doc('churches/a/jemaat/j').update({namaLengkap:'Changed'});
    await assert.rejects(call('admin','reviewProfileRequest',{requestId:'link_u',approve:true}));
    assert.equal((await db.doc('users/u').get()).data().jemaatId,'');
    await db.doc('churches/a/jemaat/j').update({namaLengkap:'Nama Jemaat'});
    await db.doc('users/u').update({isBlocked:true});
    await assert.rejects(call('admin','reviewProfileRequest',{requestId:'link_u',approve:true}),e=>e.code==='PERMISSION_DENIED');
  });
  test('concurrent approval cannot let two accounts own one book', async () => {
    const payload={jemaatId:'j',phone:'081234567890',year:'2000'};
    await call('u','requestJemaatLink',payload); await call('v','requestJemaatLink',payload);
    const results=await Promise.allSettled(['u','v'].map(uid=>call('admin','reviewProfileRequest',{requestId:`link_${uid}`,approve:true})));
    assert.equal(results.filter(r=>r.status==='fulfilled').length,1);
    const owner=(await db.doc('churches/a/jemaat/j').get()).data().uid;
    assert.equal((await db.doc(`users/${owner}`).get()).data().jemaatId,'j');
    const loser=owner==='u'?'v':'u'; assert.equal((await db.doc(`users/${loser}`).get()).data().jemaatId,'');
  });
  test('reject does not mutate membership/book and revoked reviewer loses permission', async () => {
    await call('u','requestJemaatLink',{jemaatId:'j',phone:'081234567890',year:'2000'});
    await call('admin','reviewProfileRequest',{requestId:'link_u',approve:false});
    assert.equal((await db.doc('users/u').get()).data().jemaatId,'');
    await call('v','requestJemaatLink',{jemaatId:'j',phone:'081234567890',year:'2000'});
    await db.doc('users/admin').update({role:'user'});
    await assert.rejects(call('admin','reviewProfileRequest',{requestId:'link_v',approve:true}),e=>e.code==='PERMISSION_DENIED');
  });
  test('rate limit prevents unlimited phone enumeration', async () => {
    for(let i=0;i<10;i++) await call('u','searchJemaatCandidate',{phone:'081234567890'});
    await assert.rejects(call('u','searchJemaatCandidate',{phone:'081234567890'}),e=>e.code==='RESOURCE_EXHAUSTED');
  });
});
