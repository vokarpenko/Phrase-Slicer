import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

class InputPane extends StatelessWidget {
  const InputPane({
    super.key,
    required this.audioPath,
    required this.outputDir,
    required this.phrasesController,
    required this.phraseCount,
    required this.onPickAudio,
    required this.onPickOutput,
  });

  final String? audioPath;
  final String? outputDir;
  final TextEditingController phrasesController;
  final int phraseCount;
  final VoidCallback onPickAudio;
  final VoidCallback onPickOutput;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFD9E0DD)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: _PathTile(
                    icon: Icons.graphic_eq,
                    label: 'MP3',
                    value: audioPath == null
                        ? 'Не выбран'
                        : p.basename(audioPath!),
                    onTap: onPickAudio,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _PathTile(
                    icon: Icons.folder,
                    label: 'Результат',
                    value: outputDir == null
                        ? 'Не выбрана'
                        : p.basename(outputDir!),
                    onTap: onPickOutput,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Text(
                  'Фразы',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                Text(
                  '$phraseCount строк',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: TextField(
                controller: phrasesController,
                expands: true,
                minLines: null,
                maxLines: null,
                textAlignVertical: TextAlignVertical.top,
                decoration: const InputDecoration(
                  hintText: 'Hello world\nHow are you?\nNice to meet you',
                  border: OutlineInputBorder(),
                  filled: true,
                  fillColor: Color(0xFFFBFCFB),
                  contentPadding: EdgeInsets.all(12),
                ),
                style: const TextStyle(fontSize: 14, height: 1.35),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PathTile extends StatelessWidget {
  const _PathTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F7F6),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFD9E0DD)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.labelSmall),
                  Text(value, maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
