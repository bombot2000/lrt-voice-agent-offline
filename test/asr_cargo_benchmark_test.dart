import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cargo_voice_agent_offline/command_parser_service.dart';

void main() {
  group('ASR cargo benchmark corpus', () {
    late List<Map<String, dynamic>> cases;

    setUpAll(() {
      final file = File('test/fixtures/asr_cargo_benchmark.json');
      expect(file.existsSync(), isTrue,
          reason: 'Corpus referensi harus tersedia untuk pengujian.');
      final decoded = jsonDecode(file.readAsStringSync()) as List<dynamic>;
      cases = decoded.cast<Map<String, dynamic>>();
    });

    test('memiliki 30 contoh unik dan kategori yang terisi', () {
      expect(cases, hasLength(30));
      final ids = cases.map((item) => item['id']).toSet();
      expect(ids, hasLength(cases.length));
      for (final item in cases) {
        expect(item['reference_text'], isA<String>());
        expect((item['reference_text'] as String).trim(), isNotEmpty);
        expect(item['category'], isA<String>());
        expect(item['expected_intent'], 'cargoTariff');
      }
    });

    for (final category in const [
      'tarif_reguler',
      'tarif_khusus',
      'layanan_sp',
      'kendaraan',
      'angka',
      'variasi_ucapan',
      'tujuan',
    ]) {
      test('semua transkrip kategori $category dikenali sebagai perintah cargo',
          () {
        final selected =
            cases.where((item) => item['category'] == category).toList();
        expect(selected, isNotEmpty);
        for (final item in selected) {
          final parsed =
              CommandParserService.parse(item['reference_text'] as String);
          expect(
            parsed.intent,
            CommandIntent.cargoTariff,
            reason: '${item['id']}: ${item['reference_text']}',
          );
        }
      });
    }
  });
}
