// Path: lib/models/item.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class Item {
  String? id;
  final String name;
  final String barcode;
  final dynamic quantityOrRemark;
  final DateTime createdAt;
  final DateTime? expiryDate;
  final String? classification;
  final List<String> allowedDepartments;

  Item({
    this.id,
    required this.name,
    required this.barcode,
    required this.quantityOrRemark,
    required this.createdAt,
    this.expiryDate,
    this.classification,
    required this.allowedDepartments,
  });

  factory Item.fromFirestore(Map<String, dynamic> firestoreData, String docId) {
    return Item(
      id: docId,
      name: firestoreData['name'] ?? '',
      barcode: firestoreData['barcode'] ?? '',
      quantityOrRemark: firestoreData['quantityOrRemark'],
      createdAt: (firestoreData['createdAt'] as Timestamp).toDate(),
      expiryDate: (firestoreData['expiryDate'] as Timestamp?)?.toDate(),
      classification: firestoreData['classification'],
      allowedDepartments:
          List<String>.from(firestoreData['allowedDepartments'] ?? []),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'barcode': barcode,
      'quantityOrRemark': quantityOrRemark,
      'createdAt': createdAt,
      'expiryDate': expiryDate,
      'classification': classification,
      'allowedDepartments': allowedDepartments,
    };
  }
}
