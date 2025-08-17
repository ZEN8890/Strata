// Path: lib/screens/take_item_screen.dart
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'dart:async';
import 'dart:developer';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:Strata_lite/models/item.dart';
import 'package:Strata_lite/models/log_entry.dart';
import 'package:another_flushbar/flushbar.dart';
import 'package:audioplayers/audioplayers.dart';

class TakeItemScreen extends StatefulWidget {
  const TakeItemScreen({super.key});

  @override
  State<TakeItemScreen> createState() => _TakeItemScreenState();
}

class _TakeItemScreenState extends State<TakeItemScreen> {
  final TextEditingController _barcodeController = TextEditingController();
  final TextEditingController _quantityController = TextEditingController();
  final TextEditingController _remarksController = TextEditingController();

  MobileScannerController? _scannerController;
  bool _isLoading = false;
  bool _isScanning = false;
  Timer? _alertTimer;

  Timer? _notificationTimer;

  Item? _scannedItem;
  bool _isQuantityBased = true;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  final AudioPlayer _audioPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
    );
  }

  @override
  void dispose() {
    _barcodeController.dispose();
    _quantityController.dispose();
    _remarksController.dispose();
    _scannerController?.stop();
    _scannerController?.dispose();
    _alertTimer?.cancel();
    _notificationTimer?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _playScanSound() async {
    try {
      await _audioPlayer.play(AssetSource('sounds/Beep.mp3'));
    } catch (e) {
      log('Error playing sound: $e');
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

  void _startScanBarcode() {
    setState(() {
      _isScanning = true;
      _scannedItem = null;
      _barcodeController.clear();
      _quantityController.clear();
      _remarksController.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scannerController?.start();
    });
  }

  void _onBarcodeDetected(BarcodeCapture capture) {
    if (_alertTimer != null && _alertTimer!.isActive) {
      return;
    }

    if (capture.barcodes.isNotEmpty) {
      final Barcode detectedBarcode = capture.barcodes.first;
      final String? barcodeValue = detectedBarcode.rawValue;

      log('Scanned barcode result: $barcodeValue (Format: ${detectedBarcode.format})');

      if (barcodeValue != null && barcodeValue.length == 13) {
        _barcodeController.text = barcodeValue;
        _showNotification(
            'Barcode Ditemukan', 'Barcode EAN-13 terdeteksi: $barcodeValue');

        _playScanSound();

        setState(() {
          _isScanning = false;
        });
        _scannerController?.stop();

        _fetchItemDetails(barcodeValue);
      } else {
        _showNotification(
            'Barcode Invalid', 'Barcode tidak valid atau bukan EAN-13.',
            isError: true);
      }
    }
  }

  Future<void> _fetchItemDetails(String barcode) async {
    setState(() {
      _isLoading = true;
      _scannedItem = null;
      _quantityController.clear();
      _remarksController.clear();
    });

    try {
      QuerySnapshot snapshot = await _firestore
          .collection('items')
          .where('barcode', isEqualTo: barcode)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        DocumentSnapshot itemDoc = snapshot.docs.first;
        setState(() {
          _scannedItem = Item.fromFirestore(
              itemDoc.data() as Map<String, dynamic>, itemDoc.id);
          _isQuantityBased = _scannedItem!.quantityOrRemark is int;
          _isLoading = false;
        });
        _showNotification('Item Ditemukan',
            'Barcode: $barcode\nNama Item: ${_scannedItem!.name}');
      } else {
        setState(() {
          _isLoading = false;
        });
        _showNotification('Item Tidak Ditemukan',
            'Item dengan barcode "$barcode" tidak ditemukan.',
            isError: true);
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showNotification(
          'Gagal Mengambil Item', 'Error mengambil detail item: $e',
          isError: true);
      log('Error fetching item details: $e');
    }
  }

  Future<void> _takeItem() async {
    if (_scannedItem == null) {
      _showNotification('Item Belum Dipindai',
          'Silakan pindai atau masukkan barcode item terlebih dahulu.',
          isError: true);
      return;
    }

    if (_isQuantityBased) {
      int? quantityTaken = int.tryParse(_quantityController.text.trim());
      if (quantityTaken == null || quantityTaken <= 0) {
        _showNotification(
            'Kuantitas Invalid', 'Kuantitas yang diambil harus lebih dari 0.',
            isError: true);
        return;
      }
      if (quantityTaken > _scannedItem!.quantityOrRemark) {
        _showNotification('Stok Tidak Cukup',
            'Kuantitas yang diambil ($quantityTaken) melebihi stok yang tersedia (${_scannedItem!.quantityOrRemark}).',
            isError: true);
        return;
      }

      try {
        await _firestore.collection('items').doc(_scannedItem!.id).update({
          'quantityOrRemark': FieldValue.increment(-quantityTaken),
        });

        // Ambil dokumen terbaru setelah update
        DocumentSnapshot updatedItemDoc =
            await _firestore.collection('items').doc(_scannedItem!.id).get();
        int? updatedStock =
            (updatedItemDoc.data() as Map<String, dynamic>)['quantityOrRemark'];

        _showNotification('Stok Berhasil Dikurangi',
            'Stok item "${_scannedItem!.name}" dikurangi sebanyak $quantityTaken. Sisa Stok: $updatedStock',
            isError: false);

        await _addLogEntry(
          _scannedItem!,
          quantityTaken,
          remarks: _remarksController.text.trim().isEmpty
              ? null
              : _remarksController.text.trim(),
          remainingStock: updatedStock,
        );
      } catch (e) {
        _showNotification('Gagal Mengurangi Stok', 'Gagal mengurangi stok: $e',
            isError: true);
        log('Error reducing stock: $e');
        return;
      }
    } else {
      String remarks = _remarksController.text.trim();
      if (remarks.isEmpty) {
        _showNotification('Remarks Kosong',
            'Remarks pengambilan tidak boleh kosong untuk item ini.',
            isError: true);
        return;
      }
      await _addLogEntry(_scannedItem!, remarks, remarks: remarks);
      _showNotification('Pengambilan Dicatat',
          'Pengambilan item "${_scannedItem!.name}" dicatat.',
          isError: false);
    }

    setState(() {
      _barcodeController.clear();
      _quantityController.clear();
      _remarksController.clear();
      _isLoading = false;
      _scannedItem = null;
    });
  }

  Future<void> _addLogEntry(Item item, dynamic quantityOrRemark,
      {String? remarks, int? remainingStock}) async {
    User? currentUser = _auth.currentUser;
    String staffName = currentUser?.email ?? 'Unknown User';
    String staffDepartment = 'Unknown Department';

    if (currentUser != null) {
      try {
        DocumentSnapshot userDoc =
            await _firestore.collection('users').doc(currentUser.uid).get();
        if (userDoc.exists) {
          Map<String, dynamic> userData =
              userDoc.data() as Map<String, dynamic>;
          staffName = userData['name'] ?? currentUser.email ?? 'Unknown User';
          staffDepartment = userData['department'] ?? 'Unknown Department';
        }
      } catch (e) {
        log('Error fetching staff details for log entry: $e');
      }
    }

    LogEntry newLog = LogEntry(
      itemName: item.name,
      barcode: item.barcode,
      quantityOrRemark: quantityOrRemark,
      timestamp: DateTime.now(),
      staffName: staffName,
      staffDepartment: staffDepartment,
      remarks: remarks,
      remainingStock: remainingStock,
    );

    try {
      await _firestore.collection('log_entries').add(newLog.toFirestore());
      log('Log entry added for ${item.name}');
    } catch (e) {
      _showNotification(
          'Gagal Mencatat Log', 'Gagal mencatat log pengambilan: $e',
          isError: true);
      log('Error adding log entry: $e');
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
        scanLeft, scanTop, scanLeft + scanWidth, scanTop + scanHeight);

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: GestureDetector(
        onTap: () {
          FocusScope.of(context).unfocus();
        },
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
            : ListView(
                children: [
                  const SizedBox(height: 20),
                  TextField(
                    controller: _barcodeController,
                    readOnly: _isLoading,
                    decoration: InputDecoration(
                      labelText: 'Barcode EAN-13',
                      border: const OutlineInputBorder(),
                      suffixIcon: _isLoading
                          ? const Padding(
                              padding: EdgeInsets.all(8.0),
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : IconButton(
                              icon: const Icon(Icons.qr_code_scanner),
                              onPressed: _startScanBarcode,
                            ),
                    ),
                    keyboardType: TextInputType.number,
                    onSubmitted: (value) {
                      if (value.length == 13) {
                        _fetchItemDetails(value);
                      } else {
                        _showNotification(
                            'Barcode Invalid', 'Barcode harus 13 digit.',
                            isError: true);
                      }
                    },
                  ),
                  const SizedBox(height: 15),
                  if (_scannedItem != null) ...[
                    Card(
                      margin: const EdgeInsets.symmetric(vertical: 10),
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Nama Barang: ${_scannedItem!.name}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            Text('Barcode: ${_scannedItem!.barcode}'),
                            Text(
                                'Stok Tersedia: ${_scannedItem!.quantityOrRemark.toString()}'),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 15),
                    if (_isQuantityBased)
                      TextField(
                        controller: _quantityController,
                        decoration: InputDecoration(
                          labelText: 'Kuantitas yang Diambil',
                          border: const OutlineInputBorder(),
                          hintText:
                              'Stok tersedia: ${_scannedItem!.quantityOrRemark}',
                        ),
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (value) {
                          FocusScope.of(context).unfocus();
                        },
                      )
                    else
                      TextField(
                        controller: _remarksController,
                        decoration: const InputDecoration(
                          labelText: 'Remarks Pengambilan',
                          border: OutlineInputBorder(),
                          hintText: 'Contoh: Untuk P3K di ruang rapat',
                        ),
                        maxLines: 3,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (value) {
                          FocusScope.of(context).unfocus();
                        },
                      ),
                    const SizedBox(height: 20),
                    Center(
                      child: ElevatedButton(
                        onPressed: _takeItem,
                        child: const Text('Ambil Barang'),
                      ),
                    ),
                  ] else if (_isLoading) ...[
                    const Center(child: CircularProgressIndicator()),
                    const SizedBox(height: 10),
                    const Text('Mencari detail item...',
                        textAlign: TextAlign.center),
                  ] else ...[
                    const Center(
                        child: Text(
                            'Pindai barcode atau masukkan secara manual untuk mengambil barang.')),
                  ],
                ],
              ),
      ),
    );
  }
}
