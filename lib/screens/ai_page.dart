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
            'Hai! 👋 Saya Nevets, AI personal Anda yang siap membantu cek inventaris dengan mudah! 😉 Berikut list yang bisa saya lakukan:\n\n' +
                '• Barang apa saja yang masuk hari ini?\n' +
                '• Barang yang keluar hari ini?\n' +
                '• Item dengan stok rendah\n' +
                '• Barang yang paling sering diambil\n' +
                '• Siapa yang mengambil barang hari ini/tanggal tertentu?\n' +
                '• Apa saja yang tersedia\n'
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

    // Regex untuk format 'DD MMMM'
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

    // Simpan pesan loading
    final loadingMessageIndex = _messages.length;
    setState(() {
      _messages.add({'sender': 'bot', 'text': '...'});
    });
    _scrollToBottom();

    try {
      final allItems = await _fetchAllItems();
      final queryLower = query.toLowerCase();
      final targetDate = _parseDateFromQuery(queryLower);

      if (queryLower.contains("masuk hari ini") ||
          queryLower.contains("ditambahkan hari ini")) {
        result = await _handleItemsAddedTodayQuery(allItems);
      } else if (queryLower.contains("keluar") ||
          queryLower.contains("diambil")) {
        if (targetDate != null) {
          result = await _handleItemsTakenQuery(targetDate);
        } else {
          result = await _handleItemsTakenQuery(DateTime.now());
        }
      } else if (queryLower.contains("stok rendah") ||
          queryLower.contains("stok sedikit")) {
        result = await _handleLowStockQuery(allItems);
      } else if (queryLower.contains("barang yang paling sering diambil")) {
        result = await _handleMostTakenItemsQuery();
      } else if (queryLower.contains("siapa yang mengambil") ||
          queryLower.contains("siapa yang ambil")) {
        if (targetDate != null) {
          result = await _handleWhoTookItemsQuery(allItems, targetDate);
        } else {
          result = await _handleWhoTookItemsQuery(allItems, DateTime.now());
        }
      } else if (queryLower.contains("apa saja yang tersedia")) {
        result = await _handleAvailableItemsQuery(allItems);
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

  /// Handler untuk pertanyaan "Barang masuk hari ini".
  Future<String> _handleItemsAddedTodayQuery(List<Item> allItems) async {
    final today = DateTime.now();
    final itemsToday = allItems
        .where((item) =>
            item.createdAt.year == today.year &&
            item.createdAt.month == today.month &&
            item.createdAt.day == today.day)
        .toList();

    if (itemsToday.isNotEmpty) {
      final totalItems = itemsToday.length;
      final totalQuantity = itemsToday
          .where((e) => e.quantityOrRemark is int)
          .fold(0, (sum, item) => sum + (item.quantityOrRemark as int));

      String details = "";
      for (var item in itemsToday) {
        final quantityInfo = item.quantityOrRemark is int
            ? "Stok masuk: ${item.quantityOrRemark}"
            : "Stok masuk: N/A";
        details +=
            "- **${item.name}** ($quantityInfo) pada ${DateFormat('HH:mm').format(item.createdAt)}\n";
      }

      return "Barang yang masuk hari ini ($totalItems item, total $totalQuantity unit):\n\n$details";
    }
    return "Tidak ada barang yang masuk hari ini.";
  }

  /// Handler untuk pertanyaan "Barang keluar hari ini" atau tanggal tertentu.
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

  /// Handler untuk pertanyaan "Barang yang paling sering diambil".
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
    final bubbleColor = isUser
        ? Colors.blue[400]
        : const Color(0xFF282828); // Warna card yang lebih gelap
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
      backgroundColor:
          const Color(0xFF1E1E1E), // Warna latar belakang yang lebih gelap
      appBar: AppBar(
        automaticallyImplyLeading: false, // Menghapus tombol back
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
                'Apa saja yang tersedia'
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

// Tambahkan ekstensi ini untuk memudahkan pencarian
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
