import 'dart:async';
import 'dart:io';
import 'dart:isolate';
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
/// Persistent native recognizer worker. The ONNX recognizer and synchronous
/// decode calls stay off the Flutter UI isolate; only PCM bytes cross isolates.
Future<void> _whisperWorkerMain(Map<String, Object?> args) async {
  final readyPort = args['readyPort'] as SendPort;
  final encoderPath = args['encoderPath'] as String;
  final decoderPath = args['decoderPath'] as String;
  final tokensPath = args['tokensPath'] as String;
  ReceivePort? commands;
  OfflineRecognizer? recognizer;

  try {
    await initBindingsAsync();
    final model = OfflineModelConfig(
      whisper: OfflineWhisperModelConfig(
        encoder: encoderPath,
        decoder: decoderPath,
        language: 'id',
        task: 'transcribe',
      ),
      tokens: tokensPath,
      modelType: 'whisper',
      numThreads: 2,
      debug: false,
      provider: 'cpu',
    );
    final activeRecognizer =
        OfflineRecognizer(OfflineRecognizerConfig(model: model));
    recognizer = activeRecognizer;
    final commandPort = ReceivePort();
    commands = commandPort;
    readyPort.send(commandPort.sendPort);

    await for (final raw in commandPort) {
      if (raw is! Map) continue;
      final replyTo = raw['replyTo'];
      if (replyTo is! SendPort) continue;

      if (raw['type'] == 'dispose') {
        activeRecognizer.free();
        recognizer = null;
        replyTo.send(true);
        break;
      }

      if (raw['type'] != 'decode') continue;
      try {
        final transferable = raw['samples'];
        if (transferable is! TransferableTypedData) {
          throw const FormatException('Data audio tidak valid.');
        }
        final bytes = transferable.materialize().asUint8List();
        if (bytes.lengthInBytes % Float32List.bytesPerElement != 0) {
          throw const FormatException('Data audio tidak lengkap.');
        }
        final samples = Float32List.view(
          bytes.buffer,
          bytes.offsetInBytes,
          bytes.lengthInBytes ~/ Float32List.bytesPerElement,
        );
        final stream = activeRecognizer.createStream();
        try {
          stream.acceptWaveform(samples: samples, sampleRate: 16000);
          activeRecognizer.decode(stream);
          replyTo.send({
            'ok': true,
            'text': activeRecognizer.getResult(stream).text.trim(),
          });
        } finally {
          stream.free();
        }
      } catch (error) {
        replyTo.send({'ok': false, 'error': error.toString()});
      }
    }
  } catch (error) {
    readyPort.send({'error': error.toString()});
  } finally {
    commands?.close();
    recognizer?.free();
  }
}

class OfflineAsrService {
  static const int sampleRate = 16000;
  static const int _totalBytes = 103609903;
  static const String _verificationMarkerName = '.model-verified-v1';
  static final String _verificationMarkerContent =
      _modelFiles.map((model) => model.sha256).join('\n');

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
  Isolate? _recognizerIsolate;
  SendPort? _workerSendPort;
  String? _recordingPath;
  bool _recording = false;
  bool _busy = false;
  HttpClient? _downloadClient;
  Future<void>? _loadingModel;

  bool get isRecording => _recording;
  bool get isReady => _workerSendPort != null;

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
    }

    // A verified marker avoids hashing ~104 MB whenever settings opens or
    // loadModel runs. If the marker is absent/outdated, verify every file once.
    final marker = File(p.join(directory.path, _verificationMarkerName));
    if (await marker.exists() &&
        await marker.readAsString() == _verificationMarkerContent) {
      return true;
    }
    for (final model in _modelFiles) {
      final file = File(p.join(directory.path, model.name));
      final digest = await sha256.bind(file.openRead()).first;
      if (digest.toString() != model.sha256) return false;
    }
    await marker.writeAsString(_verificationMarkerContent, flush: true);
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
      final marker = File(
        p.join(modelDirectory.path, _verificationMarkerName),
      );
      if (await marker.exists()) await marker.delete();
      client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 30)
        ..idleTimeout = const Duration(seconds: 45);
      _downloadClient = client;

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
      // Write the marker only after all model files passed size and SHA-256 checks.
      await File(p.join(modelDirectory.path, _verificationMarkerName))
          .writeAsString(_verificationMarkerContent, flush: true);
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
      if (identical(_downloadClient, client)) _downloadClient = null;
      _busy = false;
    }
  }

  /// Aborts an active model download. Partial files are removed by the
  /// download cleanup path before the operation completes.
  void cancelDownload() {
    _downloadClient?.close(force: true);
  }

  Future<void> loadModel() async {
    if (_workerSendPort != null) return;
    final pending = _loadingModel;
    if (pending != null) return pending;

    final future = _startModelWorker();
    _loadingModel = future;
    try {
      await future;
    } finally {
      if (identical(_loadingModel, future)) _loadingModel = null;
    }
  }

  Future<void> _startModelWorker() async {
    if (!await isModelInstalled) {
      throw StateError('Model suara belum diunduh atau tidak valid.');
    }
    final directory = await _modelDirectory();
    final ready = ReceivePort();
    final isolate = await Isolate.spawn(
      _whisperWorkerMain,
      {
        'readyPort': ready.sendPort,
        'encoderPath': p.join(directory.path, 'tiny-encoder.int8.onnx'),
        'decoderPath': p.join(directory.path, 'tiny-decoder.int8.onnx'),
        'tokensPath': p.join(directory.path, 'tiny-tokens.txt'),
      },
    );
    _recognizerIsolate = isolate;
    try {
      final result = await ready.first.timeout(const Duration(minutes: 2));
      if (result is SendPort) {
        _workerSendPort = result;
        return;
      }
      isolate.kill(priority: Isolate.immediate);
      _recognizerIsolate = null;
      final detail = result is Map ? result['error'] : null;
      throw StateError(
        detail == null
            ? 'Mesin pengenalan suara offline gagal disiapkan.'
            : 'Mesin pengenalan suara offline gagal disiapkan: $detail',
      );
    } on TimeoutException {
      isolate.kill(priority: Isolate.immediate);
      _recognizerIsolate = null;
      throw StateError('Persiapan model suara terlalu lama. Coba lagi.');
    } finally {
      ready.close();
    }
  }

  Future<String> _decodeInWorker(Float32List samples) async {
    final worker = _workerSendPort;
    if (worker == null) {
      throw StateError('Mesin pengenalan suara offline belum siap.');
    }
    final response = ReceivePort();
    final audioBytes = samples.buffer.asUint8List(
      samples.offsetInBytes,
      samples.lengthInBytes,
    );
    worker.send({
      'type': 'decode',
      'samples': TransferableTypedData.fromList([audioBytes]),
      'replyTo': response.sendPort,
    });
    try {
      final result = await response.first.timeout(const Duration(minutes: 2));
      if (result is Map && result['ok'] == true) {
        return (result['text'] ?? '').toString();
      }
      final detail = result is Map ? result['error'] : null;
      throw StateError(
        detail == null
            ? 'Pengenalan suara offline gagal.'
            : 'Pengenalan suara offline gagal: $detail',
      );
    } on TimeoutException {
      throw StateError('Pengenalan suara terlalu lama. Coba rekam lebih singkat.');
    } finally {
      response.close();
    }
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

      if (_workerSendPort == null) return '';
      return await _decodeInWorker(samples);
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
    final loading = _loadingModel;
    if (loading != null) {
      try {
        await loading;
      } catch (_) {
        // Continue cleanup if worker initialization failed.
      }
    }
    final worker = _workerSendPort;
    if (worker != null) {
      final response = ReceivePort();
      worker.send({'type': 'dispose', 'replyTo': response.sendPort});
      try {
        await response.first.timeout(const Duration(seconds: 5));
      } on TimeoutException {
        // Kill the worker below if native cleanup does not respond.
      } finally {
        response.close();
      }
    }
    _workerSendPort = null;
    _recognizerIsolate?.kill(priority: Isolate.immediate);
    _recognizerIsolate = null;
  }

  Future<void> dispose() async {
    await unloadModel();
    await _recorder.dispose();
  }
}
