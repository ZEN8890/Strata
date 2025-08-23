// Path: lib/screens/settings_screen.dart
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

  // Controllers untuk input yang bisa diedit
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController =
      TextEditingController(); // Email biasanya tidak diedit langsung

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

    _emailController.text =
        _currentUser!.email ?? 'N/A'; // Email dari FirebaseAuth

    try {
      DocumentSnapshot userDoc =
          await _firestore.collection('users').doc(_currentUser!.uid).get();

      if (userDoc.exists) {
        Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;
        _nameController.text = userData['name'] ?? '';
        log('User data loaded: Name=${_nameController.text}, Email=${_emailController.text}');
      } else {
        // Jika dokumen user tidak ada, set nilai default
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
      await _firestore.collection('users').doc(_currentUser!.uid).set(
          {
            'name': _nameController.text.trim(),
            'email': _emailController.text.trim(),
          },
          SetOptions(
              merge:
                  true)); // Gunakan merge: true agar tidak menimpa field lain

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

  @override
  Widget build(BuildContext context) {
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
                  // Menggunakan ListView agar bisa discroll
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
                              decoration: const InputDecoration(
                                labelText: 'Nama Lengkap',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.person),
                              ),
                            ),
                            const SizedBox(height: 15),
                            TextField(
                              controller: _emailController,
                              readOnly:
                                  true, // Email biasanya tidak bisa diedit langsung
                              decoration: const InputDecoration(
                                labelText: 'Email',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.email),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Center(
                      child: ElevatedButton(
                        onPressed: _saveUserData, // Panggil fungsi simpan
                        child: _isLoading
                            ? const CircularProgressIndicator(
                                color: Colors.white)
                            : const Text('Simpan Perubahan'),
                      ),
                    ),
                  ],
                ),
    );
  }
}
