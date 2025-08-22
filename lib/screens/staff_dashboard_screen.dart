import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:Strata_lite/screens/scan_barcode.dart'; // Import halaman Ambil Barang
import 'package:Strata_lite/screens/settings_screen.dart'; // Import halaman Pengaturan
import 'dart:developer'; // Untuk log.log()

class StaffDashboardScreen extends StatefulWidget {
  const StaffDashboardScreen({super.key});

  @override
  State<StaffDashboardScreen> createState() => _StaffDashboardScreenState();
}

class _StaffDashboardScreenState extends State<StaffDashboardScreen> {
  int _selectedIndex = 0; // Indeks halaman yang dipilih

  // State untuk data pengguna di DrawerHeader (mirip AdminDashboard)
  String _drawerUserName = 'Memuat Nama...';
  String _drawerUserEmail = 'Memuat Email...';
  String _drawerUserDepartment = 'Memuat Departemen...';
  bool _isDrawerLoading = true;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Daftar halaman yang dapat diakses staff
  final List<Widget> _pages = [
    const ScanBarcodeScreen(), // Indeks 0: Halaman Ambil Barang
    const SettingsScreen(), // Indeks 1: Halaman Pengaturan
  ];

  @override
  void initState() {
    super.initState();
    _loadDrawerUserData(); // Muat data pengguna saat initState
  }

  // Fungsi untuk memuat data pengguna untuk DrawerHeader (disalin dari AdminDashboard)
  Future<void> _loadDrawerUserData() async {
    if (!mounted) return;
    setState(() {
      _isDrawerLoading = true;
    });

    User? currentUser = _auth.currentUser;

    if (currentUser == null) {
      if (!mounted) return;
      setState(() {
        _drawerUserEmail = 'Tidak Login';
        _drawerUserName = 'Pengguna Tamu';
        _drawerUserDepartment = '';
        _isDrawerLoading = false;
      });
      log('Error: No user logged in for staff dashboard.');
      return;
    }

    if (!mounted) return;
    setState(() {
      _drawerUserEmail = currentUser.email ?? 'Email Tidak Tersedia';
    });

    try {
      DocumentSnapshot userDoc =
          await _firestore.collection('users').doc(currentUser.uid).get();
      if (!mounted) return;

      if (userDoc.exists) {
        Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;
        setState(() {
          _drawerUserName =
              userData['name'] ?? currentUser.email ?? 'Nama Tidak Ditemukan';
          _drawerUserDepartment =
              userData['department'] ?? 'Departemen Tidak Ditemukan';
        });
      } else {
        setState(() {
          _drawerUserName = currentUser.email ?? 'Nama Tidak Ditemukan';
          _drawerUserDepartment = 'Data Profil Tidak Lengkap';
        });
        log('Warning: User document not found in Firestore for UID: ${currentUser.uid}');
      }
    } catch (e) {
      log('Error loading drawer user data from Firestore: $e');
      if (!mounted) return;
      setState(() {
        _drawerUserName = currentUser.email ?? 'Error Memuat Nama';
        _drawerUserDepartment = 'Error Memuat Departemen';
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _isDrawerLoading = false;
      });
    }
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  // Fungsi untuk menampilkan dialog konfirmasi logout (disalin dari AdminDashboard)
  Future<void> _confirmLogout() async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Konfirmasi Logout'),
        content: const Text('Apakah Anda yakin ingin keluar dari aplikasi?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Logout', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseAuth.instance.signOut();
      if (!context.mounted) return;
      // Navigate to login screen and remove all previous routes
      Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
            'Dashboard Staff Strata Lite'), // Judul AppBar untuk staff
        // Bagian 'actions' dihilangkan untuk menghapus ikon logout
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(
                color: Colors.blue,
              ),
              child: _isDrawerLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.white))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const CircleAvatar(
                          radius: 30,
                          backgroundColor: Colors.white,
                          child:
                              Icon(Icons.person, size: 40, color: Colors.blue),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _drawerUserName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          _drawerUserEmail,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                        if (_drawerUserDepartment.isNotEmpty)
                          Text(
                            _drawerUserDepartment,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
            ),
            ListTile(
              leading: const Icon(Icons.shopping_cart),
              title: const Text('Ambil Barang'),
              onTap: () {
                _onItemTapped(0); // Indeks 0 untuk ScanBarcodeScreen
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('Pengaturan'),
              onTap: () {
                _onItemTapped(1); // Indeks 1 untuk SettingsScreen
                Navigator.pop(context);
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Logout'),
              onTap: _confirmLogout,
            ),
          ],
        ),
      ),
      body: _pages[_selectedIndex],
    );
  }
}
