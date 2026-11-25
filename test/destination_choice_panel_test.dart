import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cargo_voice_agent_offline/answer_engine.dart';
import 'package:cargo_voice_agent_offline/destination_choice_panel.dart';

void main() {
  group('DestinationChoicePanel', () {
    testWidgets('shows destination candidates and selects the tapped item',
        (tester) async {
      final first = Choice('Pakisaji, Malang', {
        '_suggestion_level': 'district',
        'city': 'Kabupaten Malang',
        'district': 'Pakisaji',
        'province': 'Jawa Timur',
      });
      final second = Choice('Kepanjen, Malang', {
        '_suggestion_level': 'district',
        'city': 'Kabupaten Malang',
        'district': 'Kepanjen',
        'province': 'Jawa Timur',
      });
      Choice? selected;

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: DestinationChoicePanel(
            choices: [first, second],
            onSelected: (choice) => selected = choice,
          ),
        ),
      ));

      expect(find.text('Pilih tujuan (2 saran)'), findsOneWidget);
      expect(find.text('Pakisaji'), findsOneWidget);
      expect(find.text('Kepanjen'), findsOneWidget);
      await tester.tap(find.text('Kepanjen'));
      expect(selected, same(second));
    });

    testWidgets('uses village as title and hides when there are no choices',
        (tester) async {
      final choice = Choice('Sukun, Malang', {
        'city': 'Kota Malang',
        'district': 'Sukun',
        'village': 'Bandungrejosari',
        'province': 'Jawa Timur',
      });

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: DestinationChoicePanel(
            choices: [choice],
            onSelected: (_) {},
          ),
        ),
      ));
      expect(find.text('Bandungrejosari'), findsOneWidget);
      expect(find.text('Sukun • Kota Malang • Jawa Timur'), findsOneWidget);

      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: DestinationChoicePanel(
          choices: [],
          onSelected: _ignoreChoice,
        )),
      ));
      expect(find.textContaining('Pilih tujuan'), findsNothing);
    });
  });
}

void _ignoreChoice(Choice choice) {}
