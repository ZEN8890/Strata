// Path: lib/screens/credit_page.dart
import 'package:flutter/material.dart';

class CreditPage extends StatefulWidget {
  const CreditPage({super.key});

  @override
  State<CreditPage> createState() => _CreditPageState();
}

class _CreditPageState extends State<CreditPage> with TickerProviderStateMixin {
  late AnimationController _strataController;
  late AnimationController _nevetsController;
  late AnimationController _geminiController;

  @override
  void initState() {
    super.initState();
    _strataController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      lowerBound: 0.9,
      upperBound: 1.1,
    );
    _nevetsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      lowerBound: 0.9,
      upperBound: 1.1,
    );
    _geminiController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      lowerBound: 0.9,
      upperBound: 1.1,
    );
  }

  @override
  void dispose() {
    _strataController.dispose();
    _nevetsController.dispose();
    _geminiController.dispose();
    super.dispose();
  }

  void _animateLogo(AnimationController controller) async {
    await controller.forward();
    await controller.reverse();
  }

  void _showProfilePictureDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: ClipOval(
              child: Image.asset(
                'assets/profile_steven.jpg',
                width: 300,
                height: 300,
                fit: BoxFit.cover,
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Text(
                  'Aplikasi ini dibuat oleh',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 18,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'Steven Gunawan',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(width: 16),
                    GestureDetector(
                      onTap: () => _showProfilePictureDialog(context),
                      child: ClipOval(
                        child: Image.asset(
                          'assets/profile_steven.jpg',
                          width: 50,
                          height: 50,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 40),
                const Text(
                  'version 1.0 | 15 agustus 2025',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 40),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    GestureDetector(
                      onTap: () => _animateLogo(_strataController),
                      child: AnimatedBuilder(
                        animation: _strataController,
                        builder: (context, child) {
                          return Transform.scale(
                            scale: _strataController.value,
                            child: Column(
                              children: [
                                const Text(
                                  'Strata',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Image.asset(
                                  'assets/Strata_logo.png',
                                  width: 80,
                                  height: 80,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    GestureDetector(
                      onTap: () => _animateLogo(_nevetsController),
                      child: AnimatedBuilder(
                        animation: _nevetsController,
                        builder: (context, child) {
                          return Transform.scale(
                            scale: _nevetsController.value,
                            child: Column(
                              children: [
                                const Text(
                                  'Nevets AI',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Image.asset(
                                  'assets/Nevets_remove.png',
                                  width: 80,
                                  height: 80,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    GestureDetector(
                      onTap: () => _animateLogo(_geminiController),
                      child: AnimatedBuilder(
                        animation: _geminiController,
                        builder: (context, child) {
                          return Transform.scale(
                            scale: _geminiController.value,
                            child: const Column(
                              children: [
                                Text(
                                  'Gemini AI',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(height: 8),
                                Icon(Icons.auto_awesome,
                                    size: 60, color: Colors.indigo),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
