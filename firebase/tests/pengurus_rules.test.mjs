import fs from 'node:fs';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, collection, getDoc, getDocs, setDoc, updateDoc, deleteDoc, writeBatch } from 'firebase/firestore';

const env = await initializeTestEnvironment({
  projectId: 'demo-gkii-pengurus',
  firestore: {
    host: '127.0.0.1', port: 8181,
    rules: fs.readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8'),
  },
});
try {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async context => {
    const db = context.firestore();
    for (const [id, account] of Object.entries({
      own: { role: 'user', adminDaerahArea: 'Belitang' },
      other: { role: 'admin', adminDaerahArea: 'Daerah lain' },
      blocked: { role: 'superadmin', isBlocked: true },
      super: { role: 'superadmin' },
      ordinary: { role: 'user' },
    })) await setDoc(doc(db, 'users', id), account);
  });
  const own = env.authenticatedContext('own').firestore();
  const root = 'struktur_pengurus_daerah/Belitang';
  const sections = ['penasehat', 'mkdp', 'bpk', 'komisi'];
  const superDb = env.authenticatedContext('super').firestore();
  await assertSucceeds(getDoc(doc(superDb, root))); // Superadmin can open a new area.
  for (const section of sections) await assertSucceeds(getDocs(collection(superDb, `${root}/${section}`)));
  await assertFails(setDoc(doc(own, root), { daerah: 'Belitang' }));
  const batch = writeBatch(superDb);
  batch.set(doc(superDb, root), { daerah: 'Belitang', bphd_ketua: 'Ketua' });
  batch.set(doc(superDb, `${root}/komisi/anak`), { daerah: 'Belitang', namaKomisi: 'Anak', anggota: [] });
  await assertSucceeds(batch.commit()); // getAfter permits atomic parent/child creation.
  for (const section of sections) {
    const ref = doc(own, `${root}/${section}/person`);
    await assertSucceeds(setDoc(ref, { daerah: 'Belitang', nama: 'Nama' }));
    await assertSucceeds(getDocs(collection(own, `${root}/${section}`)));
    await assertSucceeds(updateDoc(ref, { nama: 'Nama baru' }));
    await assertFails(updateDoc(ref, { daerah: 'Daerah lain' }));
    await assertSucceeds(deleteDoc(ref));
  }
  await assertSucceeds(updateDoc(doc(own, `${root}/komisi/anak`), { anggota: [{ nama: 'Anggota' }] }));
  await assertFails(updateDoc(doc(own, root), { daerah: 'Daerah lain' }));
  await assertFails(deleteDoc(doc(own, root)));
  await assertFails(setDoc(doc(own, `${root}/lainnya/x`), { daerah: 'Belitang' }));
  for (const id of ['other', 'blocked', 'ordinary', null]) {
    const db = id ? env.authenticatedContext(id).firestore() : env.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(db, root)));
    for (const section of sections) {
      await assertFails(getDocs(collection(db, `${root}/${section}`)));
      await assertFails(setDoc(doc(db, `${root}/${section}/bad`), { daerah: 'Belitang' }));
    }
    await assertFails(setDoc(doc(db, root), { daerah: 'Belitang' }));
  }
  await assertSucceeds(getDoc(doc(superDb, root)));
  await assertSucceeds(updateDoc(doc(superDb, root), { bphd_ketua: 'Ketua baru' }));
  await assertFails(getDoc(doc(own, 'struktur_pengurus_daerah/Daerah%20lain')));
  // Real region labels and future regions require no Rules name mapping.
  for (const area of ['Daerah Belitang', 'Daerah Ketungau', 'Daerah Pontianak', 'Daerah Baru', 'Daerah/Unicode é']) {
    const path = `struktur_pengurus_daerah/${encodeURIComponent(area)}`;
    await assertSucceeds(getDoc(doc(superDb, path)));
    for (const section of sections) await assertSucceeds(getDocs(collection(superDb, `${path}/${section}`)));
    const create = writeBatch(superDb);
    create.set(doc(superDb, path), { daerah: area, bphd_ketua: 'Ketua' });
    create.set(doc(superDb, `${path}/komisi/anak`), { daerah: area, namaKomisi: 'Anak' });
    await assertSucceeds(create.commit());
    await assertFails(getDoc(doc(own, path)));
    await assertFails(updateDoc(doc(superDb, path), { daerah: 'Lain' }));
    await assertFails(setDoc(doc(superDb, `${path}/komisi/salah`), { daerah: 'Lain' }));
  }
  await assertFails(setDoc(doc(superDb, 'struktur_pengurus_daerah/empty'), { daerah: '' }));
  // Existing module permissions from the supplied rules remain intact.
  const ordinary = env.authenticatedContext('ordinary').firestore();
  for (const path of ['prayers/a', 'songs/a', 'kamus_global/a', 'keuangan_daerah/a', 'perpuluhan_daerah/a', 'info_surat_daerah/a', 'churches/a/gallery/a']) {
    await assertSucceeds(setDoc(doc(ordinary, path), { contoh: true }));
    await assertSucceeds(getDoc(doc(ordinary, path)));
  }
  await assertSucceeds(setDoc(doc(ordinary, 'users/ordinary/notes/a'), { note: 'Catatan' }));
  await assertFails(getDoc(doc(own, 'users/ordinary/notes/a')));
  await assertFails(setDoc(doc(ordinary, 'aset_gereja/a'), { contoh: true }));
  console.log('PASS: regional access, missing data, atomic creation, membership, denied users, and existing modules');
} finally {
  await env.cleanup();
}
