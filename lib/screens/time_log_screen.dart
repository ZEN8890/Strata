// Path: lib/screens/time_log_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:Strata_lite/models/log_entry.dart';
import 'package:Strata_lite/models/item.dart';
import 'dart:developer';
import 'package:intl/intl.dart';
import 'dart:async';
import 'package:another_flushbar/flushbar.dart';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

class TimeLogScreen extends StatefulWidget {
  const TimeLogScreen({super.key});

  @override
  State<TimeLogScreen> createState() => _TimeLogScreenState();
}

class _TimeLogScreenState extends State<TimeLogScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  Timer? _notificationTimer;
  bool _isLoadingExport = false;
  bool _isLoadingDelete = false;

  DateTime? _selectedStartDate;
  DateTime? _selectedEndDate;
  TimeOfDay? _selectedStartTime;
  TimeOfDay? _selectedEndTime;
  String? _selectedDepartment;

  List<String> _dynamicDepartments = ['Semua Departemen'];
  bool _isDepartmentsLoading = true;

  final GlobalKey _filterSectionKey = GlobalKey();
  double _filterSectionHeight = 0;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _loadDepartments();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureFilterSectionHeight();
    });
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

  void _measureFilterSectionHeight() {
    final RenderBox? renderBox =
        _filterSectionKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox != null) {
      if (_filterSectionHeight != renderBox.size.height) {
        setState(() {
          _filterSectionHeight = renderBox.size.height + 10.0;
          log('Filter Section Height measured: $_filterSectionHeight');
        });
      }
    }
  }

  void _showNotification(
    String title,
    String message, {
    bool isError = false,
  }) {
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

  Future<void> _loadDepartments() async {
    setState(() {
      _isDepartmentsLoading = true;
    });
    try {
      QuerySnapshot usersSnapshot = await _firestore.collection('users').get();
      Set<String> uniqueDepartments = {};

      for (var doc in usersSnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final department = data['department'] as String?;
        if (department != null && department.isNotEmpty) {
          uniqueDepartments.add(department);
        }
      }

      setState(() {
        _dynamicDepartments = [
          'Semua Departemen',
          ...uniqueDepartments.toList()..sort()
        ];
        _selectedDepartment ??= _dynamicDepartments.first;
        _isDepartmentsLoading = false;
      });
      log('Dynamic departments loaded: $_dynamicDepartments');
    } catch (e) {
      log('Error loading departments: $e');
      setState(() {
        _dynamicDepartments = ['Semua Departemen'];
        _selectedDepartment = _dynamicDepartments.first;
        _isDepartmentsLoading = false;
      });
      _showNotification(
        'Error',
        'Gagal memuat daftar departemen.',
        isError: true,
      );
    }
  }

  Future<void> _selectDate(BuildContext context,
      {required bool isStartDate}) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        if (isStartDate) {
          _selectedStartDate = picked;
          if (_selectedEndDate != null && _selectedEndDate!.isBefore(picked)) {
            _selectedEndDate = picked;
          }
        } else {
          _selectedEndDate = picked;
          if (_selectedStartDate != null &&
              _selectedStartDate!.isAfter(picked)) {
            _selectedStartDate = picked;
          }
        }
      });
    }
  }

  Future<void> _selectTime(BuildContext context,
      {required bool isStartTime}) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (picked != null) {
      setState(() {
        if (isStartTime) {
          _selectedStartTime = picked;
        } else {
          _selectedEndTime = picked;
        }
      });
    }
  }

  void _clearFilters() {
    setState(() {
      _searchController.clear();
      _searchQuery = '';
      _selectedStartDate = null;
      _selectedEndDate = null;
      _selectedStartTime = null;
      _selectedEndTime = null;
      _selectedDepartment = 'Semua Departemen';
    });
    _showNotification('Filter Direset', 'Semua filter telah dihapus.');
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
            'Izin Ditolak',
            'Izin ditolak. Tidak dapat melanjutkan.',
            isError: true,
          );
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
              'Untuk mengimpor/mengekspor file Excel, aplikasi membutuhkan izin penyimpanan. Harap izinkan secara manually di Pengaturan Aplikasi.');
          return false;
        } else {
          if (!context.mounted) return false;
          _showNotification(
            'Izin Ditolak',
            'Izin ditolak. Tidak dapat melanjutkan.',
            isError: true,
          );
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
          'Izin Ditolak',
          'Izin ditolak. Tidak dapat melanjutkan.',
          isError: true,
        );
        return false;
      }
    } else if (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux) {
      log('Platform desktop, assuming file access is granted.');
      return true;
    }
    _showNotification(
      'Platform Tidak Didukung',
      'Platform ini tidak didukung untuk operasi file.',
      isError: true,
    );
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

  Future<void> _exportLogsToExcel(BuildContext context) async {
    setState(() {
      _isLoadingExport = true;
    });

    try {
      var excel = Excel.createExcel();
      String defaultSheetName = excel.getDefaultSheet()!;
      Sheet sheetObject = excel.sheets[defaultSheetName]!;

      for (int i = sheetObject.maxRows - 1; i >= 0; i--) {
        sheetObject.removeRow(i);
      }

      sheetObject.appendRow([
        TextCellValue('Nama Barang'),
        TextCellValue('Barcode'),
        TextCellValue('Kuantitas/Remarks'),
        TextCellValue('Tanggal & Waktu'),
        TextCellValue('Nama Staff'),
        TextCellValue('Departemen'),
        TextCellValue('Remarks Pengambilan'),
      ]);

      QuerySnapshot snapshot = await _firestore
          .collection('log_entries')
          .orderBy('timestamp', descending: true)
          .get();

      List<LogEntry> allLogs = snapshot.docs.map((doc) {
        return LogEntry.fromFirestore(
            doc.data() as Map<String, dynamic>, doc.id);
      }).toList();

      List<LogEntry> filteredLogs = allLogs.where((logEntry) {
        final String lowerCaseQuery = _searchQuery.toLowerCase();
        bool matchesSearch = logEntry.itemName
                .toLowerCase()
                .contains(lowerCaseQuery) ||
            logEntry.barcode.toLowerCase().contains(lowerCaseQuery) ||
            logEntry.staffName.toLowerCase().contains(lowerCaseQuery) ||
            logEntry.staffDepartment.toLowerCase().contains(lowerCaseQuery) ||
            (logEntry.remarks?.toLowerCase().contains(lowerCaseQuery) ?? false);

        if (!matchesSearch) return false;

        if (_selectedStartTime != null) {
          DateTime logTime = logEntry.timestamp;
          TimeOfDay entryTime =
              TimeOfDay(hour: logTime.hour, minute: logTime.minute);
          int startMinutes =
              _selectedStartTime!.hour * 60 + _selectedStartTime!.minute;
          int entryMinutes = entryTime.hour * 60 + entryTime.minute;
          if (entryMinutes < startMinutes) {
            return false;
          }
        }
        if (_selectedEndTime != null) {
          DateTime logTime = logEntry.timestamp;
          TimeOfDay entryTime =
              TimeOfDay(hour: logTime.hour, minute: logTime.minute);
          int endMinutes =
              _selectedEndTime!.hour * 60 + _selectedEndTime!.minute;
          int entryMinutes = entryTime.hour * 60 + entryTime.minute;
          if (entryMinutes > endMinutes) {
            return false;
          }
        }
        if (_selectedStartDate != null) {
          DateTime logDate = DateTime(logEntry.timestamp.year,
              logEntry.timestamp.month, logEntry.timestamp.day);
          DateTime startDate = DateTime(_selectedStartDate!.year,
              _selectedStartDate!.month, _selectedStartDate!.day);
          if (logDate.isBefore(startDate)) return false;
        }
        if (_selectedEndDate != null) {
          DateTime logDate = DateTime(logEntry.timestamp.year,
              logEntry.timestamp.month, logEntry.timestamp.day);
          DateTime endDate = DateTime(_selectedEndDate!.year,
              _selectedEndDate!.month, _selectedEndDate!.day);
          if (logDate.isAfter(endDate)) return false;
        }

        if (_selectedDepartment != null &&
            _selectedDepartment != 'Semua Departemen') {
          if (logEntry.staffDepartment != _selectedDepartment) return false;
        }

        return true;
      }).toList();

      for (var logEntry in filteredLogs) {
        String formattedDateTime =
            '${logEntry.timestamp.day.toString().padLeft(2, '0')}-'
            '${logEntry.timestamp.month.toString().padLeft(2, '0')}-'
            '${logEntry.timestamp.year} '
            '${logEntry.timestamp.hour.toString().padLeft(2, '0')}:'
            '${logEntry.timestamp.minute.toString().padLeft(2, '0')}:'
            '${logEntry.timestamp.second.toString().padLeft(2, '0')}';

        sheetObject.appendRow([
          TextCellValue(logEntry.itemName),
          TextCellValue(logEntry.barcode),
          TextCellValue(logEntry.quantityOrRemark.toString()),
          TextCellValue(formattedDateTime),
          TextCellValue(logEntry.staffName),
          TextCellValue(logEntry.staffDepartment),
          TextCellValue(logEntry.remarks ?? ''),
        ]);
      }

      if (defaultSheetName != 'Log Pengambilan Barang') {
        excel.rename(defaultSheetName, 'Log Pengambilan Barang');
        log('Sheet "$defaultSheetName" berhasil diubah namanya menjadi "Log Pengambilan Barang".');
      }

      List<int>? fileBytes = excel.save();
      if (fileBytes != null) {
        final String fileName =
            'Log_Pengambilan_Strata_Lite_${DateTime.now().millisecondsSinceEpoch}.xlsx';

        if (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.linux) {
          // Logic for desktop platforms
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
            _showNotification(
                'Ekspor Dibatalkan', 'Ekspor dibatalkan oleh pengguna.',
                isError: true);
          }
        } else {
          // Logic for mobile platforms (Android & iOS)
          final directory = await getApplicationDocumentsDirectory();
          final filePath = '${directory.path}/$fileName';
          final file = File(filePath);
          await file.writeAsBytes(fileBytes, flush: true);

          await Share.shareXFiles([XFile(filePath)],
              text: 'Data log Strata Lite');

          if (!context.mounted) return;
          _showNotification('Ekspor Berhasil',
              'Data berhasil diekspor ke aplikasi pengelola file.',
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
      _showNotification('Ekspor Gagal', 'Error saat ekspor log: $e',
          isError: true);
      log('Error saat ekspor log: $e');
    } finally {
      setState(() {
        _isLoadingExport = false;
      });
    }
  }

  Future<void> _clearLogsByDateRange() async {
    DateTime? startDateToDelete;
    DateTime? endDateToDelete;

    startDateToDelete = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'Pilih Tanggal Mulai Hapus Log',
    );
    if (!context.mounted || startDateToDelete == null) return;

    endDateToDelete = await showDatePicker(
      context: context,
      initialDate: startDateToDelete,
      firstDate: startDateToDelete,
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'Pilih Tanggal Akhir Hapus Log',
    );
    if (!context.mounted || endDateToDelete == null) return;

    if (startDateToDelete.isAfter(endDateToDelete)) {
      _showNotification('Tanggal Invalid',
          'Tanggal mulai tidak boleh lebih dari tanggal akhir.',
          isError: true);
      return;
    }

    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Konfirmasi Hapus Log'),
        content: Text(
            'Anda yakin ingin menghapus semua log dari ${DateFormat('dd-MM-yyyy').format(startDateToDelete!)} sampai ${DateFormat('dd-MM-yyyy').format(endDateToDelete!)}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Hapus', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (!context.mounted || confirm != true) return;

    setState(() {
      _isLoadingDelete = true;
    });

    try {
      QuerySnapshot logsToDelete = await _firestore
          .collection('log_entries')
          .where('timestamp',
              isGreaterThanOrEqualTo: DateTime(startDateToDelete.year,
                  startDateToDelete.month, startDateToDelete.day))
          .where('timestamp',
              isLessThanOrEqualTo: DateTime(endDateToDelete.year,
                  endDateToDelete.month, endDateToDelete.day, 23, 59, 59, 999))
          .get();

      WriteBatch batch = _firestore.batch();
      for (var doc in logsToDelete.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      _showNotification('Berhasil Dihapus',
          '${logsToDelete.docs.length} log berhasil dihapus.',
          isError: false);
      log('Deleted ${logsToDelete.docs.length} log entries from ${DateFormat('dd-MM-yyyy').format(startDateToDelete)} to ${DateFormat('dd-MM-yyyy').format(endDateToDelete)}');
    } catch (e) {
      _showNotification('Gagal Menghapus Log', 'Error menghapus log: $e',
          isError: true);
      log('Error deleting logs: $e');
    } finally {
      setState(() {
        _isLoadingDelete = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    Query<Map<String, dynamic>> query = _firestore.collection('log_entries');

    if (_selectedStartDate != null) {
      DateTime startOfDay = DateTime(_selectedStartDate!.year,
          _selectedStartDate!.month, _selectedStartDate!.day);
      query = query.where('timestamp', isGreaterThanOrEqualTo: startOfDay);
    }
    if (_selectedEndDate != null) {
      DateTime endOfDay = DateTime(_selectedEndDate!.year,
          _selectedEndDate!.month, _selectedEndDate!.day, 23, 59, 59, 999);
      query = query.where('timestamp', isLessThanOrEqualTo: endOfDay);
    }

    if (_selectedDepartment != null &&
        _selectedDepartment != 'Semua Departemen') {
      query = query.where('staffDepartment', isEqualTo: _selectedDepartment);
    }

    query = query.orderBy('timestamp', descending: true);

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: NestedScrollView(
        headerSliverBuilder: (BuildContext context, bool innerBoxIsScrolled) {
          return <Widget>[
            SliverAppBar(
              automaticallyImplyLeading: false,
              expandedHeight: _filterSectionHeight > 0
                  ? _filterSectionHeight + 20.0
                  : 450.0,
              floating: true,
              pinned: true,
              snap: true,
              flexibleSpace: FlexibleSpaceBar(
                background: SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  child: Padding(
                    key: _filterSectionKey,
                    padding: const EdgeInsets.all(16.0),
                    child: Card(
                      margin: EdgeInsets.zero,
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Opsi Filter & Aksi:',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 20,
                                color: Colors.blueAccent,
                              ),
                            ),
                            const SizedBox(height: 15),
                            TextField(
                              controller: _searchController,
                              decoration: InputDecoration(
                                hintText:
                                    'Cari log (nama barang, staff, departemen)...',
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
                            const SizedBox(height: 15),
                            const Text('Filter Tanggal:',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 16)),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () =>
                                        _selectDate(context, isStartDate: true),
                                    icon: const Icon(Icons.calendar_today),
                                    label: Text(_selectedStartDate == null
                                        ? 'Dari Tanggal'
                                        : DateFormat('dd-MM-yyyy')
                                            .format(_selectedStartDate!)),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor:
                                          _selectedStartDate != null
                                              ? Colors.blue[700]
                                              : Colors.grey[700],
                                      side: BorderSide(
                                          color: _selectedStartDate != null
                                              ? Colors.blue[700]!
                                              : Colors.grey[400]!),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(8)),
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 12),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => _selectDate(context,
                                        isStartDate: false),
                                    icon: const Icon(Icons.calendar_today),
                                    label: Text(_selectedEndDate == null
                                        ? 'Sampai Tanggal'
                                        : DateFormat('dd-MM-yyyy')
                                            .format(_selectedEndDate!)),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: _selectedEndDate != null
                                          ? Colors.blue[700]
                                          : Colors.grey[700],
                                      side: BorderSide(
                                          color: _selectedEndDate != null
                                              ? Colors.blue[700]!
                                              : Colors.grey[400]!),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(8)),
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 12),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 15),
                            const Text('Filter Waktu:',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 16)),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () =>
                                        _selectTime(context, isStartTime: true),
                                    icon: const Icon(Icons.access_time),
                                    label: Text(_selectedStartTime == null
                                        ? 'Dari Jam'
                                        : _selectedStartTime!.format(context)),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor:
                                          _selectedStartTime != null
                                              ? Colors.blue[700]
                                              : Colors.grey[700],
                                      side: BorderSide(
                                          color: _selectedStartTime != null
                                              ? Colors.blue[700]!
                                              : Colors.grey[400]!),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(8)),
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 12),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => _selectTime(context,
                                        isStartTime: false),
                                    icon: const Icon(Icons.access_time),
                                    label: Text(_selectedEndTime == null
                                        ? 'Sampai Jam'
                                        : _selectedEndTime!.format(context)),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: _selectedEndTime != null
                                          ? Colors.blue[700]
                                          : Colors.grey[700],
                                      side: BorderSide(
                                          color: _selectedEndTime != null
                                              ? Colors.blue[700]!
                                              : Colors.grey[400]!),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(8)),
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 12),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 15),
                            const Text('Filter Departemen:',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 16)),
                            const SizedBox(height: 10),
                            DropdownButtonFormField<String>(
                              value: _selectedDepartment ??
                                  _dynamicDepartments.first,
                              decoration: InputDecoration(
                                labelText: 'Pilih Departemen',
                                border: const OutlineInputBorder(),
                                prefixIcon: const Icon(Icons.business),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 12),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                      color: _selectedDepartment !=
                                              'Semua Departemen'
                                          ? Colors.blue[700]!
                                          : Colors.grey[400]!),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                      color: Colors.blue[700]!, width: 2),
                                ),
                              ),
                              items:
                                  _dynamicDepartments.map((String department) {
                                return DropdownMenuItem<String>(
                                  value: department,
                                  child: Text(department),
                                );
                              }).toList(),
                              onChanged: _isDepartmentsLoading
                                  ? null
                                  : (String? newValue) {
                                      setState(() {
                                        _selectedDepartment =
                                            newValue == 'Semua Departemen'
                                                ? null
                                                : newValue;
                                      });
                                    },
                            ),
                            if (_isDepartmentsLoading)
                              const Padding(
                                padding: EdgeInsets.only(top: 8.0),
                                child: LinearProgressIndicator(),
                              ),
                            const SizedBox(height: 15),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: _clearFilters,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.orange,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(8)),
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 12),
                                    ),
                                    child: const Text('Reset Filter'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: _isLoadingExport
                                        ? null
                                        : () => _exportLogsToExcel(context),
                                    icon: _isLoadingExport
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                                color: Colors.white,
                                                strokeWidth: 2))
                                        : const Icon(Icons.download),
                                    label: Text(_isLoadingExport
                                        ? 'Mengekspor...'
                                        : 'Ekspor Log'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(8)),
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 12),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: _isLoadingDelete
                                        ? null
                                        : _clearLogsByDateRange,
                                    icon: _isLoadingDelete
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                                color: Colors.white,
                                                strokeWidth: 2))
                                        : const Icon(Icons.delete_forever),
                                    label: Text(_isLoadingDelete
                                        ? 'Menghapus...'
                                        : 'Hapus Log'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(8)),
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 12),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ];
        },
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: const Text(
                'Riwayat Pengambilan Barang:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: StreamBuilder<QuerySnapshot>(
                  stream: query.snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(child: Text('Error: ${snapshot.error}'));
                    }

                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    List<LogEntry> allLogs = snapshot.data!.docs.map((doc) {
                      return LogEntry.fromFirestore(
                          doc.data() as Map<String, dynamic>, doc.id);
                    }).toList();

                    List<LogEntry> filteredLogs = allLogs.where((logEntry) {
                      final String lowerCaseQuery = _searchQuery.toLowerCase();
                      bool matchesSearch = logEntry.itemName
                              .toLowerCase()
                              .contains(lowerCaseQuery) ||
                          logEntry.barcode
                              .toLowerCase()
                              .contains(lowerCaseQuery) ||
                          logEntry.staffName
                              .toLowerCase()
                              .contains(lowerCaseQuery) ||
                          logEntry.staffDepartment
                              .toLowerCase()
                              .contains(lowerCaseQuery) ||
                          (logEntry.remarks
                                  ?.toLowerCase()
                                  .contains(lowerCaseQuery) ??
                              false);

                      if (!matchesSearch) return false;

                      if (_selectedStartTime != null) {
                        DateTime logTime = logEntry.timestamp;
                        TimeOfDay entryTime = TimeOfDay(
                            hour: logTime.hour, minute: logTime.minute);
                        int startMinutes = _selectedStartTime!.hour * 60 +
                            _selectedStartTime!.minute;
                        int entryMinutes =
                            entryTime.hour * 60 + entryTime.minute;
                        if (entryMinutes < startMinutes) {
                          return false;
                        }
                      }
                      if (_selectedEndTime != null) {
                        DateTime logTime = logEntry.timestamp;
                        TimeOfDay entryTime = TimeOfDay(
                            hour: logTime.hour, minute: logTime.minute);
                        int endMinutes = _selectedEndTime!.hour * 60 +
                            _selectedEndTime!.minute;
                        int entryMinutes =
                            entryTime.hour * 60 + entryTime.minute;
                        if (entryMinutes > endMinutes) {
                          return false;
                        }
                      }
                      if (_selectedStartDate != null) {
                        DateTime logDate = DateTime(logEntry.timestamp.year,
                            logEntry.timestamp.month, logEntry.timestamp.day);
                        DateTime startDate = DateTime(_selectedStartDate!.year,
                            _selectedStartDate!.month, _selectedStartDate!.day);
                        if (logDate.isBefore(startDate)) return false;
                      }
                      if (_selectedEndDate != null) {
                        DateTime logDate = DateTime(logEntry.timestamp.year,
                            logEntry.timestamp.month, logEntry.timestamp.day);
                        DateTime endDate = DateTime(_selectedEndDate!.year,
                            _selectedEndDate!.month, _selectedEndDate!.day);
                        if (logDate.isAfter(endDate)) return false;
                      }

                      if (_selectedDepartment != null &&
                          _selectedDepartment != 'Semua Departemen') {
                        if (logEntry.staffDepartment != _selectedDepartment)
                          return false;
                      }

                      return true;
                    }).toList();

                    if (filteredLogs.isEmpty) {
                      bool isAnyFilterActive = _searchQuery.isNotEmpty ||
                          _selectedStartDate != null ||
                          _selectedEndDate != null ||
                          (_selectedDepartment != null &&
                              _selectedDepartment != 'Semua Departemen');

                      if (isAnyFilterActive) {
                        return const Center(
                          child: Text(
                            'Tidak ada log yang ditemukan dengan kriteria pencarian ini.',
                          ),
                        );
                      } else {
                        return const Center(
                          child: Text(
                            'Belum ada riwayat pengambilan barang.',
                          ),
                        );
                      }
                    }

                    return ListView.builder(
                      itemCount: filteredLogs.length,
                      itemBuilder: (context, index) {
                        final logEntry = filteredLogs[index];
                        String formattedDateTime =
                            '${DateFormat('dd-MM-yyyy').format(logEntry.timestamp)} '
                            '${DateFormat('HH:mm:ss').format(logEntry.timestamp)}';

                        String stockText;
                        Color stockColor;
                        if (logEntry.remainingStock != null) {
                          stockText = 'Sisa Stok: ${logEntry.remainingStock}';
                          stockColor = (logEntry.remainingStock == 0)
                              ? Colors.red
                              : Colors.green[800]!;
                        } else {
                          stockText = 'Jenis Item: Tidak Bisa Dihitung';
                          stockColor = Colors.blueGrey;
                        }

                        return Card(
                          margin: const EdgeInsets.symmetric(
                              horizontal: 0, vertical: 10.0),
                          elevation: 8,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                            side: BorderSide(
                                color: Colors.blueAccent.withOpacity(0.5),
                                width: 1.5),
                          ),
                          color: Colors.blue[50],
                          child: Padding(
                            padding: const EdgeInsets.all(18.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Nama Barang: ${logEntry.itemName}',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                      color: Theme.of(context).primaryColor),
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    const Icon(Icons.qr_code_scanner,
                                        size: 20, color: Colors.blueGrey),
                                    const SizedBox(width: 10),
                                    Text(
                                      'Barcode: ${logEntry.barcode}',
                                      style: TextStyle(
                                          fontSize: 16,
                                          color: Colors.blueGrey[700]),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    logEntry.quantityOrRemark is String &&
                                            logEntry.quantityOrRemark
                                                .toString()
                                                .isNotEmpty
                                        ? const Icon(Icons.notes,
                                            size: 20, color: Colors.blueGrey)
                                        : const Icon(
                                            Icons.production_quantity_limits,
                                            size: 20,
                                            color: Colors.blueGrey),
                                    const SizedBox(width: 10),
                                    Text(
                                      'Kuantitas/Remarks: ${logEntry.quantityOrRemark.toString()}',
                                      style: TextStyle(
                                          fontSize: 16,
                                          color: Colors.blueGrey[700]),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Padding(
                                  padding: const EdgeInsets.only(top: 4.0),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.inventory_2,
                                          size: 20, color: Colors.blueGrey),
                                      const SizedBox(width: 10),
                                      Text(stockText,
                                          style: TextStyle(
                                              fontSize: 16,
                                              color: stockColor,
                                              fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    const Icon(Icons.access_time,
                                        size: 20, color: Colors.blueGrey),
                                    const SizedBox(width: 10),
                                    Text(
                                      'Tanggal & Waktu: $formattedDateTime',
                                      style: TextStyle(
                                          fontSize: 16,
                                          color: Colors.blueGrey[700]),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    const Icon(Icons.person,
                                        size: 20, color: Colors.blueGrey),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'Staff: ${logEntry.staffName} (${logEntry.staffDepartment})',
                                        style: TextStyle(
                                            fontSize: 16,
                                            color: Colors.blueGrey[700]),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                if (logEntry.remarks != null &&
                                    logEntry.remarks!.isNotEmpty &&
                                    !(logEntry.quantityOrRemark is String &&
                                        logEntry.remarks ==
                                            logEntry.quantityOrRemark))
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const SizedBox(height: 10),
                                      Row(
                                        children: [
                                          const Icon(Icons.info_outline,
                                              size: 20, color: Colors.blueGrey),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              'Remarks Tambahan: ${logEntry.remarks}',
                                              style: TextStyle(
                                                  fontStyle: FontStyle.italic,
                                                  fontSize: 15,
                                                  color: Colors.blueGrey[600]),
                                              overflow: TextOverflow.visible,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
