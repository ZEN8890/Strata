// Path: lib/screens/admin_dashboard_screen.dart
import 'package:flutter/material.dart';
import 'package:Strata_lite/screens/add_item_screen.dart';
import 'package:Strata_lite/screens/item_list_screen.dart';
import 'package:Strata_lite/screens/time_log_screen.dart';
import 'package:Strata_lite/screens/scan_barcode.dart';
import 'package:Strata_lite/screens/settings_screen.dart';
import 'package:Strata_lite/screens/users_screen.dart';
import 'package:Strata_lite/screens/ai_page.dart';
import 'package:Strata_lite/screens/credit_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:developer';
import 'package:Strata_lite/screens/login_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  int _selectedIndex = 0;

  String _drawerUserName = 'Memuat Nama...';
  String _drawerUserEmail = 'Memuat Email...';
  String _drawerUserDepartment = 'Memuat Departemen...';
  bool _isDrawerLoading = true;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final List<Widget> _pages = [
    const ItemListScreen(),
    const AddItemScreen(),
    const Center(child: Text('Halaman Impor/Ekspor Data (Segera Hadir!)')),
    const TimeLogScreen(),
    const SettingsScreen(),
    const ScanBarcodeScreen(),
    const UsersScreen(),
    const AiPage(),
    const CreditPage(),
  ];

  final List<String> _pageTitles = [
    'Manajemen Barang',
    'Tambah Barang Baru',
    'Impor/Ekspor Data',
    'Log Pengambilan Barang',
    'Pengaturan',
    'Ambil/tambah Barang',
    'Manajemen Pengguna',
    'AI Asisten Inventaris',
    'Tentang Aplikasi',
  ];

  String get _currentTitle => _pageTitles[_selectedIndex];

  @override
  void initState() {
    super.initState();
    _loadDrawerUserData();
  }

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
      log('Error: No user logged in for admin dashboard drawer.');
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
    Navigator.pop(context);
  }

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

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (Route<dynamic> route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isAiOrCreditPage = _selectedIndex == 7 || _selectedIndex == 8;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _currentTitle,
          style: TextStyle(
            color: isAiOrCreditPage ? Colors.white : Colors.black,
          ),
        ),
        backgroundColor: isAiOrCreditPage ? Colors.indigo : Colors.white,
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
              leading: const Icon(Icons.inventory),
              title: const Text('Manajemen Barang'),
              onTap: () => _onItemTapped(0),
              selected: _selectedIndex == 0,
            ),
            ListTile(
              leading: const Icon(Icons.add_box),
              title: const Text('Tambah Barang Baru'),
              onTap: () => _onItemTapped(1),
              selected: _selectedIndex == 1,
            ),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Log Pengambilan Barang'),
              onTap: () => _onItemTapped(3),
              selected: _selectedIndex == 3,
            ),
            ListTile(
              leading: const Icon(Icons.shopping_cart),
              title: const Text('Ambil Barang'),
              onTap: () => _onItemTapped(5),
              selected: _selectedIndex == 5,
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.group),
              title: const Text('Manajemen Pengguna'),
              onTap: () => _onItemTapped(6),
              selected: _selectedIndex == 6,
            ),
            ListTile(
              leading: const Icon(Icons.auto_awesome),
              title: const Text('AI Asisten Inventaris'),
              onTap: () => _onItemTapped(7),
              selected: _selectedIndex == 7,
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Tentang Aplikasi'),
              onTap: () => _onItemTapped(8),
              selected: _selectedIndex == 8,
            ),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('Pengaturan'),
              onTap: () => _onItemTapped(4),
              selected: _selectedIndex == 4,
            ),
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
