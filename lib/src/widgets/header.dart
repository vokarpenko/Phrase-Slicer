import 'package:flutter/material.dart';

class Header extends StatelessWidget {
  const Header({
    super.key,
    required this.ffmpegStatus,
    required this.ffmpegReady,
  });

  final String ffmpegStatus;
  final bool ffmpegReady;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      child: Row(
        children: [
          const Icon(Icons.content_cut, size: 28),
          const SizedBox(width: 10),
          const Text(
            'Phrase Slicer',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(width: 18),
          Expanded(
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
      ),
    );
  }
}
