import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'tariff_utils.dart' show formatTypedReply;
import 'chat_message.dart';

/// Menonjolkan nominal hasil perhitungan tanpa mengubah teks jawaban engine.
TextSpan formatCargoMessage(String message, {required bool isUser}) {
  final baseColor = isUser ? Colors.white : const Color(0xFF252525);
  final totalPattern = RegExp(r'(?:= |(?:Estimasi|Perkiraan) ongkir: )(Rp [0-9.]+)');
  final matches = totalPattern.allMatches(message).toList();
  if (isUser || matches.isEmpty) {
    return TextSpan(
      text: message,
      style: TextStyle(color: baseColor, fontSize: 14.5, height: 1.45),
    );
  }
  final spans = <InlineSpan>[];
  var cursor = 0;
  for (final match in matches) {
    final amount = match.group(1)!;
    final amountStart = match.start + match.group(0)!.lastIndexOf(amount);
    if (amountStart > cursor) {
      spans.add(TextSpan(text: message.substring(cursor, amountStart)));
    }
    spans.add(TextSpan(
      text: amount,
      style: const TextStyle(
        color: Color(0xFFB71C1C),
        fontWeight: FontWeight.w800,
        fontSize: 15.5,
      ),
    ));
    cursor = amountStart + amount.length;
  }
  if (cursor < message.length) spans.add(TextSpan(text: message.substring(cursor)));
  return TextSpan(
    style: TextStyle(color: baseColor, fontSize: 14.5, height: 1.5),
    children: spans,
  );
}

class ChatBubble extends StatelessWidget {
  const ChatBubble({super.key, required this.message});
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final displayText = isUser ? message.text : formatTypedReply(message.text);
    final shareText = formatTypedReply(message.text);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isUser) ...[
                const CircleAvatar(
                  radius: 15,
                  backgroundColor: Color(0xFFFFE3E0),
                  foregroundColor: Color(0xFFB71C1C),
                  child: Icon(Icons.support_agent, size: 18),
                ),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.80,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
                  decoration: BoxDecoration(
                    color: isUser ? const Color(0xFFB71C1C) : Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: Radius.circular(isUser ? 18 : 5),
                      bottomRight: Radius.circular(isUser ? 5 : 18),
                    ),
                    border: isUser ? null : Border.all(color: const Color(0xFFE8E9EC)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.035),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text.rich(
                    formatCargoMessage(displayText, isUser: isUser),
                    textAlign: TextAlign.start,
                  ),
                ),
              ),
              if (isUser) const SizedBox(width: 23),
            ],
          ),
          if (!isUser)
            Padding(
              padding: const EdgeInsets.only(left: 38, top: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: shareText));
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Jawaban disalin untuk dikirim ke pelanggan.')),
                      );
                    },
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    label: const Text('Salin'),
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  ),
                  TextButton.icon(
                    onPressed: () => Share.share(
                      shareText,
                      subject: 'Informasi Ongkir NEXT Cargo',
                    ),
                    icon: const Icon(Icons.share_rounded, size: 16),
                    label: const Text('Bagikan'),
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
