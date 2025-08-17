// Path: lib/screens/ai_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:animated_text_kit/animated_text_kit.dart';
import 'dart:developer';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../models/item.dart';

class AiPage extends StatefulWidget {
  const AiPage({super.key});

  @override
  State<AiPage> createState() => _AiPageState();
}

class _AiPageState extends State<AiPage> {
  final TextEditingController _controller = TextEditingController();
  final List<Map<String, String>> _messages = [];
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool _isSending = false;

  final Map<String, String> _commandMap = {
    'masuk': 'itemsAdded',
    'barang masuk': 'itemsAdded',
    'barang yang masuk': 'itemsAdded',
    'ditambahkan': 'itemsAdded',
    'keluar': 'itemsTaken',
    'barang keluar': 'itemsTaken',
    'ambil': 'itemsTaken',
    'diambil': 'itemsTaken',
    'stok rendah': 'lowStock',
    'stok sedikit': 'lowStock',
    'paling sering diambil': 'mostTaken',
    'siapa yang mengambil': 'whoTookItems',
    'siapa yang ambil': 'whoTookItems',
    'item list': 'availableItems',
    'apa saja yang tersedia': 'availableItems',
    'stok barang': 'itemStock',
    'cek stok': 'itemStock',
    'berapa stok': 'itemStock',
    'sisa stok': 'itemStock',
    'akan kedaluwarsa': 'expiringSoon',
    'barang kedaluwarsa': 'expiringSoon',
    'barang expired': 'expiringSoon',
    'staf paling aktif': 'mostActiveStaff',
    'siapa staf paling aktif ambil barang': 'mostActiveStaff',
  };

  final Map<String, int> _monthSynonyms = {
    'januari': 1,
    'jan': 1,
    'februari': 2,
    'feb': 2,
    'febuari': 2,
    'maret': 3,
    'mar': 3,
    'april': 4,
    'apr': 4,
    'mei': 5,
    'juni': 6,
    'jun': 6,
    'juli': 7,
    'jul': 7,
    'agustus': 8,
    'agu': 8,
    'september': 9,
    'sep': 9,
    'oktober': 10,
    'okt': 10,
    'november': 11,
    'nov': 11,
    'desember': 12,
    'des': 12,
  };

  final Map<String, int> _daySynonyms = {
    'kemaren': 1,
    'kemarin': 1,
    'lusa': -2,
  };

  @override
  void initState() {
    super.initState();
    _showInitialCommands();
    _checkLowStockAlert();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Menampilkan daftar perintah awal kepada pengguna.
  void _showInitialCommands() {
    setState(() {
      _messages.clear();
      _messages.add({
        'sender': 'bot',
        'text':
            'Hai! 👋 Saya Nevets, AI personal Anda yang siap membantu cek inventaris dengan mudah! 😉\n\n'
                'Berikut list yang bisa saya lakukan:\n\n'
                '• `Barang apa saja yang masuk hari ini/tanggal tertentu?`\n'
                '• `Barang yang keluar hari ini/tanggal tertentu?`\n'
                '• `Item dengan stok rendah`\n'
                '• `Barang yang paling sering diambil`\n'
                '• `Siapa yang mengambil barang hari ini/tanggal tertentu?`\n'
                '• `Item List`\n'
                '• `Berapa stok [nama barang]?`\n'
                '• `Barang apa yang akan kedaluwarsa?`\n'
                '• `Siapa staf paling aktif ambil barang?`'
      });
    });
    _scrollToBottom();
  }

  /// Memeriksa item dengan stok rendah dan menampilkan peringatan.
  Future<void> _checkLowStockAlert() async {
    final lowStockItems = await _fetchLowStockItems();
    if (lowStockItems.isNotEmpty) {
      final itemDetails = lowStockItems
          .map((e) => "- **${e.name}** (Stok: ${e.quantityOrRemark})")
          .join("\n");
      final lowStockMessage =
          "⚠️ Ada beberapa item dengan stok rendah:\n$itemDetails";
      setState(() {
        _messages.add({'sender': 'bot', 'text': lowStockMessage});
      });
      _scrollToBottom();
    }
  }

  /// Mengambil semua item dari Firestore.
  Future<List<Item>> _fetchAllItems() async {
    try {
      final snapshot =
          await _firestore.collection('items').orderBy('name').get();
      return snapshot.docs
          .map((doc) => Item.fromFirestore(doc.data(), doc.id))
          .toList();
    } catch (e) {
      log("Error fetching all items: $e");
      return [];
    }
  }

  /// Mengambil item dengan stok kurang dari 10.
  Future<List<Item>> _fetchLowStockItems() async {
    try {
      final snapshot = await _firestore
          .collection('items')
          .where('quantityOrRemark', isLessThan: 10)
          .get();
      return snapshot.docs
          .map((doc) => Item.fromFirestore(doc.data(), doc.id))
          .where((item) => item.quantityOrRemark is int)
          .toList();
    } catch (e) {
      log("Error fetching low stock items: $e");
      return [];
    }
  }

  /// Mengidentifikasi tanggal dari kueri pengguna
  DateTime? _parseDateFromQuery(String query) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final queryLower = query.toLowerCase();

    if (queryLower.contains('hari ini') || queryLower.contains('hariini')) {
      return today;
    }

    for (var key in _daySynonyms.keys) {
      if (queryLower.contains(key)) {
        return today.subtract(Duration(days: _daySynonyms[key]!));
      }
    }

    final relativeDaysRegex = RegExp(r'(\d+)\s+hari yang lalu');
    final relativeWeeksRegex = RegExp(r'(\d+)\s+minggu yang lalu');
    final relativeMonthsRegex = RegExp(r'(\d+)\s+bulan yang lalu');

    var match = relativeDaysRegex.firstMatch(queryLower);
    if (match != null) {
      final days = int.tryParse(match.group(1)!);
      if (days != null) return today.subtract(Duration(days: days));
    }
    match = relativeWeeksRegex.firstMatch(queryLower);
    if (match != null) {
      final weeks = int.tryParse(match.group(1)!);
      if (weeks != null) return today.subtract(Duration(days: weeks * 7));
    }
    match = relativeMonthsRegex.firstMatch(queryLower);
    if (match != null) {
      final months = int.tryParse(match.group(1)!);
      if (months != null)
        return DateTime(now.year, now.month - months, now.day);
    }

    final dateRegex = RegExp(r'(\d{1,2})\s+(\w+)');
    match = dateRegex.firstMatch(queryLower);
    if (match != null) {
      final day = int.tryParse(match.group(1)!);
      final monthString = match.group(2)!;

      final matchedMonth = _monthSynonyms.keys.firstWhereOrNull(
        (key) => key.contains(monthString) || monthString.contains(key),
      );

      if (day != null && matchedMonth != null) {
        final month = _monthSynonyms[matchedMonth];
        return DateTime(now.year, month!, day);
      }
    }
    return null;
  }

  /// Menghitung jarak Levenshtein untuk mengukur kemiripan string.
  int _calculateLevenshteinDistance(String a, String b) {
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    List<int> v0 = List<int>.filled(b.length + 1, 0);
    List<int> v1 = List<int>.filled(b.length + 1, 0);

    for (int i = 0; i < v0.length; i++) {
      v0[i] = i;
    }

    for (int i = 0; i < a.length; i++) {
      v1[0] = i + 1;
      for (int j = 0; j < b.length; j++) {
        int cost = (a[i] == b[j]) ? 0 : 1;
        v1[j + 1] = [v1[j] + 1, v0[j + 1] + 1, v0[j] + cost]
            .reduce((min, current) => min < current ? min : current);
      }
      for (int j = 0; j < v0.length; j++) {
        v0[j] = v1[j];
      }
    }
    return v1[b.length];
  }

  /// Menemukan kata kunci yang paling mirip dengan kueri pengguna.
  String? _findBestMatch(String query, List<String> targets,
      {double threshold = 0.5}) {
    String lowerQuery = query.toLowerCase().trim();
    String? bestMatch;
    double highestScore = 0;

    if (lowerQuery.isEmpty) return null;

    for (var target in targets) {
      String lowerTarget = target.toLowerCase();
      final queryWords = lowerQuery.split(' ');
      final targetWords = lowerTarget.split(' ');

      int totalDistance = 0;
      int matchedCount = 0;

      for (var qWord in queryWords) {
        int minDistance = 9999;
        for (var tWord in targetWords) {
          int distance = _calculateLevenshteinDistance(qWord, tWord);
          if (distance < minDistance) {
            minDistance = distance;
          }
        }
        totalDistance += minDistance;
        if (minDistance < qWord.length) {
          matchedCount++;
        }
      }

      double similarity = (matchedCount / queryWords.length);
      double score = similarity;

      if (score > highestScore && score > threshold) {
        highestScore = score;
        bestMatch = target;
      }
    }
    return bestMatch;
  }

  /// Memproses kueri pengguna dan menghasilkan respons.
  Future<void> _processQuery(String query) async {
    final message = query.trim();
    if (message.isEmpty || _isSending) return;

    setState(() {
      _messages.add({'sender': 'user', 'text': message});
      _controller.clear();
      _isSending = true;
    });

    _scrollToBottom();
    _focusNode.requestFocus();

    String result =
        "Maaf, saya tidak mengerti pertanyaan Anda. Coba tanyakan pertanyaan lain.";
    final loadingMessageIndex = _messages.length;
    setState(() {
      _messages.add({'sender': 'bot', 'text': '...'});
    });
    _scrollToBottom();

    try {
      final allItems = await _fetchAllItems();
      final queryLower = query.toLowerCase();
      final targetDate = _parseDateFromQuery(queryLower);

      if (queryLower.contains('barang masuk hari ini')) {
        result = await _handleItemsAddedQuery(DateTime.now(), allItems);
      } else if (queryLower.contains('barang keluar hari ini')) {
        result = await _handleItemsTakenQuery(DateTime.now());
      } else if (queryLower
          .contains('barang paling sering diambil bulan ini')) {
        result = await _handleMostTakenItemsQuery();
      } else if (queryLower.contains('item dengan stok rendah')) {
        result = await _handleLowStockQuery(allItems);
      } else if (queryLower.contains('siapa yang mengambil barang hari ini')) {
        result = await _handleWhoTookItemsQuery(allItems, DateTime.now());
      } else if (queryLower.contains('apa saja yang tersedia')) {
        result = await _handleAvailableItemsQuery(allItems);
      } else if (queryLower.contains('barang apa yang akan kedaluwarsa')) {
        result = await _handleItemsExpiringSoon(allItems);
      } else {
        final commandKeys = _commandMap.keys.toList();
        String? matchedCommand =
            _findBestMatch(queryLower, commandKeys, threshold: 0.6);

        if (matchedCommand != null) {
          switch (_commandMap[matchedCommand]) {
            case 'itemsAdded':
              result = await _handleItemsAddedQuery(
                  targetDate ?? DateTime.now(), allItems);
              break;
            case 'itemsTaken':
              result =
                  await _handleItemsTakenQuery(targetDate ?? DateTime.now());
              break;
            case 'lowStock':
              result = await _handleLowStockQuery(allItems);
              break;
            case 'mostTaken':
              result = await _handleMostTakenItemsQuery();
              break;
            case 'whoTookItems':
              result = await _handleWhoTookItemsQuery(
                  allItems, targetDate ?? DateTime.now());
              break;
            case 'availableItems':
              result = await _handleAvailableItemsQuery(allItems);
              break;
            case 'itemStock':
              result = await _handleItemStockQuery(queryLower);
              break;
            case 'expiringSoon':
              result = await _handleItemsExpiringSoon(allItems);
              break;
            case 'mostActiveStaff':
              result = await _handleMostActiveStaffQuery();
              break;
            default:
              result = "Maaf, saya tidak mengerti pertanyaan Anda.";
          }
        } else {
          result = await _handleItemStockQuery(queryLower);
        }
      }
    } catch (e) {
      log("Error processing query: $e");
      result = "Terjadi kesalahan saat memproses permintaan Anda.";
    }

    setState(() {
      _messages[loadingMessageIndex] = {'sender': 'bot', 'text': result};
      _isSending = false;
    });

    _scrollToBottom();
    _focusNode.requestFocus();
  }

  /// Handler untuk pertanyaan stok barang.
  Future<String> _handleItemStockQuery(String query) async {
    final allItems = await _fetchAllItems();
    final itemNames = allItems.map((e) => e.name).toList();
    final queryWithoutKeywords = query.replaceAll(
        RegExp(r'(stok|jumlah|berapa|cek|sisa)\s*', caseSensitive: false), '');

    final String? bestMatch =
        _findBestMatch(queryWithoutKeywords.trim(), itemNames, threshold: 0.6);

    if (bestMatch != null) {
      final item = allItems.firstWhere((element) => element.name == bestMatch);
      final stockInfo = item.quantityOrRemark is int
          ? "Stok saat ini untuk **${item.name}** adalah **${item.quantityOrRemark}** unit."
          : "Stok untuk **${item.name}** tidak terhitung.";
      return stockInfo;
    }

    return "Maaf, saya tidak menemukan barang yang cocok dengan nama tersebut.";
  }

  /// Handler untuk pertanyaan "Barang masuk".
  Future<String> _handleItemsAddedQuery(
      DateTime date, List<Item> allItems) async {
    final startOfDate = DateTime(date.year, date.month, date.day);
    final endOfDate = startOfDate
        .add(const Duration(days: 1))
        .subtract(const Duration(seconds: 1));
    final itemsAdded = allItems
        .where((item) =>
            item.createdAt.isAfter(startOfDate) &&
            item.createdAt.isBefore(endOfDate))
        .toList();

    if (itemsAdded.isNotEmpty) {
      final totalItems = itemsAdded.length;
      final totalQuantity = itemsAdded
          .where((e) => e.quantityOrRemark is int)
          .fold(0, (sum, item) => sum + (item.quantityOrRemark as int));

      String details = "";
      for (var item in itemsAdded) {
        final quantityInfo = item.quantityOrRemark is int
            ? "Stok masuk: ${item.quantityOrRemark}"
            : "Stok masuk: N/A";
        details +=
            "- **${item.name}** ($quantityInfo) pada ${DateFormat('HH:mm').format(item.createdAt)}\n";
      }

      return "Barang yang masuk pada **${DateFormat('dd MMMM yyyy').format(date)}** ($totalItems item, total $totalQuantity unit):\n\n$details";
    }
    return "Tidak ada barang yang masuk pada **${DateFormat('dd MMMM yyyy').format(date)}**.";
  }

  /// Handler untuk pertanyaan "Barang keluar".
  Future<String> _handleItemsTakenQuery(DateTime date) async {
    final startOfDate = DateTime(date.year, date.month, date.day);
    final endOfDate = startOfDate
        .add(const Duration(days: 1))
        .subtract(const Duration(seconds: 1));

    try {
      final logSnapshot = await _firestore
          .collection('log_entries')
          .where('timestamp', isGreaterThanOrEqualTo: startOfDate)
          .where('timestamp', isLessThanOrEqualTo: endOfDate)
          .get();

      if (logSnapshot.docs.isNotEmpty) {
        final Map<String, int> takenItems = {};
        final Map<String, List<DateTime>> takenTimes = {};

        for (var doc in logSnapshot.docs) {
          final data = doc.data();
          if (data.containsKey('itemName') &&
              data.containsKey('quantityOrRemark')) {
            final itemName = data['itemName'] as String;
            final quantity = (data['quantityOrRemark'] as num).toInt();
            final timestamp = (data['timestamp'] as Timestamp).toDate();

            takenItems[itemName] = (takenItems[itemName] ?? 0) + quantity;
            takenTimes.putIfAbsent(itemName, () => []).add(timestamp);
          }
        }

        final totalItems = takenItems.length;
        final totalQuantity =
            takenItems.values.fold(0, (sum, quantity) => sum + quantity);

        String details = "";
        takenItems.forEach((itemName, quantity) {
          final times = takenTimes[itemName]!
              .map((time) => DateFormat('HH:mm').format(time))
              .join(', ');
          details +=
              "- **$itemName** (Stok keluar: ${quantity} unit), diambil pada: $times\n";
        });

        final formattedDate = DateFormat('dd MMMM yyyy').format(date);
        return "Barang yang keluar pada **$formattedDate** ($totalItems jenis item, total $totalQuantity unit):\n\n$details";
      }
    } catch (e) {
      log("Error fetching taken items: $e");
    }
    return "Tidak ada barang yang keluar pada **${DateFormat('dd MMMM yyyy').format(date)}**.";
  }

  /// Handler untuk pertanyaan "Item dengan stok rendah".
  Future<String> _handleLowStockQuery(List<Item> allItems) async {
    final lowStockItems = allItems
        .where((item) =>
            item.quantityOrRemark is int && (item.quantityOrRemark as int) < 10)
        .toList();

    if (lowStockItems.isNotEmpty) {
      final itemDetails = lowStockItems
          .map((e) => "- **${e.name}** (Stok: ${e.quantityOrRemark})")
          .join("\n");
      return "Item dengan stok rendah (<10):\n$itemDetails";
    }
    return "Tidak ada item dengan stok rendah.";
  }

  /// Handler untuk pertanyaan "Barang yang paling sering diambil bulan ini".
  Future<String> _handleMostTakenItemsQuery() async {
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);

    final logSnapshot = await _firestore
        .collection('log_entries')
        .where('timestamp', isGreaterThanOrEqualTo: startOfMonth)
        .where('timestamp', isLessThanOrEqualTo: now)
        .get();

    final itemCounts = <String, int>{};
    for (var doc in logSnapshot.docs) {
      final data = doc.data();
      if (data.containsKey('itemName')) {
        final itemName = data['itemName'] as String;
        itemCounts[itemName] = (itemCounts[itemName] ?? 0) + 1;
      }
    }

    if (itemCounts.isNotEmpty) {
      final sortedItems = itemCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      final topItems = sortedItems
          .take(10)
          .map((e) => "- **${e.key}** (${e.value} kali)")
          .join("\n");

      return "Berikut adalah 10 item yang paling sering diambil bulan ini:\n$topItems";
    }
    return "Belum ada riwayat pengambilan barang bulan ini.";
  }

  /// Handler untuk pertanyaan "Siapa yang mengambil barang hari ini?" atau tanggal tertentu.
  Future<String> _handleWhoTookItemsQuery(
      List<Item> allItems, DateTime date) async {
    final startOfDate = DateTime(date.year, date.month, date.day);
    final endOfDate = startOfDate
        .add(const Duration(days: 1))
        .subtract(const Duration(seconds: 1));

    try {
      final logSnapshot = await _firestore
          .collection('log_entries')
          .where('timestamp', isGreaterThanOrEqualTo: startOfDate)
          .where('timestamp', isLessThanOrEqualTo: endOfDate)
          .get();

      if (logSnapshot.docs.isNotEmpty) {
        String logOutput =
            "Barang yang diambil pada **${DateFormat('dd MMMM yyyy').format(date)}**:\n\n";
        for (var doc in logSnapshot.docs) {
          final data = doc.data();
          final userName = data['staffName'] as String? ?? 'Tidak Diketahui';
          final itemName = data['itemName'] as String? ?? 'Tidak Diketahui';
          final quantity = (data['quantityOrRemark'] as num?)?.toInt() ?? 0;
          final logDate = (data['timestamp'] as Timestamp?)?.toDate();

          String formattedDate = logDate != null
              ? DateFormat('dd-MM-yyyy HH:mm').format(logDate)
              : 'Tanggal tidak valid';

          final itemData =
              allItems.firstWhereOrNull((item) => item.name == itemName);
          final stockInfo = itemData != null
              ? (itemData.quantityOrRemark is int
                  ? "Sisa Stok: ${itemData.quantityOrRemark}"
                  : "Stok: Tidak Terhitung")
              : "Stok tidak ditemukan.";

          logOutput +=
              "• **$itemName** diambil oleh **$userName** ($quantity unit) pada $formattedDate.\n  - $stockInfo\n\n";
        }
        return logOutput;
      }
    } catch (e) {
      log("Error fetching who took items: $e");
    }
    return "Tidak ada pengambilan barang pada **${DateFormat('dd MMMM yyyy').format(date)}**.";
  }

  /// Handler untuk pertanyaan "Apa saja yang tersedia".
  Future<String> _handleAvailableItemsQuery(List<Item> allItems) async {
    final availableItems = allItems
        .where((item) =>
            item.quantityOrRemark is! int || (item.quantityOrRemark as int) > 0)
        .toList();

    if (availableItems.isNotEmpty) {
      String details = "";
      for (var item in availableItems) {
        final stockInfo = item.quantityOrRemark is int
            ? "Stok: ${item.quantityOrRemark}"
            : "Stok: Tidak Terhitung";
        details += "- **${item.name}** ($stockInfo)\n";
      }
      return "Berikut adalah item yang tersedia di inventaris:\n\n$details";
    }
    return "Tidak ada item yang tersedia saat ini.";
  }

  /// Handler untuk pertanyaan "Barang yang akan kedaluwarsa".
  Future<String> _handleItemsExpiringSoon(List<Item> allItems) async {
    final now = DateTime.now();
    final thirtyDaysFromNow = now.add(const Duration(days: 90));

    final expiringItems = allItems
        .where((item) =>
            item.expiryDate != null &&
            item.expiryDate!.isAfter(now) &&
            item.expiryDate!.isBefore(thirtyDaysFromNow))
        .toList();

    if (expiringItems.isNotEmpty) {
      final itemDetails = expiringItems
          .map((e) =>
              "- **${e.name}** (Kedaluwarsa: ${DateFormat('dd MMMM yyyy').format(e.expiryDate!)})")
          .join("\n");
      return "⚠️ Berikut adalah item yang akan kedaluwarsa dalam 90 hari ke depan:\n$itemDetails";
    }

    return "Tidak ada item yang akan kedaluwarsa dalam waktu dekat.";
  }

  /// Handler untuk pertanyaan "Staf paling aktif".
  Future<String> _handleMostActiveStaffQuery() async {
    final logSnapshot = await _firestore.collection('log_entries').get();
    final staffCounts = <String, int>{};
    for (var doc in logSnapshot.docs) {
      final data = doc.data();
      if (data.containsKey('staffName')) {
        final staffName = data['staffName'] as String;
        staffCounts[staffName] = (staffCounts[staffName] ?? 0) + 1;
      }
    }

    if (staffCounts.isNotEmpty) {
      final sortedStaff = staffCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      final topStaff = sortedStaff
          .take(3)
          .map((e) => "- **${e.key}** (${e.value} kali pengambilan)")
          .join("\n");

      return "Berikut adalah 3 staf paling aktif dalam pengambilan barang:\n$topStaff";
    }
    return "Belum ada riwayat pengambilan barang.";
  }

  /// Menggulir `ListView` ke bawah.
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 80,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// Menampilkan dialog untuk menyalin teks.
  void _showCopyDialog(String text) {
    showModalBottomSheet(
      context: context,
      builder: (_) => Container(
        padding: const EdgeInsets.all(16),
        child: ListTile(
          leading: const Icon(Icons.copy),
          title: const Text('Salin Pesan'),
          onTap: () {
            Clipboard.setData(ClipboardData(text: text));
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Pesan disalin!')),
            );
          },
        ),
      ),
    );
  }

  /// Membangun gelembung pesan untuk chat.
  Widget _buildMessageBubble(Map<String, String> msg) {
    final isUser = msg['sender'] == 'user';
    final bubbleColor = isUser ? Colors.blue[400] : const Color(0xFF282828);
    final textColor = isUser ? Colors.white : Colors.white70;

    return GestureDetector(
      onLongPress: () => _showCopyDialog(msg['text'] ?? ''),
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment:
              isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            if (!isUser)
              Padding(
                padding: const EdgeInsets.only(right: 8.0, top: 4.0),
                child: ClipOval(
                  child: Image.asset(
                    'assets/Nevets_remove.png',
                    width: 40,
                    height: 40,
                  ),
                ),
              ),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.7,
              ),
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 6),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: bubbleColor,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: Radius.circular(isUser ? 12 : 0),
                    bottomRight: Radius.circular(isUser ? 0 : 12),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 3,
                      offset: const Offset(1, 2),
                    ),
                  ],
                ),
                child: msg['text'] == '...'
                    ? const CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      )
                    : MarkdownBody(
                        data: msg['text'] ?? '',
                        styleSheet: MarkdownStyleSheet(
                          p: TextStyle(color: textColor, height: 1.5),
                          strong: TextStyle(
                              color: isUser ? Colors.white : Colors.white,
                              fontWeight: FontWeight.bold),
                          listBullet: TextStyle(color: textColor, height: 1.5),
                          blockSpacing: 8.0,
                        ),
                      ),
              ),
            ),
            if (isUser) const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Definisi perintah cepat dengan label dan kueri internal yang unik
    final Map<String, String> quickCommands = {
      'Barang apa saja yang masuk hari ini?': 'Barang masuk hari ini',
      'Barang yang keluar hari ini?': 'Barang keluar hari ini',
      'Item dengan stok rendah': 'Item dengan stok rendah',
      'Barang paling sering diambil bulan ini':
          'Barang yang paling sering diambil bulan ini',
      'Siapa yang mengambil barang hari ini?':
          'Siapa yang mengambil barang hari ini?',
      'Item List': 'Apa saja yang tersedia',
      'Barang yang akan kedaluwarsa?': 'Barang apa yang akan kedaluwarsa?',
    };

    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Center(
          child: AnimatedTextKit(
            animatedTexts: [
              TypewriterAnimatedText(
                'Nevets AI',
                textStyle: const TextStyle(
                  fontSize: 20.0,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                speed: const Duration(milliseconds: 100),
              ),
            ],
            totalRepeatCount: 1,
            isRepeatingAnimation: false,
          ),
        ),
        backgroundColor: Colors.indigo,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: "Reset Chat",
            onPressed: _showInitialCommands,
          ),
          IconButton(
            icon: const Icon(Icons.list_alt, color: Colors.white),
            tooltip: "Perintah Cepat",
            onPressed: () {
              showModalBottomSheet(
                context: context,
                builder: (_) => Container(
                  padding: const EdgeInsets.all(16),
                  child: ListView(
                    shrinkWrap: true,
                    children: quickCommands.entries.map((entry) {
                      return ListTile(
                        title: Text(entry.key),
                        onTap: () {
                          Navigator.pop(context);
                          _processQuery(entry.value);
                        },
                      );
                    }).toList(),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(12),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  return _buildMessageBubble(_messages[index]);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      onSubmitted:
                          _isSending ? null : (value) => _processQuery(value),
                      decoration: InputDecoration(
                        hintText: 'Tulis pertanyaanmu...',
                        filled: true,
                        fillColor: Colors.grey[200],
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo,
                      padding: const EdgeInsets.all(14),
                      shape: const CircleBorder(),
                    ),
                    onPressed: _isSending
                        ? null
                        : () => _processQuery(_controller.text),
                    child: _isSending
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send, color: Colors.white),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

extension IterableExtension<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (var element in this) {
      if (test(element)) {
        return element;
      }
    }
    return null;
  }
}

extension on Item {
  DateTime? get expiryDate {
    return null;
  }
}
