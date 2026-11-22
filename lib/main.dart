import 'package:flutter/material.dart';
import 'fare_manager_page.dart';
import 'answer_engine.dart';
import 'next_cargo_tariff_service.dart';
import 'tariff_utils.dart' show spokenVersion;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

void main() {
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: CargoVoiceAgentPage(),
  ));
}

class CargoVoiceAgentPage extends StatefulWidget {
  const CargoVoiceAgentPage({super.key});

  @override
  State<CargoVoiceAgentPage> createState() =>
      _CargoVoiceAgentPageState();
}

class _CargoVoiceAgentPageState extends State<CargoVoiceAgentPage> {
  static const String _defaultStatus =
      'Mode Offline • Tekan mikrofon atau ketik pertanyaan';
  static const String _listeningStatus = 'Mendengarkan...';

  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();
  final ScrollController _scrollController = ScrollController();
  final AnswerEngine _engine = AnswerEngine(const SqliteTariffLookup());
  final TextEditingController _textController = TextEditingController();

  // Pilihan tujuan yang bisa diketuk saat hasil pencarian ambigu.
  List<Choice> _choices = const [];

  // Jawaban dibacakan hanya bila pertanyaan terakhir datang lewat suara.
  bool _voiceMode = true;

  bool _speechReady = false;
  bool _isListening = false;
  bool _isSpeaking = false;
  String _statusText = _defaultStatus;

  // Locale id yang dipakai (di Android bisa "id_ID" atau "in_ID").
  String _localeId = 'id_ID';

  // Guard agar hasil final yang terkirim dua kali tidak diproses ganda.
  String _lastQuery = '';
  DateTime _lastQueryTime = DateTime.fromMillisecondsSinceEpoch(0);
  Future<void> _queryQueue = Future<void>.value();

  final List<Map<String, String>> _messages = [
    {
      'role': 'agent',
      'text':
          'Halo, saya asisten ongkir NEXT Cargo mode offline. Sebutkan tujuan dan berat, misalnya "ongkir ke Abiansemal Badung 20 kilo".'
    }
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
      listenOptions: stt.SpeechListenOptions(
        localeId: _localeId,
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 3),
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
          _handleQuery(result.recognizedWords.trim(), speak: true);
        }
      },
    );
  }

  Future<void> _handleQuery(String query, {required bool speak}) async {
    // Abaikan hasil final ganda yang identik dalam waktu singkat.
    final now = DateTime.now();
    if (query == _lastQuery &&
        now.difference(_lastQueryTime) < const Duration(seconds: 2)) {
      return;
    }
    _lastQuery = query;
    _lastQueryTime = now;
    _voiceMode = speak;
    // Semua input (suara, ketikan, dan pilihan) diproses berurutan.
    // Error satu query tidak boleh merusak antrean untuk query berikutnya.
    _queryQueue = _queryQueue.catchError((_) {}).then((_) async {
      try {
        final reply = await _engine.ask(query);
        if (!mounted) return;
        _showReply(query, reply, speak: speak);
      } catch (_) {
        if (!mounted) return;
        _showReply(
          query,
          const Reply('Terjadi kesalahan saat membaca data tarif. Silakan coba lagi.'),
          speak: false,
        );
      }
    });
    await _queryQueue;
  }

  Future<void> _handleChoice(Choice choice) async {
    if (_isSpeaking) await _tts.stop();
    _queryQueue = _queryQueue.catchError((_) {}).then((_) async {
      try {
        final reply = _engine.select(choice);
        if (!mounted) return;
        _showReply(choice.label, reply, speak: _voiceMode);
      } catch (_) {
        if (!mounted) return;
        _showReply(
          choice.label,
          const Reply('Pilihan tujuan gagal diproses. Silakan ulangi pertanyaan.'),
          speak: false,
        );
      }
    });
    await _queryQueue;
  }

  Future<void> _submitText(String raw) async {
    final query = raw.trim();
    if (query.isEmpty) return;
    _textController.clear();
    if (_isSpeaking) await _tts.stop();
    if (_isListening) {
      await _speech.cancel();
      if (mounted) setState(() => _isListening = false);
    }
    await _handleQuery(query, speak: false);
  }

  void _showReply(String userText, Reply reply, {required bool speak}) {
    setState(() {
      _messages.add({'role': 'user', 'text': userText});
      _messages.add({'role': 'agent', 'text': reply.text});
      _choices = reply.choices;
      _statusText = _defaultStatus;
    });
    _scrollToBottom();
    if (speak) _speak(reply.text);
  }

  Future<void> _speak(String text) async {
    try {
      await _tts.speak(spokenVersion(text));
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
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        title: const Text('Cargo Voice Agent (Offline)',
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
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
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
                  if (_choices.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 150),
                      child: SingleChildScrollView(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            for (final c in _choices)
                              ActionChip(
                                label: ConstrainedBox(
                                  constraints: BoxConstraints(
                                      maxWidth:
                                          MediaQuery.of(context).size.width -
                                              96),
                                  child: Text(c.label,
                                      overflow: TextOverflow.ellipsis),
                                ),
                                onPressed: () => _handleChoice(c),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _textController,
                          textInputAction: TextInputAction.send,
                          onSubmitted: _submitText,
                          decoration: InputDecoration(
                            hintText: 'Ketik tujuan dan berat...',
                            isDense: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                            suffixIcon: IconButton(
                              tooltip: 'Kirim',
                              icon: const Icon(Icons.send),
                              onPressed: () =>
                                  _submitText(_textController.text),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 76,
                        height: 76,
                        child: Center(
                          child: GestureDetector(
                            onTap: _toggleListening,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 220),
                              width: _isListening ? 72 : 60,
                              height: _isListening ? 72 : 60,
                              decoration: BoxDecoration(
                                color: _isListening
                                    ? Colors.redAccent
                                    : (_isSpeaking
                                        ? Colors.orange
                                        : const Color(0xFFD32F2F)),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFD32F2F)
                                        .withValues(alpha: 0.28),
                                    blurRadius: _isListening ? 18 : 8,
                                    spreadRadius: _isListening ? 4 : 1,
                                  ),
                                ],
                              ),
                              child: Icon(
                                _isListening
                                    ? Icons.stop
                                    : (_isSpeaking
                                        ? Icons.volume_up
                                        : Icons.mic),
                                color: Colors.white,
                                size: 30,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
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
