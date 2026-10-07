import { readFile } from 'node:fs/promises';
import { describe, test, before, after, beforeEach } from 'node:test';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import { doc, setDoc, updateDoc } from 'firebase/firestore';
import { ref, uploadBytes, getMetadata, deleteObject, listAll, updateMetadata } from 'firebase/storage';

const local = value => /^(127\.0\.0\.1|localhost):\d+$/.test(value || '');
if (!local(process.env.FIRESTORE_EMULATOR_HOST) || !local(process.env.FIREBASE_STORAGE_EMULATOR_HOST)) {
  throw Error('Both LOCAL emulators are required; no production access is permitted');
}
const split = value => { const [host, port] = value.split(':'); return { host, port: Number(port) }; };
const bytes = new Uint8Array([1, 2, 3]); // Rules validate metadata, not actual file decoding.
const users = {
  u: { role: 'user', churchId: 'a', isBlocked: false },
  v: { role: 'user', churchId: 'b', isBlocked: false },
  admin: { role: 'admin', churchId: 'a', isBlocked: false },
  adminUnderscore: { role: 'admin', churchId: 'a_b', isBlocked: false },
  adminRegex: { role: 'admin', churchId: 'a.b', isBlocked: false },
  super: { role: 'superadmin', churchId: 'a', isBlocked: false },
  blocked: { role: 'superadmin', churchId: 'a', isBlocked: true },
  regional: { role: 'user', churchId: 'a', isBlocked: false, adminDaerahArea: ' Utara ' },
  gembala: { role: 'gembala', churchId: 'a', isBlocked: false, daerah: 'Utara' },
};
async function setup(storageRules) {
  return initializeTestEnvironment({ projectId: 'demo-gereja-rules',
    firestore: { ...split(process.env.FIRESTORE_EMULATOR_HOST), rules: await readFile('firestore.compat.rules', 'utf8') },
    storage: { ...split(process.env.FIREBASE_STORAGE_EMULATOR_HOST), rules: await readFile(storageRules, 'utf8') } });
}
async function seed(env) {
  await env.clearFirestore();
  await env.clearStorage();
  await env.withSecurityRulesDisabled(async ctx => {
    for (const [uid, data] of Object.entries(users)) await setDoc(doc(ctx.firestore(), 'users', uid), data);
    for (const path of ['churches/a/foto_jemaat/legacy.jpg', 'aset_gereja_photos/legacy.jpg', 'users/v/profil_v.jpg']) {
      await uploadBytes(ref(ctx.storage(), path), bytes, { contentType: 'image/jpeg' });
    }
  });
}
describe('Supplied Storage rules: reproduce recursive wildcard bypass', () => {
  let env;
  before(async () => { env = await setup('storage.supplied.rules'); });
  beforeEach(async () => seed(env));
  after(async () => env?.cleanup());
  test('normal user can upload jemaat and delete protected asset through wildcard', async () => {
    const s = env.authenticatedContext('u').storage();
    await assertSucceeds(uploadBytes(ref(s, 'churches/b/foto_jemaat/forged.jpg'), bytes, { contentType: 'image/jpeg' }));
    await assertSucceeds(deleteObject(ref(s, 'aset_gereja_photos/legacy.jpg')));
    await assertSucceeds(uploadBytes(ref(s, 'users/v/profil_v.jpg'), bytes, { contentType: 'text/html' }));
  });
});
describe('Storage candidate: actual app paths, ownership and validation', () => {
  let env;
  const contexts = new Map();
  const ctx = uid => {
    if (!contexts.has(uid)) contexts.set(uid, uid ? env.authenticatedContext(uid) : env.unauthenticatedContext());
    return contexts.get(uid);
  };
  const object = (uid, path) => ref(ctx(uid).storage(), path);
  const upload = (uid, path, type = 'image/jpeg', data = bytes) => uploadBytes(object(uid, path), data, { contentType: type });
  before(async () => { env = await setup('storage.compat.rules'); });
  beforeEach(async () => seed(env));
  after(async () => env?.cleanup());
  test('anonymous, missing-account and blocked access denied', async () => {
    for (const uid of [null, 'absent', 'blocked']) {
      await assertFails(getMetadata(object(uid, 'users/v/profil_v.jpg')));
      await assertFails(upload(uid, 'gereja/a/header_123.jpg'));
    }
  });
  test('own profile upload/delete allowed, another user and admin cannot alter it', async () => {
    await assertSucceeds(upload('u', 'users/u/profil_u_new.jpg'));
    await assertFails(upload('v', 'users/u/profil_u_new.jpg'));
    await assertFails(upload('admin', 'users/u/profil_u_new.jpg'));
    await assertFails(deleteObject(object('u', 'users/v/profil_v.jpg')));
    await assertSucceeds(deleteObject(object('u', 'users/u/profil_u_new.jpg')));
  });
  test('existing profile and jemaat photos remain readable to signed-in active accounts', async () => {
    await assertSucceeds(getMetadata(object('u', 'users/v/profil_v.jpg')));
    await assertSucceeds(getMetadata(object('u', 'churches/a/foto_jemaat/legacy.jpg')));
  });
  test('jemaat photos writable only by church admin/superadmin', async () => {
    await assertFails(upload('u', 'churches/a/foto_jemaat/new.jpg'));
    await assertSucceeds(upload('admin', 'churches/a/foto_jemaat/new.jpg'));
    await assertFails(upload('admin', 'churches/b/foto_jemaat/new.jpg'));
    await assertSucceeds(upload('super', 'churches/b/foto_jemaat/new.jpg'));
    await assertSucceeds(deleteObject(object('admin', 'churches/a/foto_jemaat/legacy.jpg')));
  });
  test('church header/gembala and pengurus actual paths supported', async () => {
    for (const path of ['gereja/a/header_123.jpg', 'gereja/a/gembala_123.jpg', 'gereja/a/pengurus/operation-id.jpg']) {
      await assertSucceeds(upload('admin', path));
      await assertFails(upload('u', path));
      await assertFails(upload('admin', path.replace('/a/', '/b/')));
    }
    await assertFails(upload('admin', 'gereja/a/arbitrary.jpg'));
  });
  test('current flat asset filename enforces church scope without regex injection/prefix confusion', async () => {
    await assertSucceeds(upload('admin', 'aset_gereja/a_123.jpg'));
    await assertFails(upload('admin', 'aset_gereja/b_123.jpg'));
    await assertFails(upload('admin', 'aset_gereja/a_b_123.jpg'));
    await assertSucceeds(upload('adminUnderscore', 'aset_gereja/a_b_123.jpg'));
    await assertSucceeds(upload('adminRegex', 'aset_gereja/a.b_123.jpg'));
    await assertFails(upload('adminRegex', 'aset_gereja/axb_123.jpg'));
    await assertFails(upload('u', 'aset_gereja/a_456.jpg'));
    await assertSucceeds(deleteObject(object('admin', 'aset_gereja/a_123.jpg')));
  });
  test('legacy asset folder readable; unknown church mapping only superadmin may change/delete', async () => {
    await assertSucceeds(getMetadata(object('u', 'aset_gereja_photos/legacy.jpg')));
    await assertFails(deleteObject(object('admin', 'aset_gereja_photos/legacy.jpg')));
    await assertSucceeds(deleteObject(object('super', 'aset_gereja_photos/legacy.jpg')));
  });
  test('regional attachments limited to appointed regional admin and superadmin', async () => {
    await assertSucceeds(upload('regional', 'info_daerah/Utara/doc_123.pdf', 'application/pdf'));
    await assertSucceeds(upload('regional', 'info_daerah/Utara/doc_124.jpg'));
    await assertFails(upload('regional', 'info_daerah/Selatan/doc_123.pdf', 'application/pdf'));
    await assertFails(upload('gembala', 'info_daerah/Utara/doc_123.pdf', 'application/pdf'));
    await assertFails(upload('admin', 'info_daerah/Utara/doc_123.pdf', 'application/pdf'));
    await assertSucceeds(upload('super', 'info_daerah/Selatan/doc_123.pdf', 'application/pdf'));
    await assertSucceeds(deleteObject(object('regional', 'info_daerah/Utara/doc_123.pdf')));
  });
  test('office attachment MIME types supported', async () => {
    for (const [ext, type] of Object.entries({
      doc: 'application/msword', docx: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      xls: 'application/vnd.ms-excel', xlsx: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      ppt: 'application/vnd.ms-powerpoint', pptx: 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    })) await assertSucceeds(upload('regional', `info_daerah/Utara/doc_123.${ext}`, type));
  });
  test('HTML/SVG/octet-stream, empty images and metadata type poisoning rejected', async () => {
    for (const type of ['text/html', 'image/svg+xml', 'application/octet-stream']) {
      await assertFails(upload('u', 'users/u/profil_u.jpg', type));
    }
    await assertFails(upload('u', 'users/u/empty.jpg', 'image/jpeg', new Uint8Array()));
    await assertSucceeds(upload('u', 'users/u/profil_u.jpg'));
    await assertFails(updateMetadata(object('u', 'users/u/profil_u.jpg'), { contentType: 'text/html' }));
    await assertFails(upload('regional', 'info_daerah/Utara/doc_123.exe', 'application/pdf'));
  });
  test('image and document size boundaries enforced; delete independent of upload metadata', async () => {
    await assertSucceeds(upload('u', 'users/u/limit.jpg', 'image/jpeg', new Uint8Array(10 * 1024 * 1024)));
    await assertFails(upload('u', 'users/u/oversize.jpg', 'image/jpeg', new Uint8Array(10 * 1024 * 1024 + 1)));
    await assertFails(upload('regional', 'info_daerah/Utara/doc_123.pdf', 'application/pdf', new Uint8Array(20 * 1024 * 1024 + 1)));
    await assertSucceeds(deleteObject(object('u', 'users/u/limit.jpg')));
  });
  test('unknown folders, recursive nested uploads and object listing denied', async () => {
    for (const path of ['unknown/file.jpg','users/u/nested/file.jpg','chats/a/file.jpg','churches/a/arbitrary/file.jpg']) {
      await assertFails(upload('u', path));
    }
    await assertFails(listAll(ref(ctx('u').storage(), 'users')));
  });
  test('fresh Firestore block and role revocation affect Storage immediately', async () => {
    await assertSucceeds(upload('admin', 'gereja/a/header_123.jpg'));
    await env.withSecurityRulesDisabled(ctx => updateDoc(doc(ctx.firestore(), 'users/admin'), { role: 'user' }));
    await assertFails(upload('admin', 'gereja/a/header_124.jpg'));
    await env.withSecurityRulesDisabled(ctx => updateDoc(doc(ctx.firestore(), 'users/u'), { isBlocked: true }));
    await assertFails(upload('u', 'users/u/new.jpg'));
  });
});
