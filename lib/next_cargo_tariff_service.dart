import 'dart:convert';
import 'dart:typed_data';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

const headers = ['Asal Kota','Tj. Propinsi','Tj. Kota','Tj. Kecamatan','Tj. Kelurahan','Handler','Stt Dooring','Lead Time','Tarif 10Kg','Min Reg','Tarif Reg','Min SP1','Tarif SP1','Min SP2','Tarif SP2','Min SP3','Tarif SP3','Tarif Khusus','Motor 100cc','Motor 125cc','Motor 150cc','Motor 250cc','Motor 500cc','Motor 750cc','Sepeda'];
const cols = ['origin','province','city','district','village','handler','stt_dooring','lead_time','tarif_10kg','min_reg','tarif_reg','min_sp1','tarif_sp1','min_sp2','tarif_sp2','min_sp3','tarif_sp3','tarif_khusus','motor_100cc','motor_125cc','motor_150cc','motor_250cc','motor_500cc','motor_750cc','sepeda'];
String norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
String sqlCols() => cols.map((c) => '$c TEXT').join(', ');

class NextCargoImportPreview {
  final int rowCount;
  final List<String> sampleDestinations;
  const NextCargoImportPreview(this.rowCount, this.sampleDestinations);
}

class NextCargoTariffService {
  static Database? _db;
  static Future<Database> open() async {
    if (_db != null) return _db!;
    final root = await getDatabasesPath();
    _db = await openDatabase(p.join(root, 'next_cargo_tariffs.db'), version: 1,
      onCreate: (db, version) async {
        await db.execute('CREATE TABLE tariffs (id INTEGER PRIMARY KEY AUTOINCREMENT, ' + sqlCols() + ', UNIQUE(province,city,district,village))');
        await db.execute('CREATE TABLE tariff_backup (id INTEGER PRIMARY KEY, ' + sqlCols() + ')');
        await db.execute('CREATE TABLE tariff_backup_meta (id INTEGER PRIMARY KEY CHECK(id = 1), available INTEGER NOT NULL)');
        await db.insert('tariff_backup_meta', {'id': 1, 'available': 0});
        for (final f in ['province','city','district','village']) {
          await db.execute('CREATE INDEX idx_tariff_' + f + ' ON tariffs(' + f + ')');
        }
      });
    return _db!;
  }
  static List<List<dynamic>> decode(String name, Uint8List bytes) {
    final lower=name.toLowerCase();
    if(lower.endsWith('.csv')) {
      return const CsvToListConverter(shouldParseNumbers:false, eol:'\n').convert(
        utf8.decode(bytes,allowMalformed:true).replaceFirst('\uFEFF',''));
    }
    if(lower.endsWith('.xlsx')) {
      final book=Excel.decodeBytes(bytes);
      if(book.tables.isEmpty) throw const FormatException('Sheet Excel tidak ditemukan.');
      return book.tables.values.first.rows.map((r)=>r.map((c)=>c?.value??'').toList()).toList();
    }
    if(lower.endsWith('.json')) {
      final decoded=jsonDecode(utf8.decode(bytes,allowMalformed:true));
      final data=decoded is List ? decoded : decoded is Map
        ? (decoded['data']??decoded['tarif']??decoded['fares']) : null;
      if(data is! List || data.isEmpty || data.first is! Map) {
        throw const FormatException('JSON harus berisi daftar objek tarif NEXT Cargo.');
      }
      final jsonHeaders=(data.first as Map).keys.map((k)=>k.toString()).toList();
      return [jsonHeaders,...data.map((item)=>jsonHeaders.map((h)=>(item as Map)[h]??'').toList())];
    }
    throw const FormatException('Gunakan file CSV, JSON, atau Excel .xlsx.');
  }
  static int headerAt(List<List<dynamic>> rows) {
    for (var i=0;i<rows.length;i++) {
      if (rows[i].isNotEmpty && norm(rows[i][0].toString().trim())=='asalkota') return i;
    }
    throw const FormatException('Header Asal Kota tidak ditemukan.');
  }
  static Map<String,int> mapHeader(List<dynamic> row) {
    final found=<String,int>{};
    for(var i=0;i<row.length;i++) { found[norm(row[i].toString())]=i; }
    final expected=headers.map(norm).toList();
    final missing=expected.where((h)=>!found.containsKey(h)).toList();
    if(missing.isNotEmpty) throw FormatException('Kolom hilang: '+missing.join(', '));
    return {for(var i=0;i<cols.length;i++) cols[i]:found[expected[i]]!};
  }
  static String cell(List<dynamic> row,int i)=>i<row.length?row[i].toString().trim():'';
  static Future<NextCargoImportPreview> preview(String name, Uint8List bytes) async {
    final rows=decode(name,bytes), at=headerAt(rows), map=mapHeader(rows[at]);
    final keys=<String>{}, samples=<String>[];
    var count=0;
    for(var i=at+1;i<rows.length;i++) {
      final r=rows[i]; if(r.every((v)=>v.toString().trim().isEmpty)) continue;
      final origin=cell(r,map['origin']!);
      if(norm(origin)!='malangkota') throw FormatException('Baris '+(i+1).toString()+': asal harus MALANG KOTA.');
      final p=cell(r,map['province']!), c=cell(r,map['city']!), d=cell(r,map['district']!), v=cell(r,map['village']!);
      if([p,c,d,v].any((x)=>x.isEmpty)) throw FormatException('Baris '+(i+1).toString()+': data tujuan tidak lengkap.');
      final key=[p,c,d,v].map(norm).join('|');
      if(!keys.add(key)) throw FormatException('Tujuan ganda: '+[p,c,d,v].join(' / '));
      count++; if(samples.length<8) samples.add([v,d,c,p].join(', '));
    }
    if(count==0) throw const FormatException('CSV tidak memiliki baris tarif.');
    return NextCargoImportPreview(count,samples);
  }
  static Future<int> importFile(String name, Uint8List bytes,{required bool replace}) async {
    // Validasi ulang di lapisan service agar impor tidak bisa melewati preview UI.
    // Semua pemeriksaan selesai sebelum transaksi dan backup database dimulai.
    await preview(name, bytes);
    final rows=decode(name,bytes), at=headerAt(rows), map=mapHeader(rows[at]), db=await open();
    var count=0;
    await db.transaction((txn) async {
      await txn.delete('tariff_backup');
      await txn.execute('INSERT INTO tariff_backup (id,'+cols.join(',')+') SELECT id,'+cols.join(',')+' FROM tariffs');
      await txn.update('tariff_backup_meta', {'available': 1}, where: 'id = 1');
      if(replace) await txn.delete('tariffs');
      var batch=txn.batch(), pending=0;
      for(var i=at+1;i<rows.length;i++) {
        final r=rows[i]; if(r.every((v)=>v.toString().trim().isEmpty)) continue;
        batch.insert('tariffs',{for(final c in cols)c:cell(r,map[c]!)},conflictAlgorithm:ConflictAlgorithm.replace);
        count++; pending++;
        if(pending>=400) { await batch.commit(noResult:true); batch=txn.batch(); pending=0; }
      }
      if(pending>0) await batch.commit(noResult:true);
    });
    return count;
  }
  /// Berat yang ditagihkan mengikuti minimum layanan pada baris tujuan CSV.
  static num billableWeight(num actualWeight, num serviceMinimum) =>
      actualWeight > serviceMinimum ? actualWeight : serviceMinimum;

  static Future<int> count() async {
    final db=await open();
    return Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) AS n FROM tariffs'))??0;
  }
  static Future<bool> restore() async {
    final db=await open();
    return db.transaction((t) async {
      final available=Sqflite.firstIntValue(await t.rawQuery('SELECT available FROM tariff_backup_meta WHERE id = 1'))??0;
      if(available==0)return false;
      await t.delete('tariffs');
      await t.execute('INSERT INTO tariffs (id,'+cols.join(',')+') SELECT id,'+cols.join(',')+' FROM tariff_backup');
      await t.update('tariff_backup_meta', {'available': 0}, where: 'id = 1');
      return true;
    });
  }
  static Future<List<Map<String,Object?>>> findDestination(String query) async {
    final db=await open();
    const ignored={'tarif','ongkir','ongkos','harga','biaya','ke','dari','tujuan','menuju','pengiriman','kirim','paket','barang','berapa','malang','kota','kabupaten','provinsi','propinsi','kecamatan','kelurahan','desa','reg','reguler','sp1','sp2','sp3','next','cargo','tolong','mohon','coba','cek','carikan','cari','info','informasi','hitung','hitungkan','kalkulasi','estimasi','berapa','untuk','dengan','berat','kg','kilo','kilogram','saya','minta','dong'};
    final tokens=query.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9 ]'),' ').split(RegExp(r'\s+')).where((t)=>t.length>=3&&!RegExp(r'^\d+(?:[.,]\d+)?$').hasMatch(t)&&!ignored.contains(t.toLowerCase())).toSet().toList();
    if(tokens.isEmpty)return [];
    const fields=['province','city','district','village'];
    final clauses=<String>[], args=<Object?>[];
    for(final token in tokens) {
      clauses.add('('+fields.map((f)=>'$f LIKE ?').join(' OR ')+')');
      for(var i=0;i<fields.length;i++){args.add('%'+token+'%');}
    }
    return db.query('tariffs',columns:cols,where:clauses.join(' AND '),whereArgs:args,limit:8);
  }
}
