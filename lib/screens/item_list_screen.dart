// Path: lib/screens/item_list_screen.dart
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

class ItemListScreen extends StatefulWidget {
  const ItemListScreen({super.key});

  @override
  State<ItemListScreen> createState() => _ItemListScreenState();
}

class _ItemListScreenState extends State<ItemListScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  String _expiryFilter = 'Semua Item';
  String _stockFilter = 'Semua Item';

  Timer? _notificationTimer;
  bool _isLoadingExport = false;
  bool _isLoadingImport = false;

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

  Future<bool> _requestStoragePermission(BuildContext context) async {
    log('Requesting storage permission...');
    if (defaultTargetPlatform == TargetPlatform.android) {
      DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
      AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;

      if (androidInfo.version.sdkInt >= 30) {
        var status = await Permission.manageExternalStorage.request();
        log('MANAGE_EXTERNAL_STORAGE Permission Status: $status');
        log('Status details: isGranted=${status.isGranted}, isDenied=${status.isDenied}, isPermanentlyDenied=${status.isPermanentlyDenied}, isRestricted=${status.isRestricted}, isLimited=${status.isLimited}, isProvisional=${status.isProvisional}');

        if (status.isGranted) {
          return true;
        } else if (status.isPermanentlyDenied) {
          if (!context.mounted) return false;
          _showPermissionDeniedDialog(
              context,
              'Izin "Kelola Semua File" diperlukan',
              'Untuk mengimpor/mengekspor file Excel, aplikasi membutuhkan izin "Kelola Semua File". Harap izinkan secara manual di Pengaturan Aplikasi.');
          return false;
        } else {
          if (!context.mounted) return false;
          _showNotification(
              'Izin Ditolak', 'Izin ditolak. Tidak dapat melanjutkan.',
              isError: true);
          return false;
        }
      } else {
        var status = await Permission.storage.request();
        log('STORAGE Permission Status (Legacy): $status');
        log('Status details: isGranted=${status.isGranted}, isDenied=${status.isDenied}, isPermanentlyDenied=${status.isPermanentlyDenied}, isRestricted=${status.isRestricted}, isLimited=${status.isLimited}, isProvisional=${status.isProvisional}');
        if (status.isGranted) {
          return true;
        } else if (status.isPermanentlyDenied) {
          if (!context.mounted) return false;
          _showPermissionDeniedDialog(context, 'Izin Penyimpanan Diperlukan',
              'Untuk mengimpor/mengekspor file Excel, aplikasi membutuhkan izin penyimpanan. Harap izinkan secara manual di Pengaturan Aplikasi.');
          return false;
        } else {
          if (!context.mounted) return false;
          _showNotification(
              'Izin Ditolak', 'Izin ditolak. Tidak dapat melanjutkan.',
              isError: true);
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
      } else {
        if (!context.mounted) return false;
        _showNotification(
            'Izin Ditolak', 'Izin ditolak. Tidak dapat melanjutkan.',
            isError: true);
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
    setState(() {
      _isLoadingExport = true;
    });

    try {
      var excel = Excel.createExcel();
      String defaultSheetName = excel.getDefaultSheet()!;
      Sheet sheetObject = excel.sheets[defaultSheetName]!;

      for (int i = 0; i < sheetObject.maxRows; i++) {
        sheetObject.removeRow(0);
      }

      sheetObject.appendRow([
        TextCellValue('Nama Barang'),
        TextCellValue('Barcode'),
        TextCellValue('Kuantitas/Remarks'),
        TextCellValue('Tanggal Ditambahkan'),
        TextCellValue('Expiry Date')
      ]);

      QuerySnapshot snapshot =
          await _firestore.collection('items').orderBy('name').get();
      List<Item> itemsToExport = snapshot.docs.map((doc) {
        return Item.fromFirestore(doc.data() as Map<String, dynamic>, doc.id);
      }).toList();

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
          TextCellValue(formattedExpiryDate)
        ]);
      }

      if (defaultSheetName != 'Daftar Barang') {
        excel.rename(defaultSheetName, 'Daftar Barang');
        log('Sheet "$defaultSheetName" berhasil diubah namanya menjadi "Daftar Barang".');
      }

      List<int>? fileBytes = excel.save();
      if (fileBytes != null) {
        final String fileName =
            'Daftar_Barang_Strata_Lite_${DateTime.now().millisecondsSinceEpoch}.xlsx';

        if (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.linux) {
          // Logika untuk platform desktop
          final String? resultPath = await FilePicker.platform.saveFile(
            fileName: fileName,
            type: FileType.custom,
            allowedExtensions: ['xlsx'],
          );

          if (!context.mounted) return;

          if (resultPath != null) {
            final File file = File(resultPath);
            await file.writeAsBytes(fileBytes);
            _showNotification(
                'Ekspor Berhasil', 'Data berhasil diekspor ke: $resultPath',
                isError: false);
            log('File Excel berhasil diekspor ke: $resultPath');
          } else {
            _showNotification('Ekspor Dibatalkan',
                'Ekspor dibatalkan atau file tidak disimpan.',
                isError: true);
          }
        } else {
          // Logika untuk platform mobile (Android & iOS)
          final directory = await getApplicationDocumentsDirectory();
          final filePath = '${directory.path}/$fileName';
          final file = File(filePath);
          await file.writeAsBytes(fileBytes, flush: true);

          // Gunakan share_plus untuk membagikan file dan memunculkan pilihan aplikasi
          await Share.shareXFiles([XFile(filePath)],
              text: 'Data inventaris Strata Lite');

          if (!context.mounted) return;
          _showNotification('Ekspor Berhasil',
              'Data berhasil diekspor. Pilih aplikasi untuk menyimpan file.',
              isError: false);
          log('File Excel berhasil diekspor dan akan dibagikan: $filePath');
        }
      } else {
        if (!context.mounted) return;
        _showNotification('Ekspor Gagal', 'Gagal membuat file Excel.',
            isError: true);
      }
    } catch (e) {
      if (!context.mounted) return;
      _showNotification('Ekspor Gagal', 'Error saat ekspor data: $e',
          isError: true);
      log('Error saat ekspor data: $e');
    } finally {
      setState(() {
        _isLoadingExport = false;
      });
    }
  }

  Future<void> _importDataFromExcel(BuildContext context) async {
    setState(() {
      _isLoadingImport = true;
    });

    bool hasPermission = await _requestStoragePermission(context);
    if (!hasPermission) {
      setState(() {
        _isLoadingImport = false;
      });
      return;
    }

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
      );

      if (!context.mounted) {
        setState(() {
          _isLoadingImport = false;
        });
        return;
      }

      if (result != null && result.files.single.path != null) {
        File file = File(result.files.single.path!);
        var bytes = file.readAsBytesSync();
        var excel = Excel.decodeBytes(bytes);

        int importedCount = 0;
        int updatedCount = 0;
        int skippedCount = 0;

        String? sheetName = excel.tables.keys.firstWhere(
          (key) => key == 'Daftar Barang',
          orElse: () => excel.tables.keys.first,
        );

        if (sheetName == null) {
          _showNotification('Impor Gagal',
              'File Excel tidak memiliki sheet yang dapat dibaca.',
              isError: true);
          setState(() {
            _isLoadingImport = false;
          });
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

        if (nameIndex == -1 ||
            barcodeIndex == -1 ||
            quantityOrRemarkIndex == -1) {
          _showNotification('Impor Gagal',
              'File Excel tidak memiliki semua kolom yang diperlukan (Nama Barang, Barcode, Kuantitas/Remarks).',
              isError: true);
          setState(() {
            _isLoadingImport = false;
          });
          return;
        }

        WriteBatch batch = _firestore.batch();

        for (int i = 1; i < (table.rows.length); i++) {
          var row = table.rows[i];

          String name = (row.length > nameIndex
                  ? row[nameIndex]?.value?.toString()
                  : '') ??
              '';
          String barcode = (row.length > barcodeIndex
                  ? row[barcodeIndex]?.value?.toString()
                  : '') ??
              '';
          String quantityOrRemarkString = (row.length > quantityOrRemarkIndex
                  ? row[quantityOrRemarkIndex]?.value?.toString()
                  : '') ??
              '';
          String expiryDateString =
              (row.length > expiryDateIndex && expiryDateIndex != -1
                      ? row[expiryDateIndex]?.value?.toString()
                      : '') ??
                  '';

          if (name.isEmpty || barcode.isEmpty) {
            log('Skipping row $i: Nama Barang atau Barcode kosong.');
            skippedCount++;
            continue;
          }

          dynamic quantityOrRemark;
          if (int.tryParse(quantityOrRemarkString) != null) {
            quantityOrRemark = int.parse(quantityOrRemarkString);
            if (quantityOrRemark <= 0) {
              log('Skipping row $i: Kuantitas harus angka positif.');
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
          if (expiryDateString.isNotEmpty) {
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
            });
            updatedCount++;
            log('Item updated: ${name} with barcode ${barcode}');
          } else {
            batch.set(
                _firestore.collection('items').doc(),
                Item(
                  name: name,
                  barcode: barcode,
                  quantityOrRemark: quantityOrRemark,
                  createdAt: DateTime.now(),
                  expiryDate: expiryDate,
                ).toFirestore());
            importedCount++;
            log('Item imported: ${name} with barcode ${barcode}');
          }
        }

        await batch.commit();

        if (!context.mounted) {
          setState(() {
            _isLoadingImport = false;
          });
          return;
        }

        String importSummaryMessage = '';
        if (importedCount > 0) {
          importSummaryMessage +=
              '${importedCount} item baru berhasil diimpor.';
        }
        if (updatedCount > 0) {
          if (importedCount > 0) importSummaryMessage += '\n';
          importSummaryMessage += '${updatedCount} item berhasil diperbarui.';
        }
        if (skippedCount > 0) {
          if (importedCount > 0 || updatedCount > 0)
            importSummaryMessage += '\n';
          importSummaryMessage +=
              '${skippedCount} baris dilewati karena data tidak valid.';
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
      setState(() {
        _isLoadingImport = false;
      });
    }
  }

  Future<void> _editItem(BuildContext context, Item item) async {
    TextEditingController nameController =
        TextEditingController(text: item.name);
    TextEditingController barcodeController =
        TextEditingController(text: item.barcode);
    TextEditingController quantityOrRemarkController =
        TextEditingController(text: item.quantityOrRemark.toString());
    TextEditingController expiryDateController = TextEditingController(
      text: item.expiryDate != null
          ? DateFormat('dd-MM-yyyy').format(item.expiryDate!)
          : '',
    );
    DateTime? selectedExpiryDate = item.expiryDate;
    bool isQuantityBasedEdit = item.quantityOrRemark is int;

    Item? updatedItem = await showDialog<Item>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setStateSB) {
            return AlertDialog(
              title: const Text('Edit Barang',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Nama Barang',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: barcodeController,
                      decoration: const InputDecoration(
                        labelText: 'Barcode EAN-13',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: expiryDateController,
                      decoration: const InputDecoration(
                        labelText: 'Expiry Date',
                        hintText: 'dd-MM-yyyy',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.calendar_today),
                      ),
                      readOnly: true,
                      onTap: () async {
                        final DateTime? pickedDate = await showDatePicker(
                          context: context,
                          initialDate: selectedExpiryDate ?? DateTime.now(),
                          firstDate: DateTime.now(),
                          lastDate: DateTime(2101),
                        );
                        if (pickedDate != null) {
                          setStateSB(() {
                            selectedExpiryDate = pickedDate;
                            expiryDateController.text =
                                DateFormat('dd-MM-yyyy').format(pickedDate);
                          });
                        }
                      },
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Expiry Date tidak boleh kosong';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Item Berbasis Kuantitas?'),
                        Switch(
                          value: isQuantityBasedEdit,
                          onChanged: (bool value) {
                            setStateSB(() {
                              isQuantityBasedEdit = value;
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    isQuantityBasedEdit
                        ? TextField(
                            controller: quantityOrRemarkController,
                            decoration: const InputDecoration(
                              labelText: 'Kuantitas',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                          )
                        : TextField(
                            controller: quantityOrRemarkController,
                            decoration: const InputDecoration(
                              labelText: 'Remarks',
                              border: OutlineInputBorder(),
                            ),
                            maxLines: 3,
                          ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  child: const Text('Batal'),
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                  },
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Simpan'),
                  onPressed: () {
                    dynamic newQuantityOrRemark;
                    if (isQuantityBasedEdit) {
                      final int? newQuantity =
                          int.tryParse(quantityOrRemarkController.text.trim());
                      if (newQuantity == null || newQuantity <= 0) {
                        _showNotification('Kuantitas Invalid',
                            'Kuantitas harus berupa angka positif.',
                            isError: true);
                        return;
                      }
                      newQuantityOrRemark = newQuantity;
                    } else {
                      final String newRemark =
                          quantityOrRemarkController.text.trim();
                      if (newRemark.isEmpty) {
                        _showNotification(
                            'Remarks Kosong', 'Remarks tidak boleh kosong.',
                            isError: true);
                        return;
                      }
                      newQuantityOrRemark = newRemark;
                    }

                    if (nameController.text.trim().isEmpty ||
                        barcodeController.text.trim().isEmpty) {
                      _showNotification('Input Tidak Lengkap',
                          'Nama barang dan barcode tidak boleh kosong.',
                          isError: true);
                      return;
                    }

                    if (selectedExpiryDate == null) {
                      _showNotification('Input Tidak Lengkap',
                          'Expiry Date tidak boleh kosong.',
                          isError: true);
                      return;
                    }

                    Navigator.of(dialogContext).pop(Item(
                      id: item.id,
                      name: nameController.text.trim(),
                      barcode: barcodeController.text.trim(),
                      quantityOrRemark: newQuantityOrRemark,
                      createdAt: item.createdAt,
                      expiryDate: selectedExpiryDate,
                    ));
                  },
                ),
              ],
            );
          },
        );
      },
    );

    if (updatedItem != null && updatedItem.id != null) {
      try {
        await _firestore
            .collection('items')
            .doc(updatedItem.id)
            .update(updatedItem.toFirestore());
        if (!context.mounted) return;
        _showNotification('Berhasil Diperbarui',
            'Barang "${updatedItem.name}" berhasil diperbarui!',
            isError: false);
      } catch (e) {
        if (!context.mounted) return;
        _showNotification('Gagal Memperbarui', 'Gagal memperbarui barang: $e',
            isError: true);
        log('Error updating item: $e');
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
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
            ),
            TextButton(
              child: const Text('Hapus', style: TextStyle(color: Colors.red)),
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
            ),
          ],
        );
      },
    );

    if (confirmDelete == true) {
      try {
        await _firestore.collection('items').doc(itemId).delete();
        if (!context.mounted) return;
        _showNotification('Berhasil Dihapus', 'Barang berhasil dihapus!',
            isError: false);
      } catch (e) {
        if (!context.mounted) return;
        _showNotification('Gagal Menghapus', 'Gagal menghapus barang: $e',
            isError: true);
        log('Error deleting item: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
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
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.grey[100],
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 10, horizontal: 10),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 15),
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
                                      color: Colors.white, strokeWidth: 2))
                              : const Icon(Icons.upload_file),
                          label: Text(_isLoadingExport
                              ? 'Mengekspor...'
                              : 'Ekspor Excel'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
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
                                      color: Colors.white, strokeWidth: 2))
                              : const Icon(Icons.download_for_offline),
                          label: Text(_isLoadingImport
                              ? 'Mengimpor...'
                              : 'Impor Excel'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.indigo,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 15),
              const Text('Daftar Barang Inventaris:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 10),
              // Filter options for expiry date and stock
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    FilterChip(
                      label: const Text('Semua Item'),
                      selected: _expiryFilter == 'Semua Item' &&
                          _stockFilter == 'Semua Item',
                      onSelected: (selected) {
                        setState(() {
                          _expiryFilter = 'Semua Item';
                          _stockFilter = 'Semua Item';
                        });
                      },
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: const Text('Stok Habis'),
                      selected: _stockFilter == 'Stok Habis',
                      onSelected: (selected) {
                        setState(() {
                          _stockFilter = selected ? 'Stok Habis' : 'Semua Item';
                          if (selected) {
                            _expiryFilter =
                                'Semua Item'; // Reset expiry filter when stock filter is active
                          }
                        });
                      },
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: const Text('Expiring < 1 Tahun'),
                      selected: _expiryFilter == '1 Tahun',
                      onSelected: (selected) {
                        setState(() {
                          _expiryFilter = selected ? '1 Tahun' : 'Semua Item';
                          if (selected) {
                            _stockFilter =
                                'Semua Item'; // Reset stock filter when expiry filter is active
                          }
                        });
                      },
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: const Text('Expiring < 6 Bulan'),
                      selected: _expiryFilter == '6 Bulan',
                      onSelected: (selected) {
                        setState(() {
                          _expiryFilter = selected ? '6 Bulan' : 'Semua Item';
                          if (selected) {
                            _stockFilter =
                                'Semua Item'; // Reset stock filter when expiry filter is active
                          }
                        });
                      },
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: const Text('Expiring < 5 Bulan'),
                      selected: _expiryFilter == '5 Bulan',
                      onSelected: (selected) {
                        setState(() {
                          _expiryFilter = selected ? '5 Bulan' : 'Semua Item';
                          if (selected) {
                            _stockFilter =
                                'Semua Item'; // Reset stock filter when expiry filter is active
                          }
                        });
                      },
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: const Text('Sudah Expired'),
                      selected: _expiryFilter == 'Expired',
                      onSelected: (selected) {
                        setState(() {
                          _expiryFilter = selected ? 'Expired' : 'Semua Item';
                          if (selected) {
                            _stockFilter =
                                'Semua Item'; // Reset stock filter when expiry filter is active
                          }
                        });
                      },
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
            stream: _firestore.collection('items').orderBy('name').snapshots(),
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

              List<Item> allItems = snapshot.data!.docs.map((doc) {
                return Item.fromFirestore(
                    doc.data() as Map<String, dynamic>, doc.id);
              }).toList();

              List<Item> filteredItems = allItems.where((item) {
                final String lowerCaseQuery = _searchQuery.toLowerCase();

                // Filter berdasarkan pencarian
                bool matchesSearch =
                    item.name.toLowerCase().contains(lowerCaseQuery) ||
                        item.barcode.toLowerCase().contains(lowerCaseQuery);
                if (!matchesSearch) return false;

                // Filter berdasarkan stok
                if (_stockFilter == 'Stok Habis') {
                  return item.quantityOrRemark is int &&
                      item.quantityOrRemark == 0;
                }

                // Filter berdasarkan tanggal kedaluwarsa
                if (_expiryFilter == 'Semua Item') {
                  return true;
                }

                if (item.expiryDate == null) {
                  return false; // Item tanpa expiry date tidak akan muncul di filter ini
                }

                final now = DateTime.now();
                final difference = item.expiryDate!.difference(now);
                final differenceInMonths = difference.inDays / 30.44;

                if (_expiryFilter == '1 Tahun' &&
                    differenceInMonths > 6 &&
                    differenceInMonths <= 12) {
                  return true;
                }
                if (_expiryFilter == '6 Bulan' &&
                    differenceInMonths > 5 &&
                    differenceInMonths <= 6) {
                  return true;
                }
                if (_expiryFilter == '5 Bulan' &&
                    differenceInMonths > 0 &&
                    differenceInMonths <= 5) {
                  return true;
                }
                if (_expiryFilter == 'Expired' &&
                    item.expiryDate!.isBefore(now)) {
                  return true;
                }

                return false;
              }).toList();

              if (filteredItems.isEmpty &&
                  (_searchQuery.isNotEmpty ||
                      _expiryFilter != 'Semua Item' ||
                      _stockFilter != 'Semua Item')) {
                return const Center(
                    child: Text(
                        'Barang tidak ditemukan dengan kriteria tersebut.'));
              }
              if (filteredItems.isEmpty &&
                  _searchQuery.isEmpty &&
                  _expiryFilter == 'Semua Item' &&
                  _stockFilter == 'Semua Item') {
                return const Center(
                    child: Text('Belum ada barang diinventaris.'));
              }

              return ListView.builder(
                itemCount: filteredItems.length,
                itemBuilder: (context, index) {
                  final item = filteredItems[index];

                  Color cardColor = Colors.white;
                  Color textColor = Colors.black87;

                  if (item.quantityOrRemark is int &&
                      item.quantityOrRemark == 0) {
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
                    margin:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    elevation: 3,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    color: cardColor,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      title: Text(
                        item.name,
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: textColor),
                      ),
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
                            style: TextStyle(fontSize: 14, color: textColor),
                          ),
                          if (item.expiryDate != null)
                            Text(
                              'Expiry Date: ${DateFormat('dd-MM-yyyy').format(item.expiryDate!)}',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: textColor,
                                  fontWeight: FontWeight.bold),
                            ),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(Icons.edit, color: textColor),
                            tooltip: 'Edit Barang',
                            onPressed: () => _editItem(context, item),
                          ),
                          IconButton(
                            icon: Icon(Icons.delete, color: textColor),
                            tooltip: 'Hapus Barang',
                            onPressed: () => _deleteItem(context, item.id!),
                          ),
                        ],
                      ),
                      onTap: () {
                        log('Detail item ${item.name} diklik');
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
