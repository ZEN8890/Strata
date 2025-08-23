import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart'; // Untuk mendapatkan user yang sedang login
import 'package:cloud_firestore/cloud_firestore.dart'; // Untuk mengambil data user dari Firestore
import 'dart:developer'; // Untuk log.log()
import 'package:another_flushbar/flushbar.dart'; // Untuk notifikasi

// Import the LoginScreen to navigate to it
import 'package:Strata_lite/screens/login_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  User? _currentUser;
  String _userRole = 'staff';

  // Controllers untuk input yang bisa diedit
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _currentPasswordController =
      TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();

  // State variables for password visibility
  bool _isCurrentPasswordVisible = false;
  bool _isNewPasswordVisible = false;

  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    super.dispose();
  }

  // Fungsi untuk menampilkan notifikasi yang diperbagus
  void _showNotification(String title, String message, {bool isError = false}) {
    if (!context.mounted) return;

    Flushbar(
      titleText: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 16.0,
          color: isError ? Colors.red[900] : Colors.green[900],
        ),
      ),
      messageText: Text(
        message,
        style: TextStyle(
          fontSize: 14.0,
          color: isError ? Colors.red[800] : Colors.green[800],
        ),
      ),
      flushbarPosition: FlushbarPosition.TOP,
      flushbarStyle: FlushbarStyle.FLOATING,
      backgroundColor: isError ? Colors.red[100]! : Colors.green[100]!,
      margin: const EdgeInsets.all(8),
      borderRadius: BorderRadius.circular(8),
      icon: Icon(
        isError ? Icons.error_outline : Icons.check_circle_outline,
        color: isError ? Colors.red[800] : Colors.green[800],
      ),
      duration: const Duration(seconds: 3),
    ).show(context);
  }

  Future<void> _loadUserData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    _currentUser = _auth.currentUser;

    if (_currentUser == null) {
      setState(() {
        _errorMessage = 'Tidak ada pengguna yang login.';
        _isLoading = false;
      });
      log('Error: No user logged in for settings screen.');
      return;
    }

    _emailController.text = _currentUser!.email ?? 'N/A';

    try {
      DocumentSnapshot userDoc =
          await _firestore.collection('users').doc(_currentUser!.uid).get();

      if (userDoc.exists) {
        Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;
        _nameController.text = userData['name'] ?? '';
        _userRole = userData['role'] ?? 'staff';
        log('User data loaded: Name=${_nameController.text}, Email=${_emailController.text}, Role=$_userRole');
      } else {
        _nameController.text = 'Nama Tidak Ditemukan';
        log('Warning: User document not found in Firestore for UID: ${_currentUser!.uid}');
      }
    } catch (e) {
      _errorMessage = 'Gagal memuat data profil: $e';
      log('Error loading user data from Firestore: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _saveUserData() async {
    if (_currentUser == null) {
      _showNotification('Error', 'Tidak ada pengguna yang login.',
          isError: true);
      return;
    }

    if (_nameController.text.trim().isEmpty) {
      _showNotification('Input Tidak Lengkap', 'Nama tidak boleh kosong.',
          isError: true);
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await _firestore.collection('users').doc(_currentUser!.uid).set({
        'name': _nameController.text.trim(),
        'email': _emailController.text.trim(),
      }, SetOptions(merge: true));

      _showNotification('Berhasil!', 'Profil berhasil diperbarui.',
          isError: false);
      log('User data updated successfully for UID: ${_currentUser!.uid}');
    } catch (e) {
      _showNotification('Gagal Memperbarui Profil', 'Error: $e', isError: true);
      log('Error updating user data: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _resetPassword() async {
    if (_currentUser == null) {
      _showNotification('Error', 'Tidak ada pengguna yang login.',
          isError: true);
      return;
    }

    final currentPassword = _currentPasswordController.text.trim();
    final newPassword = _newPasswordController.text.trim();

    if (currentPassword.isEmpty || newPassword.isEmpty) {
      _showNotification(
          'Input Tidak Lengkap', 'Kata sandi lama dan baru tidak boleh kosong.',
          isError: true);
      return;
    }

    if (newPassword.length < 6) {
      _showNotification('Kata Sandi Baru Tidak Valid',
          'Kata sandi baru harus memiliki minimal 6 karakter.',
          isError: true);
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Re-authenticate user with current password
      AuthCredential credential = EmailAuthProvider.credential(
        email: _currentUser!.email!,
        password: currentPassword,
      );
      await _currentUser!.reauthenticateWithCredential(credential);

      // Update password
      await _currentUser!.updatePassword(newPassword);

      _showNotification('Berhasil!', 'Kata sandi berhasil diubah.',
          isError: false);
      _currentPasswordController.clear();
      _newPasswordController.clear();
      log('Password for user ${_currentUser!.email} reset successfully.');
    } on FirebaseAuthException catch (e) {
      String message;
      if (e.code == 'wrong-password') {
        message = 'Kata sandi lama salah.';
      } else if (e.code == 'requires-recent-login') {
        message =
            'Login baru diperlukan untuk memperbarui kata sandi. Silakan logout dan login kembali.';
      } else {
        message = 'Gagal mengubah kata sandi: $e';
      }
      _showNotification('Gagal!', message, isError: true);
      log('Error resetting password: $e');
    } catch (e) {
      _showNotification('Gagal!', 'Terjadi kesalahan tidak terduga: $e',
          isError: true);
      log('Error resetting password: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isNameEditable = (_userRole == 'dev' || _userRole == 'admin');

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.red, fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                )
              : ListView(
                  children: [
                    Text(
                      'Pengaturan Profil',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 20),
                    Card(
                      margin: EdgeInsets.zero,
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextField(
                              controller: _nameController,
                              readOnly: !isNameEditable,
                              decoration: InputDecoration(
                                labelText: 'Nama Lengkap',
                                border: const OutlineInputBorder(),
                                prefixIcon: const Icon(Icons.person),
                                suffixIcon: !isNameEditable
                                    ? const Icon(Icons.lock)
                                    : null,
                              ),
                            ),
                            const SizedBox(height: 15),
                            TextField(
                              controller: _emailController,
                              readOnly: true,
                              decoration: const InputDecoration(
                                labelText: 'Email',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.email),
                              ),
                            ),
                            const SizedBox(height: 20),
                            Center(
                              child: ElevatedButton(
                                onPressed: _saveUserData,
                                child: _isLoading
                                    ? const CircularProgressIndicator(
                                        color: Colors.white)
                                    : const Text('Simpan Perubahan'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 30),
                    Text(
                      'Reset Kata Sandi',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 20),
                    Card(
                      margin: EdgeInsets.zero,
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            TextField(
                              controller: _currentPasswordController,
                              obscureText: !_isCurrentPasswordVisible,
                              decoration: InputDecoration(
                                labelText: 'Kata Sandi Lama',
                                border: const OutlineInputBorder(),
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _isCurrentPasswordVisible
                                        ? Icons.visibility
                                        : Icons.visibility_off,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _isCurrentPasswordVisible =
                                          !_isCurrentPasswordVisible;
                                    });
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(height: 15),
                            TextField(
                              controller: _newPasswordController,
                              obscureText: !_isNewPasswordVisible,
                              decoration: InputDecoration(
                                labelText: 'Kata Sandi Baru',
                                border: const OutlineInputBorder(),
                                prefixIcon: const Icon(Icons.lock),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _isNewPasswordVisible
                                        ? Icons.visibility
                                        : Icons.visibility_off,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _isNewPasswordVisible =
                                          !_isNewPasswordVisible;
                                    });
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            Center(
                              child: ElevatedButton(
                                onPressed: _resetPassword,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blueAccent,
                                  foregroundColor: Colors.white,
                                ),
                                child: _isLoading
                                    ? const CircularProgressIndicator(
                                        color: Colors.white)
                                    : const Text('Reset Kata Sandi'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
