import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:cargo_voice_agent_offline/offline_asr_service.dart';

void main() {
  group('OfflineAsrService.pcm16leToFloat32', () {
    test('converts signed PCM16 little-endian to normalized float samples', () {
      final bytes = Uint8List.fromList([
        0x00, 0x80, // -32768
        0x00, 0x00, // 0
        0x00, 0x40, // 16384
        0xFF, 0x7F, // 32767
      ] + List<int>.filled(3192, 0));
      final samples = OfflineAsrService.pcm16leToFloat32(bytes);
      expect(samples.first, -1.0);
      expect(samples[1], 0.0);
      expect(samples[2], 0.5);
      expect(samples[3], closeTo(32767 / 32768, 1e-7));
    });

    test('rejects an odd number of bytes', () {
      expect(
        () => OfflineAsrService.pcm16leToFloat32(Uint8List(3201)),
        throwsFormatException,
      );
    });

    test('rejects recordings shorter than 100 milliseconds', () {
      expect(
        () => OfflineAsrService.pcm16leToFloat32(Uint8List(3198)),
        throwsFormatException,
      );
    });
  });
}
