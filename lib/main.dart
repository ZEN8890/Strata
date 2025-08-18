import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:Strata_lite/screens/admin_dashboard_screen.dart';
import 'package:Strata_lite/screens/staff_dashboard_screen.dart';
import 'package:Strata_lite/screens/login_screen.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:Strata_lite/firebase_options.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Perubahan: Langsung set rute awal ke halaman login,
  // mengabaikan status login pengguna sebelumnya.
  String initialRoute = '/';

  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.immersiveSticky,
    overlays: [],
  ).then((_) {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]).then((_) {
      runApp(MyApp(initialRoute: initialRoute));
    });
  });
}

class MyApp extends StatelessWidget {
  final String initialRoute;

  const MyApp({super.key, required this.initialRoute});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sistem Barcode Strata Lite',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      initialRoute: initialRoute,
      routes: {
        '/': (context) => const LoginScreen(),
        '/admin_dashboard': (context) => const AdminDashboardScreen(),
        '/staff_dashboard': (context) => const StaffDashboardScreen(),
      },
      debugShowCheckedModeBanner: false,
    );
  }
}
