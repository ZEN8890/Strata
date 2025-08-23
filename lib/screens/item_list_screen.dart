import 'package:flutter/material.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:Strata_lite/models/item.dart';
import 'dart:developer';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:another_flushbar/flushbar.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ItemListScreen extends StatefulWidget {
  const ItemListScreen({super.key});

  @override
  State<ItemListScreen> createState() => _ItemListScreenState();
}

class _ItemListScreenState extends State<ItemListScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _searchController = TextEditingController();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String _searchQuery = '';
  String _expiryFilter = 'Semua Item';
  String _stockFilter = 'Semua Item';
  String _classificationFilter = 'Semua Item';

  String _userRole = 'staff';
  String _userDepartment = 'unknown';
  bool _isGroupView = false;
  List<String> _classifications = [];
  List<String> _departments = [];
  Timer? _notificationTimer;
  bool _isLoadingExport = false;
  bool _isLoadingImport = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _fetchClassifications();
    _fetchDepartments();
    _fetchUserData();
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _notificationTimer?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    if (mounted) {
      setState(() {
        _searchQuery = _searchController.text;
      });
    }
  }

  Future<void> _fetchUserData() async {
    User? currentUser = _auth.currentUser;
    if (currentUser != null) {
      DocumentSnapshot userDoc =
          await _firestore.collection('users').doc(currentUser.uid).get();
      if (userDoc.exists) {
        final userData = userDoc.data() as Map<String, dynamic>;
        if (mounted) {
          setState(() {
            _userRole = userData['role'] ?? 'staff';
            _userDepartment = userData['department'] ?? 'unknown';
          });
        }
      }
    }
  }

  Future<void> _fetchClassifications() async {
    try {
      final doc =
          await _firestore.collection('config').doc('classifications').get();
      if (mounted) {
        if (doc.exists) {
          final data = doc.data();
          if (data != null && data['list'] is List) {
            setState(() {
              _classifications = List<String>.from(data['list']);
            });
          }
        } else {
          final defaultClassifications = [
            'Bahan Makanan',
            'Peralatan',
            'Bahan Habis Pakai',
            'Elektronik',
            'Lainnya'
          ];
          await _firestore.collection('config').doc('classifications').set({
            'list': defaultClassifications,
          });
          setState(() {
            _classifications = defaultClassifications;
          });
        }
      }
    } catch (e) {
      log('Error fetching classifications: $e');
      _showNotification('Error', 'Gagal memuat klasifikasi. $e', isError: true);
    }
  }

  Future<void> _fetchDepartments() async {
    try {
      final doc =
          await _firestore.collection('config').doc('departments').get();
      if (mounted) {
        if (doc.exists) {
          final data = doc.data();
          if (data != null && data['list'] is List) {
            setState(() {
              _departments = List<String>.from(data['list']);
            });
          }
        } else {
          final defaultDepartments = [
            'kitchen',
            'barista',
            'bartender',
            'general'
          ];
          await _firestore.collection('config').doc('departments').set({
            'list': defaultDepartments,
          });
          setState(() {
            _departments = defaultDepartments;
          });
        }
      }
    } catch (e) {
      log('Error fetching departments: $e');
    }
  }

  Future<void> _renameClassification(String oldName, String newName) async {
    try {
      // 1. Update the classifications list in Firestore
      List<String> updatedClassifications = List.from(_classifications);
      final index = updatedClassifications.indexOf(oldName);
      if (index != -1) {
        updatedClassifications[index] = newName;
      }
      await _firestore.collection('config').doc('classifications').set({
        'list': updatedClassifications,
      });

      // 2. Perform a batch update on all items with the old classification name
      WriteBatch batch = _firestore.batch();
      QuerySnapshot snapshot = await _firestore
          .collection('items')
          .where('classification', isEqualTo: oldName)
          .get();

      for (var doc in snapshot.docs) {
        batch.update(doc.reference, {'classification': newName});
      }
      await batch.commit();

      if (mounted) {
        setState(() {
          _classifications = updatedClassifications;
        });
        _showNotification('Berhasil!',
            'Klasifikasi "$oldName" berhasil diubah menjadi "$newName".');
      }
    } catch (e) {
      log('Error renaming classification: $e');
      _showNotification('Gagal', 'Gagal mengubah nama klasifikasi: $e',
          isError: true);
    }
  }

  Future<void> _manageClassificationDeletion(
      String classificationToDelete) async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Konfirmasi Hapus Klasifikasi'),
        content: Text(
            'Apakah Anda yakin ingin menghapus klasifikasi "$classificationToDelete"? Semua item dengan klasifikasi ini akan disetel menjadi "Tidak Terklasifikasi".'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Hapus', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        // 1. Remove the classification from the global list
        List<String> updatedClassifications = List.from(_classifications);
        updatedClassifications.remove(classificationToDelete);
        await _firestore.collection('config').doc('classifications').set({
          'list': updatedClassifications,
        });

        // 2. Perform a batch update on all items with the old classification name
        WriteBatch batch = _firestore.batch();
        QuerySnapshot snapshot = await _firestore
            .collection('items')
            .where('classification', isEqualTo: classificationToDelete)
            .get();

        for (var doc in snapshot.docs) {
          batch.update(doc.reference, {'classification': null});
        }
        await batch.commit();

        if (mounted) {
          // Rebuild the main widget with the updated list
          setState(() {
            _classifications = updatedClassifications;
          });
          _showNotification('Berhasil!',
              'Klasifikasi "$classificationToDelete" dan item terkait berhasil diperbarui.');
        }
      } catch (e) {
        log('Error deleting classification: $e');
        _showNotification('Gagal', 'Gagal menghapus klasifikasi: $e',
            isError: true);
      }
    }
  }

  Future<void> _manageClassifications() async {
    List<String> tempClassifications = List.from(_classifications);
    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateSB) {
            return AlertDialog(
              title: const Text('Kelola Klasifikasi'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ...tempClassifications.map((c) => Row(
                          children: [
                            Expanded(child: Text(c)),
                            IconButton(
                              icon: const Icon(Icons.edit),
                              onPressed: () async {
                                final newName =
                                    await _showEditClassificationDialog(
                                        context, c);
                                if (newName != null && newName.isNotEmpty) {
                                  if (newName != c) {
                                    if (!tempClassifications
                                        .contains(newName)) {
                                      _renameClassification(c, newName);
                                      Navigator.of(context).pop();
                                    } else {
                                      _showNotification(
                                          'Gagal', 'Klasifikasi sudah ada.',
                                          isError: true);
                                    }
                                  }
                                }
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () async {
                                // Call the deletion function and refresh the dialog state
                                await _manageClassificationDeletion(c);
                                setStateSB(() {
                                  tempClassifications.remove(c);
                                });
                                // Don't pop the dialog here, let the state update
                              },
                            ),
                          ],
                        )),
                    const SizedBox(height: 10),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('Tambah Klasifikasi'),
                      onPressed: () async {
                        final newName =
                            await _showEditClassificationDialog(context, '');
                        if (newName != null && newName.isNotEmpty) {
                          if (!tempClassifications.contains(newName)) {
                            setStateSB(() {
                              tempClassifications.add(newName);
                            });
                          } else {
                            _showNotification('Gagal', 'Klasifikasi sudah ada.',
                                isError: true);
                          }
                        }
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Batal'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    try {
                      await _firestore
                          .collection('config')
                          .doc('classifications')
                          .set({
                        'list': tempClassifications,
                      });
                      if (mounted) {
                        setState(() {
                          _classifications = tempClassifications;
                        });
                      }
                      Navigator.of(context).pop();
                      _showNotification(
                          'Berhasil', 'Klasifikasi berhasil diperbarui!');
                    } catch (e) {
                      _showNotification(
                          'Gagal', 'Gagal memperbarui klasifikasi. $e',
                          isError: true);
                    }
                  },
                  child: const Text('Simpan'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _manageDepartmentAccess(String classification) async {
    QuerySnapshot snapshot = await _firestore
        .collection('items')
        .where('classification', isEqualTo: classification)
        .get();

    List<Item> itemsInGroup = snapshot.docs
        .map((doc) =>
            Item.fromFirestore(doc.data() as Map<String, dynamic>, doc.id))
        .toList();

    Set<String> currentAllowedDepartments = {};
    if (itemsInGroup.isNotEmpty) {
      currentAllowedDepartments.addAll(itemsInGroup.first.allowedDepartments);
    }

    List<String> selectedDepartments = List.from(currentAllowedDepartments);

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateSB) {
            return AlertDialog(
              title: Text('Atur Akses Departemen untuk\n"$classification"'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Departemen yang diizinkan:'),
                  ..._departments.map((dept) {
                    return CheckboxListTile(
                      title: Text(dept.toUpperCase()),
                      value: selectedDepartments.contains(dept),
                      onChanged: (bool? isChecked) {
                        setStateSB(() {
                          if (isChecked == true) {
                            selectedDepartments.add(dept);
                          } else {
                            selectedDepartments.remove(dept);
                          }
                        });
                      },
                    );
                  }),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Batal'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    WriteBatch batch = _firestore.batch();
                    for (var item in itemsInGroup) {
                      batch.update(
                        _firestore.collection('items').doc(item.id),
                        {'allowedDepartments': selectedDepartments},
                      );
                    }
                    await batch.commit();
                    if (mounted) {
                      Navigator.of(context).pop();
                      _showNotification('Berhasil',
                          'Akses departemen berhasil diperbarui untuk grup "$classification".');
                    }
                  },
                  child: const Text('Simpan'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showMassClassificationDialog(BuildContext context) async {
    List<Item> allItems = [];
    String? selectedClassification;

    try {
      QuerySnapshot allItemsSnapshot =
          await _firestore.collection('items').orderBy('name').get();
      allItems = allItemsSnapshot.docs
          .map((doc) =>
              Item.fromFirestore(doc.data() as Map<String, dynamic>, doc.id))
          .toList();
    } catch (e) {
      _showNotification('Error', 'Gagal memuat item: $e', isError: true);
      return;
    }

    // A temporary list to track user's selections.
    List<String> selectedItemsIds = [];

    // Use this list to find which items were originally selected, for comparison later.
    List<String> originalSelectedItemsIds = [];

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateSB) {
            List<Item> itemsInSelectedClassification = [];
            List<Item> unclassifiedItems = [];

            if (selectedClassification != null) {
              itemsInSelectedClassification = allItems
                  .where(
                      (item) => item.classification == selectedClassification)
                  .toList();
              unclassifiedItems = allItems
                  .where((item) =>
                      item.classification == null ||
                      item.classification!.isEmpty)
                  .toList();
            } else {
              unclassifiedItems = allItems
                  .where((item) =>
                      item.classification == null ||
                      item.classification!.isEmpty)
                  .toList();
            }

            // Sort both lists alphabetically
            itemsInSelectedClassification
                .sort((a, b) => a.name.compareTo(b.name));
            unclassifiedItems.sort((a, b) => a.name.compareTo(b.name));

            // Combine them with classified items at the top
            List<Item> itemsToDisplay = [
              ...itemsInSelectedClassification,
              ...unclassifiedItems
            ];

            return AlertDialog(
              title: const Text('Klasifikasi Massal Item',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 16),
                    if (_classifications.isNotEmpty)
                      DropdownButtonFormField<String>(
                        decoration: InputDecoration(
                            labelText: 'Pilih Klasifikasi',
                            border: const OutlineInputBorder(),
                            suffixIcon: selectedClassification != null
                                ? Padding(
                                    padding: const EdgeInsets.only(right: 12.0),
                                    child: Text(
                                      '${selectedItemsIds.length} item',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color:
                                              Theme.of(context).primaryColor),
                                    ),
                                  )
                                : null),
                        value: selectedClassification,
                        items: _classifications.map((String classification) {
                          return DropdownMenuItem<String>(
                              value: classification,
                              child: Text(classification));
                        }).toList(),
                        onChanged: (String? newValue) {
                          setStateSB(() {
                            selectedClassification = newValue;
                            selectedItemsIds.clear();
                            if (newValue != null) {
                              selectedItemsIds.addAll(allItems
                                  .where(
                                      (item) => item.classification == newValue)
                                  .map((item) => item.id!)
                                  .toList());
                            }
                            originalSelectedItemsIds =
                                List.from(selectedItemsIds);
                          });
                        },
                      ),
                    const SizedBox(height: 16),
                    const Text('Pilih item yang akan diklasifikasi:'),
                    Expanded(
                      child: ListView.builder(
                        itemCount: itemsToDisplay.length,
                        itemBuilder: (context, index) {
                          final item = itemsToDisplay[index];
                          return CheckboxListTile(
                            title: Text(item.name),
                            subtitle: Text('Barcode: ${item.barcode}'),
                            value: selectedItemsIds.contains(item.id),
                            onChanged: (bool? isChecked) {
                              setStateSB(() {
                                if (isChecked == true && item.id != null) {
                                  if (!selectedItemsIds.contains(item.id!)) {
                                    selectedItemsIds.add(item.id!);
                                  }
                                } else {
                                  selectedItemsIds.remove(item.id);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Batal'),
                ),
                ElevatedButton(
                  onPressed: selectedClassification != null
                      ? () async {
                          try {
                            WriteBatch batch = _firestore.batch();
                            final newSelectedIdsSet = selectedItemsIds.toSet();
                            final originalSelectedIdsSet =
                                originalSelectedItemsIds.toSet();

                            // Find items to add to the new classification
                            final idsToAdd = newSelectedIdsSet
                                .difference(originalSelectedIdsSet);
                            // Find items to remove from the old classification
                            final idsToRemove = originalSelectedIdsSet
                                .difference(newSelectedIdsSet);

                            for (var id in idsToAdd) {
                              batch.update(
                                  _firestore.collection('items').doc(id), {
                                'classification': selectedClassification,
                              });
                            }

                            for (var id in idsToRemove) {
                              batch.update(
                                  _firestore.collection('items').doc(id), {
                                'classification': null,
                              });
                            }

                            await batch.commit();
                            if (mounted) {
                              Navigator.of(context).pop();
                              _showNotification('Berhasil',
                                  'Klasifikasi massal berhasil diperbarui!');
                            }
                          } catch (e) {
                            _showNotification('Gagal',
                                'Gagal memperbarui klasifikasi massal: $e',
                                isError: true);
                          }
                        }
                      : null,
                  child: const Text('Simpan'),
                ),
                if (selectedClassification != null)
                  ElevatedButton(
                    onPressed: () async {
                      try {
                        WriteBatch batch = _firestore.batch();
                        final itemsToRemove = allItems.where((item) =>
                            item.classification == selectedClassification);
                        for (var item in itemsToRemove) {
                          batch.update(
                              _firestore.collection('items').doc(item.id),
                              {'classification': null});
                        }
                        await batch.commit();
                        if (mounted) {
                          Navigator.of(context).pop();
                          _showNotification('Berhasil',
                              'Semua item dari klasifikasi "$selectedClassification" telah dibersihkan.');
                        }
                      } catch (e) {
                        _showNotification(
                            'Gagal', 'Gagal membersihkan klasifikasi: $e',
                            isError: true);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Bersihkan Semua'),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Future<String?> _showEditClassificationDialog(
      BuildContext context, String currentName) {
    TextEditingController controller = TextEditingController(text: currentName);
    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(currentName.isEmpty
              ? 'Tambah Klasifikasi Baru'
              : 'Edit Klasifikasi'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(labelText: 'Nama Klasifikasi'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () {
                if (controller.text.trim().isNotEmpty) {
                  Navigator.of(context).pop(controller.text.trim());
                }
              },
              child: const Text('Simpan'),
            ),
          ],
        );
      },
    );
  }

  void _showNotification(String title, String message, {bool isError = false}) {
    if (!mounted) return;
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

  Future<bool> _requestStoragePermission(BuildContext context) async {
    log('Requesting storage permission...');
    if (defaultTargetPlatform == TargetPlatform.android) {
      DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
      AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;

      if (androidInfo.version.sdkInt >= 30) {
        var status = await Permission.manageExternalStorage.request();
        if (status.isGranted) {
          return true;
        } else if (status.isPermanentlyDenied) {
          if (!context.mounted) return false;
          _showPermissionDeniedDialog(
              context,
              'Izin "Kelola Semua File" diperlukan',
              'Untuk mengimpor/mengekspor file Excel, aplikasi membutuhkan izin "Kelola Semua File". Harap izinkan secara manual di Pengaturan Aplikasi.');
          return false;
        }
      } else {
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

  Future<void> _exportDataToExcel(BuildContext context) async {
    if (!mounted) return;
    setState(() => _isLoadingExport = true);
    try {
      var excel = Excel.createExcel();
      String defaultSheetName = excel.getDefaultSheet()!;
      Sheet sheetObject = excel.sheets[defaultSheetName]!;
      for (int i = 0; i < sheetObject.maxRows; i++) sheetObject.removeRow(0);

      sheetObject.appendRow([
        TextCellValue('Nama Barang'),
        TextCellValue('Barcode'),
        TextCellValue('Kuantitas/Remarks'),
        TextCellValue('Tanggal Ditambahkan'),
        TextCellValue('Expiry Date'),
        TextCellValue('Klasifikasi'),
        TextCellValue('Allowed Departments')
      ]);

      QuerySnapshot snapshot =
          await _firestore.collection('items').orderBy('name').get();
      List<Item> itemsToExport = snapshot.docs
          .map((doc) =>
              Item.fromFirestore(doc.data() as Map<String, dynamic>, doc.id))
          .toList();

      for (var item in itemsToExport) {
        String formattedDate =
            DateFormat('dd-MM-yyyy HH:mm:ss').format(item.createdAt);
        String formattedExpiryDate = item.expiryDate != null
            ? DateFormat('dd-MM-yyyy').format(item.expiryDate!)
            : 'N/A';
        sheetObject.appendRow([
          TextCellValue(item.name),
          TextCellValue(item.barcode),
          TextCellValue(item.quantityOrRemark.toString()),
          TextCellValue(formattedDate),
          TextCellValue(formattedExpiryDate),
          TextCellValue(item.classification ?? 'N/A'),
          TextCellValue(item.allowedDepartments.join(', '))
        ]);
      }
      if (defaultSheetName != 'Daftar Barang')
        excel.rename(defaultSheetName, 'Daftar Barang');
      List<int>? fileBytes = excel.save();
      if (fileBytes != null) {
        final String fileName =
            'Daftar_Barang_Strata${DateTime.now().millisecondsSinceEpoch}.xlsx';
        if (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.linux) {
          final String? resultPath = await FilePicker.platform.saveFile(
              fileName: fileName,
              type: FileType.custom,
              allowedExtensions: ['xlsx']);
          if (!context.mounted) return;
          if (resultPath != null) {
            final File file = File(resultPath);
            await file.writeAsBytes(fileBytes);
            _showNotification(
                'Ekspor Berhasil', 'Data berhasil diekspor ke: $resultPath');
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
          await file.writeAsBytes(fileBytes, flush: true);
          await Share.shareXFiles([XFile(filePath)],
              text: 'Data inventaris Strata');
          if (!context.mounted) return;
          _showNotification('Ekspor Berhasil',
              'Data berhasil diekspor. Pilih aplikasi untuk menyimpan file.');
          log('File Excel berhasil diekspor dan akan dibagikan: $filePath');
        }
      }
    } catch (e) {
      if (!context.mounted) return;
      _showNotification('Ekspor Gagal', 'Error saat ekspor data: $e',
          isError: true);
      log('Error saat ekspor data: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingExport = false);
      }
    }
  }

  Future<void> _importDataFromExcel(BuildContext context) async {
    if (!mounted) return;
    setState(() => _isLoadingImport = true);
    bool hasPermission = await _requestStoragePermission(context);
    if (!hasPermission) {
      if (mounted) setState(() => _isLoadingImport = false);
      return;
    }
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
          type: FileType.custom, allowedExtensions: ['xlsx', 'xls', 'csv']);
      if (!context.mounted) return;
      if (result != null && result.files.single.path != null) {
        File file = File(result.files.single.path!);
        var bytes = file.readAsBytesSync();
        var excel = Excel.decodeBytes(bytes);

        int importedCount = 0;
        int updatedCount = 0;
        int skippedCount = 0;

        String? sheetName = excel.tables.keys.firstWhere(
            (key) => key == 'Daftar Barang',
            orElse: () => excel.tables.keys.first);
        if (sheetName == null) {
          _showNotification('Impor Gagal',
              'File Excel/CSV tidak memiliki sheet yang dapat dibaca.',
              isError: true);
          if (mounted) setState(() => _isLoadingImport = false);
          return;
        }
        Sheet table = excel.tables[sheetName]!;

        final headerRow = table.rows.isNotEmpty
            ? table.rows[0]
                .map((cell) => cell?.value?.toString().trim())
                .toList()
            : [];

        final nameIndex = headerRow.indexOf('Nama Barang');
        final barcodeIndex = headerRow.indexOf('Barcode');
        final quantityOrRemarkIndex = headerRow.indexOf('Kuantitas/Remarks');
        final expiryDateIndex = headerRow.indexOf('Expiry Date');
        final classificationIndex = headerRow.indexOf('Klasifikasi');
        final allowedDepartmentsIndex =
            headerRow.indexOf('Allowed Departments');

        if (nameIndex == -1 ||
            barcodeIndex == -1 ||
            quantityOrRemarkIndex == -1) {
          _showNotification('Impor Gagal',
              'File Excel tidak memiliki semua kolom yang diperlukan (Nama Barang, Barcode, Kuantitas/Remarks).',
              isError: true);
          if (mounted) setState(() => _isLoadingImport = false);
          return;
        }

        WriteBatch batch = _firestore.batch();
        for (int i = 1; i < (table.rows.length); i++) {
          var row = table.rows[i];
          String name = (row.length > nameIndex && row[nameIndex] != null
                  ? row[nameIndex]?.value?.toString()
                  : '') ??
              '';
          String barcode =
              (row.length > barcodeIndex && row[barcodeIndex] != null
                      ? row[barcodeIndex]?.value?.toString()
                      : '') ??
                  '';
          String quantityOrRemarkString = (row.length > quantityOrRemarkIndex &&
                      row[quantityOrRemarkIndex] != null
                  ? row[quantityOrRemarkIndex]?.value?.toString()
                  : '') ??
              '';
          String expiryDateString = (row.length > expiryDateIndex &&
                      expiryDateIndex != -1 &&
                      row[expiryDateIndex] != null
                  ? row[expiryDateIndex]?.value?.toString()
                  : '') ??
              '';
          String classification = (row.length > classificationIndex &&
                      classificationIndex != -1 &&
                      row[classificationIndex] != null
                  ? row[classificationIndex]?.value?.toString()
                  : '') ??
              '';

          List<String> allowedDepartments = [];
          if (allowedDepartmentsIndex != -1 &&
              row.length > allowedDepartmentsIndex &&
              row[allowedDepartmentsIndex] != null) {
            String departmentsString =
                row[allowedDepartmentsIndex]?.value?.toString() ?? '';
            allowedDepartments =
                departmentsString.split(',').map((e) => e.trim()).toList();
          }

          if (name.isEmpty || barcode.isEmpty) {
            log('Skipping row $i: Nama Barang atau Barcode kosong.');
            skippedCount++;
            continue;
          }

          dynamic quantityOrRemark;
          if (int.tryParse(quantityOrRemarkString) != null) {
            quantityOrRemark = int.parse(quantityOrRemarkString);
            if (quantityOrRemark < 0) {
              log('Skipping row $i: Kuantitas harus angka positif atau nol.');
              skippedCount++;
              continue;
            }
          } else {
            quantityOrRemark = quantityOrRemarkString;
            if (quantityOrRemark.isEmpty) {
              log('Skipping row $i: Remarks tidak boleh kosong.');
              skippedCount++;
              continue;
            }
          }

          DateTime? expiryDate;
          if (expiryDateString.isNotEmpty && expiryDateString != 'N/A') {
            try {
              expiryDate = DateFormat('dd-MM-yyyy').parse(expiryDateString);
            } catch (e) {
              log('Skipping row $i: Format Expiry Date tidak valid. Format yang diharapkan: dd-MM-yyyy. Error: $e');
              skippedCount++;
              continue;
            }
          }

          QuerySnapshot existingItems = await _firestore
              .collection('items')
              .where('barcode', isEqualTo: barcode)
              .limit(1)
              .get();

          if (existingItems.docs.isNotEmpty) {
            String itemId = existingItems.docs.first.id;
            batch.update(_firestore.collection('items').doc(itemId), {
              'name': name,
              'barcode': barcode,
              'quantityOrRemark': quantityOrRemark,
              'expiryDate': expiryDate,
              'classification':
                  classification.isNotEmpty ? classification : null,
              'allowedDepartments': allowedDepartments,
            });
            updatedCount++;
            log('Item updated: $name with barcode $barcode');
          } else {
            batch.set(
                _firestore.collection('items').doc(),
                Item(
                  name: name,
                  barcode: barcode,
                  quantityOrRemark: quantityOrRemark,
                  createdAt: DateTime.now(),
                  expiryDate: expiryDate,
                  classification:
                      classification.isNotEmpty ? classification : null,
                  allowedDepartments: allowedDepartments,
                ).toFirestore());
            importedCount++;
            log('Item imported: $name with barcode $barcode');
          }
        }
        await batch.commit();

        if (!context.mounted) {
          setState(() => _isLoadingImport = false);
          return;
        }
        String importSummaryMessage = '';
        if (importedCount > 0)
          importSummaryMessage += '$importedCount item baru berhasil diimpor.';
        if (updatedCount > 0) {
          if (importedCount > 0) importSummaryMessage += '\n';
          importSummaryMessage += '$updatedCount item berhasil diperbarui.';
        }
        if (skippedCount > 0) {
          if (importedCount > 0 || updatedCount > 0)
            importSummaryMessage += '\n';
          importSummaryMessage +=
              '$skippedCount baris dilewati karena data tidak valid.';
        }
        if (importedCount == 0 && updatedCount == 0 && skippedCount == 0) {
          importSummaryMessage =
              'Tidak ada item yang diimpor atau diperbarui dari file Excel.';
        }
        _showNotification('Impor Selesai!', importSummaryMessage,
            isError: (skippedCount > 0));
        log('Ringkasan Impor: $importSummaryMessage');
      } else {
        _showNotification('Impor Dibatalkan', 'Pemilihan file dibatalkan.',
            isError: true);
      }
    } catch (e) {
      if (!context.mounted) return;
      _showNotification('Impor Gagal', 'Error saat impor data: $e',
          isError: true);
      log('Error saat impor data: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingImport = false);
      }
    }
  }

  Future<void> _importClassificationsFromExcel(BuildContext context) async {
    if (!mounted) return;
    setState(() => _isLoadingImport = true);
    bool hasPermission = await _requestStoragePermission(context);
    if (!hasPermission) {
      if (mounted) setState(() => _isLoadingImport = false);
      return;
    }
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
          type: FileType.custom, allowedExtensions: ['xlsx', 'xls', 'csv']);
      if (!context.mounted) return;
      if (result != null && result.files.single.path != null) {
        File file = File(result.files.single.path!);
        var bytes = file.readAsBytesSync();
        var excel = Excel.decodeBytes(bytes);

        String? sheetName = excel.tables.keys.firstWhere(
            (key) => key == 'Daftar Barang',
            orElse: () => excel.tables.keys.first);
        if (sheetName == null) {
          _showNotification('Impor Gagal',
              'File Excel tidak memiliki sheet yang dapat dibaca.',
              isError: true);
          if (mounted) setState(() => _isLoadingImport = false);
          return;
        }
        Sheet table = excel.tables[sheetName]!;
        final headerRow = table.rows.isNotEmpty
            ? table.rows[0]
                .map((cell) => cell?.value?.toString().trim())
                .toList()
            : [];
        final classificationIndex = headerRow.indexOf('Klasifikasi');
        final barcodeIndex = headerRow.indexOf('Barcode');

        if (classificationIndex == -1 || barcodeIndex == -1) {
          _showNotification('Impor Gagal',
              'File Excel harus memiliki kolom "Klasifikasi" dan "Barcode".',
              isError: true);
          if (mounted) setState(() => _isLoadingImport = false);
          return;
        }

        // Phase 1: Update the list of global classifications
        Set<String> newClassifications = {};
        for (int i = 1; i < (table.rows.length); i++) {
          var row = table.rows[i];
          String? classification = (row.length > classificationIndex &&
                      row[classificationIndex] != null
                  ? row[classificationIndex]?.value?.toString()
                  : null) ??
              '';
          if (classification.isNotEmpty && classification != 'N/A') {
            newClassifications.add(classification);
          }
        }

        Set<String> combinedClassifications = Set.from(_classifications);
        combinedClassifications.addAll(newClassifications);

        await _firestore.collection('config').doc('classifications').set({
          'list': combinedClassifications.toList(),
        });

        if (mounted) {
          setState(() {
            _classifications = combinedClassifications.toList();
          });
        }

        // Phase 2: Update items with classifications from the Excel file
        int updatedCount = 0;
        WriteBatch batch = _firestore.batch();

        for (int i = 1; i < (table.rows.length); i++) {
          var row = table.rows[i];
          String? barcode =
              (row.length > barcodeIndex && row[barcodeIndex] != null
                      ? row[barcodeIndex]?.value?.toString()
                      : null) ??
                  '';
          String? classification = (row.length > classificationIndex &&
                      row[classificationIndex] != null
                  ? row[classificationIndex]?.value?.toString()
                  : null) ??
              '';

          if (barcode.isNotEmpty) {
            QuerySnapshot existingItems = await _firestore
                .collection('items')
                .where('barcode', isEqualTo: barcode)
                .limit(1)
                .get();

            if (existingItems.docs.isNotEmpty) {
              String itemId = existingItems.docs.first.id;
              batch.update(_firestore.collection('items').doc(itemId), {
                'classification': (classification != null &&
                        classification.isNotEmpty &&
                        classification != 'N/A')
                    ? classification
                    : null,
              });
              updatedCount++;
            }
          }
        }

        await batch.commit();

        if (mounted) {
          _showNotification('Berhasil',
              '${newClassifications.length} klasifikasi baru diimpor dan $updatedCount item berhasil diperbarui.');
        }
      } else {
        _showNotification('Impor Dibatalkan', 'Pemilihan file dibatalkan.',
            isError: true);
      }
    } catch (e) {
      if (!context.mounted) return;
      _showNotification('Impor Gagal', 'Error saat impor klasifikasi: $e',
          isError: true);
      log('Error saat impor klasifikasi: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingImport = false);
      }
    }
  }

  Future<void> _deleteItem(BuildContext context, String itemId) async {
    bool? confirmDelete = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Konfirmasi Hapus'),
          content: const Text('Apakah Anda yakin ingin menghapus barang ini?'),
          actions: <Widget>[
            TextButton(
              child: const Text('Batal'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            TextButton(
              child: const Text('Hapus', style: TextStyle(color: Colors.red)),
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
          ],
        );
      },
    );
    if (confirmDelete == true) {
      try {
        await _firestore.collection('items').doc(itemId).delete();
        if (!context.mounted) return;
        _showNotification('Berhasil Dihapus', 'Barang berhasil dihapus!');
      } catch (e) {
        if (!context.mounted) return;
        _showNotification('Gagal Menghapus', 'Gagal menghapus barang: $e',
            isError: true);
        log('Error deleting item: $e');
      }
    }
  }

  Widget _buildProductListView(List<Item> filteredItems) {
    if (filteredItems.isEmpty &&
        (_searchQuery.isNotEmpty ||
            _expiryFilter != 'Semua Item' ||
            _stockFilter != 'Semua Item' ||
            _classificationFilter != 'Semua Item')) {
      return const Center(
          child: Text('Barang tidak ditemukan dengan kriteria tersebut.'));
    }
    if (filteredItems.isEmpty &&
        _searchQuery.isEmpty &&
        _expiryFilter == 'Semua Item' &&
        _stockFilter == 'Semua Item' &&
        _classificationFilter == 'Semua Item') {
      return const Center(child: Text('Belum ada barang di inventaris.'));
    }
    return ListView.builder(
      itemCount: filteredItems.length,
      itemBuilder: (context, index) {
        final item = filteredItems[index];
        Color cardColor = Colors.white;
        Color textColor = Colors.black87;

        if (item.quantityOrRemark is int && item.quantityOrRemark == 0) {
          cardColor = Colors.grey[400]!;
          textColor = Colors.white;
        } else if (item.expiryDate != null) {
          final now = DateTime.now();
          final difference = item.expiryDate!.difference(now);
          final differenceInMonths = difference.inDays / 30.44;

          if (item.expiryDate!.isBefore(now)) {
            cardColor = Colors.black87;
            textColor = Colors.white;
          } else if (differenceInMonths <= 5) {
            cardColor = Colors.red[200]!;
          } else if (differenceInMonths <= 6) {
            cardColor = Colors.yellow[200]!;
          } else if (differenceInMonths <= 12) {
            cardColor = Colors.green[200]!;
          }
        }

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          elevation: 3,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          color: cardColor,
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            title: Text(item.name,
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: textColor)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text('Barcode: ${item.barcode}',
                    style: TextStyle(fontSize: 14, color: textColor)),
                Text(
                    item.quantityOrRemark is int
                        ? 'Stok: ${item.quantityOrRemark}'
                        : 'Jenis: Tidak Bisa Dihitung (Remarks: ${item.quantityOrRemark})',
                    style: TextStyle(fontSize: 14, color: textColor)),
                if (item.expiryDate != null)
                  Text(
                      'Expiry Date: ${DateFormat('dd-MM-yyyy').format(item.expiryDate!)}',
                      style: TextStyle(
                          fontSize: 12,
                          color: textColor,
                          fontWeight: FontWeight.bold)),
                if (item.classification != null)
                  Text('Klasifikasi: ${item.classification}',
                      style: TextStyle(
                          fontSize: 12,
                          color: textColor,
                          fontWeight: FontWeight.bold)),
              ],
            ),
            trailing: (_userRole == 'admin' || _userRole == 'dev')
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(Icons.delete, color: textColor),
                        tooltip: 'Hapus Barang',
                        onPressed: () => _deleteItem(context, item.id!),
                      ),
                    ],
                  )
                : null,
          ),
        );
      },
    );
  }

  Widget _buildGroupListView(Map<String, List<Item>> groupedItems) {
    if (groupedItems.isEmpty) {
      return const Center(child: Text('Tidak ada grup yang ditemukan.'));
    }
    return ListView.builder(
      itemCount: groupedItems.keys.length,
      itemBuilder: (context, index) {
        final classification = groupedItems.keys.elementAt(index);
        final items = groupedItems[classification]!;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Card(
            elevation: 3,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            color: Colors.black87,
            child: ExpansionTile(
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      '$classification (${items.length} item)',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.white),
                    ),
                  ),
                  if (_userRole == 'admin' || _userRole == 'dev')
                    IconButton(
                      icon: const Icon(Icons.lock_open, color: Colors.white),
                      tooltip: 'Kelola Akses Departemen',
                      onPressed: () => _manageDepartmentAccess(classification),
                    ),
                ],
              ),
              children: items.map((item) {
                Color iconColor = Colors.white;

                if (item.quantityOrRemark is int &&
                    item.quantityOrRemark == 0) {
                  iconColor = Colors.grey;
                } else if (item.expiryDate != null) {
                  final now = DateTime.now();
                  final difference = item.expiryDate!.difference(now);
                  final differenceInMonths = difference.inDays / 30.44;

                  if (item.expiryDate!.isBefore(now)) {
                    iconColor = Colors.red;
                  } else if (differenceInMonths <= 5) {
                    iconColor = Colors.red;
                  } else if (differenceInMonths <= 6) {
                    iconColor = Colors.yellow;
                  }
                }

                return ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  title: Row(
                    children: [
                      Icon(Icons.circle, size: 10, color: iconColor),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Barcode: ${item.barcode}',
                          style: const TextStyle(color: Colors.white70)),
                      Text(
                          item.quantityOrRemark is int
                              ? 'Stok: ${item.quantityOrRemark}'
                              : 'Remarks: ${item.quantityOrRemark}',
                          style: const TextStyle(color: Colors.white70)),
                      if (item.expiryDate != null)
                        Text(
                            'Exp: ${DateFormat('dd-MM-yyyy').format(item.expiryDate!)}',
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.white)),
                      if (item.classification != null)
                        Text('Klasifikasi: ${item.classification}',
                            style: const TextStyle(
                                fontSize: 12,
                                color: Colors.white,
                                fontWeight: FontWeight.bold)),
                    ],
                  ),
                  trailing: (_userRole == 'admin' || _userRole == 'dev')
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon:
                                  const Icon(Icons.delete, color: Colors.white),
                              tooltip: 'Hapus Barang',
                              onPressed: () => _deleteItem(context, item.id!),
                            ),
                          ],
                        )
                      : null,
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GestureDetector(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Card(
                    margin: EdgeInsets.zero,
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Cari barang...',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8.0),
                              borderSide: BorderSide.none),
                          filled: true,
                          fillColor: Colors.grey[100],
                          contentPadding: const EdgeInsets.symmetric(
                              vertical: 10, horizontal: 10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 15),
                  if (_userRole == 'admin' || _userRole == 'dev')
                    Card(
                      margin: EdgeInsets.zero,
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _isLoadingExport
                                    ? null
                                    : () => _exportDataToExcel(context),
                                icon: _isLoadingExport
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2))
                                    : const Icon(Icons.upload_file),
                                label: Text(_isLoadingExport
                                    ? 'Mengekspor...'
                                    : 'Ekspor Excel'),
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8)),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12)),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _isLoadingImport
                                    ? null
                                    : () => _importDataFromExcel(context),
                                icon: _isLoadingImport
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2))
                                    : const Icon(Icons.download_for_offline),
                                label: Text(_isLoadingImport
                                    ? 'Mengimpor...'
                                    : 'Impor Excel'),
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.indigo,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8)),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 15),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Daftar Barang Inventaris:',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                      const Spacer(),
                      if (_userRole == 'admin' || _userRole == 'dev')
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            IconButton(
                              icon: Icon(
                                  _isGroupView ? Icons.list : Icons.folder_open,
                                  color:
                                      _isGroupView ? Colors.blue : Colors.blue),
                              onPressed: () {
                                setState(() {
                                  _isGroupView = !_isGroupView;
                                  _expiryFilter = 'Semua Item';
                                  _stockFilter = 'Semua Item';
                                  _classificationFilter = 'Semua Item';
                                });
                              },
                            ),
                          ],
                        ),
                    ],
                  ),
                  if (_isGroupView)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () =>
                                  _showMassClassificationDialog(context),
                              icon: const Icon(Icons.playlist_add),
                              label: const Text('Klasifikasi Massal'),
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.teal,
                                  foregroundColor: Colors.white,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _manageClassifications,
                              icon: const Icon(Icons.tune),
                              label: const Text('Kelola Klasifikasi'),
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blueAccent,
                                  foregroundColor: Colors.white,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _isLoadingImport
                                  ? null
                                  : () =>
                                      _importClassificationsFromExcel(context),
                              icon: _isLoadingImport
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          color: Colors.white, strokeWidth: 2))
                                  : const Icon(Icons.download),
                              label: Text(_isLoadingImport
                                  ? 'Mengimpor...'
                                  : 'Impor Klasifikasi'),
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.purple,
                                  foregroundColor: Colors.white,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream:
                    _firestore.collection('items').orderBy('name').snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(child: Text('Error: ${snapshot.error}'));
                  }
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return const Center(
                        child: Text('Belum ada barang di inventaris.'));
                  }

                  List<Item> allItems = snapshot.data!.docs
                      .map((doc) => Item.fromFirestore(
                          doc.data() as Map<String, dynamic>, doc.id))
                      .toList();

                  if (_userRole != 'admin' && _userRole != 'dev') {
                    allItems = allItems.where((item) {
                      return item.allowedDepartments.contains(_userDepartment);
                    }).toList();
                  }

                  if (_isGroupView) {
                    Map<String, List<Item>> groupedItems = {};
                    for (var item in allItems) {
                      final classification =
                          item.classification ?? 'Tidak Terklasifikasi';
                      if (!groupedItems.containsKey(classification)) {
                        groupedItems[classification] = [];
                      }
                      groupedItems[classification]!.add(item);
                    }
                    return _buildGroupListView(groupedItems);
                  } else {
                    List<Item> filteredItems = allItems.where((item) {
                      final String lowerCaseQuery = _searchQuery.toLowerCase();

                      if (!item.name.toLowerCase().contains(lowerCaseQuery) &&
                          !item.barcode
                              .toLowerCase()
                              .contains(lowerCaseQuery)) {
                        return false;
                      }

                      if (_classificationFilter != 'Semua Item' &&
                          item.classification != _classificationFilter) {
                        return false;
                      }

                      if (_stockFilter == 'Stok Habis') {
                        return item.quantityOrRemark is int &&
                            item.quantityOrRemark == 0;
                      }

                      if (_expiryFilter == 'Semua Item') {
                        return true;
                      }

                      if (item.expiryDate == null) {
                        return false;
                      }

                      final now = DateTime.now();
                      final difference = item.expiryDate!.difference(now);
                      final differenceInDays = difference.inDays;

                      if (_expiryFilter == '1 Tahun' &&
                          differenceInDays > 180 &&
                          differenceInDays <= 365) {
                        return true;
                      }
                      if (_expiryFilter == '6 Bulan' &&
                          differenceInDays > 150 &&
                          differenceInDays <= 180) {
                        return true;
                      }
                      if (_expiryFilter == '5 Bulan' &&
                          differenceInDays > 0 &&
                          differenceInDays <= 150) {
                        return true;
                      }
                      if (_expiryFilter == 'Expired' &&
                          item.expiryDate!.isBefore(now)) {
                        return true;
                      }

                      return false;
                    }).toList();

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16.0, vertical: 8.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  value: _expiryFilter,
                                  decoration: InputDecoration(
                                    labelText: 'Filter Kedaluwarsa',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8.0),
                                    ),
                                    contentPadding: EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 5),
                                  ),
                                  items: [
                                    'Semua Item',
                                    'Expired',
                                    '5 Bulan',
                                    '6 Bulan',
                                    '1 Tahun',
                                  ].map<DropdownMenuItem<String>>(
                                      (String value) {
                                    return DropdownMenuItem<String>(
                                      value: value,
                                      child: Text(value),
                                    );
                                  }).toList(),
                                  onChanged: (String? newValue) {
                                    if (newValue != null) {
                                      setState(() {
                                        _expiryFilter = newValue;
                                      });
                                    }
                                  },
                                ),
                              ),
                              const SizedBox(width: 8.0),
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  value: _stockFilter,
                                  decoration: InputDecoration(
                                    labelText: 'Filter Stok',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8.0),
                                    ),
                                    contentPadding: EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 5),
                                  ),
                                  items: [
                                    'Semua Item',
                                    'Stok Habis',
                                  ].map<DropdownMenuItem<String>>(
                                      (String value) {
                                    return DropdownMenuItem<String>(
                                      value: value,
                                      child: Text(value),
                                    );
                                  }).toList(),
                                  onChanged: (String? newValue) {
                                    if (newValue != null) {
                                      setState(() {
                                        _stockFilter = newValue;
                                      });
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16.0, vertical: 8.0),
                          child: Text(
                            'Menampilkan ${filteredItems.length} barang',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ),
                        Expanded(
                          child: _buildProductListView(filteredItems),
                        ),
                      ],
                    );
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
