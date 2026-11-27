# Benchmark ASR NEXT Cargo Bahasa Indonesia

## Tujuan

Membandingkan pengenalan suara pada perangkat Android untuk pertanyaan NEXT Cargo. Benchmark ini tidak mengubah model produksi, mesin tarif, atau database.

## Korpus awal

File `test/fixtures/asr_cargo_benchmark.json` berisi 30 kalimat referensi dengan kategori:
- tarif Reguler
- tarif khusus
- SP1, SP2, dan SP3
- tarif motor dan sepeda
- angka dan satuan berat
- variasi ucapan alami
- nama tujuan dan alamat

Tes `test/asr_cargo_benchmark_test.dart` memverifikasi bahwa kalimat referensi dapat masuk ke intent cargo. Tes ini **bukan** pengukuran akurasi audio; hasilnya hanya memeriksa parser setelah transkripsi.

## Protokol rekaman yang disarankan

1. Gunakan minimal 3 pembicara dewasa dengan aksen/kecepatan bicara berbeda.
2. Rekam setiap kalimat dua kali: kondisi tenang dan kondisi bising ringan seperti suasana kendaraan/ruang kerja.
3. Gunakan HP Android yang sama, posisi mikrofon dan jarak bicara sekitar 30–50 cm.
4. Simpan audio tanpa kompresi sebagai WAV mono PCM 16-bit, 16 kHz. Jangan mengedit noise atau memotong jeda hanya untuk satu model.
5. Gunakan kalimat referensi yang sama persis untuk setiap mesin. Jangan memperbaiki transkrip sebelum pencatatan skor.
6. Catat perangkat, versi Android, model, jumlah thread, waktu transkripsi, dan penggunaan memori jika tersedia.
7. Ulangi setiap pengukuran waktu minimal tiga kali setelah satu kali pemanasan model.

## Mesin yang dibandingkan

| ID | Mesin | Status |
|---|---|---|
| LRT-TINY | Whisper Tiny multilingual INT8 melalui Sherpa ONNX, konfigurasi produksi sekarang | Baseline |
| ANDROID | STT bawaan Android dengan locale Bahasa Indonesia dan opsi on-device | Pembanding; hasil offline tergantung model bahasa perangkat |
| ID-SMALL | Model Whisper khusus Bahasa Indonesia | Kandidat riset; belum terintegrasi dan harus diverifikasi format/runtime serta lisensinya sebelum diuji di Android |

Jangan menganggap file ONNX yang ditujukan untuk Transformers.js otomatis kompatibel dengan Sherpa ONNX. Kandidat model harus diperiksa arsitektur, tokenizer, input/output, lisensi, dan dukungan runtime terlebih dahulu.

## Skor yang wajib dicatat

- **WER** (Word Error Rate): kesalahan kata secara keseluruhan.
- **CER** (Character Error Rate): kesalahan karakter.
- **Exact destination**: kecocokan nama kelurahan, kecamatan, kota/kabupaten.
- **Exact number**: kecocokan angka berat, desimal, dan kapasitas kendaraan.
- **Intent accuracy**: apakah pertanyaan masuk ke intent yang benar.
- **Tariff answer accuracy**: apakah transkrip menghasilkan tujuan, layanan, dan perhitungan tarif yang benar terhadap fixture database.
- **Latency**: waktu dari selesai merekam sampai transkrip tersedia.
- **Stability**: crash, hasil kosong, timeout, atau kebutuhan mengulang.

Normalisasi untuk WER/CER boleh mengabaikan kapitalisasi dan tanda baca, tetapi angka, nama wilayah, serta satuan tidak boleh dihapus. Nama wilayah dan angka harus dinilai terpisah karena kesalahan pada keduanya berdampak langsung pada ongkir.

## Format lembar hasil

| Mesin | WER | CER | Tujuan tepat | Angka tepat | Intent tepat | Median latency | Gagal/crash |
|---|---:|---:|---:|---:|---:|---:|---:|
| LRT-TINY | — | — | — | — | — | — | — |
| ANDROID | — | — | — | — | — | — | — |
| ID-SMALL | — | — | — | — | — | — | — |

## Kriteria keputusan

Jangan mengganti baseline hanya karena WER umum lebih rendah. Model baru harus:
- memperbaiki atau setidaknya tidak menurunkan akurasi nama tujuan dan angka;
- dapat berjalan sepenuhnya offline setelah model tersedia;
- stabil pada perangkat target;
- memiliki waktu respons dan penggunaan memori yang dapat diterima;
- mempunyai lisensi yang sesuai untuk distribusi aplikasi.

**Belum ada model alternatif yang diaktifkan.** Keputusan integrasi hanya dibuat setelah pengujian audio nyata dan verifikasi kompatibilitas.
