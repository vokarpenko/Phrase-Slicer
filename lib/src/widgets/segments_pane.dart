import 'package:flutter/material.dart';

import '../models/phrase_segment.dart';
import '../utils/time_format.dart';

class SegmentsPane extends StatelessWidget {
  const SegmentsPane({
    super.key,
    required this.segments,
    required this.selectedSegment,
    required this.onSelectSegment,
    required this.onPreviewSegment,
  });

  final List<PhraseSegment> segments;
  final int? selectedSegment;
  final ValueChanged<int> onSelectSegment;
  final ValueChanged<int> onPreviewSegment;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFD9E0DD)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Text(
              'Выходные файлы',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: segments.isEmpty
                ? const Center(
                    child: Text(
                      'Сегменты появятся после загрузки аудио и списка фраз.',
                    ),
                  )
                : ListView.separated(
                    itemCount: segments.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final segment = segments[index];
                      final selected = selectedSegment == index;
                      return Material(
                        color: selected
                            ? const Color(0xFFE9F3F1)
                            : Colors.white,
                        child: ListTile(
                          dense: true,
                          selected: selected,
                          onTap: () => onSelectSegment(index),
                          leading: SizedBox(
                            width: 34,
                            child: Text(
                              '${index + 1}',
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          title: Text(
                            segment.phrase,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${formatSeconds(segment.start)} - ${formatSeconds(segment.end)}'
                            '  (${formatSeconds(segment.end - segment.start)})',
                          ),
                          trailing: IconButton(
                            onPressed: () => onPreviewSegment(index),
                            icon: const Icon(Icons.play_circle),
                            tooltip: 'Прослушать фразу',
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
