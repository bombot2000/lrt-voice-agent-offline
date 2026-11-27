import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:excel/excel.dart' as xls;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:cargo_voice_agent_offline/next_cargo_tariff_service.dart';

void main() {
  const header = 'Asal Kota,Tj. Propinsi,Tj. Kota,Tj. Kecamatan,Tj. Kelurahan,Handler,Stt Dooring,Lead Time,Tarif 10Kg,Min Reg,Tarif Reg,Min SP1,Tarif SP1,Min SP2,Tarif SP2,Min SP3,Tarif SP3,Tarif Khusus,Motor 100cc,Motor 125cc,Motor 150cc,Motor 250cc,Motor 500cc,Motor 750cc,Sepeda';
  const row = 'MALANG KOTA,BALI,BADUNG,ABIANSEMAL,ABIANSEMAL,DENPASAR AGEN,EKSPEDISI LAIN,6,0,25,4700,200,4500,500,4250,1000,4000,3400,705000,945900,1175000,1903500,2350000,3231250,293750';
  Uint8List bytes(String text) => Uint8List.fromList(utf8.encode(text));

  test('rejects CSV with invalid UTF-8 bytes and explains required encoding', () async {
    final invalidUtf8 = Uint8List.fromList([
      ...utf8.encode('$header\n$row\n'),
      0xC3,
      0x28,
    ]);
    await expectLater(
      NextCargoTariffService.preview('windows-1252.csv', invalidUtf8),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('CSV UTF-8'),
        ),
      ),
    );
  });

  test('rejects decoded replacement character U+FFFD in CSV', () async {
    final replacement = utf8.encode('$header\n$row\n');
    final bytesWithReplacement = Uint8List.fromList([
      ...replacement,
      ...utf8.encode('\uFFFD'),
    ]);
    await expectLater(
      NextCargoTariffService.preview('replacement.csv', bytesWithReplacement),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('U+FFFD'),
        ),
      ),
    );
  });

  test('detects header after title and blank row, retaining NEXT Cargo structure', () async {
    final result = await NextCargoTariffService.preview('sample.csv', bytes('NEXT TARIF 2026-11-21\n\n$header\n$row\n'));
    expect(result.rowCount, 1);
    expect(result.sampleDestinations.single, 'ABIANSEMAL, ABIANSEMAL, BADUNG, BALI');
  });

  test('reads typed XLSX cells and finds tariff sheet after a cover sheet', () async {
    final workbook = xls.Excel.createExcel();
    final cover = workbook['Cover'];
    cover.cell(xls.CellIndex.indexByString('A1')).value =
        xls.TextCellValue('Keterangan tarif');
    final sheet = workbook['Tarif'];
    sheet.cell(xls.CellIndex.indexByString('A1')).value =
        xls.TextCellValue('DATA TARIF NEXT CARGO');
    for (var i = 0; i < header.split(',').length; i++) {
      sheet.cell(xls.CellIndex.indexByColumnRow(
        columnIndex: i,
        rowIndex: 2,
      )).value = xls.TextCellValue(header.split(',')[i]);
    }
    final values = row.split(',');
    for (var i = 0; i < values.length; i++) {
      final value = values[i];
      final numericColumns = {7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24};
      final cellValue = numericColumns.contains(i)
          ? xls.IntCellValue(int.parse(value))
          : xls.TextCellValue(value);
      sheet.cell(xls.CellIndex.indexByColumnRow(
        columnIndex: i,
        rowIndex: 3,
      )).value = cellValue;
    }
    final encoded = workbook.save();
    expect(encoded, isNotNull);
    final result = await NextCargoTariffService.preview(
      'sample.xlsx',
      Uint8List.fromList(encoded!),
    );
    expect(result.rowCount, 1);
    expect(result.sampleDestinations.single, 'ABIANSEMAL, ABIANSEMAL, BADUNG, BALI');
  });

  test('uses exact CSV service minimum when calculating billable weight', () {
    expect(NextCargoTariffService.billableWeight(5, 10), 10);
    expect(NextCargoTariffService.billableWeight(20, 20), 20);
    expect(NextCargoTariffService.billableWeight(20, 59), 59);
    expect(NextCargoTariffService.billableWeight(160, 150), 160);
  });

  test('rejects origin other than MALANG KOTA', () async {
    expect(
      () => NextCargoTariffService.preview('sample.csv', bytes('$header\nJAKARTA,BALI,BADUNG,ABIANSEMAL,ABIANSEMAL,DENPASAR AGEN,EKSPEDISI LAIN,6,0,25,4700,200,4500,500,4250,1000,4000,3400,705000,945900,1175000,1903500,2350000,3231250,293750')),
      throwsFormatException,
    );
  });

  test('merges identical duplicate destination aliases', () async {
    final result = await NextCargoTariffService.preview(
      'sample.csv',
      bytes('$header\n$row\n$row'),
    );
    expect(result.rowCount, 1);
  });

  test('rejects duplicate destination when tariff values conflict', () async {
    const conflictingRow = 'MALANG KOTA,BALI,BADUNG,ABIANSEMAL,ABIANSEMAL,DENPASAR AGEN,EKSPEDISI LAIN,6,0,25,9999,200,4500,500,4250,1000,4000,3400,705000,945900,1175000,1903500,2350000,3231250,293750';
    await expectLater(
      NextCargoTariffService.preview(
        'sample.csv',
        bytes('$header\n$row\n$conflictingRow'),
      ),
      throwsFormatException,
    );
  });

  test('rejects a generic four-column fare CSV', () async {
    expect(
      () => NextCargoTariffService.preview('sample.csv', bytes('asal,tujuan,layanan,ongkir\nMALANG,SURABAYA,REG,15000')),
      throwsFormatException,
    );
  });

  group('normalisasi dan validasi impor', () {
    test('membaca CSV titik koma dan akhir baris CRLF', () async {
      final semicolon = '$header\r\n$row'.replaceAll(',', ';');
      final parsed = await NextCargoTariffService.parse('id.csv', bytes(semicolon));
      expect(parsed.rowCount, 1);
      expect(parsed.records.single['tarif_reg'], '4700');
    });

    test('angka berformat ribuan dinormalisasi saat impor', () async {
      final formatted = row.replaceFirst(',4700,', ',"4.700",').replaceFirst(',25,', ',25.0,');
      final parsed = await NextCargoTariffService.parse('a.csv', bytes('$header\n$formatted'));
      expect(parsed.records.single['tarif_reg'], '4700');
      expect(parsed.records.single['min_reg'], '25');
    });

    test('nilai yang sama dengan format berbeda bukan konflik', () async {
      final alt = row.replaceFirst(',4700,', ',4700.0,');
      final result = await NextCargoTariffService.preview('a.csv', bytes('$header\n$row\n$alt'));
      expect(result.rowCount, 1);
    });

    test('menolak sel rumus Excel pada kolom tarif', () async {
      final formula = row.replaceFirst(',4700,', ',=B2*2,');
      await expectLater(
        NextCargoTariffService.preview('a.csv', bytes('$header\n$formula')),
        throwsFormatException,
      );
    });

    test('menolak kolom angka yang berisi teks atau rentang', () async {
      final text = row.replaceFirst(',4700,', ',10-20,');
      await expectLater(
        NextCargoTariffService.preview('a.csv', bytes('$header\n$text')),
        throwsFormatException,
      );
    });
  });
  test('exports active tariffs as a JSON file that can be imported again', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await NextCargoTariffService.resetForTesting();
    addTearDown(NextCargoTariffService.resetForTesting);

    final parsed = await NextCargoTariffService.parse(
      'source.csv',
      bytes('$header\n$row'),
    );
    await NextCargoTariffService.importParsed(parsed, replace: true);

    final exported = await NextCargoTariffService.exportJson();
    final document = jsonDecode(utf8.decode(exported)) as Map<String, dynamic>;
    expect(document['format'], 'next_cargo_tariff_backup');
    expect(document['version'], 1);
    expect(document['data'], isA<List<dynamic>>());

    final restored = await NextCargoTariffService.parse('backup.json', exported);
    expect(restored.rowCount, 1);
    expect(restored.records.single['origin'], 'MALANG KOTA');
    expect(restored.records.single['district'], 'ABIANSEMAL');
    expect(restored.records.single['tarif_reg'], '4700');
  });

  test('merge updates normalized destination aliases instead of inserting duplicates', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await NextCargoTariffService.resetForTesting();
    addTearDown(NextCargoTariffService.resetForTesting);

    final firstRow = row.replaceFirst(
      'BALI,BADUNG,ABIANSEMAL,ABIANSEMAL',
      'JAWA TIMUR,KAB. MALANG,PAKISAJI,PAKISAJI',
    );
    final aliasRow = row
        .replaceFirst(
          'BALI,BADUNG,ABIANSEMAL,ABIANSEMAL',
          'JAWA TIMUR,KAB MALANG,PAKISAJI,PAKISAJI',
        )
        .replaceFirst(',4700,', ',4800,');

    final first = await NextCargoTariffService.parse(
      'first.csv',
      bytes('$header\n$firstRow'),
    );
    await NextCargoTariffService.importParsed(first, replace: true);

    final second = await NextCargoTariffService.parse(
      'alias.csv',
      bytes('$header\n$aliasRow'),
    );
    await NextCargoTariffService.importParsed(second, replace: false);

    expect(await NextCargoTariffService.count(), 1);
    final found = await NextCargoTariffService.findDestination('Pakisaji Malang');
    expect(found.length, 1);
    expect(found.single['city'], 'KAB MALANG');
    expect(found.single['tarif_reg'], '4800');
  });

  test('city-only lookup returns every distinct district beyond eight rows', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await NextCargoTariffService.resetForTesting();
    addTearDown(NextCargoTariffService.resetForTesting);

    final districts = [
      'KEPANJEN', 'PAKISAJI', 'TAJINAN', 'BULULAWANG', 'TUREN',
      'DAMPIT', 'PAGELARAN', 'GONDANGLEGI', 'WAGIR', 'DAU',
    ];
    final csvRows = districts.map((district) => row.replaceFirst(
      'BALI,BADUNG,ABIANSEMAL,ABIANSEMAL',
      'JAWA TIMUR,KABUPATEN MALANG,$district,$district',
    )).join('\n') + '\n' + row.replaceFirst(
      'BALI,BADUNG,ABIANSEMAL,ABIANSEMAL',
      'JAWA TENGAH,KABUPATEN PEMALANG,PEMALANG,PEMALANG',
    );
    final parsed = await NextCargoTariffService.parse(
      'malang.csv',
      bytes('$header\n$csvRows'),
    );
    await NextCargoTariffService.importParsed(parsed, replace: true);

    final found = await NextCargoTariffService.findDestination('Malang');
    expect(found.length, districts.length);
    expect(found.map((item) => item['district']).toSet(), districts.toSet());
    expect(found.every((item) =>
      !(item['city'] ?? '').toString().contains('PEMALANG'),
    ), isTrue);
    expect(found.every((item) => item['_suggestion_level'] == 'district'), isTrue);
  });

  test('whole-word destination matches rank before substring matches', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await NextCargoTariffService.resetForTesting();
    addTearDown(NextCargoTariffService.resetForTesting);

    final substringRows = [
      for (var i = 0; i < 10; i++)
        row.replaceFirst(
          'BALI,BADUNG,ABIANSEMAL,ABIANSEMAL',
          'JAWA TIMUR,KOTA CONTOH,DISTRICT ${i.toString().padLeft(2, '0')},BATUAN ${i.toString().padLeft(2, '0')}',
        ),
    ];
    final exactRow = row.replaceFirst(
      'BALI,BADUNG,ABIANSEMAL,ABIANSEMAL',
      'JAWA TIMUR,KOTA BATU,DISTRICT KHUSUS,BATU',
    );
    final parsed = await NextCargoTariffService.parse(
      'batu.csv',
      bytes('$header\n${[...substringRows, exactRow].join('\n')}'),
    );
    await NextCargoTariffService.importParsed(parsed, replace: true);

    final found = await NextCargoTariffService.findDestination('BATU');
    expect(found, isNotEmpty);
    expect(found.first['village'], 'BATU');
  });

  test('multi-word city query returns every distinct district', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await NextCargoTariffService.resetForTesting();
    addTearDown(NextCargoTariffService.resetForTesting);

    final districts = [
      'GAMBIR', 'TANAH ABANG', 'MENTENG', 'SENEN', 'CEMPAKA PUTIH',
      'JOHAR BARU', 'KEMAYORAN', 'SAWAH BESAR', 'KELAPA GADING',
      'TANJUNG PRIOK',
    ];
    final csvRows = districts.map((district) => row.replaceFirst(
      'BALI,BADUNG,ABIANSEMAL,ABIANSEMAL',
      'DKI JAKARTA,KOTA ADMINISTRASI JAKARTA PUSAT,$district,$district',
    )).join('\n');
    final parsed = await NextCargoTariffService.parse(
      'jakarta-pusat.csv',
      bytes('$header\n$csvRows'),
    );
    await NextCargoTariffService.importParsed(parsed, replace: true);

    final found = await NextCargoTariffService.findDestination('Jakarta Pusat');
    expect(found.length, districts.length);
    expect(found.map((item) => item['district']).toSet(), districts.toSet());
    expect(found.every((item) => item['_suggestion_level'] == 'district'), isTrue);
  });

  test('same city and district names are matched by their field qualifiers', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await NextCargoTariffService.resetForTesting();
    addTearDown(NextCargoTariffService.resetForTesting);

    final sameName = row.replaceFirst(
      'BALI,BADUNG,ABIANSEMAL,ABIANSEMAL',
      'JAWA TENGAH,WONOSOBO,WONOSOBO,WONOSOBO',
    );
    final otherDistrict = row.replaceFirst(
      'BALI,BADUNG,ABIANSEMAL,ABIANSEMAL',
      'JAWA TENGAH,WONOSOBO,KALIKAJAR,KALIKAJAR',
    );
    // Nama Wonosobo hanya muncul sebagai kelurahan di kota lain.
    final incidentalMatch = row.replaceFirst(
      'BALI,BADUNG,ABIANSEMAL,ABIANSEMAL',
      'JAWA TIMUR,KOTA MALANG,DENPASAR,WONOSOBO',
    );
    final parsed = await NextCargoTariffService.parse(
      'wonosobo.csv',
      bytes('$header\n$sameName\n$otherDistrict\n$incidentalMatch'),
    );
    await NextCargoTariffService.importParsed(parsed, replace: true);

    // Tanpa kecamatan, nama kota saja memang masih ambigu.
    final cityOnly = await NextCargoTariffService.findDestination('Wonosobo');
    expect(cityOnly.length, 2);

    // Kata yang sama harus tetap dicocokkan pada dua kolom yang berbeda.
    final sameCityDistrict = await NextCargoTariffService.findDestination(
      'Wonosobo kec Wonosobo',
    );
    expect(sameCityDistrict.length, 1);
    expect(sameCityDistrict.single['city'], 'WONOSOBO');
    expect(sameCityDistrict.single['district'], 'WONOSOBO');

    // Penulisan dua nama identik tanpa label kecamatan tetap dipahami
    // sebagai Kota Wonosobo + Kecamatan Wonosobo.
    final repeatedName = await NextCargoTariffService.findDestination(
      'Wonosobo Wonosobo',
    );
    expect(repeatedName.length, 1);
    expect(repeatedName.single['city'], 'WONOSOBO');
    expect(repeatedName.single['district'], 'WONOSOBO');

    // Pencarian satu kata kota tidak boleh mengambil kota lain hanya
    // karena nama kelurahannya kebetulan mengandung "Wonosobo".
    expect(cityOnly.every((r) => r['city'] == 'WONOSOBO'), isTrue);

    final explicitLabels = await NextCargoTariffService.findDestination(
      'Kota Wonosobo Kecamatan Kalikajar',
    );
    expect(explicitLabels.length, 1);
    expect(explicitLabels.single['city'], 'WONOSOBO');
    expect(explicitLabels.single['district'], 'KALIKAJAR');
  });

  test('first import does not create a restorable empty backup', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await NextCargoTariffService.resetForTesting();
    addTearDown(NextCargoTariffService.resetForTesting);

    final parsed = await NextCargoTariffService.parse(
      'first.csv',
      bytes('$header\n$row'),
    );
    await NextCargoTariffService.importParsed(parsed, replace: true);
    expect(await NextCargoTariffService.count(), 1);
    expect(await NextCargoTariffService.hasBackup(), isFalse);
    expect(await NextCargoTariffService.restore(), isFalse);
    expect(await NextCargoTariffService.count(), 1);
  });

  test('SQLite fuzzy lookup and vocabulary cache invalidation on import/restore', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await NextCargoTariffService.resetForTesting();
    addTearDown(NextCargoTariffService.resetForTesting);

    final original = await NextCargoTariffService.parse(
      'original.csv',
      bytes('$header\n$row'),
    );
    await NextCargoTariffService.importParsed(original, replace: true);

    var found = await NextCargoTariffService.findDestination('ABIANSEMEL');
    expect(found, isNotEmpty);
    expect(found.first['district'], 'ABIANSEMAL');

    final replacementRow = row
        .replaceFirst('BALI,BADUNG,ABIANSEMAL,ABIANSEMAL', 'JAWA TIMUR,KOTA MALANG,DENPASAR,DENPASAR');
    final replacement = await NextCargoTariffService.parse(
      'replacement.csv',
      bytes('$header\n$replacementRow'),
    );
    await NextCargoTariffService.importParsed(replacement, replace: true);

    found = await NextCargoTariffService.findDestination('DENPASAAR');
    expect(found, isNotEmpty);
    expect(found.first['district'], 'DENPASAR');

    expect(await NextCargoTariffService.restore(), isTrue);
    found = await NextCargoTariffService.findDestination('ABIANSEMEL');
    expect(found, isNotEmpty);
    expect(found.first['district'], 'ABIANSEMAL');
    expect(await NextCargoTariffService.findDestination('DENPASAAR'), isEmpty);
  });


  test('SQLite merge preserves other destinations and backup restore is single-use', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await NextCargoTariffService.resetForTesting();
    addTearDown(NextCargoTariffService.resetForTesting);

    final original = await NextCargoTariffService.parse(
      'original.csv',
      bytes('$header\n$row'),
    );
    await NextCargoTariffService.importParsed(original, replace: true);
    expect(await NextCargoTariffService.count(), 1);
    expect(await NextCargoTariffService.hasBackup(), isFalse);

    final secondRow = row.replaceFirst(
      'BALI,BADUNG,ABIANSEMAL,ABIANSEMAL',
      'JAWA TIMUR,KOTA MALANG,DENPASAR,DENPASAR',
    );
    final addition = await NextCargoTariffService.parse(
      'second.csv',
      bytes('$header\n$secondRow'),
    );
    await NextCargoTariffService.importParsed(addition, replace: false);

    expect(await NextCargoTariffService.hasBackup(), isTrue);
    expect(await NextCargoTariffService.count(), 2);
    expect(await NextCargoTariffService.findDestination('ABIANSEMAL'), isNotEmpty);
    expect(await NextCargoTariffService.findDestination('DENPASAR'), isNotEmpty);

    expect(await NextCargoTariffService.restore(), isTrue);
    expect(await NextCargoTariffService.hasBackup(), isFalse);
    expect(await NextCargoTariffService.count(), 1);
    expect(await NextCargoTariffService.findDestination('ABIANSEMAL'), isNotEmpty);
    expect(await NextCargoTariffService.findDestination('DENPASAR'), isEmpty);

    expect(await NextCargoTariffService.restore(), isFalse);
    expect(await NextCargoTariffService.count(), 1);
  });


  test('restore refuses an empty backup and preserves active tariffs', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await NextCargoTariffService.resetForTesting();
    addTearDown(NextCargoTariffService.resetForTesting);

    final parsed = await NextCargoTariffService.parse(
      'active.csv',
      bytes('$header\n$row'),
    );
    await NextCargoTariffService.importParsed(parsed, replace: true);
    expect(await NextCargoTariffService.count(), 1);

    final db = await NextCargoTariffService.open();
    // Simulasikan metadata tersedia tetapi isi backup hilang/rusak.
    await db.update('tariff_backup_meta', {'available': 1}, where: 'id = 1');
    await db.delete('tariff_backup');

    expect(await NextCargoTariffService.hasBackup(), isTrue);
    expect(await NextCargoTariffService.restore(), isFalse);
    expect(await NextCargoTariffService.count(), 1);
    expect(await NextCargoTariffService.findDestination('ABIANSEMAL'), isNotEmpty);
    expect(await NextCargoTariffService.hasBackup(), isFalse);
  });

  test('failed import rolls back active tariffs and preserves the previous backup', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await NextCargoTariffService.resetForTesting();
    addTearDown(NextCargoTariffService.resetForTesting);

    final original = await NextCargoTariffService.parse(
      'original.csv',
      bytes('$header\n$row'),
    );
    await NextCargoTariffService.importParsed(original, replace: true);
    expect(await NextCargoTariffService.hasBackup(), isFalse);

    final secondRow = row.replaceFirst(
      'BALI,BADUNG,ABIANSEMAL,ABIANSEMAL',
      'JAWA TIMUR,KOTA MALANG,DENPASAR,DENPASAR',
    );
    final second = await NextCargoTariffService.parse(
      'second.csv',
      bytes('$header\n$secondRow'),
    );
    await NextCargoTariffService.importParsed(second, replace: true);
    expect(await NextCargoTariffService.hasBackup(), isTrue);

    // Cache pencarian dipanaskan sebelum transaksi yang sengaja digagalkan.
    expect(await NextCargoTariffService.findDestination('DENPASAR'), isNotEmpty);

    final db = await NextCargoTariffService.open();
    await db.execute('''
      CREATE TRIGGER reject_test_tariff
      BEFORE INSERT ON tariffs
      WHEN NEW.city = 'KOTA GAGAL'
      BEGIN
        SELECT RAISE(ABORT, 'simulated import failure');
      END
    ''');

    final failingRow = row.replaceFirst(
      'BALI,BADUNG,ABIANSEMAL,ABIANSEMAL',
      'JAWA TIMUR,KOTA GAGAL,DENPASAR,DENPASAR',
    );
    final failing = await NextCargoTariffService.parse(
      'failing.csv',
      bytes('$header\n$failingRow'),
    );
    await expectLater(
      NextCargoTariffService.importParsed(failing, replace: true),
      throwsA(anything),
    );

    expect(await NextCargoTariffService.count(), 1);
    expect(await NextCargoTariffService.hasBackup(), isTrue);
    expect(await NextCargoTariffService.findDestination('DENPASAR'), isNotEmpty);
    expect(await NextCargoTariffService.findDestination('KOTA GAGAL'), isEmpty);

    // Backup dari sebelum impor gagal tetap dapat dipulihkan.
    expect(await NextCargoTariffService.restore(), isTrue);
    expect(await NextCargoTariffService.hasBackup(), isFalse);
    expect(await NextCargoTariffService.findDestination('ABIANSEMAL'), isNotEmpty);
    expect(await NextCargoTariffService.findDestination('DENPASAR'), isEmpty);
  });

}
