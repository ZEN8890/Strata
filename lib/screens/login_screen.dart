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
    _loadRememberedEmail(); // Muat email yang disimpan saat screen diinisialisasi
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // Fungsi untuk memuat email yang disimpan
  void _loadRememberedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    final rememberedEmail = prefs.getString('remembered_email');
    if (rememberedEmail != null && rememberedEmail.isNotEmpty) {
      setState(() {
        _emailController.text = rememberedEmail;
        _rememberMe = true; // Set checkbox ke true jika email ditemukan
      });
    }
  }

  // Fungsi untuk menyimpan email jika "Remember Me" dicentang
  void _saveRememberedEmail(String email) async {
    final prefs = await SharedPreferences.getInstance();
    if (_rememberMe) {
      await prefs.setString('remembered_email', email);
    } else {
      await prefs.remove('remembered_email'); // Hapus jika tidak dicentang
    }
  }

  void _performLogin() async {
    String email = _emailController.text.trim();
    String password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showMessage('Email dan Password tidak boleh kosong!');
      return;
    }

    try {
      UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      User? user = userCredential.user;

      if (user != null) {
        _saveRememberedEmail(email);

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

          if (role == 'admin') {
            _showMessage('Login Berhasil sebagai Admin: ${user.email}!');
            if (!context.mounted) return;
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(
                  builder: (context) => const AdminDashboardScreen()),
              (Route<dynamic> route) => false,
            );
          } else if (role == 'supervisor') {
            _showMessage('Login Berhasil sebagai Supervisor: ${user.email}!');
            if (!context.mounted) return;
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(
                  builder: (context) => const SupervisorDashboardScreen()),
              (Route<dynamic> route) => false,
            );
          } else {
            // Default to staff for any other or missing roles
            _showMessage(
                'Login Berhasil sebagai Pengguna Biasa (Staff): ${user.email}!');
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
        message = 'Tidak ada pengguna dengan email tersebut.';
      } else if (e.code == 'wrong-password') {
        message = 'Password salah untuk email tersebut.';
      } else if (e.code == 'invalid-email') {
        message = 'Format email tidak valid.';
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
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.email),
                  ),
                  keyboardType: TextInputType.emailAddress,
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
