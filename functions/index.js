const { initializeApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { onCall } = require('firebase-functions/v2/https');
const { createApprovalService } = require('./profile_approval');
initializeApp();
const service = createApprovalService(getFirestore());
// Draft backend, not deployed. No notification or automatic migration triggers.
const options = { region: 'us-central1', maxInstances: 3, timeoutSeconds: 30 };
exports.searchJemaatCandidate = onCall(options, req => service.search(req));
exports.requestJemaatLink = onCall(options, req => service.requestLink(req));
exports.requestChurchMembership = onCall(options, req => service.requestChurch(req));
exports.reviewProfileRequest = onCall(options, req => service.review(req));
