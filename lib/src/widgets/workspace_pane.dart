import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../utils/time_format.dart';
import 'waveform_editor.dart';

class WorkspacePane extends StatelessWidget {
  const WorkspacePane({
    super.key,
    required this.status,
    required this.busy,
    required this.duration,
    required this.position,
    required this.playing,
    required this.waveform,
    required this.boundaries,
    required this.onTogglePlay,
    required this.onSeek,
    required this.onBoundaryDragStart,
    required this.onBoundaryDragUpdate,
    required this.onBoundaryDragEnd,
  });

  final String status;
  final bool busy;
  final Duration duration;
  final Duration position;
  final bool playing;
  final List<double> waveform;
  final List<double> boundaries;
  final VoidCallback onTogglePlay;
  final ValueChanged<double> onSeek;
  final ValueChanged<int> onBoundaryDragStart;
  final void Function(int index, double seconds) onBoundaryDragUpdate;
  final VoidCallback onBoundaryDragEnd;

  @override
  Widget build(BuildContext context) {
    final totalSeconds = duration.inMilliseconds / 1000;
    final waveformHeight = MediaQuery.sizeOf(context).height < 760
        ? 100.0
        : 180.0;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFD9E0DD)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                IconButton.filledTonal(
                  onPressed: duration > Duration.zero ? onTogglePlay : null,
                  icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                  tooltip: playing ? 'Пауза' : 'Воспроизвести',
                ),
                const SizedBox(width: 8),
                Text(formatDuration(position)),
                Expanded(
                  child: Slider(
                    value: totalSeconds <= 0
                        ? 0
                        : position.inMilliseconds / 1000,
                    min: 0,
                    max: math.max(0.001, totalSeconds),
                    onChanged: totalSeconds <= 0 ? null : onSeek,
                  ),
                ),
                Text(formatDuration(duration)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: SizedBox(
              height: waveformHeight,
              child: WaveformEditor(
                waveform: waveform,
                boundaries: boundaries,
                duration: duration,
                position: position,
                selectedSegment: null,
                onSeek: onSeek,
                onBoundaryDragStart: onBoundaryDragStart,
                onBoundaryDragUpdate: onBoundaryDragUpdate,
                onBoundaryDragEnd: onBoundaryDragEnd,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
            child: Row(
              children: [
                if (busy)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                if (busy) const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    status,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.grey.shade800),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
