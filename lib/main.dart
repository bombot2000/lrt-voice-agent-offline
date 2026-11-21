import 'package:flutter/material.dart';
import 'fare_manager_page.dart';
import 'next_cargo_tariff_service.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

void main() {
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: LrtOfflineVoiceAgentPage(),
  ));
}

class LrtOfflineVoiceAgentPage extends StatefulWidget {
  const LrtOfflineVoiceAgentPage({super.key});

  @override
  State<LrtOfflineVoiceAgentPage> createState() =>
      _LrtOfflineVoiceAgentPageState();
}

class _LrtOfflineVoiceAgentPageState extends State<LrtOfflineVoiceAgentPage> {
  static const String _defaultStatus =
      'Mode Offline • Tekan mikrofon untuk bertanya';
  static const String _listeningStatus = 'Mendengarkan...';

  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();
  final ScrollController _scrollController = ScrollController();

  bool _speechReady = false;
  bool _isListening = false;
  bool _isSpeaking = false;
  String _statusText = _defaultStatus;

  // Locale id yang dipakai (di Android bisa "id_ID" atau "in_ID").
  String _localeId = 'id_ID';

  // Guard agar hasil final yang terkirim dua kali tidak diproses ganda.
  String _lastQuery = '';
  DateTime _lastQueryTime = DateTime.fromMillisecondsSinceEpoch(0);

  final List<Map<String, String>> _messages = [
    {
      'role': 'agent',
      'text':
          'Halo, saya asisten LRT mode offline. Tanyakan jam operasional, tarif, pembayaran, atau rute stasiun.'
    }
  ];

  // Catatan: kata kunci satu kata dicocokkan sebagai KATA UTUH,
  // kata kunci berspasi dicocokkan sebagai frasa.
  final List<_LrtKnowledgeItem> _knowledgeBase = const [
    _LrtKnowledgeItem(
      keywords: [
        'jam',
        'operasional',
        'beroperasi',
        'buka',
        'tutup',
        'jadwal',
        'berangkat',
        'terakhir',
      ],
      answer:
          'LRT Jabodebek beroperasi setiap hari mulai pukul 05.00 hingga 23.30 WIB.',
    ),
    _LrtKnowledgeItem(
      keywords: [
        'tarif',
        'harga',
        'tiket',
        'ongkos',
        'ongkir',
        'biaya',
        'mahal',
        'murah',
        'berapa harga',
      ],
      answer:
          'Data tarif rute belum diimpor. Buka menu Kelola Data Ongkir untuk memasukkan file tarif terbaru.',
    ),
    _LrtKnowledgeItem(
      keywords: [
        'bayar',
        'pembayaran',
        'kartu',
        'emoney',
        'e-money',
        'flazz',
        'brizzi',
        'tapcash',
        'qris',
        'saldo',
      ],
      answer:
          'Pembayaran menggunakan Kartu Uang Elektronik bank yang tap in dan tap out harus sama, atau metode pembayaran resmi yang tersedia di stasiun.',
    ),
    _LrtKnowledgeItem(
      keywords: [
        'transit',
        'pindah',
        'krl',
        'commuter',
        'transjakarta',
        'busway',
        'cawang',
        'dukuh atas',
      ],
      answer:
          'Transit utama LRT Jabodebek berada di Stasiun Cawang untuk perpindahan lintas Harjamukti dan Jatimulya, serta Stasiun Dukuh Atas untuk akses KRL dan TransJakarta.',
    ),
    _LrtKnowledgeItem(
      keywords: ['harjamukti', 'cibubur', 'ciracas', 'kampung rambutan'],
      answer:
          'Lini Harjamukti melayani rute dari Stasiun Harjamukti menuju Cawang dan Dukuh Atas.',
    ),
    _LrtKnowledgeItem(
      keywords: ['jatimulya', 'bekasi', 'bekasi barat', 'cikunir'],
      answer:
          'Lini Jatimulya melayani rute dari Stasiun Jatimulya menuju Cawang dan Dukuh Atas.',
    ),
    _LrtKnowledgeItem(
      keywords: ['velodrome', 'pegangsaan', 'kelapa gading', 'lrt jakarta'],
      answer:
          'LRT Jakarta melayani rute Pegangsaan Dua hingga Velodrome dengan koneksi TransJakarta.',
    ),
    _LrtKnowledgeItem(
      keywords: [
        'halo',
        'hai',
        'selamat',
        'pagi',
        'siang',
        'sore',
        'malam',
        'bantuan',
        'bisa apa',
      ],
      answer:
          'Saya bisa membantu info jam operasional, tarif, pembayaran, transit, dan rute stasiun LRT secara offline.',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _initVoice();
  }

  Future<void> _openFareManager() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const FareManagerPage(),
    ));
  }

  Future<String?> _findImportedFare(String query) async {
    final matches = await NextCargoTariffService.findDestination(query);
    if (matches.isEmpty) {
      final count = await NextCargoTariffService.count();
      if (count == 0) return null;
      return 'Tarif NEXT Cargo dari MALANG KOTA tersedia untuk ' + count.toString() + ' tujuan. Sebutkan kota serta kecamatan atau kelurahan tujuan.';
    }
    if (matches.length > 1) {
      final choices = matches.take(5).map((r) => [r['village'],r['district'],r['city'],r['province']].join(', ')).join('; ');
      return 'Ada beberapa tujuan yang cocok. Sebutkan kecamatan atau kelurahan lebih lengkap. Contoh: ' + choices + '.';
    }
    final r=matches.first;
    String money(Object? value) {
      final raw=(value??'').toString().trim();
      if(raw.isEmpty||raw=='0')return 'tidak tersedia';
      final n=int.tryParse(raw.replaceAll(RegExp(r'[^0-9-]'),''));
      if(n==null)return raw;
      final digits=n.abs().toString();
      final grouped=digits.replaceAllMapped(RegExp(r'(?<=\d)(?=(\d{3})+$)'),(_)=>'.');
      return 'Rp '+(n<0?'-':'')+grouped;
    }
    final destination=[r['village'],r['district'],r['city'],r['province']].join(', ');
    return 'Tarif NEXT Cargo dari MALANG KOTA ke '+destination+
      '. Reguler minimum '+(r['min_reg']??'-').toString()+' kg, tarif '+money(r['tarif_reg'])+
      '. SP1 minimum '+(r['min_sp1']??'-').toString()+' kg, tarif '+money(r['tarif_sp1'])+
      '. SP2 minimum '+(r['min_sp2']??'-').toString()+' kg, tarif '+money(r['tarif_sp2'])+
      '. SP3 minimum '+(r['min_sp3']??'-').toString()+' kg, tarif '+money(r['tarif_sp3'])+
      '. Tarif 10 kg '+money(r['tarif_10kg'])+'; tarif khusus '+money(r['tarif_khusus'])+
      '. Lead time '+(r['lead_time']??'-').toString()+' hari. Handler '+(r['handler']??'-').toString()+'.';
  }

  Future<void> _initVoice() async {
    await _initSpeech();
    await _initTts();
  }

  Future<bool> _initSpeech() async {
    try {
      _speechReady = await _speech.initialize(
        onStatus: _onSpeechStatus,
        onError: _onSpeechError,
      );
    } catch (_) {
      _speechReady = false;
    }

    if (!_speechReady) {
      _setStatus('Layanan suara tidak tersedia. Periksa izin mikrofon.');
      return false;
    }

    try {
      final locales = await _speech.locales();
      final match = locales.where((l) {
        final id = l.localeId.toLowerCase().replaceAll('-', '_');
        return id == 'id_id' || id == 'in_id';
      });
      if (match.isNotEmpty) {
        _localeId = match.first.localeId;
      } else {
        _setStatus(
            'Bahasa Indonesia belum terdeteksi. Unduh paket bahasa Indonesia offline di pengaturan suara perangkat.');
      }
    } catch (_) {
      // Pakai default id_ID.
    }
    return true;
  }

  Future<void> _initTts() async {
    try {
      final available = await _tts.isLanguageAvailable('id-ID');
      if (available != true && available != 1) {
        _setStatus(
            'Suara Indonesia (TTS) belum terpasang. Pasang data suara bahasa Indonesia di pengaturan perangkat.');
      }
      await _tts.setLanguage('id-ID');
      await _tts.setSpeechRate(0.5);
      await _tts.setPitch(1.0);
      await _tts.awaitSpeakCompletion(true);

      _tts.setStartHandler(() {
        if (mounted) setState(() => _isSpeaking = true);
      });
      _tts.setCompletionHandler(() {
        if (mounted) setState(() => _isSpeaking = false);
      });
      _tts.setCancelHandler(() {
        if (mounted) setState(() => _isSpeaking = false);
      });
      _tts.setErrorHandler((_) {
        if (mounted) setState(() => _isSpeaking = false);
      });
    } catch (_) {
      // TTS gagal diinisialisasi; aplikasi tetap bisa menampilkan teks.
    }
  }

  void _setStatus(String text) {
    if (!mounted) return;
    setState(() => _statusText = text);
  }

  void _onSpeechStatus(String status) {
    if (status == 'done' || status == 'notListening') {
      if (!mounted) return;
      setState(() {
        _isListening = false;
        if (_statusText == _listeningStatus) _statusText = _defaultStatus;
      });
    }
  }

  void _onSpeechError(SpeechRecognitionError error) {
    final msg = error.errorMsg;
    String text;
    if (msg.contains('language')) {
      text =
          'Paket bahasa Indonesia offline belum terpasang. Unduh di pengaturan suara/Google di perangkat.';
    } else if (msg == 'error_permission') {
      text = 'Izin mikrofon ditolak. Aktifkan di pengaturan aplikasi.';
    } else if (msg == 'error_no_match' || msg == 'error_speech_timeout') {
      text = 'Suara tidak terdengar jelas. Coba lagi.';
    } else {
      text = 'Terjadi kesalahan suara ($msg). Coba lagi.';
    }
    if (!mounted) return;
    setState(() {
      _isListening = false;
      _statusText = text;
    });
  }

  Future<void> _toggleListening() async {
    if (_isSpeaking) {
      await _tts.stop();
      if (mounted) setState(() => _isSpeaking = false);
    }

    if (_isListening) {
      await _speech.stop();
      if (!mounted) return;
      setState(() {
        _isListening = false;
        _statusText = _defaultStatus;
      });
      return;
    }

    if (!_speechReady) {
      final ok = await _initSpeech();
      if (!ok) return;
    }

    if (!mounted) return;
    setState(() {
      _isListening = true;
      _statusText = _listeningStatus;
    });

    await _speech.listen(
      localeId: _localeId,
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      listenOptions: stt.SpeechListenOptions(
        onDevice: true,
        partialResults: true,
        cancelOnError: true,
      ),
      onResult: (result) {
        if (!mounted) return;
        setState(() {
          _statusText = result.recognizedWords.isEmpty
              ? _listeningStatus
              : result.recognizedWords;
        });
        if (result.finalResult && result.recognizedWords.trim().isNotEmpty) {
          _handleOfflineQuery(result.recognizedWords.trim());
        }
      },
    );
  }

  Future<String> _matchOfflineAnswer(String query) async {
    final fareQuestion = await _findImportedFare(query);
    if (fareQuestion != null &&
        (query.toLowerCase().contains('tarif') ||
         query.toLowerCase().contains('harga') ||
         query.toLowerCase().contains('ongkos') ||
         query.toLowerCase().contains('berapa'))) {
      return fareQuestion;
    }
    final normalized = query
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s-]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final words =
        normalized.split(' ').where((w) => w.isNotEmpty).toSet();

    _LrtKnowledgeItem? bestMatch;
    int highestScore = 0;

    for (final item in _knowledgeBase) {
      int score = 0;
      for (final kw in item.keywords) {
        if (kw.contains(' ')) {
          if (normalized.contains(kw)) score += 2;
        } else if (words.contains(kw)) {
          score += 1;
        }
      }
      if (score > highestScore) {
        highestScore = score;
        bestMatch = item;
      }
    }

    if (bestMatch != null && highestScore > 0) {
      return bestMatch.answer;
    }

    return 'Maaf, data offline saya belum mencakup pertanyaan itu. Coba tanyakan jam operasional, tarif, pembayaran, transit Cawang atau Dukuh Atas, atau rute stasiun.';
  }

  Future<void> _handleOfflineQuery(String query) async {
    // Abaikan hasil final ganda yang identik dalam waktu singkat.
    final now = DateTime.now();
    if (query == _lastQuery &&
        now.difference(_lastQueryTime) < const Duration(seconds: 2)) {
      return;
    }
    _lastQuery = query;
    _lastQueryTime = now;

    final reply = await _matchOfflineAnswer(query);

    if (!mounted) return;
    setState(() {
      _messages.add({'role': 'user', 'text': query});
      _messages.add({'role': 'agent', 'text': reply});
      _statusText = _defaultStatus;
    });
    _scrollToBottom();

    try {
      await _tts.speak(reply);
    } catch (_) {
      // Jawaban tetap tampil sebagai teks.
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _speech.cancel();
    _tts.stop();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        title: const Text('LRT Voice Agent (Offline)',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            tooltip: 'Kelola Data Ongkir',
            onPressed: _openFareManager,
            icon: const Icon(Icons.price_change),
          ),
        ],
        backgroundColor: const Color(0xFFD32F2F),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final isUser = msg['role'] == 'user';
                return Align(
                  alignment:
                      isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.78),
                    decoration: BoxDecoration(
                      color: isUser ? const Color(0xFFD32F2F) : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 5,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      msg['text'] ?? '',
                      style: TextStyle(
                        color: isUser ? Colors.white : Colors.black87,
                        fontSize: 15,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _statusText,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _isListening
                          ? const Color(0xFFD32F2F)
                          : Colors.grey[700],
                      fontWeight:
                          _isListening ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: _toggleListening,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      width: _isListening ? 76 : 64,
                      height: _isListening ? 76 : 64,
                      decoration: BoxDecoration(
                        color: _isListening
                            ? Colors.redAccent
                            : (_isSpeaking
                                ? Colors.orange
                                : const Color(0xFFD32F2F)),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color:
                                const Color(0xFFD32F2F).withValues(alpha: 0.28),
                            blurRadius: _isListening ? 18 : 8,
                            spreadRadius: _isListening ? 4 : 1,
                          ),
                        ],
                      ),
                      child: Icon(
                        _isListening
                            ? Icons.stop
                            : (_isSpeaking ? Icons.volume_up : Icons.mic),
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LrtKnowledgeItem {
  final List<String> keywords;
  final String answer;

  const _LrtKnowledgeItem({
    required this.keywords,
    required this.answer,
  });
}