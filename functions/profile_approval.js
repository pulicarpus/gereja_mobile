const { HttpsError } = require('firebase-functions/v2/https');
const { Timestamp, FieldValue } = require('firebase-admin/firestore');
const { createHash } = require('node:crypto');
const text = v => typeof v === 'string' ? v.trim() : typeof v === 'number' ? String(v) : '';
const fail = message => { throw new HttpsError('failed-precondition', message); };
const id = value => typeof value === 'string' && value.length > 0 && value.length <= 200 && !value.includes('/');
const category = value => ['Sekolah Minggu','AMKI','Perkawan','Perkaria','Lainnya'].find(c => c.toLowerCase() === text(value).toLowerCase()) || 'Lainnya';
const revision = book => createHash('sha256').update(JSON.stringify([
  text(book.namaLengkap), text(book.nomorTelepon), typeof book.tanggalLahir?.toMillis === 'function'
    ? book.tanggalLahir.toMillis() : text(book.tanggalLahir), category(book.kelompok),
])).digest('hex');
function phone(raw) {
  let n = text(raw);
  if (!n || /[^0-9+\s().-]/.test(n)) fail('Nomor telepon tidak valid.');
  n = n.replace(/[\s().-]/g, '');
  const international = n.startsWith('+');
  if (international) n = n.slice(1);
  if (n.includes('+')) fail('Nomor telepon tidak valid.');
  if (n.startsWith('62')) n = `0${n.slice(2)}`;
  else if (!international && n.startsWith('8')) n = `0${n}`;
  if (!/^0[1-9][0-9]{7,12}$|^[1-9][0-9]{7,14}$/.test(n)) fail('Nomor telepon tidak valid.');
  return n;
}
function variants(raw) {
  const n = phone(raw), values = new Set([text(raw), n]);
  if (n.startsWith('0')) {
    const intl = `62${n.slice(1)}`;
    for (const value of [intl, `+${intl}`, n.slice(1), Number(n.slice(1)), Number(intl)]) values.add(value);
    for (const separator of [' ', '-', '.']) {
      const national = `${n.slice(1,4)}${separator}${n.slice(4,8)}${separator}${n.slice(8)}`;
      values.add(`${n.slice(0,4)}${separator}${n.slice(4,8)}${separator}${n.slice(8)}`);
      values.add(`62${separator}${national}`); values.add(`+62${separator}${national}`);
    }
  } else { values.add(`+${n}`); values.add(Number(n)); }
  return [...values];
}
function birthYear(value) {
  if (typeof value?.toDate === 'function') value = value.toDate();
  if (value instanceof Date) return value.getUTCFullYear();
  const s = text(value);
  if (/^\d{4}$/.test(s)) return Number(s);
  const local = /^(\d{1,2})[-/.](\d{1,2})[-/.](\d{4})$/.exec(s);
  const iso = /^(\d{4})-(\d{2})-(\d{2})(?:[T ].*)?$/.exec(s);
  if (!local && !iso) return null;
  const [y, m, d] = local ? [Number(local[3]),Number(local[2]),Number(local[1])] : [Number(iso[1]),Number(iso[2]),Number(iso[3])];
  const date = new Date(Date.UTC(y,m-1,d));
  return date.getUTCFullYear() === y && date.getUTCMonth()+1 === m && date.getUTCDate() === d ? y : null;
}
function createApprovalService(db, clock = () => Date.now()) {
  async function limit(user) {
    const ref = db.doc(`profile_rate_limits/${user}`);
    await db.runTransaction(async tx => {
      active(await tx.get(db.doc(`users/${user}`)));
      const snap = await tx.get(ref), old = snap.data();
      const window = old?.startedAt?.toMillis() > clock() - 15*60*1000;
      const count = window ? old.count : 0;
      if (count >= 10) throw new HttpsError('resource-exhausted', 'Terlalu banyak percobaan. Coba lagi setelah 15 menit.');
      tx.set(ref, { startedAt: window ? old.startedAt : Timestamp.fromMillis(clock()), count: count+1 });
    });
  }
  function uid(req) {
    if (!req.auth?.uid) throw new HttpsError('unauthenticated', 'Silakan login kembali.');
    return req.auth.uid;
  }
  function active(snapshot) {
    if (!snapshot.exists || snapshot.data().isBlocked === true) throw new HttpsError('permission-denied', 'Akun tidak tersedia atau diblokir.');
    return snapshot.data();
  }
  function eligibility(account, church, bookId, book, user) {
    if (text(account.churchId) !== church) fail('Gereja asal akun berubah.');
    if (text(account.jemaatId) && text(account.jemaatId) !== bookId) fail('Akun sudah tertaut ke data lain.');
    if (text(book.uid) && text(book.uid) !== user) fail('Buku induk sudah tertaut ke akun lain.');
    if (account.isPengurus === true && category(account.kelompok) !== category(book.kelompok)) fail('Kategori pengurus harus diperiksa admin.');
  }
  function unassigned(account) {
    if (text(account.churchId) || text(account.jemaatId) || (account.role || 'user') !== 'user' || account.isPengurus === true || text(account.adminDaerahArea)) {
      fail('Akun sudah terdaftar atau memiliki hak akses khusus.');
    }
  }
  async function enqueue(req, kind, church, bookId = '', verify = null) {
    const user = uid(req), userRef = db.doc(`users/${user}`), requestRef = db.doc(`profile_requests/${kind}_${user}`);
    return db.runTransaction(async tx => {
      const account = active(await tx.get(userRef));
      const churchDoc = await tx.get(db.doc(`churches/${church}`));
      const old = await tx.get(requestRef);
      if (!churchDoc.exists) fail('Gereja tidak ditemukan.');
      let book = null;
      if (kind === 'link') {
        const snapshot = await tx.get(db.doc(`churches/${church}/jemaat/${bookId}`));
        if (!snapshot.exists) fail('Data jemaat tidak ditemukan.');
        book = snapshot.data(); eligibility(account, church, bookId, book, user);
        const year = birthYear(book.tanggalLahir);
        if (phone(book.nomorTelepon) !== phone(verify.phone) || !/^\d{4}$/.test(verify.year)
          || year == null || year < 1000 || year > new Date(clock()).getUTCFullYear() || year !== Number(verify.year)) fail('Nomor atau tahun lahir tidak cocok.');
        if (text(account.jemaatId) === bookId && text(book.uid) === user) return { status: 'approved' };
      } else {
        unassigned(account);
        if (text(churchDoc.data().kodeUndangan) !== verify.code) fail('Kode undangan berubah.');
      }
      const previous = old.data();
      if (previous?.status === 'pending') {
        if (previous.churchId === church && previous.jemaatId === bookId) return { status: 'pending', id: requestRef.id };
        fail('Masih ada permohonan lain. Hubungi admin sebelum mengganti data.');
      }
      if (previous?.submittedAt?.toMillis() > clock() - 60000) throw new HttpsError('resource-exhausted', 'Tunggu sebentar sebelum mengirim ulang.');
      // No phone/year copied into the request. Admin inspects existing book.
      tx.set(requestRef, { uid: user, kind, churchId: church, jemaatId: bookId, status: 'pending',
        namaLengkap: text(account.namaLengkap), email: text(account.email), bookName: text(book?.namaLengkap),
        ...(book ? { bookRevision: revision(book) } : {}),
        submittedAt: Timestamp.fromMillis(clock()) });
      return { status: 'pending', id: requestRef.id };
    });
  }
  return {
    async search(req) {
      const user = uid(req), account = active(await db.doc(`users/${user}`).get()), church = text(account.churchId);
      if (!id(church)) fail('Gereja asal belum tersedia.');
      await limit(user);
      const possible = variants(req.data?.phone), matches = new Map();
      for (let i=0; i<possible.length; i+=10) {
        const snap = await db.collection(`churches/${church}/jemaat`).where('nomorTelepon','in',possible.slice(i,i+10)).limit(3).get();
        for (const doc of snap.docs) matches.set(doc.id, doc);
      }
      if (matches.size !== 1) fail('Nomor tidak ditemukan atau dipakai bersama. Hubungi admin.');
      const doc = [...matches.values()][0], book = doc.data();
      eligibility(account, church, doc.id, book, user);
      // Reveal only a masked display name; identity still needs admin approval.
      const parts = text(book.namaLengkap).split(/\s+/);
      return { churchId: church, jemaatId: doc.id, namaLengkap: `${parts[0] || 'Jemaat'}${parts.length > 1 ? ' '+parts.slice(1).map(p=>p[0]+'.').join(' ') : ''}` };
    },
    async requestLink(req) {
      const account = active(await db.doc(`users/${uid(req)}`).get()), church = text(account.churchId), book = req.data?.jemaatId;
      if (!id(church) || !id(book)) fail('Tautan tidak valid.');
      await limit(uid(req));
      return enqueue(req, 'link', church, book, { phone: req.data?.phone, year: text(req.data?.year) });
    },
    async requestChurch(req) {
      const user = uid(req);
      const code = text(req.data?.code);
      if (!code || code.length > 100) fail('Kode undangan tidak valid.');
      await limit(user);
      const matches = await db.collection('churches').where('kodeUndangan','==',code).limit(2).get();
      if (matches.size !== 1) fail('Kode tidak ditemukan atau ambigu. Hubungi admin.');
      return enqueue(req, 'membership', matches.docs[0].id, '', { code });
    },
    async review(req) {
      const reviewer = uid(req), requestId = req.data?.requestId, approve = req.data?.approve;
      if (!id(requestId) || typeof approve !== 'boolean') fail('Permintaan tidak valid.');
      const ref = db.doc(`profile_requests/${requestId}`);
      return db.runTransaction(async tx => {
        const actor = active(await tx.get(db.doc(`users/${reviewer}`))), pending = await tx.get(ref);
        if (!pending.exists) fail('Permohonan tidak ditemukan.');
        const p = pending.data();
        if (p.uid === reviewer || !(actor.role === 'superadmin' || (actor.role === 'admin' && text(actor.churchId) === p.churchId))) {
          throw new HttpsError('permission-denied', 'Hanya admin gereja terkait dapat meninjau akun lain.');
        }
        if (p.status !== 'pending') return { status: p.status };
        if (!approve) {
          tx.update(ref, { status: 'rejected', reviewedBy: reviewer, reviewedAt: FieldValue.serverTimestamp() });
          return { status: 'rejected' };
        }
        if (p.submittedAt.toMillis() < clock()-7*24*60*60*1000) fail('Permohonan kedaluwarsa. Tolak dan minta kirim ulang.');
        const accountRef = db.doc(`users/${p.uid}`), account = active(await tx.get(accountRef));
        const churchDoc = await tx.get(db.doc(`churches/${p.churchId}`));
        if (!churchDoc.exists) fail('Gereja tidak tersedia.');
        if (p.kind === 'membership') {
          unassigned(account);
          const c = churchDoc.data();
          tx.update(accountRef, { churchId: p.churchId, churchName: text(c.namaGereja || c.nama || c.churchName) || 'Gereja', daerah: text(c.daerah) });
        } else if (p.kind === 'link') {
          const bookRef = db.doc(`churches/${p.churchId}/jemaat/${p.jemaatId}`), snap = await tx.get(bookRef);
          if (!snap.exists) fail('Buku induk tidak tersedia.');
          const book = snap.data(); eligibility(account, p.churchId, p.jemaatId, book, p.uid);
          if (revision(book) !== p.bookRevision) fail('Biodata berubah setelah permohonan. Tolak dan minta pemohon kirim ulang.');
          tx.update(bookRef, { uid: p.uid });
          tx.update(accountRef, { jemaatId: p.jemaatId, kelompok: category(book.kelompok) });
        } else fail('Jenis permohonan tidak didukung.');
        tx.update(ref, { status: 'approved', reviewedBy: reviewer, reviewedAt: FieldValue.serverTimestamp() });
        return { status: 'approved' };
      });
    },
  };
}
module.exports = { createApprovalService, phone, birthYear };
