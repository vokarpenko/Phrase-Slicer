import 'package:flutter/material.dart';

class Header extends StatelessWidget {
  const Header({
    super.key,
    required this.ffmpegStatus,
    required this.ffmpegReady,
    required this.busy,
    required this.installingDependencies,
    required this.onPickAudio,
    required this.onPickOutput,
    required this.onInstallDependencies,
    required this.onAutoMark,
    required this.onExport,
  });

  final String ffmpegStatus;
  final bool ffmpegReady;
  final bool busy;
  final bool installingDependencies;
  final VoidCallback onPickAudio;
  final VoidCallback onPickOutput;
  final VoidCallback? onInstallDependencies;
  final VoidCallback onAutoMark;
  final VoidCallback? onExport;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final actions = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton.tonalIcon(
                onPressed: busy ? null : onPickAudio,
                icon: const Icon(Icons.audio_file),
                label: const Text('MP3'),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: busy ? null : onPickOutput,
                icon: const Icon(Icons.folder_open),
                label: const Text('Папка'),
              ),
              const SizedBox(width: 8),
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
                    : const Icon(Icons.download),
                label: const Text('Установить ffmpeg'),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: busy ? null : onAutoMark,
                icon: const Icon(Icons.auto_fix_high),
                label: const Text('Авторазметка'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: busy ? null : onExport,
                icon: const Icon(Icons.save_alt),
                label: const Text('Экспорт'),
              ),
            ],
          );

          final title = Row(
            children: [
              const Icon(Icons.content_cut, size: 28),
              const SizedBox(width: 10),
              const Text(
                'Phrase Slicer',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
              const SizedBox(width: 18),
              Flexible(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Chip(
                    avatar: Icon(
                      ffmpegReady ? Icons.check_circle : Icons.warning_amber,
                      size: 18,
                      color: ffmpegReady
                          ? const Color(0xFF226B45)
                          : const Color(0xFF9B5E00),
                    ),
                    label: Text(ffmpegStatus, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ),
            ],
          );

          if (constraints.maxWidth < 980) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                title,
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: actions,
                ),
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: title),
              const SizedBox(width: 12),
              actions,
            ],
          );
        },
      ),
    );
  }
}
