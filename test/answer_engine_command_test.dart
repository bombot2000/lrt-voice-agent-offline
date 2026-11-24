import 'package:flutter_test/flutter_test.dart';
import 'package:cargo_voice_agent_offline/answer_engine.dart';

class EmptyTariffs implements TariffLookup {
  @override
  Future<List<Map<String, Object?>>> find(String query) async => const [];
  @override
  Future<int> count() async => 0;
}

void main() {
  group('AnswerEngine local arithmetic', () {
    test('answers arithmetic without querying tariff database', () async {
      final reply = await AnswerEngine(EmptyTariffs()).ask('berapa 25 kali 4');
      expect(reply.text, 'Hasil perhitungan: 25 dikali 4 = 100.');
    });

    test('supports addition, subtraction and division', () async {
      final engine = AnswerEngine(EmptyTariffs());
      expect((await engine.ask('jumlahkan 20 dan 30')).text, contains('= 50.'));
      expect((await engine.ask('kurangi 100 dengan 25')).text, contains('= 75.'));
      expect((await engine.ask('100 dibagi 4')).text, contains('= 25.'));
    });

    test('division by zero returns a safe message', () async {
      final reply = await AnswerEngine(EmptyTariffs()).ask('10 dibagi 0');
      expect(reply.text, contains('pembaginya nol'));
    });
  });
}
