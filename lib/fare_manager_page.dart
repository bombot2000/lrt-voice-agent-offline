import 'dart:convert';
import 'dart:typed_data';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '');
int? _money(dynamic v) {
  if (v is num) return v.round();
  final digits = v.toString().replaceAll(RegExp(r'[^0-9]'), '');
  return digits.isEmpty ? null : int.tryParse(digits);
}

class FareRecord {
  final String origin, destination, service;
  final int price;
  const FareRecord(this.origin, this.destination, this.service, this.price);
  String get id => _norm(origin) + '|' + _norm(destination) + '|' + _norm(service);
  Map<String,dynamic> toJson() => {'asal':origin,'tujuan':destination,'layanan':service,'ongkir':price};
  factory FareRecord.parse(Map row) {
    final m = {for(final e in row.entries) _norm(e.key.toString()):e.value};
    String get(List<String> names) {
      for(final n in names) {
        final v=m[_norm(n)];
        if(v!=null && v.toString().trim().isNotEmpty) return v.toString().trim();
      }
      return '';
    }
    final a=get(['asal','origin','dari','stasiun_asal']);
    final b=get(['tujuan','destination','ke','stasiun_tujuan']);
    final s=get(['layanan','service','jenis']);
    final p=_money(get(['ongkir','tarif','harga','price','biaya']));
    if(a.isEmpty || b.isEmpty || p==null || p<=0) {
      throw const FormatException('Kolom asal, tujuan, dan ongkir wajib valid.');
    }
    return FareRecord(a,b,s.isEmpty?'REGULER':s,p);
  }
}

class FareDataService {
  static const dataKey='lrt_fare_data_v1', backupKey='lrt_fare_backup_v1';
  static Future<List<FareRecord>> load() async {
    final p=await SharedPreferences.getInstance(), raw=p.getString(dataKey);
    if(raw==null) return [];
    try { return (jsonDecode(raw) as List).map((e)=>FareRecord.parse(Map<String,dynamic>.from(e))).toList(); }
    catch(_) { return []; }
  }
  static Future<List<FareRecord>> parse(String name, Uint8List bytes) async {
    final n=name.toLowerCase(); List<Map> rows=[];
    if(n.endsWith('.json')) {
      final d=jsonDecode(utf8.decode(bytes));
      final data=d is List?d:d is Map?(d['tarif']??d['fares']??d['data']):null;
      if(data is! List) throw const FormatException('JSON harus berupa daftar tarif.');
      rows=data.cast<Map>();
    } else if(n.endsWith('.csv')) {
      final t=const CsvToListConverter(shouldParseNumbers:false).convert(utf8.decode(bytes,allowMalformed:true));
      if(t.length<2) throw const FormatException('CSV tanpa baris data.');
      final h=t.first.map((e)=>e.toString().trim()).toList();
      rows=t.skip(1).where((r)=>r.any((v)=>v.toString().trim().isNotEmpty))
        .map((r)=>{for(var i=0;i<h.length;i++) h[i]:i<r.length?r[i]:''}).toList();
    } else if(n.endsWith('.xlsx')) {
      final book=Excel.decodeBytes(bytes);
      if(book.tables.isEmpty) throw const FormatException('Sheet Excel tidak ditemukan.');
      final sh=book.tables.values.first;
      if(sh.rows.length<2) throw const FormatException('Excel tanpa baris data.');
      final h=sh.rows.first.map((c)=>c?.value?.toString().trim()??'').toList();
      rows=sh.rows.skip(1).where((r)=>r.any((c)=>c?.value!=null))
        .map((r)=>{for(var i=0;i<h.length;i++) h[i]:i<r.length?r[i]?.value??'':''}).toList();
    } else { throw const FormatException('Gunakan JSON, CSV, atau Excel .xlsx.'); }
    final out=<FareRecord>[];
    for(var i=0;i<rows.length;i++) {
      try { out.add(FareRecord.parse(rows[i])); }
      catch(e) { throw FormatException('Baris '+(i+2).toString()+': '+e.toString()); }
    }
    if(out.isEmpty) throw const FormatException('Tidak ada tarif valid.');
    final ids=<String>{};
    for(final r in out) { if(!ids.add(r.id)) throw FormatException('Rute ganda: '+r.origin+' ke '+r.destination); }
    return out;
  }
  static Future<void> apply(List<FareRecord> incoming,bool replace) async {
    final p=await SharedPreferences.getInstance(), old=p.getString(dataKey)??'[]';
    final merged=<String,FareRecord>{
      if(!replace) for(final r in await load()) r.id:r,
      for(final r in incoming) r.id:r,
    };
    if(!await p.setString(backupKey,old)) throw Exception('Backup data lama gagal.');
    if(!await p.setString(dataKey,jsonEncode(merged.values.map((e)=>e.toJson()).toList()))) {
      await p.setString(dataKey,old); throw Exception('Simpan gagal; data lama dipulihkan.');
    }
  }
  static Future<bool> restore() async {
    final p=await SharedPreferences.getInstance(), b=p.getString(backupKey);
    if(b==null) return false; return p.setString(dataKey,b);
  }
  static Future<void> exportTemplate() async {
    const csv='asal,tujuan,layanan,ongkir\nMALANG,SURABAYA,REGULER,15000\n';
    await FilePicker.platform.saveFile(
      fileName:'template_data_ongkir.csv',
      bytes:Uint8List.fromList([0xEF,0xBB,0xBF,...utf8.encode(csv)]),
    );
  }
  static Future<void> export(String ext) async {
    final rows=(await load()).map((e)=>e.toJson()).toList();
    final data=ext=='json'?const JsonEncoder.withIndent('  ').convert(rows):
      const ListToCsvConverter().convert([['asal','tujuan','layanan','ongkir'],
        ...rows.map((r)=>[r['asal'],r['tujuan'],r['layanan'],r['ongkir']])]);
    final bytes=Uint8List.fromList(ext=='csv'?[0xEF,0xBB,0xBF,...utf8.encode(data)]:utf8.encode(data));
    await FilePicker.platform.saveFile(fileName:'data_ongkir_lrt.'+ext,bytes:bytes);
  }
}

class FareManagerPage extends StatefulWidget {
  const FareManagerPage({super.key});
  @override State<FareManagerPage> createState()=>_FareManagerPageState();
}
class _FareManagerPageState extends State<FareManagerPage> {
  List<FareRecord> current=[],preview=[];
  String? filename; bool replace=false,busy=false;
  @override void initState(){super.initState();_reload();}
  Future<void> _reload() async {final d=await FareDataService.load();if(mounted)setState(()=>current=d);}
  void _msg(String s,[bool error=false]) {if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(s),backgroundColor:error?Colors.red:Colors.green));}
  Future<void> _pick() async {
    try {
      final f=await FilePicker.platform.pickFiles(type:FileType.custom,allowedExtensions:['json','csv','xlsx'],withData:true);
      if(f==null||f.files.single.bytes==null)return;
      setState(()=>busy=true);
      final parsed=await FareDataService.parse(f.files.single.name,f.files.single.bytes!);
      if(mounted)setState(() { preview=parsed; filename=f.files.single.name; });
    } catch(e){_msg('File tidak valid: '+e.toString(),true);}
    finally{if(mounted)setState(()=>busy=false);}
  }
  Future<void> _apply() async {
    setState(()=>busy=true);
    try{await FareDataService.apply(preview,replace);await _reload();if(mounted)setState(() { preview=[]; filename=null; });_msg('Tarif diperbarui. Backup lama tersimpan.');}
    catch(e){_msg('Gagal menerapkan tarif: '+e.toString(),true);}
    finally{if(mounted)setState(()=>busy=false);}
  }
  Future<void> _restore() async {
    final yes=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(
      title:const Text('Pulihkan backup?'),content:const Text('Tarif aktif diganti dengan data sebelum impor terakhir.'),
      actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Batal')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Pulihkan'))]));
    if(yes!=true)return;final ok=await FareDataService.restore();await _reload();_msg(ok?'Backup dipulihkan.':'Backup belum tersedia.',!ok);
  }
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Kelola Data Ongkir'),backgroundColor:const Color(0xFFD32F2F),foregroundColor:Colors.white),
    body:ListView(padding:const EdgeInsets.all(16),children:[
      Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('Data tersimpan: '+current.length.toString()+' rute',style:Theme.of(context).textTheme.titleMedium),
        const SizedBox(height:6),const Text('Data tersimpan di HP dan dapat digunakan offline.'),
        Wrap(spacing:8,runSpacing:8,children:[
          OutlinedButton.icon(onPressed:busy?null:_pick,icon:const Icon(Icons.upload_file),label:const Text('Impor file')),
          OutlinedButton.icon(onPressed:current.isEmpty?null:()=>FareDataService.export('json'),icon:const Icon(Icons.data_object),label:const Text('Ekspor JSON')),
          OutlinedButton.icon(onPressed:current.isEmpty?null:()=>FareDataService.export('csv'),icon:const Icon(Icons.table_view),label:const Text('Ekspor CSV')),
          OutlinedButton.icon(onPressed:busy?null:FareDataService.exportTemplate,icon:const Icon(Icons.file_download),label:const Text('Template CSV')),
          TextButton.icon(onPressed:_restore,icon:const Icon(Icons.restore),label:const Text('Pulihkan backup')),
        ]),
      ]))),
      if(filename!=null)...[
        Text('Pratinjau: '+filename!,style:Theme.of(context).textTheme.titleMedium),
        const SizedBox(height:8),
        SegmentedButton<bool>(segments:const[
          ButtonSegment(value:false,label:Text('Perbarui/campur')),
          ButtonSegment(value:true,label:Text('Ganti semua'))],
          selected:{replace},onSelectionChanged:(v)=>setState(()=>replace=v.first)),
        const SizedBox(height:8),
        Text(replace?'Semua tarif lama akan diganti.':'Rute sama diperbarui; rute lain tetap dipertahankan.'),
        Text(preview.length.toString()+' baris valid',style:const TextStyle(fontWeight:FontWeight.bold)),
        SizedBox(height:250,child:ListView.builder(itemCount:preview.length,itemBuilder:(c,i){
          final r=preview[i];return ListTile(dense:true,title:Text(r.origin+' → '+r.destination),subtitle:Text(r.service),trailing:Text('Rp '+r.price.toString()));})),
        FilledButton.icon(onPressed:busy||preview.isEmpty?null:_apply,icon:const Icon(Icons.check),label:const Text('Terapkan tarif')),
        TextButton(onPressed:busy?null:()=>setState(() { preview=[]; filename=null; }),child:const Text('Batalkan pratinjau')),
      ],
      if(busy)const Center(child:Padding(padding:EdgeInsets.all(18),child:CircularProgressIndicator())),
      const SizedBox(height:12),const Text('Format file',style:TextStyle(fontWeight:FontWeight.bold)),
      const Text('Header wajib: asal, tujuan, ongkir. Kolom layanan opsional.'),
      const Text('JSON: daftar objek tarif. CSV: asal,tujuan,layanan,ongkir. Excel: .xlsx.'),
      const Text('Riwayat lama tidak diubah. Tarif baru digunakan setelah impor berhasil.'),
    ]));
}
