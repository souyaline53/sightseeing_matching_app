const { HttpsError } = require('firebase-functions/v2/https');
const { FieldValue } = require('firebase-admin/firestore');

async function promoteMunicipality(request, auth, firestore) {
  if (!request.auth) throw new HttpsError('unauthenticated', 'ログインしてください。');
  const token = request.auth.token;
  if (token.email?.toLowerCase() !== 'nichi-ka@nichi-ka.com' || token.email_verified !== true) {
    throw new HttpsError('permission-denied', '管理者のみ変更できます。');
  }
  const email = request.data?.email;
  if (typeof email !== 'string' || email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim())) {
    throw new HttpsError('invalid-argument', 'メールアドレスを確認してください。');
  }
  let user;
  try { user = await auth.getUserByEmail(email.trim()); }
  catch (error) {
    if (error.code === 'auth/user-not-found') throw new HttpsError('not-found', '登録済みユーザーが見つかりません。', { reason: 'user-not-found' });
    throw error;
  }
  if (user.disabled) throw new HttpsError('failed-precondition', 'このアカウントは無効です。');
  const reference = firestore.collection('users').doc(user.uid);
  return firestore.runTransaction(async (transaction) => {
    const profile = await transaction.get(reference);
    if (!profile.exists || !profile.data().nickname) {
      throw new HttpsError('failed-precondition', 'プロフィール登録を完了してください。');
    }
    const displayName = profile.data().nickname;
    transaction.update(reference, { userType: 'municipality', updatedAt: FieldValue.serverTimestamp() });
    transaction.set(firestore.collection('public_profiles').doc(user.uid), {
      uid: user.uid, displayName, userType: 'municipality', updatedAt: FieldValue.serverTimestamp(),
    });
    return { uid: user.uid, displayName, userType: 'municipality' };
  });
}

module.exports = { promoteMunicipality };
