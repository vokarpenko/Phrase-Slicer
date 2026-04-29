import 'dart:math' as math;

import 'package:flutter/material.dart';

class WaveformEditor extends StatefulWidget {
  const WaveformEditor({
    super.key,
    required this.waveform,
    required this.boundaries,
    required this.duration,
    required this.position,
    required this.selectedSegment,
    required this.onSeek,
    required this.onBoundaryDragStart,
    required this.onBoundaryDragUpdate,
    required this.onBoundaryDragEnd,
  });

  final List<double> waveform;
  final List<double> boundaries;
  final Duration duration;
  final Duration position;
  final int? selectedSegment;
  final ValueChanged<double> onSeek;
  final ValueChanged<int> onBoundaryDragStart;
  final void Function(int index, double seconds) onBoundaryDragUpdate;
  final VoidCallback onBoundaryDragEnd;

  @override
  State<WaveformEditor> createState() => _WaveformEditorState();
}

class _WaveformEditorState extends State<WaveformEditor> {
  int _activeBoundary = -1;

  @override
  Widget build(BuildContext context) {
    final totalSeconds = math.max(0.001, widget.duration.inMilliseconds / 1000);

    return LayoutBuilder(
      builder: (context, constraints) {
        double secondsAt(Offset localPosition) {
          final x = localPosition.dx.clamp(0, constraints.maxWidth).toDouble();
          return totalSeconds * x / math.max(1, constraints.maxWidth);
        }

        int nearestBoundary(Offset localPosition) {
          if (widget.boundaries.length <= 2) return -1;
          var nearest = -1;
          var distance = double.infinity;
          for (var i = 1; i < widget.boundaries.length - 1; i++) {
            final x =
                widget.boundaries[i] / totalSeconds * constraints.maxWidth;
            final d = (x - localPosition.dx).abs();
            if (d < distance) {
              nearest = i;
              distance = d;
            }
          }
          return distance <= 14 ? nearest : -1;
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) =>
              widget.onSeek(secondsAt(details.localPosition)),
          onPanStart: (details) {
            _activeBoundary = nearestBoundary(details.localPosition);
            if (_activeBoundary >= 0) {
              widget.onBoundaryDragStart(_activeBoundary);
            }
          },
          onPanUpdate: (details) {
            if (_activeBoundary >= 0) {
              widget.onBoundaryDragUpdate(
                _activeBoundary,
                secondsAt(details.localPosition),
              );
            }
          },
          onPanEnd: (_) {
            _activeBoundary = -1;
            widget.onBoundaryDragEnd();
          },
          onPanCancel: () {
            _activeBoundary = -1;
            widget.onBoundaryDragEnd();
          },
          child: CustomPaint(
            painter: _WaveformPainter(
              waveform: widget.waveform,
              boundaries: widget.boundaries,
              totalSeconds: totalSeconds,
              positionSeconds: widget.position.inMilliseconds / 1000,
              selectedSegment: widget.selectedSegment,
            ),
            child: const SizedBox.expand(),
          ),
        );
      },
    );
  }
}

class _WaveformPainter extends CustomPainter {
  const _WaveformPainter({
    required this.waveform,
    required this.boundaries,
    required this.totalSeconds,
    required this.positionSeconds,
    required this.selectedSegment,
  });

  final List<double> waveform;
  final List<double> boundaries;
  final double totalSeconds;
  final double positionSeconds;
  final int? selectedSegment;

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = const Color(0xFFEEF2F0);
    final borderPaint = Paint()
      ..color = const Color(0xFFD3DBD8)
      ..style = PaintingStyle.stroke;
    final wavePaint = Paint()
      ..color = const Color(0xFF2F6F73)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    final markerPaint = Paint()
      ..color = const Color(0xFFB6483A)
      ..strokeWidth = 2;
    final playheadPaint = Paint()
      ..color = const Color(0xFF1C1F1E)
      ..strokeWidth = 2;

    final rect = Offset.zero & size;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(8)),
      bgPaint,
    );

    if (boundaries.length > 2) {
      for (var i = 0; i < boundaries.length - 1; i++) {
        final startX = boundaries[i] / totalSeconds * size.width;
        final endX = boundaries[i + 1] / totalSeconds * size.width;
        final paint = Paint()
          ..color = i == selectedSegment
              ? const Color(0xFF97D3C9).withValues(alpha: 0.38)
              : (i.isEven
                    ? Colors.white.withValues(alpha: 0.46)
                    : Colors.transparent);
        canvas.drawRect(Rect.fromLTRB(startX, 0, endX, size.height), paint);
      }
    }

    final centerY = size.height / 2;
    if (waveform.isEmpty) {
      final emptyPaint = Paint()
        ..color = const Color(0xFFAAB6B2)
        ..strokeWidth = 1.2;
      canvas.drawLine(
        Offset(0, centerY),
        Offset(size.width, centerY),
        emptyPaint,
      );
    } else {
      final step = size.width / waveform.length;
      for (var i = 0; i < waveform.length; i++) {
        final x = i * step;
        final amp = waveform[i].clamp(0, 1).toDouble() * (size.height * 0.44);
        canvas.drawLine(
          Offset(x, centerY - amp),
          Offset(x, centerY + amp),
          wavePaint,
        );
      }
    }

    for (var i = 1; i < boundaries.length - 1; i++) {
      final x = boundaries[i] / totalSeconds * size.width;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), markerPaint);
      canvas.drawCircle(Offset(x, 14), 5, markerPaint);
    }

    final playX =
        positionSeconds.clamp(0, totalSeconds).toDouble() /
        totalSeconds *
        size.width;
    canvas.drawLine(
      Offset(playX, 0),
      Offset(playX, size.height),
      playheadPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.deflate(0.5), const Radius.circular(8)),
      borderPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.waveform != waveform ||
        oldDelegate.boundaries != boundaries ||
        oldDelegate.totalSeconds != totalSeconds ||
        oldDelegate.positionSeconds != positionSeconds ||
        oldDelegate.selectedSegment != selectedSegment;
  }
}
