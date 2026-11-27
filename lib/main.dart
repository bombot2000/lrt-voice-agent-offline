import 'dart:async';
import 'voice_controller.dart';

import 'chat_message.dart';
import 'chat_bubble.dart';
import 'asr_settings_dialog.dart';
import 'package:flutter/material.dart';
import 'fare_manager_page.dart';
import 'answer_engine.dart';
import 'offline_asr_service.dart';
import 'next_cargo_tariff_service.dart';
import 'tariff_utils.dart' show formatTypedReply, spokenVersion;

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
  final VoiceController _voice = VoiceController();
  final OfflineAsrService _offlineAsr = OfflineAsrService();
  Timer? _offlineRecordTimer;
  bool _useOfflineAsr = false;
  bool _localRecording = false;
  final ScrollController _scrollController = ScrollController();
  final AnswerEngine _engine = AnswerEngine(const SqliteTariffLookup());
  final TextEditingController _textController = TextEditingController();

  // Pilihan tujuan yang bisa diketuk saat hasil pencarian ambigu.
  List<Choice> _choices = const [];

  // Jawaban dibacakan hanya bila pertanyaan terakhir datang lewat suara.
  bool _voiceMode = true;

  // Teks sementara dari speech_to_text; tidak disimpan sebagai pesan final.
  String _liveTranscript = '';


  // Guard agar hasil final yang terkirim dua kali tidak diproses ganda.
  String _lastQuery = '';
  DateTime _lastQueryTime = DateTime.fromMillisecondsSinceEpoch(0);
  Future<void> _queryQueue = Future<void>.value();

  final List<ChatMessage> _messages = [];

  @override
  void initState() {
    super.initState();
    _voice.addListener(_onVoiceChanged);
    _voice.initialize();
  }

  Future<void> _openFareManager() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const FareManagerPage(),
    ));
  }

  void _onVoiceChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _setStatus(String text) => _voice.setStatus(text);

  void _updatePartialTranscript(String text) {
    if (!mounted) return;
    final value = text.trim();
    if (value == VoiceController.listeningStatus) return;
    if (_liveTranscript == value) return;
    setState(() => _liveTranscript = value);
  }

  Future<void> _openAsrSettings() async {
    await showDialog<void>(
      context: context,
      builder: (_) => AsrSettingsDialog(
        service: _offlineAsr,
        useOfflineAsr: _useOfflineAsr,
        onModeChanged: (enabled) {
          if (!mounted) return;
          setState(() => _useOfflineAsr = enabled);
        },
        onStatusChanged: _setStatus,
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
      setState(() => _localRecording = true);
      _voice.setExternalListening(
        true,
        status: 'Mendengarkan offline... tekan mikrofon untuk selesai',
      );
      _offlineRecordTimer?.cancel();
      _offlineRecordTimer = Timer(const Duration(seconds: 25), () {
        if (mounted && _localRecording) _finishOfflineRecording();
      });
    } catch (e) {
      _setStatus('Mikrofon tidak dapat dimulai. Periksa izin mikrofon dan coba lagi.');
    }
  }

  Future<void> _finishOfflineRecording() async {
    _offlineRecordTimer?.cancel();
    if (!_localRecording) return;
    setState(() => _localRecording = false);
    _voice.setExternalListening(
      false,
      status: 'Memproses suara secara offline...',
    );
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
      _setStatus('Suara belum berhasil dikenali. Pastikan model offline terpasang, lalu coba lagi.');
    }
  }

  Future<void> _stopSpeaking() async {
    if (!_voice.isSpeaking) return;
    await _voice.stopSpeaking();
    if (mounted) _voice.setStatus(VoiceController.defaultStatus);
  }

  Future<void> _toggleListening() async {
    if (_voice.isSpeaking) await _voice.stopSpeaking();

    if (_useOfflineAsr) {
      await _toggleOfflineListening();
      return;
    }

    if (_voice.isListening) {
      await _voice.stopListening();
      if (mounted) setState(() => _liveTranscript = '');
      return;
    }
    await _voice.startListening(
      onPartialResult: _updatePartialTranscript,
      onFinalResult: (query) {
        if (mounted) setState(() => _liveTranscript = '');
        _handleQuery(query, speak: true);
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
    if (_liveTranscript.isNotEmpty && mounted) {
      setState(() => _liveTranscript = '');
    }
    _voiceMode = speak;
    // Sembunyikan saran lama segera setelah pertanyaan baru diterima.
    // Pending query di AnswerEngine tetap dipertahankan agar jawaban lanjutan
    // masih dapat mempersempit tujuan yang sebelumnya ambigu.
    if (_choices.isNotEmpty && mounted) {
      setState(() => _choices = const []);
    }
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
    // Tutup daftar pilihan segera agar ketukan ganda tidak memproses tujuan
    // yang sama dua kali atau meninggalkan pilihan lama di layar.
    if (!_choices.contains(choice)) return;
    setState(() => _choices = const []);
    if (_voice.isSpeaking) await _voice.stopSpeaking();
    final selectedLabel = 'Tujuan dipilih: ${choice.label}';
    _queryQueue = _queryQueue.catchError((_) {}).then((_) async {
      try {
        final reply = _engine.select(choice);
        if (!mounted) return;
        _showReply(selectedLabel, reply, speak: _voiceMode);
      } catch (_) {
        if (!mounted) return;
        _showReply(
          selectedLabel,
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
    if (_voice.isSpeaking) await _voice.stopSpeaking();
    if (_localRecording) {
      _offlineRecordTimer?.cancel();
      await _offlineAsr.cancelRecording();
      if (mounted) {
        setState(() {
          _localRecording = false;
        });
      }
    } else if (_voice.isListening) {
      await _voice.cancelListening();
    }
    await _handleQuery(query, speak: false);
  }

  bool _isTariffResult(String text) {
    final value = text.trimLeft();
    return value.startsWith('TARIF PENGIRIMAN') ||
        value.startsWith('ESTIMASI TARIF PENGIRIMAN') ||
        value.startsWith('Tarif NEXT Cargo ke ');
  }

  void _showReply(String userText, Reply reply, {required bool speak}) {
    _voice.setStatus(VoiceController.defaultStatus);
    setState(() {
      _messages.add(ChatMessage.user(userText));
      _messages.add(ChatMessage.agent(
        speak ? reply.text : formatTypedReply(reply.text),
        showActions: _isTariffResult(reply.text),
        choices: reply.choices,
      ));
      _choices = reply.choices;
    });
    _scrollToBottom();
    if (speak) _voice.speak(spokenVersion(reply.text));
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
    _voice.removeListener(_onVoiceChanged);
    _voice.dispose();
    _scrollController.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isFirstMessage = _messages.isEmpty;
    final showLiveTranscript = _voice.isListening && !_useOfflineAsr;
    final listeningLabel = _localRecording
        ? 'Merekam suara offline • ketuk untuk selesai'
        : _voice.isListening
            ? 'Sedang mendengarkan • ketuk untuk berhenti'
            : _voice.isSpeaking
                ? 'Jawaban sedang dibacakan'
                : _voice.statusText;

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
              itemCount: _messages.length +
                  (isFirstMessage ? 1 : 0) +
                  (showLiveTranscript ? 1 : 0),
              itemBuilder: (context, index) {
                final liveIndex = _messages.length + (isFirstMessage ? 1 : 0);
                if (showLiveTranscript && index == liveIndex) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const CircleAvatar(
                          radius: 15,
                          backgroundColor: Color(0xFFFFE3E0),
                          foregroundColor: Color(0xFFB71C1C),
                          child: Icon(Icons.graphic_eq_rounded, size: 18),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Container(
                            constraints: BoxConstraints(
                              maxWidth: MediaQuery.of(context).size.width * 0.80,
                              minHeight: 48,
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 15, vertical: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF8F7),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                  color: const Color(0xFFEBC9C5)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Transkrip sementara',
                                  style: TextStyle(
                                    color: Color(0xFFB71C1C),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _liveTranscript.isEmpty
                                      ? 'Mendengarkan suara Anda…'
                                      : _liveTranscript,
                                  style: const TextStyle(
                                    color: Color(0xFF252525),
                                    fontSize: 14.5,
                                    height: 1.45,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Periksa tujuan dan berat sebelum hasil dihitung',
                                  style: TextStyle(
                                    color: Color(0xFF777777),
                                    fontSize: 10.5,
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
                return ChatBubble(message: msg, onChoiceSelected: _handleChoice);
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
                          color: (_voice.isListening || _localRecording)
                              ? const Color(0xFFE53935)
                              : _voice.isSpeaking
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
                            color: (_voice.isListening || _localRecording)
                                ? const Color(0xFFB71C1C)
                                : const Color(0xFF62666D),
                            fontWeight: (_voice.isListening || _localRecording)
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
                      const SizedBox(width: 4),
                      if (_voice.isSpeaking)
                        Tooltip(
                          message: 'Hentikan suara',
                          child: Material(
                            color: const Color(0xFFFFE5E2),
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: _stopSpeaking,
                              child: const SizedBox(
                                width: 44,
                                height: 52,
                                child: Icon(
                                  Icons.stop_circle_outlined,
                                  color: Color(0xFFB71C1C),
                                  size: 27,
                                ),
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(width: 5),
                      Tooltip(
                        message: _localRecording
                            ? 'Selesai merekam'
                            : (_voice.isListening || _localRecording)
                                ? 'Hentikan mikrofon'
                                : 'Tanya dengan suara',
                        child: Material(
                          color: (_voice.isListening || _localRecording)
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
                                (_voice.isListening || _localRecording) ? Icons.stop_rounded : Icons.mic_rounded,
                                color: (_voice.isListening || _localRecording)
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
