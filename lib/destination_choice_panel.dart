import 'package:flutter/material.dart';

import 'answer_engine.dart';

/// Daftar kandidat tujuan ketika pencarian tarif menghasilkan lebih dari satu hasil.
class DestinationChoicePanel extends StatelessWidget {
  final List<Choice> choices;
  final ValueChanged<Choice> onSelected;

  const DestinationChoicePanel({
    super.key,
    required this.choices,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    if (choices.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7F6),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFF0D9D6)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.location_searching,
                    color: Color(0xFFB71C1C), size: 19),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    'Pilih tujuan (${choices.length} saran)',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Ketuk kecamatan atau alamat yang paling sesuai.',
              style: TextStyle(color: Color(0xFF777777), fontSize: 11.5),
            ),
            const SizedBox(height: 9),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (var i = 0; i < choices.length; i++)
                      _DestinationChoiceTile(
                        choice: choices[i],
                        index: i,
                        onTap: () => onSelected(choices[i]),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DestinationChoiceTile extends StatelessWidget {
  final Choice choice;
  final int index;
  final VoidCallback onTap;

  const _DestinationChoiceTile({
    required this.choice,
    required this.index,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final row = choice.row;
    final isDistrict = row['_suggestion_level'] == 'district';
    final city = (row['city'] ?? '').toString().trim();
    final district = (row['district'] ?? '').toString().trim();
    final village = (row['village'] ?? '').toString().trim();
    final province = (row['province'] ?? '').toString().trim();
    final title = isDistrict
        ? (district.isNotEmpty ? district : choice.label)
        : (village.isNotEmpty ? village : district);
    final subtitle = isDistrict
        ? [city, province].where((value) => value.isNotEmpty).join(' • ')
        : [district, city, province]
            .where((value) => value.isNotEmpty)
            .toSet()
            .join(' • ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE7C4C0)),
            ),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFFE5E2),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      color: Color(0xFF9B1C1C),
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title.isEmpty ? choice.label : title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: Color(0xFF292929),
                        ),
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF777777),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right, color: Color(0xFF9B1C1C)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
