// Path: lib/models/log_entry.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class LogEntry {
  String? id;
  final String itemName;
  final String barcode;
  final dynamic quantityOrRemark;
  final DateTime timestamp;
  final String staffName;
  final String staffDepartment;
  final String? remarks;
  final int? remainingStock; // Properti baru

  LogEntry({
    this.id,
    required this.itemName,
    required this.barcode,
    required this.quantityOrRemark,
    required this.timestamp,
    required this.staffName,
    required this.staffDepartment,
    this.remarks,
    this.remainingStock, // Perbarui constructor
  });

  factory LogEntry.fromFirestore(
      Map<String, dynamic> firestoreData, String docId) {
    return LogEntry(
      id: docId,
      itemName: firestoreData['itemName'] ?? '',
      barcode: firestoreData['barcode'] ?? '',
      quantityOrRemark: firestoreData['quantityOrRemark'],
      timestamp: (firestoreData['timestamp'] as Timestamp).toDate(),
      staffName: firestoreData['staffName'] ?? '',
      staffDepartment: firestoreData['staffDepartment'] ?? '',
      remarks: firestoreData['remarks'],
      remainingStock: firestoreData['remainingStock'] as int?, // Ambil nilai
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'itemName': itemName,
      'barcode': barcode,
      'quantityOrRemark': quantityOrRemark,
      'timestamp': timestamp,
      'staffName': staffName,
      'staffDepartment': staffDepartment,
      'remarks': remarks,
      'remainingStock': remainingStock, // Simpan nilai
    };
  }
}
