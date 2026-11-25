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
    await initializeSpeech();
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
      } else {
        setStatus(
          'Bahasa Indonesia belum terdeteksi. Unduh paket bahasa Indonesia offline di pengaturan suara perangkat.',
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
    final msg = error.errorMsg;
    if (msg.contains('language')) {
      _statusText =
          'Paket bahasa Indonesia offline belum terpasang. Unduh di pengaturan suara/Google di perangkat.';
    } else if (msg == 'error_permission') {
      _statusText = 'Izin mikrofon ditolak. Aktifkan di pengaturan aplikasi.';
    } else if (msg == 'error_no_match' || msg == 'error_speech_timeout') {
      _statusText = 'Suara tidak terdengar jelas. Coba lagi.';
    } else {
      _statusText = 'Terjadi kesalahan suara ($msg). Coba lagi.';
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
        final words = result.recognizedWords.trim();
        onPartialResult(words.isEmpty ? listeningStatus : words);
        if (result.finalResult && words.isNotEmpty) onFinalResult(words);
      },
    );
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
