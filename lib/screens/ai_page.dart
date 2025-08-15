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
    'masuk': 'itemsAddedToday',
    'keluar': 'itemsTakenToday',
    'ambil': 'itemsTakenToday',
    'diambil': 'itemsTakenToday',
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

  void _showInitialCommands() {
    setState(() {
      _messages.clear();
      _messages.add({
        'sender': 'bot',
        'text':
            'Hai! 👋 Saya Nevets, AI personal Anda yang siap membantu cek inventaris dengan mudah! 😉\n\n'
                'Berikut list yang bisa saya lakukan:\n\n'
                '• Barang apa saja yang masuk hari ini?\n'
                '• Barang yang keluar hari ini/tanggal tertentu?\n'
                '• Item dengan stok rendah\n'
                '• Barang yang paling sering diambil\n'
                '• Siapa yang mengambil barang hari ini/tanggal tertentu?\n'
                '• Item List\n'
                '• Berapa stok [nama barang]?\n'
                '• Barang apa yang akan kedaluwarsa?\n'
                '• Siapa staf paling aktif ambil barang?'
      });
    });
    _scrollToBottom();
  }

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

  DateTime? _parseDateFromQuery(String query) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final queryLower = query.toLowerCase();

    if (queryLower.contains('hari ini') || queryLower.contains('hariini')) {
      return today;
    }
    if (queryLower.contains('kemarin')) {
      final yesterday = now.subtract(const Duration(days: 1));
      return DateTime(yesterday.year, yesterday.month, yesterday.day);
    }
    if (queryLower.contains('lusa')) {
      final dayAfterTomorrow = now.add(const Duration(days: 2));
      return DateTime(
          dayAfterTomorrow.year, dayAfterTomorrow.month, dayAfterTomorrow.day);
    }
    if (queryLower.contains('minggu lalu')) {
      return today.subtract(const Duration(days: 7));
    }
    if (queryLower.contains('bulan lalu')) {
      final lastMonth = DateTime(now.year, now.month - 1, now.day);
      return lastMonth;
    }

    final dateRegex = RegExp(
        r'(\d{1,2})\s+(januari|februari|maret|april|mei|juni|juli|agustus|september|oktober|november|desember)');
    final match = dateRegex.firstMatch(queryLower);
    if (match != null) {
      final day = int.tryParse(match.group(1)!);
      final monthString = match.group(2)!;
      final months = {
        'januari': 1,
        'februari': 2,
        'maret': 3,
        'april': 4,
        'mei': 5,
        'juni': 6,
        'juli': 7,
        'agustus': 8,
        'september': 9,
        'oktober': 10,
        'november': 11,
        'desember': 12
      };
      final month = months[monthString];
      if (day != null && month != null) {
        return DateTime(now.year, month, day);
      }
    }
    return null;
  }

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

  String? _findBestMatch(String query, List<String> targets,
      {double threshold = 0.5}) {
    String lowerQuery = query.toLowerCase();
    String? bestMatch;
    double highestScore = 0;

    if (lowerQuery.isEmpty) return null;

    for (var target in targets) {
      String lowerTarget = target.toLowerCase();
      int distance = _calculateLevenshteinDistance(lowerQuery, lowerTarget);
      double similarity = 1.0 - (distance / lowerQuery.length);

      // Tingkatkan akurasi dengan memberikan bobot lebih pada kecocokan di awal kata
      double score = similarity;
      if (lowerTarget.startsWith(lowerQuery)) {
        score += 0.5; // Beri bonus skor untuk kecocokan awal yang kuat
      }

      if (score > highestScore && score > threshold) {
        highestScore = score;
        bestMatch = target;
      }
    }

    return bestMatch;
  }

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

      // Prioritaskan pencocokan untuk perintah yang membutuhkan tanggal atau spesifikasi
      if (queryLower.contains('masuk') || queryLower.contains('tambah')) {
        result = await _handleItemsAddedQuery(
            targetDate ?? DateTime.now(), allItems);
      } else if (queryLower.contains('keluar') ||
          queryLower.contains('ambil') ||
          queryLower.contains('diambil')) {
        result = await _handleItemsTakenQuery(targetDate ?? DateTime.now());
      } else if (queryLower.contains('siapa yang mengambil') ||
          queryLower.contains('siapa yang ambil')) {
        result = await _handleWhoTookItemsQuery(
            allItems, targetDate ?? DateTime.now());
      } else {
        // Untuk perintah lain, gunakan logika pencocokan yang ada
        final commandKeys = _commandMap.keys.toList();
        String? matchedCommand =
            _findBestMatch(queryLower, commandKeys, threshold: 0.4);

        if (matchedCommand != null) {
          switch (_commandMap[matchedCommand]) {
            case 'lowStock':
              result = await _handleLowStockQuery(allItems);
              break;
            case 'mostTaken':
              result = await _handleMostTakenItemsQuery();
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
          // Jika tidak ada perintah yang cocok, cek apakah itu pertanyaan stok barang
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

  Future<String> _handleItemStockQuery(String query) async {
    final allItems = await _fetchAllItems();
    final itemNames = allItems.map((e) => e.name).toList();
    final queryWithoutKeywords = query.replaceAll(
        RegExp(r'(stok|jumlah|berapa|cek)\s*', caseSensitive: false), '');

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
        for (var doc in logSnapshot.docs) {
          final data = doc.data();
          if (data.containsKey('itemName') &&
              data.containsKey('quantityOrRemark')) {
            final itemName = data['itemName'] as String;
            final quantity = (data['quantityOrRemark'] as num).toInt();
            takenItems[itemName] = (takenItems[itemName] ?? 0) + quantity;
          }
        }

        final result = takenItems.entries
            .map((e) => "- **${e.key}** (${e.value} unit)")
            .join("\n");
        final formattedDate = DateFormat('dd MMMM yyyy').format(date);
        return "Barang yang keluar pada $formattedDate:\n$result";
      }
    } catch (e) {
      log("Error fetching taken items: $e");
    }
    return "Tidak ada barang yang keluar pada **${DateFormat('dd MMMM yyyy').format(date)}**.";
  }

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

  Future<String> _handleMostTakenItemsQuery() async {
    final logSnapshot = await _firestore.collection('log_entries').get();
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
          .take(5)
          .map((e) => "- **${e.key}** (${e.value} kali)")
          .join("\n");

      return "Berikut adalah 5 item yang paling sering diambil:\n$topItems";
    }
    return "Belum ada riwayat pengambilan barang.";
  }

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
              "• **$itemName** diambil oleh **$userName** ($quantity unit) pada $formattedDate.\n  - $stockInfo\n\n";
        }
        return logOutput;
      }
    } catch (e) {
      log("Error fetching who took items: $e");
    }
    return "Tidak ada pengambilan barang pada **${DateFormat('dd MMMM yyyy').format(date)}**.";
  }

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

  Future<String> _handleItemsExpiringSoon(List<Item> allItems) async {
    final now = DateTime.now();
    final thirtyDaysFromNow = now.add(const Duration(days: 30));

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
      return "⚠️ Berikut adalah item yang akan kedaluwarsa dalam 30 hari ke depan:\n$itemDetails";
    }

    return "Tidak ada item yang akan kedaluwarsa dalam waktu dekat.";
  }

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
              final commands = [
                'Barang apa saja yang masuk hari ini?',
                'Barang yang keluar hari ini?',
                'Item dengan stok rendah',
                'Barang yang paling sering diambil',
                'Siapa yang mengambil barang hari ini?',
                'Item List',
                'Barang apa yang akan kedaluwarsa?',
                'Siapa staf paling aktif ambil barang?',
              ];
              showModalBottomSheet(
                context: context,
                builder: (_) => Container(
                  padding: const EdgeInsets.all(16),
                  child: ListView(
                    shrinkWrap: true,
                    children: commands.map((cmd) {
                      return ListTile(
                        title: Text(cmd),
                        onTap: () {
                          Navigator.pop(context);
                          _processQuery(cmd);
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
