// Path: lib/screens/login_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:Strata_lite/screens/admin_dashboard_screen.dart';
import 'package:Strata_lite/screens/supervisor_dashboard_screen.dart';
import 'package:Strata_lite/screens/staff_dashboard_screen.dart';
import 'package:animated_text_kit/animated_text_kit.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _rememberMe = false;
  bool _obscurePassword = true;
  bool _isLoading = false; // State baru untuk loading

  @override
  void initState() {
    super.initState();
    _loadRememberedPreferences();
    _checkLoggedInUser();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // Menambahkan fungsi baru untuk memeriksa pengguna yang sudah login.
  void _checkLoggedInUser() async {
    final prefs = await SharedPreferences.getInstance();
    final rememberMeStatus = prefs.getBool('remember_me_status') ?? false;
    final user = _auth.currentUser;

    if (rememberMeStatus && user != null) {
      // Menambahkan loading screen
      setState(() {
        _isLoading = true;
      });

      try {
        DocumentSnapshot userDoc =
            await _firestore.collection('users').doc(user.uid).get();
        if (userDoc.exists) {
          String role =
              (userDoc.data() as Map<String, dynamic>)['role'] ?? 'staff';
          _navigateToDashboard(role);
        } else {
          _navigateToDashboard('staff');
        }
      } catch (e) {
        print('Error fetching user role on startup: $e');
        _navigateToDashboard('staff');
      }
    }
  }

  void _navigateToDashboard(String role) {
    if (!mounted) return;
    Widget destination;
    if (role == 'admin' || role == 'dev') {
      destination = const AdminDashboardScreen();
    } else if (role == 'supervisor') {
      destination = const SupervisorDashboardScreen();
    } else {
      destination = const StaffDashboardScreen();
    }
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => destination),
      (Route<dynamic> route) => false,
    );
  }

  void _loadRememberedPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final rememberedUsername = prefs.getString('remembered_username');
    final rememberMeStatus = prefs.getBool('remember_me_status') ?? false;

    if (rememberedUsername != null && rememberedUsername.isNotEmpty) {
      setState(() {
        _usernameController.text = rememberedUsername;
      });
    }

    setState(() {
      _rememberMe = rememberMeStatus;
    });
  }

  void _saveRememberMeStatus(bool status) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('remember_me_status', status);
  }

  void _saveRememberedUsername(String username) async {
    final prefs = await SharedPreferences.getInstance();
    if (_rememberMe) {
      await prefs.setString('remembered_username', username);
    } else {
      await prefs.remove('remembered_username');
    }
  }

  void _performLogin() async {
    String username = _usernameController.text.trim();
    String password = _passwordController.text.trim();

    if (username.isEmpty || password.isEmpty) {
      _showMessage('Username dan Password tidak boleh kosong!');
      return;
    }

    final emailWithDomain = '$username@strata-lite.com';

    // Menampilkan indikator loading saat mulai login
    setState(() {
      _isLoading = true;
    });

    try {
      UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: emailWithDomain,
        password: password,
      );

      User? user = userCredential.user;

      if (user != null) {
        _saveRememberedUsername(username);

        if (!mounted) return;

        try {
          DocumentSnapshot userDoc =
              await _firestore.collection('users').doc(user.uid).get();
          if (!userDoc.exists) {
            _showMessage(
                'Login Berhasil, tetapi data profil tidak lengkap. Anda dialihkan ke dasbor staff.');
            if (!mounted) return;
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

          if (role == 'admin' || role == 'dev') {
            _showMessage('Login Berhasil sebagai Admin: $name!');
            if (!mounted) return;
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(
                  builder: (context) => const AdminDashboardScreen()),
              (Route<dynamic> route) => false,
            );
          } else if (role == 'supervisor') {
            _showMessage('Login Berhasil sebagai Supervisor: $name!');
            if (!mounted) return;
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(
                  builder: (context) => const SupervisorDashboardScreen()),
              (Route<dynamic> route) => false,
            );
          } else {
            _showMessage('Login Berhasil sebagai Staff: $name!');
            if (!mounted) return;
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(
                  builder: (context) => const StaffDashboardScreen()),
              (Route<dynamic> route) => false,
            );
          }
        } catch (e) {
          _showMessage(
              'Error saat mengambil peran pengguna: $e. Dialihkan ke dasbor staff.');
          if (!mounted) return;
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
                builder: (context) => const StaffDashboardScreen()),
            (Route<dynamic> route) => false,
          );
          print('Error fetching user role during login: $e');
        }
      } else {
        _showMessage('Login Gagal: Pengguna tidak ditemukan.');
        setState(() {
          _isLoading = false;
        });
      }
    } on FirebaseAuthException catch (e) {
      String message;
      if (e.code == 'user-not-found' || e.code == 'invalid-credential') {
        message = 'Tidak ada pengguna dengan username atau password tersebut.';
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
      setState(() {
        _isLoading = false;
      });
      print('Firebase Auth Error: ${e.code} - ${e.message}');
    } catch (e) {
      _showMessage('Terjadi kesalahan yang tidak terduga: $e');
      setState(() {
        _isLoading = false;
      });
      print('General Login Error: $e');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedTextKit(
                      animatedTexts: [
                        TypewriterAnimatedText(
                          'Strata',
                          textStyle: const TextStyle(
                            fontSize: 45.0,
                            fontWeight: FontWeight.w900,
                            color: Colors.blueAccent,
                            letterSpacing: 2.0,
                          ),
                          speed: const Duration(milliseconds: 200),
                        ),
                      ],
                      totalRepeatCount: 1,
                      isRepeatingAnimation: false,
                    ),
                    const SizedBox(height: 10),
                    Image.asset(
                      'assets/Strata_logo.png',
                      height: 100,
                    ),
                    const SizedBox(height: 30),
                    Text(
                      'Login',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[800],
                      ),
                    ),
                    const SizedBox(height: 40),
                    SizedBox(
                      width: 300,
                      child: TextField(
                        controller: _usernameController,
                        decoration: InputDecoration(
                          labelText: 'Username',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          prefixIcon: const Icon(Icons.person),
                        ),
                        keyboardType: TextInputType.text,
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: 300,
                      child: TextField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          prefixIcon: const Icon(Icons.lock),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
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
                                _saveRememberMeStatus(_rememberMe);
                                if (!_rememberMe) {
                                  _usernameController.clear();
                                  _saveRememberedUsername('');
                                }
                              });
                            },
                            activeColor: Colors.blueAccent,
                          ),
                          const Text('Ingat Saya',
                              style: TextStyle(color: Colors.black54)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 30),
                    SizedBox(
                      width: 300,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _performLogin,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Login',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'made by Steven Gunawan 2025',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
