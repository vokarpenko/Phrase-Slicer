String formatDuration(Duration duration) {
  final totalSeconds = duration.inSeconds;
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

String formatSeconds(double seconds) {
  final wholeSeconds = seconds.floor();
  final minutes = wholeSeconds ~/ 60;
  final rest = wholeSeconds % 60;
  final tenths = ((seconds - wholeSeconds) * 10).round().clamp(0, 9).toInt();
  return '$minutes:${rest.toString().padLeft(2, '0')}.$tenths';
}
