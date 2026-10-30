const { initializeApp } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { getFirestore } = require('firebase-admin/firestore');
const { onCall } = require('firebase-functions/v2/https');
const { promoteMunicipality } = require('./municipality');

initializeApp();
exports.setMunicipalityUser = onCall(
  { region: 'asia-northeast1', maxInstances: 2 },
  (request) => promoteMunicipality(request, getAuth(), getFirestore()),
);
