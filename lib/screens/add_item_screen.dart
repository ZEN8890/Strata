// Path: lib/screens/add_item_screen.dart
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'dart:async';
import 'dart:developer';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:Strata_lite/models/item.dart';
import 'package:another_flushbar/flushbar.dart';
import 'package:intl/intl.dart';

class AddItemScreen extends StatefulWidget {
  const AddItemScreen({super.key});

  @override
  State<AddItemScreen> createState() => _AddItemScreenState();
}

class _AddItemScreenState extends State<AddItemScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _barcodeController = TextEditingController();
  final TextEditingController _quantityController = TextEditingController();
  final TextEditingController _remarkController = TextEditingController();
  final TextEditingController _expiryDateController = TextEditingController();

  MobileScannerController? _scannerController;
  bool _isQuantityBased = true;
  bool _isScanning = false;
  DateTime? _selectedExpiryDate;
  String? _selectedClassification;

  // State baru untuk toggle
  bool _hasExpiryDate = false;
  bool _hasClassification = true;

  Timer? _notificationTimer;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  List<String> _classifications = [];

  @override
  void initState() {
    super.initState();
    _scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
    );
    _fetchClassifications();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _barcodeController.dispose();
    _quantityController.dispose();
    _remarkController.dispose();
    _expiryDateController.dispose();
    _scannerController?.dispose();
    _notificationTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchClassifications() async {
    try {
      final doc =
          await _firestore.collection('config').doc('classifications').get();
      if (doc.exists) {
        final data = doc.data();
        if (data != null && data['list'] is List) {
          if (mounted) {
            setState(() {
              _classifications = List<String>.from(data['list']);
            });
          }
        }
      }
    } catch (e) {
      log('Error fetching classifications: $e');
      _showNotification('Error', 'Gagal memuat klasifikasi. $e', isError: true);
    }
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

  void _addItem() async {
    if (_formKey.currentState?.validate() == false) {
      _showNotification(
          'Input Tidak Lengkap', 'Harap lengkapi semua bidang dengan benar.',
          isError: true);
      return;
    }

    String itemName = _nameController.text.trim();
    String barcode = _barcodeController.text.trim();
    dynamic quantityOrRemark;

    if (_isQuantityBased) {
      int quantity = int.tryParse(_quantityController.text.trim()) ?? 0;
      if (quantity <= 0) {
        _showNotification('Kuantitas Invalid', 'Kuantitas harus lebih dari 0.',
            isError: true);
        return;
      }
      quantityOrRemark = quantity;
    } else {
      String remark = _remarkController.text.trim();
      if (remark.isEmpty) {
        _showNotification('Remarks Kosong',
            'Remarks tidak boleh kosong untuk item non-kuantitas.',
            isError: true);
        return;
      }
      quantityOrRemark = remark;
    }

    if (barcode.length != 13) {
      _showNotification('Barcode Invalid', 'Barcode harus 13 digit (EAN-13).',
          isError: true);
      return;
    }

    if (_hasClassification &&
        (_selectedClassification == null || _selectedClassification!.isEmpty)) {
      _showNotification('Klasifikasi Kosong', 'Harap pilih klasifikasi item.',
          isError: true);
      return;
    }

    if (_hasExpiryDate && _selectedExpiryDate != null) {
      if (_selectedExpiryDate!.isBefore(DateTime.now())) {
        _showNotification('Tanggal Kedaluwarsa Invalid',
            'Tanggal kedaluwarsa tidak boleh di masa lalu.',
            isError: true);
        return;
      }
    }

    try {
      QuerySnapshot existingItems = await _firestore
          .collection('items')
          .where('barcode', isEqualTo: barcode)
          .limit(1)
          .get();

      if (existingItems.docs.isNotEmpty) {
        String existingItemName =
            (existingItems.docs.first.data() as Map<String, dynamic>)['name'] ??
                'Tidak Dikenal';
        _showNotification('Barcode Duplikat',
            'Barcode ini sudah terdaftar untuk item "$existingItemName".',
            isError: true);
        return;
      }

      Item newItem = Item(
        name: itemName,
        barcode: barcode,
        quantityOrRemark: quantityOrRemark,
        createdAt: DateTime.now(),
        expiryDate: _hasExpiryDate ? _selectedExpiryDate : null,
        classification: _hasClassification ? _selectedClassification : null,
      );

      await _firestore.collection('items').add(newItem.toFirestore());

      _showNotification(
          'Berhasil!', 'Barang "${newItem.name}" berhasil ditambahkan!',
          isError: false);
      log('Item added: Name: $itemName, Barcode: $barcode, Type: ${_isQuantityBased ? "Quantity" : "Remark"}, Value: $quantityOrRemark');

      FocusScope.of(context).unfocus();
      if (mounted) {
        setState(() {
          _nameController.clear();
          _barcodeController.clear();
          _quantityController.clear();
          _remarkController.clear();
          _expiryDateController.clear();
          _selectedExpiryDate = null;
          _isQuantityBased = true;
          _selectedClassification = null;
          _hasExpiryDate = false;
          _hasClassification = true;
        });
      }
    } catch (e) {
      _showNotification(
          'Gagal Menambahkan Barang', 'Gagal menambahkan barang: $e',
          isError: true);
      log('Error adding item: $e');
    }
  }

  Future<void> _selectExpiryDate(BuildContext context) async {
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedExpiryDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2101),
    );
    if (pickedDate != null && pickedDate != _selectedExpiryDate) {
      if (mounted) {
        setState(() {
          _selectedExpiryDate = pickedDate;
          _expiryDateController.text =
              DateFormat('dd-MM-yyyy').format(pickedDate);
        });
      }
    }
  }

  void _startScanBarcode() {
    setState(() {
      _isScanning = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scannerController?.start();
    });
  }

  void _onBarcodeDetected(BarcodeCapture capture) {
    if (capture.barcodes.isNotEmpty) {
      final Barcode detectedBarcode = capture.barcodes.first;
      final String? barcodeValue = detectedBarcode.rawValue;

      log('Detected barcode value: $barcodeValue');
      log('Detected barcode format: ${detectedBarcode.format}');

      if (barcodeValue != null && barcodeValue.length == 13) {
        _barcodeController.text = barcodeValue;
        _showNotification('Barcode Terdeteksi', 'Barcode EAN-13: $barcodeValue',
            isError: false);

        setState(() {
          _isScanning = false;
        });
        _scannerController?.stop();
      } else {
        _showNotification(
            'Barcode Invalid', 'Barcode tidak valid atau bukan EAN-13.',
            isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final Size screenSize = MediaQuery.of(context).size;

    final double scanWidth = screenSize.width * 0.7;
    final double scanHeight = screenSize.height * 0.15;
    final double scanLeft = (screenSize.width - scanWidth) / 2;
    final double scanTop =
        (screenSize.height / 2) - (scanHeight / 2) - (screenSize.height * 0.15);

    final Rect scanWindowRect = Rect.fromLTRB(
      scanLeft,
      scanTop,
      scanLeft + scanWidth,
      scanTop + scanHeight,
    );

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: _isScanning
          ? Stack(
              children: [
                MobileScanner(
                  controller: _scannerController,
                  onDetect: _onBarcodeDetected,
                  scanWindow: scanWindowRect,
                ),
                Positioned(
                  left: scanWindowRect.left,
                  top: scanWindowRect.top,
                  width: scanWindowRect.width,
                  height: scanWindowRect.height,
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.red, width: 4),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 16,
                  left: 16,
                  right: 16,
                  child: ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _isScanning = false;
                      });
                      _scannerController?.stop();
                    },
                    child: const Text('Batalkan Scan'),
                  ),
                ),
              ],
            )
          : Form(
              key: _formKey,
              child: ListView(
                children: [
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Nama Barang',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Nama Barang tidak boleh kosong';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 15),
                  TextFormField(
                    controller: _barcodeController,
                    decoration: InputDecoration(
                      labelText: 'Barcode EAN-13',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.qr_code_scanner),
                        onPressed: _startScanBarcode,
                      ),
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Barcode tidak boleh kosong';
                      }
                      if (value.length != 13) {
                        return 'Barcode harus 13 digit (EAN-13)';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 15),
                  Row(
                    children: [
                      const Text('Punya Klasifikasi?'),
                      Switch(
                        value: _hasClassification,
                        onChanged: (bool value) {
                          setState(() {
                            _hasClassification = value;
                            if (!value) {
                              _selectedClassification = null;
                            }
                          });
                        },
                      ),
                    ],
                  ),
                  if (_hasClassification)
                    DropdownButtonFormField<String>(
                      value: _selectedClassification,
                      decoration: const InputDecoration(
                        labelText: 'Klasifikasi Item',
                        border: OutlineInputBorder(),
                      ),
                      items: _classifications.map((String classification) {
                        return DropdownMenuItem<String>(
                          value: classification,
                          child: Text(classification),
                        );
                      }).toList(),
                      onChanged: (String? newValue) {
                        setState(() {
                          _selectedClassification = newValue;
                        });
                      },
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Klasifikasi tidak boleh kosong';
                        }
                        return null;
                      },
                    ),
                  const SizedBox(height: 15),
                  Row(
                    children: [
                      const Text('Item Berbasis Kuantitas?'),
                      Switch(
                        value: _isQuantityBased,
                        onChanged: (bool value) {
                          setState(() {
                            _isQuantityBased = value;
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 15),
                  if (_isQuantityBased)
                    TextFormField(
                      controller: _quantityController,
                      decoration: const InputDecoration(
                        labelText: 'Kuantitas Awal',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Kuantitas tidak boleh kosong';
                        }
                        if (int.tryParse(value) == null ||
                            int.parse(value) <= 0) {
                          return 'Kuantitas harus berupa angka positif';
                        }
                        return null;
                      },
                    )
                  else
                    TextFormField(
                      controller: _remarkController,
                      decoration: const InputDecoration(
                        labelText: 'Remarks (Contoh: Cairan, Tidak Habis)',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 3,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Remarks tidak boleh kosong';
                        }
                        return null;
                      },
                    ),
                  const SizedBox(height: 15),
                  Row(
                    children: [
                      const Text('Punya Expiry Date?'),
                      Switch(
                        value: _hasExpiryDate,
                        onChanged: (bool value) {
                          setState(() {
                            _hasExpiryDate = value;
                            if (!value) {
                              _selectedExpiryDate = null;
                              _expiryDateController.clear();
                            }
                          });
                        },
                      ),
                    ],
                  ),
                  if (_hasExpiryDate)
                    TextFormField(
                      controller: _expiryDateController,
                      decoration: const InputDecoration(
                        labelText: 'Expiry Date',
                        hintText: 'dd-MM-yyyy',
                        border: OutlineInputBorder(),
                        suffixIcon: Icon(Icons.calendar_today),
                      ),
                      readOnly: true,
                      onTap: () => _selectExpiryDate(context),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Tanggal kedaluwarsa tidak boleh kosong';
                        }
                        return null;
                      },
                    ),
                  const SizedBox(height: 20),
                  Center(
                    child: ElevatedButton(
                      onPressed: _addItem,
                      child: const Text('Tambahkan Barang'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
