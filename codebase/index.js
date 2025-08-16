// Path: codebase/index.js
const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();

// ====================================================================================
// 1. Fungsi HTTPS yang Dapat Dipanggil: createUserAndProfile
//    Membuat pengguna di Firebase Auth dan profil di Firestore.
//    Dipanggil dari aplikasi Flutter Anda.
// ====================================================================================
exports.createUserAndProfile = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "Authentication required. Only authenticated users can call this function.",
    );
  }

  // DIUBAH: Mengambil data 'username' dan 'password'
  const {name, email, password, phoneNumber, department, role} = data;

  // Validasi input
  if (!email || !password || !name || !department || !role) { // DIUBAH
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Required data (email, password, name, department, role) is missing.", // DIUBAH
    );
  }
  if (password.length < 6) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Password must be at least 6 characters long.",
    );
  }

  try {
    // Buat Pengguna di Firebase Authentication
    const userRecord = await admin.auth().createUser({
      email: email, // MENGGUNAKAN EMAIL YANG SUDAH DIBUAT DARI CLIENT
      password: password,
      displayName: name,
      phoneNumber: phoneNumber || null,
    });

    // Simpan Data Profil Pengguna di Cloud Firestore
    await admin.firestore().collection("users").doc(userRecord.uid).set({
      name: name,
      email: email, // Simpan email lengkap di Firestore
      phoneNumber: phoneNumber || "",
      department: department,
      role: role,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      uid: userRecord.uid,
    });

    await admin.auth().setCustomUserClaims(userRecord.uid, {role: role});

    console.log(`Pengguna baru dibuat: ${userRecord.uid} (${email})`);

    return {success: true, message: "User created successfully."};
  } catch (error) {
    console.error("Error creating user in Cloud Function:", error);

    let errorMessage = "An error occurred while creating the user.";
    if (error.code === "auth/email-already-in-use") {
      errorMessage = "This username is already registered."; // DIUBAH
    } else if (error.code === "auth/weak-password") {
      errorMessage = "The password is too weak.";
    } else if (error.message) {
      errorMessage = error.message;
    }

    throw new functions.https.HttpsError("internal", errorMessage);
  }
});

// ====================================================================================
// 2. Fungsi Trigger Firestore: deleteUserAuthOnProfileDelete
//    Otomatis menghapus akun Firebase Auth saat dokumen profil pengguna di Firestore dihapus.
// ====================================================================================
exports.deleteUserAuthOnProfileDelete = functions.firestore
  .document("users/{userId}")
  .onDelete(async (snap, context) => {
    const userId = context.params.userId;
    try {
      await admin.auth().deleteUser(userId);
      console.log(`Firebase Auth account for UID ${userId} deleted successfully.`);
      return null;
    } catch (error) {
      console.error(`Failed to delete Firebase Auth account for UID ${userId}:`, error);
      if (error.code === "auth/user-not-found") {
        console.warn(`Auth user with UID ${userId} not found, likely already deleted.`);
        return null;
      }
      throw new functions.https.HttpsError("internal", `Failed to delete Auth account: ${error.message}`);
    }
  });