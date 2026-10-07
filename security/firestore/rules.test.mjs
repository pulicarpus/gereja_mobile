import { readFile } from 'node:fs/promises';
import { describe, test, before, after, beforeEach } from 'node:test';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import { doc, collection, getDoc, getDocs, setDoc, updateDoc, deleteDoc, writeBatch, runTransaction, query, where, arrayUnion } from 'firebase/firestore';

// Fail closed: these tests may ONLY connect to the local emulator, never prod.
const address = process.env.FIRESTORE_EMULATOR_HOST;
if (!address || !/^(127\.0\.0\.1|localhost):\d+$/.test(address)) throw Error('Local Firestore emulator is required');
const [host, port] = address.split(':');
const account = (uid, extra = {}) => ({ uid, role: 'user', isBlocked: false, churchId: 'a',
  churchName: 'A', jemaatId: '', kelompok: 'AMKI', isPengurus: false, daerah: 'Utara', namaLengkap: uid, ...extra });
const fixtures = {
  'churches/a': { namaGereja: 'A', daerah: 'Utara', kodeUndangan: 'old-code' },
  'churches/b': { namaGereja: 'B', daerah: 'Selatan', kodeUndangan: 'another-code' },
  'users/u': account('u'), 'users/v': account('v', { jemaatId: 'claimed' }), 'users/other': account('other', { churchId: 'b', daerah: 'Selatan' }),
  'users/admin': account('admin', { role: 'admin' }),
  'users/super': account('super', { role: 'superadmin' }),
  'users/blocked': account('blocked', { role: 'superadmin', isBlocked: true }),
  'users/leader': account('leader', { isPengurus: true, kelompok: ' amki ' }),
  'users/regional': account('regional', { adminDaerahArea: 'Utara' }),
  'users/gembala': account('gembala', { role: 'gembala' }),
  'users/bpj': account('bpj', { role: 'bpj' }),
  'users/new': account('new', { churchId: '', churchName: '', daerah: '', kelompok: 'Umum' }),
  'churches/a/jemaat/free': { kelompok: ' amki ', nama: 'Legacy' },
  'churches/a/jemaat/claimed': { uid: 'v', kelompok: 'AMKI' },
  'churches/b/jemaat/free': { kelompok: 'Perkawan' },
  'churches/a/aset/x': { nama: 'Meja' },
  'churches/a/chats/m': { pengirimId: 'v', pesan: 'Hi', tipe: 'text' },
  'churches/a/chats/legacy': { senderId: 'u', pesan: 'Old' },
  'churches/a/transaksi/general': { kategori: 'Umum', jumlah: '1000' },
  'churches/a/transaksi/amki': { kategori: 'AMKI', jumlah: 1000 },
  'churches/a/jadwal/amki': { kategoriKegiatan: 'AMKI', namaKegiatan: 'Ibadah' },
  'churches/a/gallery_folders/f': { nama: 'Album' },
  'aset_gereja/x': { gerejaId: 'a', nama: 'Meja' },
  'keuangan_daerah/n': { daerah: 'Utara', jumlah: 100 },
  'keuangan_daerah/s': { daerah: 'Selatan', jumlah: 100 },
  'prayers/private': { churchId: 'a', uid: 'v', isPrivat: true, isiDoa: 'Private', daftarAmin: [] },
  'prayers/public': { churchId: 'a', uid: 'v', isPrivat: false, isiDoa: 'Public', daftarAmin: [] },
  'songs/s': { judul: 'Lagu' }, 'kamus_global/iman': { arti: 'Legacy definition' },
  'users/u/notes/n': { text: 'Note' },
};
async function setup(projectId, rules) {
  return initializeTestEnvironment({ projectId, firestore: { host, port: Number(port), rules } });
}
async function seed(env) {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async context => {
    const batch = writeBatch(context.firestore());
    for (const [path, value] of Object.entries(fixtures)) batch.set(doc(context.firestore(), path), value);
    await batch.commit();
  });
}
describe('Reproduce supplied rules vulnerabilities', () => {
  let env;
  before(async () => { env = await setup('demo-gereja-rules-original', await readFile('firestore.supplied.rules', 'utf8')); });
  beforeEach(async () => seed(env));
  after(async () => env?.cleanup());
  test('a member can grant themselves superadmin', async () => {
    await assertSucceeds(updateDoc(doc(env.authenticatedContext('u').firestore(), 'users/u'), { role: 'superadmin' }));
  });
  test('recursive wildcard bypasses asset, jemaat and chat restrictions', async () => {
    const db = env.authenticatedContext('u').firestore();
    await assertSucceeds(updateDoc(doc(db, 'churches/a/jemaat/claimed'), { uid: 'u' }));
    await assertSucceeds(deleteDoc(doc(db, 'churches/a/aset/x')));
    await assertSucceeds(deleteDoc(doc(db, 'churches/a/chats/m')));
  });
});
describe('Transition rules: application contracts and denied attacks', () => {
  let env;
  // A batch/transaction must use references from the SAME SDK instance.
  const databases = new Map();
  const db = uid => {
    if (!databases.has(uid)) databases.set(uid, uid
      ? env.authenticatedContext(uid).firestore() : env.unauthenticatedContext().firestore());
    return databases.get(uid);
  };
  const ref = (uid, path) => doc(db(uid), path);
  before(async () => { env = await setup('demo-gereja-rules', await readFile('firestore.compat.rules', 'utf8')); });
  beforeEach(async () => seed(env));
  after(async () => env?.cleanup());
  test('anonymous access denied', async () => assertFails(getDoc(ref(null, 'songs/s'))));
  test('login can read its missing/blocked account, blocked cannot access modules', async () => {
    await assertSucceeds(getDoc(ref('absent', 'users/absent')));
    await assertSucceeds(getDoc(ref('blocked', 'users/blocked')));
    await assertFails(getDoc(ref('blocked', 'songs/s')));
    await assertFails(setDoc(ref('blocked', 'churches/a/aset/new'), { nama: 'No' }));
  });
  test('ordinary registration allowed; forged privilege, extra field and foreign UID denied', async () => {
    const initial = { uid: 'fresh', email: 'test@example.test', namaLengkap: 'Fresh', photoUrl: null,
      role: 'user', isBlocked: false, churchId: '', churchName: '', jemaatId: '', isPengurus: false, daerah: '' };
    await assertFails(setDoc(ref('fresh', 'users/fresh'), { ...initial, role: 'superadmin' }));
    await assertFails(setDoc(ref('fresh', 'users/fresh'), { ...initial, adminDaerahArea: 'Utara' }));
    await assertFails(setDoc(ref('u', 'users/fresh'), initial));
    await assertSucceeds(setDoc(ref('fresh', 'users/fresh'), initial));
  });
  test('profile name/photo allowed; role, block, leader and regional escalation denied', async () => {
    await assertSucceeds(updateDoc(ref('u', 'users/u'), { namaLengkap: 'Changed', photoUrl: null }));
    for (const patch of [{ role: 'admin' }, { isBlocked: false, role: 'superadmin' }, { isPengurus: true },
      { adminDaerahArea: 'Utara' }, { daerah: 'Selatan' }, { churchId: 'b' }, { kelompok: 'Perkawan' }]) {
      await assertFails(updateDoc(ref('u', 'users/u'), patch));
    }
  });
  test('compatibility exception: initial church assignment allowed, repeat transfer denied', async () => {
    await assertSucceeds(updateDoc(ref('new', 'users/new'), { churchId: 'a', churchName: 'A' }));
    await assertFails(updateDoc(ref('new', 'users/new'), { churchId: 'b', churchName: 'B' }));
  });
  test('user queries require admin and church scope', async () => {
    await assertSucceeds(getDocs(query(collection(db('admin'), 'users'), where('churchId', '==', 'a'))));
    await assertFails(getDocs(collection(db('admin'), 'users')));
    await assertFails(getDoc(ref('admin', 'users/other')));
    await assertFails(getDoc(ref('u', 'users/v')));
    await assertSucceeds(getDocs(query(collection(db('super'), 'users'), where('churchId', '==', 'b'))));
  });
  test('local admin manages normal local members but not regional authority or other admins', async () => {
    await assertSucceeds(updateDoc(ref('admin', 'users/u'), { role: 'admin', isPengurus: false }));
    await assertFails(updateDoc(ref('admin', 'users/u'), { isBlocked: true }));
    await assertFails(updateDoc(ref('admin', 'users/v'), { adminDaerahArea: 'Utara' }));
    await assertFails(updateDoc(ref('admin', 'users/other'), { isPengurus: true }));
    await assertFails(updateDoc(ref('admin', 'users/admin'), { role: 'superadmin' }));
  });
  test('superadmin may appoint regional admin but cannot create another superadmin client-side', async () => {
    await assertSucceeds(updateDoc(ref('super', 'users/v'), { adminDaerahArea: 'Utara' }));
    await assertFails(updateDoc(ref('super', 'users/v'), { role: 'superadmin' }));
    await assertFails(updateDoc(ref('super', 'users/super'), { churchId: 'b' }));
    await assertFails(updateDoc(ref('super', 'users/new'), { role: 'admin' }));
  });
  test('management category edits keep linked account/book consistent and reset leadership', async () => {
    await assertFails(updateDoc(ref('admin', 'users/v'), { kelompok: 'Perkawan', isPengurus: false }));
    const batch = writeBatch(db('admin'));
    batch.update(ref('admin', 'users/v'), { kelompok: 'Perkawan', isPengurus: false });
    batch.update(ref('admin', 'churches/a/jemaat/claimed'), { kelompok: 'Perkawan' });
    await assertSucceeds(batch.commit());
  });
  test('atomic account/book link allowed including legacy missing uid and category spacing', async () => {
    const batch = writeBatch(db('u'));
    batch.update(ref('u', 'users/u'), { jemaatId: 'free', kelompok: 'AMKI' });
    batch.update(ref('u', 'churches/a/jemaat/free'), { uid: 'u' });
    await assertSucceeds(batch.commit());
  });
  test('one-sided link and stolen book denied', async () => {
    await assertFails(updateDoc(ref('u', 'users/u'), { jemaatId: 'free', kelompok: 'AMKI' }));
    await assertFails(updateDoc(ref('u', 'churches/a/jemaat/free'), { uid: 'u' }));
    const batch = writeBatch(db('u'));
    batch.update(ref('u', 'users/u'), { jemaatId: 'claimed', kelompok: 'AMKI' });
    batch.update(ref('u', 'churches/a/jemaat/claimed'), { uid: 'u' });
    await assertFails(batch.commit());
  });
  test('link cannot change biodata or invent category', async () => {
    for (const bad of ['biodata', 'category']) {
      const batch = writeBatch(db('u'));
      batch.update(ref('u', 'users/u'), { jemaatId: 'free', kelompok: bad === 'category' ? 'Perkawan' : 'AMKI' });
      batch.update(ref('u', 'churches/a/jemaat/free'), { uid: 'u', ...(bad === 'biodata' ? { nama: 'Forged' } : {}) });
      await assertFails(batch.commit());
    }
  });
  test('jemaat writes admin only except coupled self link; region reads remain supported', async () => {
    await assertFails(deleteDoc(ref('u', 'churches/a/jemaat/free')));
    await assertSucceeds(updateDoc(ref('admin', 'churches/a/jemaat/free'), { nama: 'Updated' }));
    await assertFails(updateDoc(ref('admin', 'churches/b/jemaat/free'), { nama: 'Other church' }));
    await assertSucceeds(getDocs(collection(db('regional'), 'churches/a/jemaat')));
    await assertFails(getDocs(collection(db('u'), 'churches/b/jemaat')));
  });
  test('asset restrictions cannot be bypassed by wildcard', async () => {
    await assertFails(deleteDoc(ref('u', 'churches/a/aset/x')));
    await assertSucceeds(deleteDoc(ref('admin', 'churches/a/aset/x')));
    await assertFails(updateDoc(ref('admin', 'aset_gereja/x'), { gerejaId: 'b' }));
    await assertSucceeds(updateDoc(ref('admin', 'aset_gereja/x'), { nama: 'Updated' }));
  });
  test('church metadata admin fields allowed, invitation/region edits central only', async () => {
    await assertSucceeds(updateDoc(ref('admin', 'churches/a'), { namaBank: 'Bank' }));
    await assertFails(updateDoc(ref('admin', 'churches/a'), { kodeUndangan: 'forge' }));
    await assertFails(updateDoc(ref('u', 'churches/a'), { noRekening: '123' }));
    await assertSucceeds(updateDoc(ref('super', 'churches/a'), { daerah: 'New' }));
  });
  test('finance writers follow local category and cannot move records to another category', async () => {
    await assertSucceeds(updateDoc(ref('leader', 'churches/a/transaksi/amki'), { jumlah: 200 }));
    await assertFails(updateDoc(ref('leader', 'churches/a/transaksi/general'), { jumlah: 200 }));
    await assertFails(updateDoc(ref('leader', 'churches/a/transaksi/amki'), { kategori: 'Perkawan' }));
    await assertFails(setDoc(ref('u', 'churches/a/perpuluhan/new'), { jumlah: 100 }));
    await assertSucceeds(setDoc(ref('admin', 'churches/a/perpuluhan/new'), { jumlah: 100 }));
  });
  test('category schedule and announcement use actual app field/path names', async () => {
    await assertSucceeds(updateDoc(ref('leader', 'churches/a/jadwal/amki'), { susunanAcara: [] }));
    await assertFails(updateDoc(ref('leader', 'churches/a/jadwal/amki'), { kategoriKegiatan: 'Perkawan' }));
    await assertSucceeds(setDoc(ref('leader', 'churches/a/pengumuman/pengumuman_AMKI'), { teks: 'Hi' }));
    await assertFails(setDoc(ref('leader', 'churches/a/pengumuman/utama'), { teks: 'Hi' }));
  });
  test('chat sender identity, legacy owner edits, deletes and mute enforced', async () => {
    await assertSucceeds(setDoc(ref('u', 'churches/a/chats/new'), { pengirimId: 'u', pesan: 'Hi' }));
    await assertFails(setDoc(ref('u', 'churches/a/chats/forged'), { pengirimId: 'v', pesan: 'Hi' }));
    await assertSucceeds(updateDoc(ref('u', 'churches/a/chats/legacy'), { pesan: 'Edited' }));
    await assertFails(updateDoc(ref('u', 'churches/a/chats/legacy'), { senderId: 'v' }));
    await assertFails(deleteDoc(ref('u', 'churches/a/chats/m')));
    await assertSucceeds(deleteDoc(ref('admin', 'churches/a/chats/m')));
    await assertSucceeds(setDoc(ref('admin', 'churches/a/muted_chats/u'), { muted: true }));
    await assertSucceeds(getDoc(ref('u', 'churches/a/muted_chats/u')));
    await assertFails(setDoc(ref('u', 'churches/a/chats/muted'), { pengirimId: 'u', pesan: 'No' }));
  });
  test('category chat access and mute management limited to appropriate category', async () => {
    await assertSucceeds(setDoc(ref('leader', 'churches/a/muted_chats_AMKI/u'), { muted: true }));
    await assertFails(setDoc(ref('leader', 'churches/a/muted_chats_Perkawan/u'), { muted: true }));
    await assertFails(getDocs(collection(db('u'), 'churches/a/chats_Perkawan')));
    await assertSucceeds(getDocs(collection(db('u'), 'churches/a/chats_AMKI')));
  });
  test('gallery image parent required; batch deletion and category upload supported', async () => {
    await assertSucceeds(setDoc(ref('admin', 'churches/a/gallery_folders/f/images/i'), { imageUrl: 'old-format' }));
    await assertFails(setDoc(ref('admin', 'churches/a/gallery_folders/missing/images/i'), { imageUrl: 'orphan' }));
    await assertSucceeds(setDoc(ref('leader', 'churches/a/gallery_folders_AMKI/f'), { nama: 'Album' }));
    await assertFails(setDoc(ref('u', 'churches/a/gallery_folders_AMKI/x'), { nama: 'No' }));
    const batch = writeBatch(db('admin'));
    batch.delete(ref('admin', 'churches/a/gallery_folders/f/images/i'));
    batch.delete(ref('admin', 'churches/a/gallery_folders/f'));
    await assertSucceeds(batch.commit());
  });
  test('regional finance allows designated admin, gembala and BPJ but no cross-region move', async () => {
    for (const uid of ['regional','gembala','bpj']) await assertSucceeds(updateDoc(ref(uid, 'keuangan_daerah/n'), { jumlah: 200 }));
    await assertFails(updateDoc(ref('u', 'keuangan_daerah/n'), { jumlah: 200 }));
    await assertFails(updateDoc(ref('regional', 'keuangan_daerah/s'), { jumlah: 200 }));
    await assertFails(updateDoc(ref('regional', 'keuangan_daerah/n'), { daerah: 'Selatan' }));
    await assertSucceeds(getDocs(query(collection(db('regional'), 'keuangan_daerah'), where('daerah', '==', 'Utara'))));
    await assertFails(getDocs(collection(db('regional'), 'keuangan_daerah')));
  });
  test('regional notices require appointment; paired tithe/ledger batch supported', async () => {
    await assertFails(setDoc(ref('gembala', 'info_surat_daerah/new'), { daerah: 'Utara' }));
    await assertSucceeds(setDoc(ref('regional', 'info_surat_daerah/new'), { daerah: 'Utara' }));
    const batch = writeBatch(db('bpj'));
    for (const c of ['perpuluhan_daerah','keuangan_daerah']) batch.set(ref('bpj', `${c}/paired`), { daerah: 'Utara', jumlah: 100 });
    await assertSucceeds(batch.commit());
  });
  test('actual create transactions may read missing asset, notice and both regional ledger docs', async () => {
    for (const [uid, entries] of [
      ['admin', [['aset_gereja/new', { gerejaId: 'a', nama: 'Meja' }]]],
      ['regional', [['info_surat_daerah/new', { daerah: 'Utara', judul: 'Info' }]]],
      ['bpj', [['perpuluhan_daerah/new', { daerah: 'Utara', jumlah: 100 }],
        ['keuangan_daerah/new', { daerah: 'Utara', jumlah: 100 }]]],
    ]) {
      await assertSucceeds(runTransaction(db(uid), async tx => {
        await tx.get(ref(uid, `users/${uid}`));
        for (const [path] of entries) await tx.get(ref(uid, path));
        for (const [path, value] of entries) tx.set(ref(uid, path), value);
      }));
    }
  });
  test('songs admin writable; notes private; unknown modules/worker queue denied', async () => {
    await assertFails(updateDoc(ref('u', 'songs/s'), { judul: 'Forged' }));
    await assertSucceeds(updateDoc(ref('admin', 'songs/s'), { judul: 'Updated' }));
    await assertSucceeds(getDoc(ref('u', 'users/u/notes/n')));
    await assertFails(getDoc(ref('admin', 'users/u/notes/n')));
    for (const path of ['churches/a/settings/x','pending_notifications/x','chats_daerah/Utara/messages/x']) {
      await assertFails(setDoc(ref('u', path), { data: 'No' }));
    }
  });
  test('dictionary cache may be contributed once, cannot overwrite existing definition', async () => {
    await assertSucceeds(setDoc(ref('u', 'kamus_global/new'), { kata_asli: 'New', arti: 'Definition' }));
    await assertFails(setDoc(ref('v', 'kamus_global/new'), { kata_asli: 'New', arti: 'Poison' }));
    await assertFails(deleteDoc(ref('admin', 'kamus_global/iman')));
  });
  test('prayer ownership/moderation and legacy name-based Amin preserved', async () => {
    await assertFails(updateDoc(ref('u', 'prayers/public'), { isiDoa: 'Forged' }));
    await assertSucceeds(updateDoc(ref('v', 'prayers/public'), { isiDoa: 'Edited', isPrivat: true }));
    await assertSucceeds(updateDoc(ref('u', 'prayers/public'), { daftarAmin: arrayUnion('u') }));
    await assertFails(updateDoc(ref('u', 'prayers/public'), { daftarAmin: ['forged'] }));
    await assertFails(deleteDoc(ref('u', 'prayers/public')));
    await assertSucceeds(deleteDoc(ref('admin', 'prayers/public')));
  });
  test('explicit unresolved compatibility risk: private prayer still readable within church', async () => {
    await assertSucceeds(getDoc(ref('u', 'prayers/private')));
    await assertSucceeds(getDocs(query(collection(db('u'), 'prayers'), where('churchId', '==', 'a'))));
    await assertFails(getDoc(ref('other', 'prayers/private')));
  });
});
