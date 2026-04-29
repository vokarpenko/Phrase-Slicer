import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

class InputPane extends StatelessWidget {
  const InputPane({
    super.key,
    required this.audioPath,
    required this.outputDir,
    required this.phrasesController,
    required this.phraseCount,
    required this.ffmpegReady,
    required this.busy,
    required this.installingDependencies,
    required this.exportVolumeMultiplier,
    required this.onPickAudio,
    required this.onPickOutput,
    required this.onInstallDependencies,
    required this.onAutoMark,
    required this.onExport,
    required this.onExportVolumeChanged,
  });

  final String? audioPath;
  final String? outputDir;
  final TextEditingController phrasesController;
  final int phraseCount;
  final bool ffmpegReady;
  final bool busy;
  final bool installingDependencies;
  final double exportVolumeMultiplier;
  final VoidCallback onPickAudio;
  final VoidCallback onPickOutput;
  final VoidCallback? onInstallDependencies;
  final VoidCallback onAutoMark;
  final VoidCallback? onExport;
  final ValueChanged<double> onExportVolumeChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFD9E0DD)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cramped = constraints.maxHeight < 360;
          final phrasesField = TextField(
            controller: phrasesController,
            expands: !cramped,
            minLines: cramped ? 10 : null,
            maxLines: cramped ? 10 : null,
            textAlignVertical: TextAlignVertical.top,
            decoration: const InputDecoration(
              hintText: 'Hello world\nHow are you?\nNice to meet you',
              border: OutlineInputBorder(),
              filled: true,
              fillColor: Color(0xFFFBFCFB),
              contentPadding: EdgeInsets.all(12),
            ),
            style: const TextStyle(fontSize: 14, height: 1.35),
          );

          final content = [
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
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: busy ? null : onPickAudio,
                  icon: const Icon(Icons.audio_file),
                  label: const Text('MP3'),
                ),
                FilledButton.tonalIcon(
                  onPressed: busy ? null : onPickOutput,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Папка'),
                ),
                FilledButton.tonalIcon(
                  onPressed: installingDependencies
                      ? null
                      : onInstallDependencies,
                  icon: installingDependencies
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(ffmpegReady ? Icons.check_circle : Icons.download),
                  label: Text(
                    ffmpegReady ? 'ffmpeg готов' : 'Установить ffmpeg',
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: busy ? null : onAutoMark,
                  icon: const Icon(Icons.auto_fix_high),
                  label: const Text('Авторазметка'),
                ),
                FilledButton.icon(
                  onPressed: busy ? null : onExport,
                  icon: const Icon(Icons.save_alt),
                  label: const Text('Экспорт'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Text(
                  'Громкость экспорта',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                Text('${exportVolumeMultiplier.toStringAsFixed(2)}x'),
              ],
            ),
            Slider(
              value: exportVolumeMultiplier,
              min: 0.5,
              max: 4.0,
              divisions: 15,
              label: '${exportVolumeMultiplier.toStringAsFixed(2)}x',
              onChanged: busy ? null : onExportVolumeChanged,
            ),
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
          ];

          if (cramped) {
            return Padding(
              padding: const EdgeInsets.all(14),
              child: ListView(
                children: [
                  ...content,
                  SizedBox(height: 220, child: phrasesField),
                ],
              ),
            );
          }

          return Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...content,
                Expanded(child: phrasesField),
              ],
            ),
          );
        },
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
