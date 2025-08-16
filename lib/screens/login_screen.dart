// Path: lib/screens/login_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart'; // Import Firebase Auth
import 'package:shared_preferences/shared_preferences.dart'; // Import shared_preferences
import 'package:cloud_firestore/cloud_firestore.dart'; // Import Cloud Firestore to read user roles
import 'package:Strata_lite/screens/admin_dashboard_screen.dart'; // Import AdminDashboardScreen
import 'package:Strata_lite/screens/supervisor_dashboard_screen.dart'; // Import SupervisorDashboardScreen
import 'package:Strata_lite/screens/staff_dashboard_screen.dart'; // Assuming you have a staff dashboard

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore =
      FirebaseFirestore.instance; // Add Firestore instance

  bool _rememberMe = false; // State untuk checkbox "Remember Me"
  bool _obscurePassword = true; // State untuk toggle tampil/sembunyi password

  @override
  void initState() {
    super.initState();
    _loadRememberedUsername(); // Muat username yang disimpan saat screen diinisialisasi
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // Fungsi untuk memuat username yang disimpan
  void _loadRememberedUsername() async {
    final prefs = await SharedPreferences.getInstance();
    final rememberedUsername = prefs.getString('remembered_username');
    if (rememberedUsername != null && rememberedUsername.isNotEmpty) {
      setState(() {
        _emailController.text = rememberedUsername;
        _rememberMe = true; // Set checkbox ke true jika username ditemukan
      });
    }
  }

  // Fungsi untuk menyimpan username jika "Remember Me" dicentang
  void _saveRememberedUsername(String username) async {
    final prefs = await SharedPreferences.getInstance();
    if (_rememberMe) {
      await prefs.setString('remembered_username', username);
    } else {
      await prefs.remove('remembered_username'); // Hapus jika tidak dicentang
    }
  }

  void _performLogin() async {
    String username = _emailController.text.trim();
    String password = _passwordController.text.trim();

    if (username.isEmpty || password.isEmpty) {
      _showMessage('Username dan Password tidak boleh kosong!');
      return;
    }

    // Tambahkan domain fiktif ke username sebelum login ke Firebase
    final emailWithDomain = '$username@strata-lite.com';

    try {
      UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: emailWithDomain,
        password: password,
      );

      User? user = userCredential.user;

      if (user != null) {
        // Simpan username, bukan email lengkap
        _saveRememberedUsername(username);

        if (!context.mounted) return;

        try {
          DocumentSnapshot userDoc =
              await _firestore.collection('users').doc(user.uid).get();
          if (!userDoc.exists) {
            _showMessage(
                'Login Berhasil, tetapi data profil tidak lengkap. Anda dialihkan ke dasbor staff.');
            if (!context.mounted) return;
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(
                  builder: (context) => const StaffDashboardScreen()),
              (Route<dynamic> route) => false,
            );
            return;
          }

          String role =
              (userDoc.data() as Map<String, dynamic>)['role'] ?? 'staff';
          String name =
              (userDoc.data() as Map<String, dynamic>)['name'] ?? 'Guest';

          if (role == 'admin') {
            _showMessage('Login Berhasil sebagai Admin: $name!');
            if (!context.mounted) return;
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(
                  builder: (context) => const AdminDashboardScreen()),
              (Route<dynamic> route) => false,
            );
          } else if (role == 'supervisor') {
            _showMessage('Login Berhasil sebagai Supervisor: $name!');
            if (!context.mounted) return;
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(
                  builder: (context) => const SupervisorDashboardScreen()),
              (Route<dynamic> route) => false,
            );
          } else {
            // Default to staff for any other or missing roles
            _showMessage('Login Berhasil sebagai Staff: $name!');
            if (!context.mounted) return;
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(
                  builder: (context) => const StaffDashboardScreen()),
              (Route<dynamic> route) => false,
            );
          }
        } catch (e) {
          _showMessage(
              'Error saat mengambil peran pengguna: $e. Dialihkan ke dasbor staff.');
          if (!context.mounted) return;
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
                builder: (context) => const StaffDashboardScreen()),
            (Route<dynamic> route) => false,
          );
          print('Error fetching user role during login: $e');
        }
      } else {
        _showMessage('Login Gagal: Pengguna tidak ditemukan.');
      }
    } on FirebaseAuthException catch (e) {
      String message;
      if (e.code == 'user-not-found') {
        message = 'Tidak ada pengguna dengan username tersebut.';
      } else if (e.code == 'wrong-password') {
        message = 'Password salah untuk username tersebut.';
      } else if (e.code == 'invalid-email') {
        message = 'Username tidak valid.';
      } else if (e.code == 'too-many-requests') {
        message = 'Terlalu banyak percobaan login gagal. Coba lagi nanti.';
      } else {
        message = 'Terjadi kesalahan otentikasi: ${e.message}';
      }
      _showMessage(message);
      print('Firebase Auth Error: ${e.code} - ${e.message}');
    } catch (e) {
      _showMessage('Terjadi kesalahan yang tidak terduga: $e');
      print('General Login Error: $e');
    }
  }

  void _showMessage(String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login Page')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'assets/Strata_logo.png',
                height: 100,
              ),
              const SizedBox(height: 30),
              SizedBox(
                width: 300,
                child: TextField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                  ),
                  keyboardType: TextInputType.text,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: 300,
                child: TextField(
                  controller: _passwordController,
                  obscureText:
                      _obscurePassword, // Controlled by _obscurePassword state
                  decoration: InputDecoration(
                    labelText: 'Password',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.lock),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility
                            : Icons.visibility_off,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword; // Toggle state
                        });
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: 300,
                child: Row(
                  children: [
                    Checkbox(
                      value: _rememberMe,
                      onChanged: (bool? newValue) {
                        setState(() {
                          _rememberMe = newValue ?? false;
                        });
                      },
                    ),
                    const Text('Ingat Saya'),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              SizedBox(
                width: 300,
                height: 50,
                child: ElevatedButton(
                  onPressed: _performLogin,
                  child: const Text(
                    'Login',
                    style: TextStyle(fontSize: 18),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
