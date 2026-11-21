import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'next_cargo_tariff_service.dart';

class FareManagerPage extends StatefulWidget {
  const FareManagerPage({super.key});
  @override State<FareManagerPage> createState()=>_FareManagerPageState();
}
class _FareManagerPageState extends State<FareManagerPage> {
  int count=0; String? filename; Uint8List? bytes; NextCargoImportPreview? preview;
  bool replace=true,busy=false;
  @override void initState(){super.initState();reload();}
  Future<void> reload() async {try{final n=await NextCargoTariffService.count();if(mounted)setState(()=>count=n);}catch(e){msg('Gagal membaca database: '+e.toString(),true);}}
  void msg(String s,[bool error=false]){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(s),backgroundColor:error?Colors.red:Colors.green));}
  Future<void> pick() async {
    try{
      final f=await FilePicker.platform.pickFiles(type:FileType.custom,allowedExtensions:['csv'],withData:true);
      if(f==null)return; final file=f.files.single; final data=file.bytes;
      if(data==null)throw Exception('File tidak dapat dibaca.');
      setState(()=>busy=true); final p=await NextCargoTariffService.preview(data);
      if(mounted)setState(()=>{filename=file.name,bytes=data,preview=p});
    }catch(e){msg('CSV tidak valid: '+e.toString(),true);}finally{if(mounted)setState(()=>busy=false);}
  }
  Future<void> apply() async {
    final data=bytes;if(data==null||preview==null)return;
    final yes=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(
      title:Text(replace?'Ganti seluruh tarif?':'Gabungkan tarif?'),
      content:Text(replace?'Data aktif diganti dengan '+preview!.rowCount.toString()+' tujuan. Backup otomatis dibuat.':'Tujuan sama diperbarui dan tujuan lain dipertahankan. Backup otomatis dibuat.'),
      actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Batal')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Lanjutkan'))]));
    if(yes!=true)return;setState(()=>busy=true);
    try{final n=await NextCargoTariffService.importCsv(data,replace:replace);await reload();if(!mounted)return;setState(()=>{filename=null,bytes=null,preview=null});msg(n.toString()+' baris tersimpan offline.');}
    catch(e){msg('Impor gagal: '+e.toString(),true);}finally{if(mounted)setState(()=>busy=false);}
  }
  Future<void> restore() async {
    final yes=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(title:const Text('Pulihkan backup?'),content:const Text('Tarif aktif dikembalikan ke kondisi sebelum impor terakhir.'),actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Batal')),FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Pulihkan'))]));
    if(yes!=true)return;setState(()=>busy=true);
    try{final ok=await NextCargoTariffService.restore();await reload();msg(ok?'Backup dipulihkan.':'Backup belum tersedia.',!ok);}catch(e){msg('Pemulihan gagal: '+e.toString(),true);}finally{if(mounted)setState(()=>busy=false);}
  }
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Kelola Tarif NEXT Cargo'),backgroundColor:const Color(0xFFD32F2F),foregroundColor:Colors.white),
    body:ListView(padding:const EdgeInsets.all(16),children:[
      Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('Database lokal: '+count.toString()+' tujuan',style:Theme.of(context).textTheme.titleLarge),
        const SizedBox(height:8),const Text('Asal tarif MALANG KOTA. Semua 25 kolom disimpan di SQLite dan dapat dicari offline.'),
        const SizedBox(height:12),Wrap(spacing:8,children:[
          FilledButton.icon(onPressed:busy?null:pick,icon:const Icon(Icons.upload_file),label:const Text('Impor CSV NEXT Cargo')),
          OutlinedButton.icon(onPressed:busy?null:restore,icon:const Icon(Icons.restore),label:const Text('Pulihkan backup'))]),
      ]))),
      if(preview!=null)...[
        Text('Pratinjau: '+(filename??''),style:Theme.of(context).textTheme.titleMedium),
        Text(preview!.rowCount.toString()+' baris valid • Asal MALANG KOTA'),
        SegmentedButton<bool>(segments:const [ButtonSegment(value:true,label:Text('Ganti semua')),ButtonSegment(value:false,label:Text('Gabungkan'))],selected:{replace},onSelectionChanged:(v)=>setState(()=>replace=v.first)),
        ...preview!.sampleDestinations.map((s)=>ListTile(dense:true,leading:const Icon(Icons.location_on_outlined),title:Text(s))),
        FilledButton.icon(onPressed:busy?null:apply,icon:const Icon(Icons.check_circle),label:const Text('Terapkan tarif')),
        TextButton(onPressed:busy?null:()=>setState(()=>{preview=null,bytes=null,filename=null}),child:const Text('Batalkan')),
      ],
      if(busy)const Padding(padding:EdgeInsets.all(24),child:Center(child:CircularProgressIndicator())),
      const Text('Header NEXT Cargo dideteksi otomatis walau file memiliki baris judul di atas header.'),
    ]),
  );
}
