import fs from 'node:fs';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, collection, getDoc, getDocs, setDoc, updateDoc, deleteDoc, writeBatch, query, where, runTransaction, serverTimestamp } from 'firebase/firestore';

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
      pastor: { role: 'gembala', churchId: 'pastorChurch', jemaatId: 'member', daerah: 'Stale' },
      unlinked: { role: 'gembala', churchId: 'pastorChurch' },
      dangling: { role: 'gembala', churchId: 'pastorChurch', jemaatId: 'gone' },
      mismatched: { role: 'gembala', churchId: 'pastorChurch', jemaatId: 'member' },
      blockedPastor: { role: 'gembala', churchId: 'pastorChurch', jemaatId: 'blocked', isBlocked: true },
    })) await setDoc(doc(db, 'users', id), account);
    await setDoc(doc(db, 'churches/pastorChurch'), { daerah: 'Belitang' });
    await setDoc(doc(db, 'churches/pastorChurch/jemaat/member'), { uid: 'pastor' });
    await setDoc(doc(db, 'churches/pastorChurch/jemaat/blocked'), { uid: 'blockedPastor' });
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
  for (const name of ['inventaris_daerah', 'pengurus_daerah', 'keuangan_daerah', 'perpuluhan_daerah', 'info_surat_daerah']) {
    const ownRecord = doc(own, `${name}/own`);
    await assertSucceeds(getDocs(query(collection(own, name), where('daerah', '==', 'Belitang'))));
    await assertSucceeds(runTransaction(own, async tx => {
      const missing = await tx.get(ownRecord);
      if (!missing.exists()) tx.set(ownRecord, { daerah: 'Belitang', nama: 'Barang', fotoUrl: '' });
    }));
    await assertSucceeds(updateDoc(ownRecord, { nama: 'Barang baru', fotoUrl: 'https://example.com/a.jpg' }));
    await assertSucceeds(getDoc(ownRecord));
    await assertFails(updateDoc(ownRecord, { daerah: 'Daerah lain' }));
    for (const area of ['Daerah Belitang', 'Daerah Ketungau', 'Daerah Baru']) {
      await assertSucceeds(setDoc(doc(superDb, name, encodeURIComponent(area)), { daerah: area, nama: 'Barang' }));
      await assertSucceeds(getDocs(query(collection(superDb, name), where('daerah', '==', area))));
      await assertFails(getDocs(query(collection(own, name), where('daerah', '==', area))));
    }
    await assertFails(getDocs(collection(own, name))); // Unscoped query rejected.
    for (const id of ['other', 'blocked', 'ordinary', null]) {
      const db = id ? env.authenticatedContext(id).firestore() : env.unauthenticatedContext().firestore();
      await assertFails(getDoc(doc(db, `${name}/own`)));
      await assertFails(getDocs(query(collection(db, name), where('daerah', '==', 'Belitang'))));
      await assertFails(setDoc(doc(db, `${name}/bad`), { daerah: 'Belitang', nama: 'Barang' }));
      await assertFails(updateDoc(doc(db, `${name}/own`), { nama: 'Ubah' }));
      await assertFails(deleteDoc(doc(db, `${name}/own`)));
    }
    await assertFails(setDoc(doc(superDb, `${name}/empty`), { daerah: '' }));
    await assertSucceeds(deleteDoc(ownRecord));
  }
  const pastor = env.authenticatedContext('pastor').firestore();
  await assertSucceeds(getDoc(doc(pastor, root)));
  for (const section of sections) {
    await assertSucceeds(getDocs(collection(pastor, `${root}/${section}`)));
    await assertFails(setDoc(doc(pastor, `${root}/${section}/bad`), { daerah: 'Belitang' }));
  }
  await assertFails(updateDoc(doc(pastor, root), { bphd_ketua: 'Ubah' }));
  await assertFails(getDoc(doc(pastor, 'struktur_pengurus_daerah/Daerah%20Ketungau')));
  for (const name of ['inventaris_daerah', 'pengurus_daerah', 'keuangan_daerah', 'perpuluhan_daerah', 'info_surat_daerah']) {
    await assertSucceeds(setDoc(doc(superDb, `${name}/readOnly`), { daerah: 'Belitang', nama: 'Contoh' }));
    await assertSucceeds(getDoc(doc(pastor, `${name}/readOnly`)));
    await assertSucceeds(getDocs(query(collection(pastor, name), where('daerah', '==', 'Belitang'))));
    await assertFails(getDocs(query(collection(pastor, name), where('daerah', '==', 'Daerah Baru'))));
    await assertFails(setDoc(doc(pastor, `${name}/new`), { daerah: 'Belitang' }));
    await assertFails(updateDoc(doc(pastor, `${name}/readOnly`), { nama: 'Ubah' }));
    await assertFails(deleteDoc(doc(pastor, `${name}/readOnly`)));
    for (const id of ['unlinked', 'dangling', 'mismatched', 'blockedPastor']) {
      const db = env.authenticatedContext(id).firestore();
      await assertFails(getDocs(query(collection(db, name), where('daerah', '==', 'Belitang'))));
      await assertFails(getDoc(doc(db, root)));
    }
  }
  await assertFails(updateDoc(doc(pastor, 'users/pastor'), { role: 'superadmin' }));
  await assertFails(updateDoc(doc(pastor, 'users/pastor'), { adminDaerahArea: 'Belitang' }));
  await assertSucceeds(updateDoc(doc(pastor, 'users/pastor'), { namaLengkap: 'Gembala' }));
  // Real-time discussion permits questions but does not grant post editing.
  const discussionPost = 'info_surat_daerah/discussion';
  await assertSucceeds(runTransaction(superDb, async tx => {
    const ref = doc(superDb, discussionPost);
    const current = await tx.get(ref);
    if (!current.exists()) tx.set(ref, { daerah: 'Belitang', judul: 'Info' });
  }));
  const comments = `${discussionPost}/komentar`;
  const message = { authorId: 'pastor', authorName: 'Gembala', text: 'Bolehkah bertanya?', createdAt: serverTimestamp() };
  const pastorComment = doc(pastor, `${comments}/one`);
  await assertSucceeds(runTransaction(pastor, async tx => {
    await tx.get(doc(pastor, discussionPost));
    const existing = await tx.get(pastorComment);
    if (!existing.exists()) tx.set(pastorComment, message);
  }));
  await assertSucceeds(getDocs(query(collection(pastor, comments), where('authorId', '==', 'pastor'))));
  await assertSucceeds(getDocs(collection(own, comments)));
  await assertFails(setDoc(doc(pastor, `${comments}/spoof`), { ...message, authorId: 'super' }));
  await assertFails(setDoc(doc(pastor, `${comments}/long`), { ...message, text: 'a'.repeat(2001) }));
  await assertFails(setDoc(doc(pastor, `${comments}/empty`), { ...message, text: '' }));
  await assertFails(setDoc(doc(pastor, `${comments}/extra`), { ...message, daerah: 'Belitang' }));
  await assertFails(setDoc(doc(pastor, `${comments}/timestamp`), { ...message, createdAt: null }));
  await assertFails(updateDoc(pastorComment, { text: 'Edit' }));
  await assertFails(updateDoc(doc(pastor, discussionPost), { judul: 'Edit' }));
  await assertSucceeds(setDoc(doc(own, `${comments}/admin`), { ...message, authorId: 'own' }));
  await assertFails(deleteDoc(doc(pastor, `${comments}/admin`)));
  for (const id of ['other', 'ordinary', 'blocked', 'unlinked', 'dangling', 'mismatched', null]) {
    const db = id ? env.authenticatedContext(id).firestore() : env.unauthenticatedContext().firestore();
    await assertFails(getDocs(collection(db, comments)));
    await assertFails(setDoc(doc(db, `${comments}/bad`), { ...message, authorId: id }));
    await assertFails(deleteDoc(doc(db, `${comments}/one`)));
  }
  // Legacy uppercase/whitespace region aliases must not isolate pastors.
  await assertSucceeds(setDoc(doc(superDb, 'info_surat_daerah/alias'), { daerah: ' BELITANG ' }));
  await assertSucceeds(getDocs(query(collection(pastor, 'info_surat_daerah'), where('daerah', 'in', ['Belitang', ' BELITANG ']))));
  await assertSucceeds(setDoc(doc(pastor, 'info_surat_daerah/alias/komentar/pastor'), message));
  await assertFails(updateDoc(doc(pastor, 'info_surat_daerah/alias'), { judul: 'Tidak boleh' }));
  await assertFails(getDocs(query(collection(pastor, 'info_surat_daerah'), where('daerah', 'in', ['Belitang', 'Ketungau']))));
  await assertSucceeds(deleteDoc(pastorComment));
  await assertSucceeds(setDoc(pastorComment, message));
  await assertSucceeds(deleteDoc(doc(own, `${comments}/one`))); // Moderator.
  await assertSucceeds(setDoc(pastorComment, message));
  await assertSucceeds(deleteDoc(doc(superDb, discussionPost)));
  await assertFails(getDocs(collection(pastor, comments)));
  await assertFails(setDoc(doc(pastor, `${comments}/orphan`), message));
  // Existing module permissions from the supplied rules remain intact.
  const ordinary = env.authenticatedContext('ordinary').firestore();
  for (const path of ['prayers/a', 'songs/a', 'kamus_global/a', 'churches/a/gallery/a']) {
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
