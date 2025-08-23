import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:developer';
import 'package:another_flushbar/flushbar.dart';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'dart:typed_data';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:share_plus/share_plus.dart';

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  Timer? _notificationTimer;
  final List<String> _departments = [
    'kitchen',
    'barista',
    'bartender',
    'waiter/waiteress',
    'front service'
  ];
  final List<String> _roles = ['staff', 'admin', 'supervisor', 'dev'];
  final List<String> _userRolesForDropdown = [
    'staff',
    'supervisor',
  ];

  bool _isNewUserPasswordVisible = false;
  bool _isAdminPasswordVisible = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _notificationTimer?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text;
    });
  }

  void _showNotification(String title, String message, {bool isError = false}) {
    if (!context.mounted) return;

    if (_notificationTimer != null && _notificationTimer!.isActive) {
      log('Notification already active, skipping new one.');
      return;
    }

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

    _notificationTimer = Timer(const Duration(seconds: 2), () {
      _notificationTimer = null;
    });
  }

  Future<void> _addEditUser({DocumentSnapshot? userToEdit}) async {
    final bool isEditing = userToEdit != null;

    if (isEditing) {
      final userRole = (userToEdit!.data() as Map<String, dynamic>)['role'];
      if (userRole == 'admin' || userRole == 'dev') {
        _showNotification(
          'Akses Ditolak',
          'Akun Admin dan Dev tidak dapat diedit melalui halaman ini.',
          isError: true,
        );
        return;
      }
    }

    final _formKey = GlobalKey<FormState>();

    final String? currentRole = isEditing
        ? (userToEdit!.data() as Map<String, dynamic>)['role']
        : _userRolesForDropdown.first;
    final bool isDev = currentRole == 'dev';

    TextEditingController nameController = TextEditingController(
        text: isEditing
            ? (userToEdit!.data() as Map<String, dynamic>)['name']
            : '');
    TextEditingController usernameController = TextEditingController(
        text: isEditing
            ? (userToEdit!.data() as Map<String, dynamic>)['email']
                .toString()
                .split('@')[0]
            : '');
    TextEditingController passwordController = TextEditingController();
    String? selectedRole = currentRole;

    String? selectedDepartment = isEditing
        ? (userToEdit!.data() as Map<String, dynamic>)['department']
        : _departments.first;

    if (!isEditing && !_userRolesForDropdown.contains(selectedRole)) {
      selectedRole = _userRolesForDropdown.first;
    }

    if (!isEditing && !_departments.contains(selectedDepartment)) {
      selectedDepartment = _departments.first;
    }

    String? adminEmail = _auth.currentUser?.email;
    if (adminEmail == null) {
      _showNotification(
          'Error', 'Sesi admin tidak ditemukan. Silakan login ulang.',
          isError: true);
      return;
    }

    TextEditingController adminPasswordController = TextEditingController();

    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(isEditing ? 'Edit Pengguna' : 'Tambah Pengguna Baru'),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
        content: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nama Lengkap',
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  validator: (value) =>
                      value!.isEmpty ? 'Nama tidak boleh kosong' : null,
                ),
                const SizedBox(height: 10),
                if (!isEditing) ...[
                  TextFormField(
                    controller: usernameController,
                    decoration: const InputDecoration(
                      labelText: 'Username',
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    keyboardType: TextInputType.text,
                    validator: (value) {
                      if (value!.isEmpty) return 'Username tidak boleh kosong';
                      return null;
                    },
                  ),
                  const SizedBox(height: 10),
                ],
                DropdownButtonFormField<String>(
                  value: selectedRole,
                  decoration: const InputDecoration(
                    labelText: 'Role',
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  items: _userRolesForDropdown
                      .map((role) => DropdownMenuItem(
                          value: role, child: Text(role.toUpperCase())))
                      .toList(),
                  onChanged: (value) => setState(() => selectedRole = value),
                  validator: (value) =>
                      value == null || value.isEmpty ? 'Pilih role' : null,
                ),
                const SizedBox(height: 10),
                if (selectedRole != 'admin' && selectedRole != 'dev')
                  DropdownButtonFormField<String>(
                    value: selectedDepartment,
                    decoration: const InputDecoration(
                      labelText: 'Departemen',
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    items: _departments
                        .map((dept) =>
                            DropdownMenuItem(value: dept, child: Text(dept)))
                        .toList(),
                    onChanged: (value) =>
                        setState(() => selectedDepartment = value),
                    validator: (value) => value == null || value.isEmpty
                        ? 'Pilih departemen'
                        : null,
                  ),
                const SizedBox(height: 10),
                if (!isEditing) ...[
                  StatefulBuilder(builder: (context, setInnerState) {
                    return TextFormField(
                      controller: passwordController,
                      decoration: InputDecoration(
                        labelText: 'Password Pengguna Baru (min. 6 karakter)',
                        border: const OutlineInputBorder(),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _isNewUserPasswordVisible
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                          onPressed: () {
                            setInnerState(() {
                              _isNewUserPasswordVisible =
                                  !_isNewUserPasswordVisible;
                            });
                          },
                        ),
                      ),
                      obscureText: !_isNewUserPasswordVisible,
                      validator: (value) => value!.length < 6
                          ? 'Password minimal 6 karakter'
                          : null,
                    );
                  }),
                  const SizedBox(height: 10),
                ],
                StatefulBuilder(builder: (context, setInnerState) {
                  return TextFormField(
                    controller: adminPasswordController,
                    decoration: InputDecoration(
                      labelText: 'Sandi Admin Anda',
                      border: const OutlineInputBorder(),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _isAdminPasswordVisible
                              ? Icons.visibility
                              : Icons.visibility_off,
                        ),
                        onPressed: () {
                          setInnerState(() {
                            _isAdminPasswordVisible = !_isAdminPasswordVisible;
                          });
                        },
                      ),
                    ),
                    obscureText: !_isAdminPasswordVisible,
                    validator: (value) => value!.isEmpty
                        ? 'Sandi admin tidak boleh kosong.'
                        : null,
                  );
                }),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (_formKey.currentState!.validate()) {
                if (isEditing) {
                  await _firestore
                      .collection('users')
                      .doc(userToEdit!.id)
                      .update({
                    'name': nameController.text.trim(),
                    'department': selectedDepartment,
                    'role': selectedRole,
                  });
                  if (mounted) {
                    Navigator.of(context).pop();
                  }
                  _showNotification('Berhasil!',
                      'Pengguna ${nameController.text} berhasil diperbarui.',
                      isError: false);
                } else {
                  if (selectedRole == null || selectedRole!.isEmpty) {
                    _showNotification(
                        'Validasi Gagal', 'Role tidak boleh kosong.',
                        isError: true);
                    return;
                  }
                  final newUserEmail =
                      '${usernameController.text.trim()}@strata-lite.com';
                  try {
                    final String? currentAdminUid = _auth.currentUser?.uid;

                    await _auth.createUserWithEmailAndPassword(
                      email: newUserEmail,
                      password: passwordController.text.trim(),
                    );

                    final String? newUserId = _auth.currentUser?.uid;

                    if (newUserId != null) {
                      await _firestore.collection('users').doc(newUserId).set({
                        'name': nameController.text.trim(),
                        'email': newUserEmail,
                        'department': selectedDepartment,
                        'role': selectedRole,
                        'createdAt': FieldValue.serverTimestamp(),
                      });
                    }

                    if (currentAdminUid != null &&
                        adminPasswordController.text.isNotEmpty) {
                      await _auth.signInWithEmailAndPassword(
                          email: adminEmail!,
                          password: adminPasswordController.text);
                    }

                    if (mounted) {
                      Navigator.of(context).pop();
                    }
                    _showNotification('Akun Berhasil Dibuat!',
                        'Pengguna ${nameController.text} berhasil ditambahkan.',
                        isError: false);
                  } on FirebaseAuthException catch (e) {
                    String message;
                    if (e.code == 'email-already-in-use') {
                      message = 'Email ini sudah terdaftar.';
                    } else if (e.code == 'weak-password') {
                      message = 'Password terlalu lemah.';
                    } else {
                      message = 'Gagal memproses akun: ${e.message}';
                    }
                    if (mounted) {
                      Navigator.of(context).pop();
                    }
                    _showNotification('Gagal!', message, isError: true);
                    log('Error in add/edit user flow: $e');
                  } catch (e) {
                    _showNotification('Error', 'Terjadi kesalahan umum: $e',
                        isError: true);
                    log('Error in add/edit user flow: $e');
                    if (mounted) {
                      Navigator.of(context).pop();
                    }
                  }
                }
              }
            },
            child: Text(isEditing ? 'Simpan Perubahan' : 'Tambah Pengguna'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteUser(String userId, String userName) async {
    try {
      final userDoc = await _firestore.collection('users').doc(userId).get();
      final userData = userDoc.data() as Map<String, dynamic>?;
      final userRole = userData?['role'];

      if (userRole == 'dev' || userRole == 'admin') {
        _showNotification(
            'Akses Ditolak', 'Akun Admin dan Dev tidak dapat dihapus.',
            isError: true);
        return;
      }

      final confirm = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Konfirmasi Hapus'),
          content:
              Text('Apakah Anda yakin ingin menghapus pengguna $userName?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Batal'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Hapus'),
            ),
          ],
        ),
      );

      if (confirm == true) {
        await _firestore.collection('users').doc(userId).delete();
        _showNotification('Berhasil!', 'Pengguna $userName berhasil dihapus.',
            isError: false);
      }
    } catch (e) {
      _showNotification('Gagal!', 'Terjadi kesalahan saat menghapus pengguna.',
          isError: true);
      log('Error deleting user: $e');
    }
  }

  Future<void> _exportUsersToExcel() async {
    try {
      final querySnapshot = await _firestore.collection('users').get();
      final usersData = querySnapshot.docs;

      if (usersData.isEmpty) {
        _showNotification('Info', 'Tidak ada pengguna untuk diekspor.',
            isError: false);
        return;
      }

      final excel = Excel.createExcel();
      final defaultSheetName = excel.getDefaultSheet()!;
      excel.rename(defaultSheetName, 'Daftar Pengguna');
      final sheet = excel['Daftar Pengguna'];

      List<String> headers = ['Nama Lengkap', 'Username', 'Departemen', 'Role'];
      sheet.insertRowIterables(
          headers.map((e) => TextCellValue(e)).toList(), 0);

      for (int i = 0; i < usersData.length; i++) {
        final userData = usersData[i].data();

        List<dynamic> row = [
          userData['name'] ?? '',
          (userData['email'] ?? '').toString().split('@')[0],
          userData['department'] ?? '',
          userData['role'] ?? '',
        ];
        sheet.insertRowIterables(
            row.map((e) => TextCellValue(e.toString())).toList(), i + 1);
      }

      final excelBytes = excel.encode()!;

      final String fileName = 'Daftar_Pengguna_Strata.xlsx';

      if (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux) {
        final String? resultPath = await FilePicker.platform.saveFile(
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: ['xlsx'],
        );

        if (!mounted) return;

        if (resultPath != null) {
          final File file = File(resultPath);
          await file.writeAsBytes(Uint8List.fromList(excelBytes));
          _showNotification('Berhasil!',
              'Daftar pengguna berhasil diekspor ke Excel di: $resultPath',
              isError: false);
          log('File Excel berhasil diekspor ke: $resultPath');
        } else {
          _showNotification('Ekspor Dibatalkan',
              'Ekspor dibatalkan atau file tidak disimpan.',
              isError: true);
        }
      } else {
        final directory = await getApplicationDocumentsDirectory();
        final filePath = '${directory.path}/$fileName';
        final file = File(filePath);
        await file.writeAsBytes(Uint8List.fromList(excelBytes), flush: true);
        await Share.shareXFiles([XFile(filePath)],
            text: 'Data pengguna Strata');
        if (!mounted) return;
        _showNotification('Ekspor Berhasil',
            'Data berhasil diekspor. Pilih aplikasi untuk menyimpan file.');
        log('File Excel berhasil diekspor dan akan dibagikan: $filePath');
      }
    } catch (e) {
      _showNotification(
          'Gagal Export', 'Terjadi kesalahan saat mengekspor data: $e',
          isError: true);
      log('Error exporting users: $e');
    }
  }

  Future<void> _importUsersFromExcel() async {
    if (!mounted) return;
    bool hasPermission = await _requestStoragePermission(context);
    if (!hasPermission) return;

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );

      if (result == null || result.files.single.path == null) {
        _showNotification(
            'Impor Dibatalkan', 'Tidak ada file yang dipilih untuk diimpor.',
            isError: true);
        return;
      }

      File file = File(result.files.single.path!);
      var bytes = file.readAsBytesSync();
      var excel = Excel.decodeBytes(bytes);

      int importedCount = 0;
      int failedCount = 0;

      for (var table in excel.tables.keys) {
        var sheet = excel.tables[table];
        if (sheet == null || sheet.rows.isEmpty) continue;

        final headerRow = sheet.rows.first
            .map((cell) => cell?.value?.toString().trim())
            .toList();

        final nameIndex = headerRow.indexOf('Nama Lengkap');
        final usernameIndex = headerRow.indexOf('Username');
        final departmentIndex = headerRow.indexOf('Departemen');
        final roleIndex = headerRow.indexOf('Role');
        final passwordIndex = headerRow.indexOf('Password');
        final phoneIndex = headerRow.indexOf(
            'Nomor Telepon'); // Dihapus dari template tapi masih dicheck

        if (nameIndex == -1 ||
            usernameIndex == -1 ||
            departmentIndex == -1 ||
            roleIndex == -1 ||
            passwordIndex == -1) {
          _showNotification('Gagal Import',
              'File Excel tidak memiliki semua kolom yang diperlukan (Nama Lengkap, Username, Departemen, Role, Password).',
              isError: true);
          return;
        }

        String? adminPassword = await _showAdminPasswordDialog();
        if (adminPassword == null) {
          _showNotification('Impor Dibatalkan', 'Sandi admin tidak dimasukkan.',
              isError: true);
          return;
        }
        final currentAdminEmail = _auth.currentUser!.email;

        for (int i = 1; i < sheet.rows.length; i++) {
          final row = sheet.rows[i];
          final String name = (row[nameIndex]?.value?.toString().trim() ?? '');
          final String username =
              (row[usernameIndex]?.value?.toString().trim() ?? '');
          final String department =
              (row[departmentIndex]?.value?.toString().trim() ?? '');
          String role = (row[roleIndex]?.value?.toString().trim() ?? 'staff')
              .toLowerCase();
          final String password =
              (row[passwordIndex]?.value?.toString().trim() ?? '');

          if (name.isEmpty || username.isEmpty || password.isEmpty) {
            log('Skipping row $i: Nama, Username, atau Password kosong.');
            failedCount++;
            continue;
          }
          if (password.length < 6) {
            log('Skipping row $i: Password kurang dari 6 karakter.');
            failedCount++;
            continue;
          }

          if (!_roles.contains(role)) {
            role = 'staff';
          }
          if (!_departments.contains(department)) {
            log('Skipping row $i: Departemen tidak valid.');
            failedCount++;
            continue;
          }

          try {
            final newUserEmail = '$username@strata-lite.com';
            await _functions.httpsCallable('createUserAndProfile').call({
              'name': name,
              'email': newUserEmail,
              'password': password,
              'department': department,
              'role': role,
            });
            importedCount++;

            await _auth.signInWithEmailAndPassword(
                email: currentAdminEmail!, password: adminPassword);
          } on FirebaseAuthException catch (e) {
            log('Gagal mengimpor $username (Auth Error): ${e.message}');
            failedCount++;
          } catch (e) {
            log('Gagal mengimpor $username (General Error): $e');
            failedCount++;
          }
        }
      }

      String importSummaryMessage =
          '${importedCount} pengguna berhasil diimpor. ${failedCount} pengguna gagal diimpor.';

      _showNotification(
        'Impor Selesai!',
        importSummaryMessage,
        isError: failedCount > 0,
      );
    } catch (e) {
      _showNotification(
          'Gagal Import', 'Terjadi kesalahan saat mengimpor file Excel: $e',
          isError: true);
      log('Error importing users: $e');
    }
  }

  Future<void> _downloadImportTemplate() async {
    try {
      final excel = Excel.createExcel();
      final defaultSheetName = excel.getDefaultSheet()!;
      excel.rename(defaultSheetName, 'Template Import Pengguna');
      final sheet = excel['Template Import Pengguna'];

      List<String> headers = [
        'Nama Lengkap',
        'Username',
        'Departemen',
        'Role',
        'Password'
      ];
      sheet.insertRowIterables(
          headers.map((e) => TextCellValue(e)).toList(), 0);

      final excelBytes = excel.encode()!;

      final String fileName = 'Template_Import_Pengguna_Strata.xlsx';

      if (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux) {
        final String? resultPath = await FilePicker.platform.saveFile(
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: ['xlsx'],
        );

        if (!mounted) return;

        if (resultPath != null) {
          final File file = File(resultPath);
          await file.writeAsBytes(Uint8List.fromList(excelBytes));
          _showNotification('Berhasil!',
              'Template impor Excel berhasil diunduh ke: $resultPath',
              isError: false);
          log('File template berhasil diunduh ke: $resultPath');
        } else {
          _showNotification('Pengunduhan Dibatalkan',
              'Pengunduhan template dibatalkan atau file tidak disimpan.',
              isError: true);
        }
      } else {
        final directory = await getApplicationDocumentsDirectory();
        final filePath = '${directory.path}/$fileName';
        final file = File(filePath);
        await file.writeAsBytes(Uint8List.fromList(excelBytes), flush: true);
        await Share.shareXFiles([XFile(filePath)],
            text: 'Template impor pengguna Strata');
        if (!mounted) return;
        _showNotification('Berhasil!',
            'Template impor Excel berhasil diunduh. Pilih aplikasi untuk menyimpan file.',
            isError: false);
        log('File template berhasil diunduh dan akan dibagikan: $filePath');
      }
    } catch (e) {
      _showNotification('Gagal Download Template',
          'Terjadi kesalahan saat mengunduh template: $e',
          isError: true);
      log('Error downloading template: $e');
    }
  }

  Future<bool> _requestStoragePermission(BuildContext context) async {
    log('Requesting storage permission...');
    if (defaultTargetPlatform == TargetPlatform.android) {
      if (Theme.of(context).platform == TargetPlatform.android) {
        var status = await Permission.storage.request();
        if (status.isGranted) {
          return true;
        } else if (status.isPermanentlyDenied) {
          if (!context.mounted) return false;
          _showPermissionDeniedDialog(context, 'Izin Penyimpanan Diperlukan',
              'Untuk mengimpor/mengekspor file Excel, aplikasi membutuhkan izin penyimpanan. Harap izinkan secara manual di Pengaturan Aplikasi.');
          return false;
        }
      }
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      var status = await Permission.photos.request();
      if (status.isGranted) {
        return true;
      } else if (status.isPermanentlyDenied) {
        if (!context.mounted) return false;
        _showPermissionDeniedDialog(context, 'Izin Foto Diperlukan',
            'Untuk mengimpor/mengekspor file, aplikasi membutuhkan izin akses foto. Harap izinkan secara manual di Pengaturan Aplikasi.');
        return false;
      }
    } else if (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux) {
      log('Platform desktop, assuming file access is granted.');
      return true;
    }
    _showNotification('Platform Tidak Didukung',
        'Platform ini tidak didukung untuk operasi file.',
        isError: true);
    return false;
  }

  void _showPermissionDeniedDialog(
      BuildContext context, String title, String content) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              openAppSettings();
            },
            child: const Text('Buka Pengaturan'),
          ),
        ],
      ),
    );
  }

  Future<String?> _showAdminPasswordDialog() async {
    TextEditingController passwordController = TextEditingController();
    return await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Konfirmasi Sandi Admin'),
          content: StatefulBuilder(builder: (context, setInnerState) {
            return TextField(
              controller: passwordController,
              obscureText: !_isAdminPasswordVisible,
              decoration: InputDecoration(
                hintText: 'Masukkan sandi admin',
                suffixIcon: IconButton(
                  icon: Icon(
                    _isAdminPasswordVisible
                        ? Icons.visibility
                        : Icons.visibility_off,
                  ),
                  onPressed: () {
                    setInnerState(() {
                      _isAdminPasswordVisible = !_isAdminPasswordVisible;
                    });
                  },
                ),
              ),
            );
          }),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () {
                if (passwordController.text.isNotEmpty) {
                  Navigator.of(context).pop(passwordController.text);
                }
              },
              child: const Text('Konfirmasi'),
            ),
          ],
        );
      },
    );
  }

  void _showImportExportOptions() {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext bc) {
        return SafeArea(
          child: Wrap(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.download),
                title: const Text('Export Pengguna ke Excel'),
                onTap: () {
                  Navigator.pop(bc);
                  _exportUsersToExcel();
                },
              ),
              ListTile(
                leading: const Icon(Icons.upload),
                title: const Text('Import Pengguna dari Excel'),
                onTap: () {
                  Navigator.pop(bc);
                  _importUsersFromExcel();
                },
              ),
              ListTile(
                leading: const Icon(Icons.file_download),
                title: const Text('Download Template Import Excel'),
                onTap: () {
                  Navigator.pop(bc);
                  _downloadImportTemplate();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Card(
            margin: EdgeInsets.zero,
            elevation: 2,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Cari pengguna (nama, email, departemen, role)...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8.0),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Colors.grey[100],
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              ElevatedButton.icon(
                onPressed: () => _addEditUser(),
                icon: const Icon(Icons.person_add),
                label: const Text('Tambah Pengguna'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                icon: const Icon(Icons.more_vert),
                onPressed: _showImportExportOptions,
                tooltip: 'Opsi Import/Export',
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _firestore.collection('users').orderBy('name').snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }

              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return const Center(
                    child: Text('Belum ada pengguna terdaftar.'));
              }

              List<DocumentSnapshot> allUsers = snapshot.data!.docs;

              List<DocumentSnapshot> filteredUsers = allUsers.where((userDoc) {
                final data = userDoc.data() as Map<String, dynamic>?;
                if (data == null) return false;

                final String lowerCaseQuery = _searchQuery.toLowerCase();
                final String name = (data['name'] ?? '').toLowerCase();
                final String email = (data['email'] ?? '').toLowerCase();
                final String department =
                    (data['department'] ?? '').toLowerCase();
                final String role = (data['role'] ?? '').toLowerCase();
                final String username = email.split('@')[0];

                return name.contains(lowerCaseQuery) ||
                    email.contains(lowerCaseQuery) ||
                    department.contains(lowerCaseQuery) ||
                    role.contains(lowerCaseQuery) ||
                    username.contains(lowerCaseQuery);
              }).toList();

              if (filteredUsers.isEmpty && _searchQuery.isNotEmpty) {
                return const Center(child: Text('Pengguna tidak ditemukan.'));
              }
              if (filteredUsers.isEmpty && _searchQuery.isEmpty) {
                return const Center(
                    child: Text('Belum ada pengguna terdaftar.'));
              }

              return ListView.builder(
                itemCount: filteredUsers.length,
                itemBuilder: (context, index) {
                  final userDoc = filteredUsers[index];
                  final userData = userDoc.data() as Map<String, dynamic>;

                  final String name = userData['name'] ?? 'N/A';
                  final String email = userData['email'] ?? 'N/A';
                  final String username = email.split('@')[0];
                  final String department = userData['department'] ?? 'N/A';
                  final String role = userData['role'] ?? 'N/A';

                  Color roleColor;
                  switch (role) {
                    case 'admin':
                      roleColor = Colors.red[700]!;
                      break;
                    case 'supervisor':
                      roleColor = Colors.orange[700]!;
                      break;
                    case 'staff':
                      roleColor = Colors.blue[700]!;
                      break;
                    case 'dev':
                      roleColor = Colors.purple[700]!;
                      break;
                    default:
                      roleColor = Colors.grey;
                  }

                  return Card(
                    margin:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    elevation: 3,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      leading: CircleAvatar(
                        backgroundColor: roleColor,
                        child: const Icon(Icons.person, color: Colors.white),
                      ),
                      title: Text(
                        name,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: Colors.black87),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Text('Username: $username',
                              style: const TextStyle(fontSize: 14)),
                          Text('Departemen: $department',
                              style: const TextStyle(fontSize: 14)),
                          Text('Role: ${role.toUpperCase()}',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: roleColor,
                              )),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (role != 'admin' && role != 'dev')
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.blue),
                              tooltip: 'Edit User',
                              onPressed: () =>
                                  _addEditUser(userToEdit: userDoc),
                            ),
                          if (role != 'admin' && role != 'dev')
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              tooltip: 'Hapus User',
                              onPressed: () => _deleteUser(userDoc.id, name),
                            ),
                        ],
                      ),
                      onTap: () {
                        log('Detail user ${name} diklik');
                      },
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
