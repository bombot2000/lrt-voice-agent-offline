import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart';

class _ModelFile {
  final String name;
  final int bytes;
  final String sha256;
  const _ModelFile(this.name, this.bytes, this.sha256);

  String get url =>
      'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-tiny/resolve/65176e2/$name';
}

/// Whisper Tiny multilingual INT8. Model disimpan di app-support, bukan APK.
/// SHA-256 memverifikasi unduhan sebelum file dianggap siap digunakan.
class OfflineAsrService {
  static const int sampleRate = 16000;
  static const int _totalBytes = 103609903;

  static const List<_ModelFile> _modelFiles = [
    _ModelFile(
      'tiny-encoder.int8.onnx',
      12937772,
      'd24fb083ae3b1041fc24e97971d60e280c9342201fbb67b0ab428a8b4a51a434',
    ),
    _ModelFile(
      'tiny-decoder.int8.onnx',
      89855401,
      'd2fece8dd42771f1df975c6c0445770d0c292bf7547c2cae04a6c0cc57540925',
    ),
    _ModelFile(
      'tiny-tokens.txt',
      816730,
      'b34b360dbb493e781e479794586d661700670d65564001f23024971d1f2fa126',
    ),
  ];

  final AudioRecorder _recorder = AudioRecorder();
  OfflineRecognizer? _recognizer;
  String? _recordingPath;
  bool _recording = false;
  bool _busy = false;

  bool get isRecording => _recording;
  bool get isReady => _recognizer != null;

  Future<Directory> _modelDirectory() async {
    final root = await getApplicationSupportDirectory();
    final directory = Directory(p.join(root.path, 'offline_asr', 'whisper_tiny_id'));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<bool> get isModelInstalled async {
    final directory = await _modelDirectory();
    for (final model in _modelFiles) {
      final file = File(p.join(directory.path, model.name));
      if (!await file.exists() || await file.length() != model.bytes) {
        return false;
      }
      final digest = await sha256.bind(file.openRead()).first;
      if (digest.toString() != model.sha256) return false;
    }
    return true;
  }

  Future<void> downloadModel({
    void Function(int receivedBytes, int totalBytes)? onProgress,
  }) async {
    if (_busy) throw StateError('Proses pengenalan suara sedang berjalan.');
    _busy = true;
    HttpClient? client;
    Directory? modelDirectory;
    var completedBytes = 0;

    try {
      // Keep setup inside the guarded block so filesystem failures cannot
      // leave the service permanently marked as busy.
      modelDirectory = await _modelDirectory();
      client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 30)
        ..idleTimeout = const Duration(seconds: 45);

      for (final model in _modelFiles) {
        final target = File(p.join(modelDirectory.path, model.name));
        if (await target.exists() && await target.length() == model.bytes) {
          final digest = await sha256.bind(target.openRead()).first;
          if (digest.toString() == model.sha256) {
            completedBytes += model.bytes;
            onProgress?.call(completedBytes, _totalBytes);
            continue;
          }
        }

        final partial = File(target.path + '.part');
        if (await partial.exists()) await partial.delete();

        final request = await client.getUrl(Uri.parse(model.url)).timeout(
          const Duration(seconds: 45),
        );
        request.headers.set(HttpHeaders.userAgentHeader, 'CargoVoiceAgent/1.0');
        final response = await request.close().timeout(const Duration(minutes: 3));
        if (response.statusCode != HttpStatus.ok) {
          throw HttpException(
            'Unduhan ${model.name} gagal (HTTP ${response.statusCode}).',
          );
        }

        var fileBytes = 0;
        final sink = partial.openWrite();
        try {
          await for (final chunk in response.timeout(const Duration(seconds: 45))) {
            sink.add(chunk);
            fileBytes += chunk.length;
            onProgress?.call(completedBytes + fileBytes, _totalBytes);
          }
          await sink.flush();
        } finally {
          await sink.close();
        }

        if (fileBytes != model.bytes) {
          throw const FormatException('Ukuran model tidak sesuai.');
        }
        final digest = await sha256.bind(partial.openRead()).first;
        if (digest.toString() != model.sha256) {
          throw const FormatException('Verifikasi SHA-256 model gagal.');
        }

        if (await target.exists()) await target.delete();
        await partial.rename(target.path);
        completedBytes += model.bytes;
        onProgress?.call(completedBytes, _totalBytes);
      }
    } catch (_) {
      // Directory creation itself can fail; clean partial downloads only
      // after the model directory has been resolved successfully.
      final directory = modelDirectory;
      if (directory != null) {
        for (final model in _modelFiles) {
          try {
            final partial = File(p.join(directory.path, model.name + '.part'));
            if (await partial.exists()) await partial.delete();
          } on FileSystemException {
            // Preserve the original download/setup error.
          }
        }
      }
      rethrow;
    } finally {
      client?.close(force: true);
      _busy = false;
    }
  }

  Future<void> loadModel() async {
    if (_recognizer != null) return;
    if (!await isModelInstalled) {
      throw StateError('Model suara belum diunduh atau tidak valid.');
    }
    final directory = await _modelDirectory();
    final whisper = OfflineWhisperModelConfig(
      encoder: p.join(directory.path, 'tiny-encoder.int8.onnx'),
      decoder: p.join(directory.path, 'tiny-decoder.int8.onnx'),
      language: 'id',
      task: 'transcribe',
    );
    final model = OfflineModelConfig(
      whisper: whisper,
      tokens: p.join(directory.path, 'tiny-tokens.txt'),
      modelType: 'whisper',
      numThreads: 1,
      debug: false,
      provider: 'cpu',
    );
    _recognizer = await OfflineRecognizer.createAsync(
      OfflineRecognizerConfig(model: model),
    );
  }

  Future<void> startRecording() async {
    if (_recording) return;
    if (_busy) throw StateError('Pengenalan suara sedang berjalan.');
    await loadModel();
    if (!await _recorder.hasPermission()) {
      throw StateError('Izin mikrofon belum diberikan.');
    }

    final temp = await getTemporaryDirectory();
    _recordingPath = p.join(
      temp.path,
      'cargo_voice_${DateTime.now().microsecondsSinceEpoch}.pcm',
    );
    final recordingPath = _recordingPath!;
    try {
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: sampleRate,
          numChannels: 1,
        ),
        path: recordingPath,
      );
      _recording = true;
    } catch (_) {
      _recordingPath = null;
      final file = File(recordingPath);
      try {
        if (await file.exists()) await file.delete();
      } on FileSystemException {
        // Preserve the recorder startup error.
      }
      rethrow;
    }
  }

  /// Converts mono signed PCM16 little-endian bytes to normalized float samples.
  /// Rejects recordings shorter than 100 ms or with an incomplete sample.
  static Float32List pcm16leToFloat32(Uint8List bytes) {
    if (bytes.length.isOdd) {
      throw const FormatException('Data PCM harus berisi pasangan byte lengkap.');
    }
    if (bytes.length < 3200) {
      throw const FormatException('Rekaman terlalu pendek (minimal 100 ms).');
    }
    final data = ByteData.sublistView(bytes);
    final samples = Float32List(bytes.length ~/ 2);
    for (var i = 0; i < samples.length; i++) {
      samples[i] = data.getInt16(i * 2, Endian.little) / 32768.0;
    }
    return samples;
  }

  Future<String> stopAndTranscribe() async {
    if (!_recording || _recordingPath == null) return '';
    _busy = true;
    _recording = false;
    final path = _recordingPath!;
    _recordingPath = null;

    try {
      await _recorder.stop();
      final file = File(path);
      if (!await file.exists()) return '';
      final bytes = await file.readAsBytes();
      final samples = pcm16leToFloat32(bytes);

      final recognizer = _recognizer;
      if (recognizer == null) return '';
      final stream = recognizer.createStream();
      try {
        stream.acceptWaveform(samples: samples, sampleRate: sampleRate);
        recognizer.decode(stream);
        return recognizer.getResult(stream).text.trim();
      } finally {
        stream.free();
      }
    } finally {
      // Cleanup must never leave the service permanently busy if the OS
      // refuses to remove a temporary recording file.
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } on FileSystemException {
        // The transcription result/error is more important than temp cleanup.
      } finally {
        _busy = false;
      }
    }
  }

  Future<void> cancelRecording() async {
    if (!_recording) return;
    final path = _recordingPath;
    _recording = false;
    _recordingPath = null;
    try {
      await _recorder.cancel();
    } finally {
      // Recorder cancellation can fail on a disconnected audio device; the
      // temporary PCM file must still be removed.
      if (path != null) {
        final file = File(path);
        if (await file.exists()) await file.delete();
      }
    }
  }

  Future<void> unloadModel() async {
    if (_recording) await cancelRecording();
    _recognizer?.free();
    _recognizer = null;
  }

  Future<void> dispose() async {
    await unloadModel();
    await _recorder.dispose();
  }
}
