import 'package:flutter_test/flutter_test.dart';
import 'package:cargo_voice_agent_offline/command_parser_service.dart';

void main() {
  group('CommandParserService', () {
    test('normalizes Indonesian text and spaces', () {
      expect(CommandParserService.normalize('  ONGKIR   Malang!!  '), 'ongkir malang');
    });

    test('routes cargo and destination searches separately', () {
      expect(CommandParserService.parse('ongkir Malang Pakisaji 20 kg').intent,
          CommandIntent.cargoTariff);
      expect(CommandParserService.parse('Pakisaji Malang').intent,
          CommandIntent.destinationSearch);
      expect(CommandParserService.parse('halo').intent, CommandIntent.greeting);
    });

    test('parses arithmetic operators and decimal commas', () {
      final parsed = CommandParserService.parse('berapa 12,5 kali 4');
      expect(parsed.intent, CommandIntent.arithmetic);
      expect(parsed.arithmetic!.calculate(), 50);
    });

    test('parses Indonesian phrase forms', () {
      expect(CommandParserService.parse('jumlahkan 20 dan 30').arithmetic!.calculate(), 50);
      expect(CommandParserService.parse('kurangi 100 dengan 25').arithmetic!.calculate(), 75);
      expect(CommandParserService.parse('kalikan 12 dengan 4').arithmetic!.calculate(), 48);
      expect(CommandParserService.parse('bagikan 100 dengan 4').arithmetic!.calculate(), 25);
    });

    test('division by zero is represented safely', () {
      final expression = CommandParserService.parse('10 dibagi 0').arithmetic!;
      expect(expression.calculate(), isNull);
    });

    test('does not classify cargo weight as arithmetic', () {
      expect(CommandParserService.parse('ongkir 20 kg ke Pakisaji').intent,
          CommandIntent.cargoTariff);
    });
  });
}
