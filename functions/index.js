const { initializeApp } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");
const { getFirestore } = require("firebase-admin/firestore");
const { onCall } = require("firebase-functions/v2/https");
const { promoteMunicipality } = require("./municipality");

initializeApp();
exports.setMunicipalityUser = onCall(
  { region: "asia-northeast1", maxInstances: 2 },
  (request) => promoteMunicipality(request, getAuth(), getFirestore()),
);

const { getStorage } = require("firebase-admin/storage");
const { importTransport } = require("./transport_import");
exports.importTransport = onCall(
  {
    region: "asia-northeast1",
    maxInstances: 1,
    concurrency: 1,
    timeoutSeconds: 540,
    memory: "1GiB",
  },
  (request) => importTransport(request, getFirestore(), getStorage().bucket()),
);
const { sampleInventory } = require("./sample_inventory");
exports.transportSampleInventory = onCall(
  { region: "asia-northeast1", maxInstances: 1 },
  (request) => sampleInventory(request, getFirestore()),
);
const { saveManualTransport } = require("./manual_transport");
exports.saveManualTransport = onCall(
  { region: "asia-northeast1", maxInstances: 2 },
  (request) => saveManualTransport(request, getFirestore(), getStorage().bucket()),
);

const { searchTransportJourneys } = require("./transport_journey_api");
exports.searchTransportJourneys = onCall(
  {
    region: "asia-northeast1",
    maxInstances: 2,
    concurrency: 1,
    timeoutSeconds: 60,
    memory: "1GiB",
  },
  (request) => searchTransportJourneys(request, getFirestore(), getStorage().bucket()),
);

exports.geocodeAddress = onCall(
  { region: 'asia-northeast1', maxInstances: 2 },
  require('./geocode').geocodeAddress,
);
