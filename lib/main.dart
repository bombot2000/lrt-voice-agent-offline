import 'dart:async';
import 'package:flutter/material.dart';
import 'fare_manager_page.dart';
import 'answer_engine.dart';
import 'offline_asr_service.dart';
import 'next_cargo_tariff_service.dart';
import 'tariff_utils.dart' show formatTypedReply, spokenVersion;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

void main() {
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFFB71C1C),
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: const Color(0xFFF5F6F8),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFB71C1C),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF5F6F8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFB71C1C), width: 1.4),
        ),
      ),
    ),
    home: const CargoVoiceAgentPage(),
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
  final OfflineAsrService _offlineAsr = OfflineAsrService();
  Timer? _offlineRecordTimer;
  bool _useOfflineAsr = false;
  bool _localRecording = false;
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

  Future<void> _openAsrSettings() async {
    var installed = await _offlineAsr.isModelInstalled;
    var downloading = false;
    var progress = 0.0;
    String? downloadError;

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Mesin Suara Offline'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Whisper Tiny multilingual INT8 berjalan langsung di HP. '
                'Model sekitar 104 MB, diunduh satu kali dan disimpan di penyimpanan aplikasi.',
              ),
              const SizedBox(height: 12),
              Text(installed
                  ? 'Model sudah terpasang dan siap digunakan.'
                  : 'Model belum diunduh. Mode suara bawaan tetap tersedia.'),
              if (downloading) ...[
                const SizedBox(height: 12),
                LinearProgressIndicator(value: progress == 0 ? null : progress),
                const SizedBox(height: 6),
                Text('${(progress * 100).toStringAsFixed(0)}%'),
              ],
              if (downloadError != null) ...[
                const SizedBox(height: 8),
                Text(downloadError!, style: const TextStyle(color: Colors.red)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: downloading ? null : () => Navigator.pop(dialogContext),
              child: const Text('Tutup'),
            ),
            if (!installed)
              FilledButton(
                onPressed: downloading
                    ? null
                    : () async {
                        setDialogState(() {
                          downloading = true;
                          progress = 0;
                          downloadError = null;
                        });
                        try {
                          await _offlineAsr.downloadModel(
                            onProgress: (received, total) {
                              if (!dialogContext.mounted) return;
                              setDialogState(() {
                                progress = total == 0 ? 0 : received / total;
                              });
                            },
                          );
                          if (!dialogContext.mounted) return;
                          setDialogState(() {
                            installed = true;
                            downloading = false;
                            progress = 1;
                          });
                        } catch (e) {
                          if (!dialogContext.mounted) return;
                          setDialogState(() {
                            downloading = false;
                            downloadError = 'Unduhan gagal: $e';
                          });
                        }
                      },
                child: const Text('Unduh ±104 MB'),
              ),
            if (installed)
              FilledButton(
                onPressed: () {
                  if (!mounted) return;
                  setState(() => _useOfflineAsr = true);
                  Navigator.pop(dialogContext);
                  _setStatus('Mode suara Whisper offline aktif.');
                },
                child: const Text('Aktifkan suara lokal'),
              ),
            if (_useOfflineAsr)
              TextButton(
                onPressed: () {
                  if (!mounted) return;
                  setState(() => _useOfflineAsr = false);
                  Navigator.pop(dialogContext);
                  _setStatus(_defaultStatus);
                },
                child: const Text('Gunakan suara bawaan'),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleOfflineListening() async {
    if (_localRecording) {
      await _finishOfflineRecording();
      return;
    }
    try {
      await _offlineAsr.startRecording();
      if (!mounted) return;
      setState(() {
        _localRecording = true;
        _isListening = true;
        _statusText = 'Mendengarkan offline... tekan mikrofon untuk selesai';
      });
      _offlineRecordTimer?.cancel();
      _offlineRecordTimer = Timer(const Duration(seconds: 25), () {
        if (mounted && _localRecording) _finishOfflineRecording();
      });
    } catch (e) {
      _setStatus('Gagal memulai suara lokal: $e');
    }
  }

  Future<void> _finishOfflineRecording() async {
    _offlineRecordTimer?.cancel();
    if (!_localRecording) return;
    setState(() {
      _localRecording = false;
      _isListening = false;
      _statusText = 'Memproses suara secara offline...';
    });
    try {
      final transcript = await _offlineAsr.stopAndTranscribe();
      if (!mounted) return;
      if (transcript.trim().isEmpty) {
        _setStatus('Suara belum tertangkap jelas. Coba bicara lebih dekat ke mikrofon.');
        return;
      }
      _setStatus(transcript);
      await _handleQuery(transcript.trim(), speak: true);
    } catch (e) {
      _setStatus('Pengenalan suara lokal gagal: $e');
    }
  }

  Future<void> _toggleListening() async {
    if (_isSpeaking) {
      await _tts.stop();
      if (mounted) setState(() => _isSpeaking = false);
    }

    if (_useOfflineAsr) {
      await _toggleOfflineListening();
      return;
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
    if (_localRecording) {
      _offlineRecordTimer?.cancel();
      await _offlineAsr.cancelRecording();
      if (mounted) {
        setState(() {
          _localRecording = false;
          _isListening = false;
        });
      }
    } else if (_isListening) {
      await _speech.cancel();
      if (mounted) setState(() => _isListening = false);
    }
    await _handleQuery(query, speak: false);
  }

  void _showReply(String userText, Reply reply, {required bool speak}) {
    setState(() {
      _messages.add({'role': 'user', 'text': userText});
      _messages.add({
        'role': 'agent',
        'text': speak ? reply.text : formatTypedReply(reply.text),
      });
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
    _offlineRecordTimer?.cancel();
    unawaited(_offlineAsr.dispose());
    _speech.cancel();
    _tts.stop();
    _scrollController.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isFirstMessage = _messages.length == 1;
    final listeningLabel = _localRecording
        ? 'Merekam suara offline • ketuk untuk selesai'
        : _isListening
            ? 'Sedang mendengarkan • ketuk untuk berhenti'
            : _isSpeaking
                ? 'Jawaban sedang dibacakan'
                : _statusText;

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('NEXT Cargo', style: TextStyle(fontWeight: FontWeight.w800)),
            Text('Asisten ongkir offline',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Kelola data tarif',
            onPressed: _openFareManager,
            icon: const Icon(Icons.storage),
          ),
          IconButton(
            tooltip: 'Pengaturan mesin suara',
            onPressed: _openAsrSettings,
            icon: Icon(_useOfflineAsr
                ? Icons.record_voice_over
                : Icons.settings_voice_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
              itemCount: _messages.length + (isFirstMessage ? 1 : 0),
              itemBuilder: (context, index) {
                if (isFirstMessage && index == 0) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 18),
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFFF1F0), Color(0xFFFFFFFF)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: const Color(0xFFF2D5D2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: Color(0xFFB71C1C),
                              foregroundColor: Colors.white,
                              child: Icon(Icons.local_shipping_outlined),
                            ),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text('Hitung ongkir lebih praktis',
                                  style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Masukkan kota/kecamatan tujuan dan berat barang. '
                          'Tarif dihitung dari MALANG KOTA dan bisa digunakan tanpa internet.',
                          style: TextStyle(height: 1.45, color: Color(0xFF555555)),
                        ),
                        const SizedBox(height: 14),
                        const Text('Contoh pertanyaan',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ActionChip(
                              avatar: const Icon(Icons.edit_location_alt_outlined, size: 17),
                              label: const Text('Malang Pakisaji 20 kg'),
                              onPressed: () => _submitText('ongkir Malang Pakisaji 20 kg'),
                            ),
                            ActionChip(
                              avatar: const Icon(Icons.scale_outlined, size: 17),
                              label: const Text('Abiansemal Badung 20 kg'),
                              onPressed: () => _submitText('ongkir ke Abiansemal Badung 20 kilo'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }
                final messageIndex = index - (isFirstMessage ? 1 : 0);
                final msg = _messages[messageIndex];
                final isUser = msg['role'] == 'user';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    mainAxisAlignment:
                        isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (!isUser) ...[
                        const CircleAvatar(
                          radius: 15,
                          backgroundColor: Color(0xFFFFE3E0),
                          foregroundColor: Color(0xFFB71C1C),
                          child: Icon(Icons.support_agent, size: 18),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: Container(
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.80,
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 15, vertical: 12),
                          decoration: BoxDecoration(
                            color: isUser ? const Color(0xFFB71C1C) : Colors.white,
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(18),
                              topRight: const Radius.circular(18),
                              bottomLeft: Radius.circular(isUser ? 18 : 5),
                              bottomRight: Radius.circular(isUser ? 5 : 18),
                            ),
                            border: isUser
                                ? null
                                : Border.all(color: const Color(0xFFE8E9EC)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.035),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Text(
                            msg['text'] ?? '',
                            style: TextStyle(
                              color: isUser ? Colors.white : const Color(0xFF252525),
                              fontSize: 14.5,
                              height: 1.45,
                            ),
                          ),
                        ),
                      ),
                      if (isUser) const SizedBox(width: 23),
                    ],
                  ),
                );
              },
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 14,
                  offset: const Offset(0, -3),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _isListening
                              ? const Color(0xFFE53935)
                              : _isSpeaking
                                  ? Colors.orange
                                  : const Color(0xFF2E9D63),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          listeningLabel,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: _isListening
                                ? const Color(0xFFB71C1C)
                                : const Color(0xFF62666D),
                            fontWeight: _isListening
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                      if (_useOfflineAsr)
                        const Chip(
                          visualDensity: VisualDensity.compact,
                          avatar: Icon(Icons.offline_bolt, size: 15),
                          label: Text('Whisper offline'),
                          padding: EdgeInsets.zero,
                        ),
                    ],
                  ),
                  if (_choices.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF7F6),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFF0D9D6)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Pilih tujuan yang sesuai',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 13)),
                          const SizedBox(height: 7),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 132),
                            child: SingleChildScrollView(
                              child: Column(
                                children: [
                                  for (final c in _choices)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 5),
                                      child: SizedBox(
                                        width: double.infinity,
                                        child: OutlinedButton(
                                          style: OutlinedButton.styleFrom(
                                            alignment: Alignment.centerLeft,
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 12, vertical: 10),
                                            foregroundColor: const Color(0xFF8E1717),
                                            side: const BorderSide(
                                                color: Color(0xFFE7C4C0)),
                                            shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(12)),
                                          ),
                                          onPressed: () => _handleChoice(c),
                                          child: Row(
                                            children: [
                                              const Icon(Icons.place_outlined, size: 18),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(c.label,
                                                    maxLines: 2,
                                                    overflow: TextOverflow.ellipsis),
                                              ),
                                              const Icon(Icons.chevron_right, size: 18),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _textController,
                          minLines: 1,
                          maxLines: 3,
                          textCapitalization: TextCapitalization.sentences,
                          textInputAction: TextInputAction.send,
                          onSubmitted: _submitText,
                          decoration: InputDecoration(
                            hintText: 'Tujuan dan berat, mis. Malang 20 kg',
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 13),
                            prefixIcon: const Icon(Icons.chat_outlined, size: 20),
                            suffixIcon: IconButton(
                              tooltip: 'Kirim pertanyaan',
                              icon: const Icon(Icons.send_rounded),
                              color: const Color(0xFFB71C1C),
                              onPressed: () => _submitText(_textController.text),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 9),
                      Tooltip(
                        message: _localRecording
                            ? 'Selesai merekam'
                            : _isListening
                                ? 'Hentikan mikrofon'
                                : 'Tanya dengan suara',
                        child: Material(
                          color: _isListening
                              ? const Color(0xFFB71C1C)
                              : const Color(0xFFFFE5E2),
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: _toggleListening,
                            child: SizedBox(
                              width: 52,
                              height: 52,
                              child: Icon(
                                _isListening ? Icons.stop_rounded : Icons.mic_rounded,
                                color: _isListening
                                    ? Colors.white
                                    : const Color(0xFFB71C1C),
                                size: 26,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  const Center(
                    child: Text(
                      'Tarif tersimpan di perangkat • Bisa digunakan offline',
                      style: TextStyle(fontSize: 10.5, color: Color(0xFF858990)),
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
