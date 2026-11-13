'use strict';
// Counts successful SDK reads, not a billing export. Index-entry reads, SDK retries,
// security-rule reads and network bytes are not observable through this wrapper.
function measureFirestore(db) {
  const stats = { firestoreQueries: 0, firestoreDocumentGets: 0, firestoreReturnedDocuments: 0, firestoreEmptyQueries: 0 };
  function wrap(ref, isQuery) {
    return new Proxy(ref, { get(target, property) {
      if (property === 'get') return async (...args) => {
        const snap = await target.get(...args);
        if (isQuery) {
          stats.firestoreQueries++; stats.firestoreReturnedDocuments += snap.size;
          if (!snap.size) stats.firestoreEmptyQueries++;
        } else { stats.firestoreDocumentGets++; if (snap.exists !== false) stats.firestoreReturnedDocuments++; }
        return snap;
      };
      const value = target[property];
      if (typeof value !== 'function') return value;
      return (...args) => {
        const result = value.apply(target, args);
        return ['orderBy', 'limit', 'startAfter', 'where', 'select'].includes(property) ? wrap(result, true) : result;
      };
    } });
  }
  return { stats, db: new Proxy(db, { get(target, property) {
    if (property === 'collection') return (...args) => wrap(target.collection(...args), true);
    if (property === 'doc') return (...args) => wrap(target.doc(...args), false);
    const value = target[property]; return typeof value === 'function' ? value.bind(target) : value;
  } }) };
}
module.exports = { measureFirestore };
