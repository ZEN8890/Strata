import 'package:cloud_firestore/cloud_firestore.dart';

class AddedLogEntry {
  final String id;
  final String itemName;
  final int quantity;
  final DateTime timestamp;

  AddedLogEntry({
    required this.id,
    required this.itemName,
    required this.quantity,
    required this.timestamp,
  });

  factory AddedLogEntry.fromFirestore(Map<String, dynamic> data, String id) {
    return AddedLogEntry(
      id: id,
      itemName: data['itemName'] ?? 'Unknown Item',
      quantity: (data['quantity'] as num?)?.toInt() ?? 0,
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}
