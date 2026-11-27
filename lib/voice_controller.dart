import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// Mengelola speech-to-text perangkat dan text-to-speech.
class VoiceController extends ChangeNotifier {
  static const defaultStatus =
      'Mode Offline • Tekan mikrofon atau ketik pertanyaan';
  static const listeningStatus = 'Mendengarkan...';

  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();

  bool _speechReady = false;
  bool _isListening = false;
  bool _isSpeaking = false;
  bool _disposed = false;
  String _statusText = defaultStatus;
  String _localeId = 'id_ID';

  bool get isListening => _isListening;
  bool get isSpeaking => _isSpeaking;
  bool get speechReady => _speechReady;
  String get statusText => _statusText;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void setStatus(String text) {
    _statusText = text;
    _notify();
  }

  void setExternalListening(bool listening, {String? status}) {
    _isListening = listening;
    if (status != null) _statusText = status;
    _notify();
  }

  Future<void> initialize() async {
    // TTS can be prepared without microphone access. Speech recognition and
    // its permission prompt are initialized lazily on the first mic tap.
    await initializeTts();
  }

  Future<bool> initializeSpeech() async {
    try {
      _speechReady = await _speech.initialize(
        onStatus: _onSpeechStatus,
        onError: _onSpeechError,
      );
    } catch (_) {
      _speechReady = false;
    }
    if (!_speechReady) {
      setStatus('Layanan suara tidak tersedia. Periksa izin mikrofon.');
      return false;
    }
    try {
      final locales = await _speech.locales();
      final match = locales.where((locale) {
        final id = locale.localeId.toLowerCase().replaceAll('-', '_');
        return id == 'id_id' || id == 'in_id';
      });
      if (match.isNotEmpty) {
        _localeId = match.first.localeId;
        setStatus(
          'Bahasa Indonesia terdeteksi. Untuk pengenalan tanpa internet, pastikan paket bahasa offline sudah diunduh di pengaturan suara perangkat.',
        );
      } else {
        setStatus(
          'Bahasa Indonesia belum tersedia. Tambahkan bahasa Indonesia di pengaturan pengenalan suara perangkat.',
        );
      }
    } catch (_) {
      // Tetap gunakan locale default id_ID.
    }
    return true;
  }

  Future<void> initializeTts() async {
    try {
      final available = await _tts.isLanguageAvailable('id-ID');
      if (available != true && available != 1) {
        setStatus(
          'Suara Indonesia (TTS) belum terpasang. Pasang data suara bahasa Indonesia di pengaturan perangkat.',
        );
      }
      await _tts.setLanguage('id-ID');
      await _tts.setSpeechRate(0.5);
      await _tts.setPitch(1.0);
      await _tts.awaitSpeakCompletion(true);
      _tts.setStartHandler(() {
        _isSpeaking = true;
        _notify();
      });
      _tts.setCompletionHandler(() {
        _isSpeaking = false;
        _notify();
      });
      _tts.setCancelHandler(() {
        _isSpeaking = false;
        _notify();
      });
      _tts.setErrorHandler((_) {
        _isSpeaking = false;
        _notify();
      });
    } catch (_) {
      // TTS opsional; aplikasi tetap menampilkan jawaban dalam teks.
    }
  }

  void _onSpeechStatus(String status) {
    if (status == 'done' || status == 'notListening') {
      _isListening = false;
      if (_statusText == listeningStatus) _statusText = defaultStatus;
      _notify();
    }
  }

  void _onSpeechError(SpeechRecognitionError error) {
    final code = error.errorMsg.toLowerCase();
    if (code.contains('language') || code.contains('locale')) {
      _statusText =
          'Paket bahasa Indonesia belum siap. Unduh paket bahasa offline di pengaturan suara perangkat.';
    } else if (code == 'error_permission') {
      _statusText = 'Izin mikrofon ditolak. Aktifkan di pengaturan aplikasi.';
    } else if (code == 'error_no_match' || code == 'error_speech_timeout') {
      _statusText = 'Suara tidak terdengar jelas. Coba bicara lebih dekat lalu ulangi.';
    } else if (code == 'error_network' || code == 'error_network_timeout') {
      _statusText =
          'Mesin suara perangkat tidak dapat digunakan saat ini. Periksa paket bahasa offline atau coba lagi.';
    } else {
      _statusText =
          'Pengenalan suara perangkat gagal dimulai. Periksa izin mikrofon dan paket bahasa Indonesia, lalu coba lagi.';
    }
    _isListening = false;
    _notify();
  }

  Future<void> startListening({
    required ValueChanged<String> onPartialResult,
    required ValueChanged<String> onFinalResult,
  }) async {
    if (!_speechReady && !await initializeSpeech()) return;
    _isListening = true;
    _statusText = listeningStatus;
    _notify();
    try {
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
          if (_disposed) return;
          final words = result.recognizedWords.trim();
          onPartialResult(words.isEmpty ? listeningStatus : words);
          if (result.finalResult && words.isNotEmpty) onFinalResult(words);
        },
      );
    } catch (error) {
      _isListening = false;
      _statusText = 'Pengenalan suara tidak dapat dimulai. Periksa izin mikrofon dan coba lagi.';
      _notify();
    }
  }

  Future<void> stopListening() async {
    await _speech.stop();
    _isListening = false;
    _statusText = defaultStatus;
    _notify();
  }

  Future<void> cancelListening() async {
    await _speech.cancel();
    _isListening = false;
    _notify();
  }

  Future<void> stopSpeaking() async {
    await _tts.stop();
    _isSpeaking = false;
    _notify();
  }

  Future<void> speak(String text) async {
    try {
      await _tts.speak(text);
    } catch (_) {
      // Jawaban tetap tersedia dalam bentuk teks.
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _speech.cancel();
    _tts.stop();
    super.dispose();
  }
}
