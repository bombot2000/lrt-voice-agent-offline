import 'package:flutter/material.dart';
import 'offline_asr_service.dart';

class AsrSettingsDialog extends StatefulWidget {
  const AsrSettingsDialog({
    super.key,
    required this.service,
    required this.useOfflineAsr,
    required this.onModeChanged,
    required this.onStatusChanged,
  });

  final OfflineAsrService service;
  final bool useOfflineAsr;
  final ValueChanged<bool> onModeChanged;
  final ValueChanged<String> onStatusChanged;

  @override
  State<AsrSettingsDialog> createState() => _AsrSettingsDialogState();
}

class _AsrSettingsDialogState extends State<AsrSettingsDialog> {
  bool _installed = false;
  bool _downloading = false;
  bool _checking = true;
  double _progress = 0;
  String? _downloadError;

  @override
  void initState() {
    super.initState();
    _checkInstallation();
  }

  Future<void> _checkInstallation() async {
    try {
      final installed = await widget.service.isModelInstalled;
      if (!mounted) return;
      setState(() {
        _installed = installed;
        _checking = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _downloadError = 'Gagal memeriksa model: $error';
      });
    }
  }

  Future<void> _download() async {
    setState(() {
      _downloading = true;
      _progress = 0;
      _downloadError = null;
    });
    try {
      await widget.service.downloadModel(onProgress: (received, total) {
        if (!mounted) return;
        setState(() => _progress = total == 0 ? 0 : received / total);
      });
      if (!mounted) return;
      setState(() {
        _installed = true;
        _downloading = false;
        _progress = 1;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _downloadError = 'Unduhan gagal: $error';
      });
    }
  }

  void _activate(bool enabled) {
    widget.onModeChanged(enabled);
    widget.onStatusChanged(enabled
        ? 'Mode suara Whisper offline aktif.'
        : 'Mode Offline • Tekan mikrofon atau ketik pertanyaan');
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Mesin Suara Offline'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Whisper Tiny multilingual INT8 berjalan langsung di HP. '
            'Model sekitar 104 MB, diunduh satu kali dan disimpan di penyimpanan aplikasi.',
          ),
          const SizedBox(height: 12),
          Text(_checking
              ? 'Memeriksa model...'
              : _installed
                  ? 'Model sudah terpasang dan siap digunakan.'
                  : 'Model belum diunduh. Mode suara bawaan tetap tersedia.'),
          if (_downloading) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(value: _progress == 0 ? null : _progress),
            const SizedBox(height: 6),
            Text('${(_progress * 100).toStringAsFixed(0)}%'),
          ],
          if (_downloadError != null) ...[
            const SizedBox(height: 8),
            Text(_downloadError!, style: const TextStyle(color: Colors.red)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _downloading ? null : () => Navigator.pop(context),
          child: const Text('Tutup'),
        ),
        if (!_installed && !_checking)
          FilledButton(
            onPressed: _downloading ? null : _download,
            child: const Text('Unduh ±104 MB'),
          ),
        if (_installed)
          FilledButton(
            onPressed: _downloading ? null : () => _activate(true),
            child: const Text('Aktifkan suara lokal'),
          ),
        if (widget.useOfflineAsr)
          TextButton(
            onPressed: _downloading ? null : () => _activate(false),
            child: const Text('Gunakan suara bawaan'),
          ),
      ],
    );
  }
}
