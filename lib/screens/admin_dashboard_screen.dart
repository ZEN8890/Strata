import 'package:flutter/material.dart';
import 'package:Strata_lite/screens/add_item_screen.dart';
import 'package:Strata_lite/screens/item_list_screen.dart';
import 'package:Strata_lite/screens/time_log_screen.dart';
import 'package:Strata_lite/screens/take_item_screen.dart';
import 'package:Strata_lite/screens/settings_screen.dart';
import 'package:Strata_lite/screens/users_screen.dart'; // <--- Import UsersScreen
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:developer';

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
    const TakeItemScreen(),
    const UsersScreen(), // <--- Tambahkan UsersScreen di sini (indeks 6)
  ];

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
      Navigator.pushReplacementNamed(context, '/');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard Admin Strata Lite'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: _confirmLogout,
          ),
        ],
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
              onTap: () {
                _onItemTapped(0);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.add_box),
              title: const Text('Tambah Barang Baru'),
              onTap: () {
                _onItemTapped(1);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Log Pengambilan Barang'),
              onTap: () {
                _onItemTapped(3);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.shopping_cart),
              title: const Text('Ambil Barang'),
              onTap: () {
                _onItemTapped(5);
                Navigator.pop(context);
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.group), // <--- Icon untuk halaman Users
              title: const Text(
                  'Manajemen Pengguna'), // <--- Nama menu untuk Users
              onTap: () {
                _onItemTapped(6); // <--- Indeks 6 untuk UsersScreen
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('Pengaturan'),
              onTap: () {
                _onItemTapped(4);
                Navigator.pop(context);
              },
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
