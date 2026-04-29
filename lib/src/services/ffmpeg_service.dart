import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;

class FfmpegInstallResult {
  const FfmpegInstallResult({required this.success, required this.message});

  final bool success;
  final String message;
}

class FfmpegService {
  Future<bool> isAvailable() async {
    final ffmpeg = await _findTool('ffmpeg');
    final ffprobe = await _findTool('ffprobe');
    return ffmpeg != null && ffprobe != null;
  }

  Future<FfmpegInstallResult> install(
    void Function(String message) onProgress,
  ) async {
    if (await isAvailable()) {
      return const FfmpegInstallResult(
        success: true,
        message: 'ffmpeg уже установлен.',
      );
    }

    if (Platform.isMacOS) {
      return _installOnMacOS(onProgress);
    }
    if (Platform.isWindows) {
      return _installOnWindows(onProgress);
    }

    return const FfmpegInstallResult(
      success: false,
      message: 'Автоустановка поддержана только на macOS и Windows.',
    );
  }

  Future<Duration> duration(String inputPath) async {
    final ffprobe = await _requiredTool('ffprobe');
    final result = await Process.run(ffprobe, [
      '-v',
      'error',
      '-show_entries',
      'format=duration',
      '-of',
      'default=noprint_wrappers=1:nokey=1',
      inputPath,
    ], runInShell: Platform.isWindows);
    if (result.exitCode != 0) {
      throw Exception((result.stderr as Object).toString().trim());
    }
    final seconds = double.tryParse(
      (result.stdout as Object).toString().trim(),
    );
    if (seconds == null || seconds <= 0) {
      throw Exception('ffprobe не вернул длительность файла');
    }
    return Duration(milliseconds: (seconds * 1000).round());
  }

  Future<List<double>> waveform(String inputPath) async {
    final ffmpeg = await _requiredTool('ffmpeg');
    const sampleRate = 8000;
    const pointsPerSecond = 45;
    final samplesPerPoint = sampleRate ~/ pointsPerSecond;
    final process = await Process.start(ffmpeg, [
      '-hide_banner',
      '-loglevel',
      'error',
      '-i',
      inputPath,
      '-ac',
      '1',
      '-ar',
      '$sampleRate',
      '-f',
      's16le',
      'pipe:1',
    ], runInShell: Platform.isWindows);

    final points = <double>[];
    final pending = <int>[];
    var sampleCount = 0;
    var peak = 0;
    final stderr = StringBuffer();

    final stderrSub = process.stderr
        .transform(systemEncoding.decoder)
        .listen(stderr.write);
    await for (final chunk in process.stdout) {
      pending.addAll(chunk);
      while (pending.length >= 2) {
        final value = _readInt16Le(pending[0], pending[1]).abs();
        pending.removeRange(0, 2);
        peak = math.max(peak, value);
        sampleCount++;
        if (sampleCount >= samplesPerPoint) {
          points.add((peak / 32768).clamp(0, 1).toDouble());
          sampleCount = 0;
          peak = 0;
        }
      }
    }

    final exitCode = await process.exitCode;
    await stderrSub.cancel();
    if (exitCode != 0) {
      throw Exception(stderr.toString().trim());
    }
    if (sampleCount > 0) {
      points.add((peak / 32768).clamp(0, 1).toDouble());
    }
    return points;
  }

  Future<List<double>> detectBoundaries(
    String inputPath,
    Duration duration,
    int phraseCount,
  ) async {
    if (phraseCount <= 0) return const [];
    final ffmpeg = await _requiredTool('ffmpeg');
    final result = await Process.run(ffmpeg, [
      '-hide_banner',
      '-i',
      inputPath,
      '-af',
      'silencedetect=noise=-35dB:d=0.25',
      '-f',
      'null',
      '-',
    ], runInShell: Platform.isWindows);
    final stderr = (result.stderr as Object).toString();
    if (result.exitCode != 0) {
      throw Exception(stderr.trim());
    }

    final totalSeconds = duration.inMilliseconds / 1000;
    var chunks = _chunksFromSilence(stderr, totalSeconds);
    chunks = _fitChunks(chunks, totalSeconds, phraseCount);
    if (chunks.length != phraseCount) {
      return [
        for (var i = 0; i <= phraseCount; i++) totalSeconds * i / phraseCount,
      ];
    }

    final boundaries = <double>[0];
    for (var i = 0; i < chunks.length - 1; i++) {
      boundaries.add((chunks[i].end + chunks[i + 1].start) / 2);
    }
    boundaries.add(totalSeconds);
    return boundaries;
  }

  Future<void> exportSegment(
    String inputPath,
    String outputPath,
    double startSeconds,
    double endSeconds,
    double volumeMultiplier,
  ) async {
    final ffmpeg = await _requiredTool('ffmpeg');
    final duration = math.max(0.05, endSeconds - startSeconds);
    final result = await Process.run(ffmpeg, [
      '-y',
      '-hide_banner',
      '-loglevel',
      'error',
      '-i',
      inputPath,
      '-ss',
      _formatFfmpegSeconds(startSeconds),
      '-t',
      _formatFfmpegSeconds(duration),
      '-vn',
      '-filter:a',
      'volume=${volumeMultiplier.toStringAsFixed(3)}',
      '-codec:a',
      'libmp3lame',
      '-q:a',
      '2',
      outputPath,
    ], runInShell: Platform.isWindows);
    if (result.exitCode != 0) {
      throw Exception((result.stderr as Object).toString().trim());
    }
  }

  List<_AudioChunk> _chunksFromSilence(String stderr, double totalSeconds) {
    final starts = RegExp(
      r'silence_start:\s*([0-9.]+)',
    ).allMatches(stderr).map((match) => double.parse(match.group(1)!)).toList();
    final ends = RegExp(
      r'silence_end:\s*([0-9.]+)',
    ).allMatches(stderr).map((match) => double.parse(match.group(1)!)).toList();

    final chunks = <_AudioChunk>[];
    var cursor = 0.0;
    for (var i = 0; i < starts.length; i++) {
      final silenceStart = starts[i].clamp(0, totalSeconds).toDouble();
      if (silenceStart - cursor > 0.08) {
        chunks.add(_AudioChunk(cursor, silenceStart));
      }
      if (i < ends.length) {
        cursor = ends[i].clamp(0, totalSeconds).toDouble();
      }
    }
    if (totalSeconds - cursor > 0.08) {
      chunks.add(_AudioChunk(cursor, totalSeconds));
    }

    return chunks.where((chunk) => chunk.end - chunk.start > 0.12).toList();
  }

  List<_AudioChunk> _fitChunks(
    List<_AudioChunk> chunks,
    double totalSeconds,
    int targetCount,
  ) {
    if (targetCount <= 0) return const [];
    if (chunks.isEmpty) {
      return [
        for (var i = 0; i < targetCount; i++)
          _AudioChunk(
            totalSeconds * i / targetCount,
            totalSeconds * (i + 1) / targetCount,
          ),
      ];
    }

    final fitted = List<_AudioChunk>.from(chunks);
    while (fitted.length > targetCount) {
      var mergeAt = 0;
      var smallestGap = double.infinity;
      for (var i = 0; i < fitted.length - 1; i++) {
        final gap = fitted[i + 1].start - fitted[i].end;
        if (gap < smallestGap) {
          smallestGap = gap;
          mergeAt = i;
        }
      }
      fitted[mergeAt] = _AudioChunk(
        fitted[mergeAt].start,
        fitted[mergeAt + 1].end,
      );
      fitted.removeAt(mergeAt + 1);
    }

    while (fitted.length < targetCount) {
      var splitAt = 0;
      var longest = 0.0;
      for (var i = 0; i < fitted.length; i++) {
        final length = fitted[i].end - fitted[i].start;
        if (length > longest) {
          longest = length;
          splitAt = i;
        }
      }
      final chunk = fitted[splitAt];
      final midpoint = (chunk.start + chunk.end) / 2;
      fitted[splitAt] = _AudioChunk(chunk.start, midpoint);
      fitted.insert(splitAt + 1, _AudioChunk(midpoint, chunk.end));
    }

    return fitted;
  }

  Future<String> _requiredTool(String name) async {
    final tool = await _findTool(name);
    if (tool == null) {
      throw Exception(
        '$name не найден. Установите ffmpeg и добавьте его в PATH.',
      );
    }
    return tool;
  }

  Future<FfmpegInstallResult> _installOnMacOS(
    void Function(String message) onProgress,
  ) async {
    final brew = await _findCommand('brew');
    if (brew == null) {
      return const FfmpegInstallResult(
        success: false,
        message:
            'Homebrew не найден. Установите Homebrew с https://brew.sh или выполните в терминале: brew install ffmpeg',
      );
    }

    onProgress('Устанавливаю ffmpeg через Homebrew...');
    final install = await _runCommand(brew, const ['install', 'ffmpeg']);
    if (!install.success && !await isAvailable()) {
      return FfmpegInstallResult(
        success: false,
        message:
            'Homebrew не смог установить ffmpeg. ${install.output.isEmpty ? '' : install.output}',
      );
    }

    if (await isAvailable()) {
      return const FfmpegInstallResult(
        success: true,
        message: 'ffmpeg установлен через Homebrew.',
      );
    }

    return const FfmpegInstallResult(
      success: false,
      message:
          'Установка завершилась, но ffmpeg не найден. Перезапустите приложение или проверьте PATH.',
    );
  }

  Future<FfmpegInstallResult> _installOnWindows(
    void Function(String message) onProgress,
  ) async {
    final attempts = <_InstallAttempt>[
      _InstallAttempt(
        manager: 'winget',
        command: 'winget',
        args: const [
          'install',
          '--id',
          'Gyan.FFmpeg',
          '-e',
          '--source',
          'winget',
          '--accept-package-agreements',
          '--accept-source-agreements',
          '--silent',
          '--disable-interactivity',
        ],
      ),
      _InstallAttempt(
        manager: 'Chocolatey',
        command: 'choco',
        args: const ['install', 'ffmpeg', '-y'],
      ),
      _InstallAttempt(
        manager: 'Scoop',
        command: 'scoop',
        args: const ['install', 'ffmpeg'],
      ),
    ];

    final errors = <String>[];
    for (final attempt in attempts) {
      if (await _findCommand(attempt.command) == null) {
        errors.add('${attempt.manager}: не найден');
        continue;
      }

      onProgress('Устанавливаю ffmpeg через ${attempt.manager}...');
      final command = await _findCommand(attempt.command);
      final result = await _runCommand(command!, attempt.args);
      if (await isAvailable()) {
        return FfmpegInstallResult(
          success: true,
          message: 'ffmpeg установлен через ${attempt.manager}.',
        );
      }
      errors.add('${attempt.manager}: ${_shortCommandOutput(result.output)}');
    }

    return FfmpegInstallResult(
      success: false,
      message:
          'Не удалось автоустановить ffmpeg. Если установка через winget уже завершилась, нажмите "Установить ffmpeg" еще раз или перезапустите приложение. Детали: ${errors.join(' | ')}',
    );
  }

  Future<String?> _findTool(String name) async {
    final executable = Platform.isWindows ? '$name.exe' : name;
    final candidates = <String>[
      executable,
      p.join(Directory.current.path, executable),
      p.join(p.dirname(Platform.resolvedExecutable), executable),
    ];
    if (Platform.isWindows) {
      candidates.addAll(await _windowsToolCandidates(executable));
    }
    if (Platform.isMacOS) {
      candidates.addAll([
        p.join('/opt/homebrew/bin', executable),
        p.join('/usr/local/bin', executable),
        p.join('/usr/bin', executable),
      ]);
    }

    for (final candidate in candidates) {
      try {
        final result = await Process.run(candidate, [
          '-version',
        ], runInShell: Platform.isWindows || candidate == executable);
        if (result.exitCode == 0) return candidate;
      } on Object {
        continue;
      }
    }
    return null;
  }

  Future<String?> _findCommand(String name) async {
    if (Platform.isWindows) {
      final knownCommand = _knownWindowsCommand(name);
      if (knownCommand != null && await File(knownCommand).exists()) {
        return knownCommand;
      }

      final check = await _runCommand('cmd.exe', ['/c', 'where', name]);
      if (check.success) {
        final output = check.output.split(RegExp(r'\r?\n')).first.trim();
        if (output.isNotEmpty) return output;
      }
      return null;
    }

    final check = await _runCommand('/bin/sh', ['-lc', 'command -v $name']);
    if (!check.success) return null;

    final output = check.output.split(RegExp(r'\r?\n')).first.trim();
    return output.isEmpty ? name : output;
  }

  Future<_CommandResult> _runCommand(String command, List<String> args) async {
    try {
      final windowsScript =
          Platform.isWindows &&
          (command.toLowerCase().endsWith('.cmd') ||
              command.toLowerCase().endsWith('.bat'));
      final result = await Process.run(
        windowsScript ? 'cmd.exe' : command,
        windowsScript ? ['/d', '/c', command, ...args] : args,
        runInShell: false,
        stdoutEncoding: Platform.isWindows ? utf8 : systemEncoding,
        stderrEncoding: Platform.isWindows ? utf8 : systemEncoding,
      );
      final stdout = (result.stdout as Object).toString().trim();
      final stderr = (result.stderr as Object).toString().trim();
      return _CommandResult(
        success: result.exitCode == 0,
        output: [
          stdout,
          stderr,
        ].where((part) => part.isNotEmpty).join('\n').trim(),
      );
    } on Object catch (error) {
      return _CommandResult(success: false, output: error.toString());
    }
  }

  int _readInt16Le(int lo, int hi) {
    final value = lo | (hi << 8);
    return value >= 0x8000 ? value - 0x10000 : value;
  }

  Future<List<String>> _windowsToolCandidates(String executable) async {
    final env = Platform.environment;
    final localAppData = env['LOCALAPPDATA'];
    final programFiles = env['ProgramFiles'];
    final programFilesX86 = env['ProgramFiles(x86)'];
    final programData = env['ProgramData'] ?? r'C:\ProgramData';
    final userProfile = env['USERPROFILE'];
    final chocolateyInstall = env['ChocolateyInstall'];

    final candidates = <String>[
      if (localAppData != null)
        p.join(localAppData, 'Microsoft', 'WinGet', 'Links', executable),
      if (localAppData != null)
        p.join(localAppData, 'Microsoft', 'WindowsApps', executable),
      if (programFiles != null)
        p.join(programFiles, 'ffmpeg', 'bin', executable),
      if (programFilesX86 != null)
        p.join(programFilesX86, 'ffmpeg', 'bin', executable),
      if (chocolateyInstall != null)
        p.join(chocolateyInstall, 'bin', executable),
      p.join(programData, 'chocolatey', 'bin', executable),
      if (userProfile != null)
        p.join(userProfile, 'scoop', 'shims', executable),
      p.join(programData, 'scoop', 'shims', executable),
    ];

    if (localAppData != null) {
      candidates.addAll(
        await _findNestedWindowsTools(
          Directory(p.join(localAppData, 'Microsoft', 'WinGet', 'Packages')),
          executable,
        ),
      );
    }

    return candidates;
  }

  Future<List<String>> _findNestedWindowsTools(
    Directory root,
    String executable,
  ) async {
    if (!await root.exists()) return const [];
    final matches = <String>[];
    try {
      await for (final entity in root.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File &&
            p.basename(entity.path).toLowerCase() == executable.toLowerCase()) {
          matches.add(entity.path);
          if (matches.length >= 8) break;
        }
      }
    } on Object {
      return matches;
    }
    return matches;
  }

  String? _knownWindowsCommand(String name) {
    final env = Platform.environment;
    final localAppData = env['LOCALAPPDATA'];
    final programData = env['ProgramData'] ?? r'C:\ProgramData';
    final userProfile = env['USERPROFILE'];
    final chocolateyInstall = env['ChocolateyInstall'];

    final executable = name.toLowerCase().endsWith('.exe') ? name : '$name.exe';
    final candidates = <String>[
      if (name == 'winget' && localAppData != null)
        p.join(localAppData, 'Microsoft', 'WindowsApps', executable),
      if (name == 'choco' && chocolateyInstall != null)
        p.join(chocolateyInstall, 'bin', executable),
      if (name == 'choco') p.join(programData, 'chocolatey', 'bin', executable),
      if (name == 'scoop' && userProfile != null)
        p.join(userProfile, 'scoop', 'shims', executable),
      if (name == 'scoop') p.join(programData, 'scoop', 'shims', executable),
    ];

    for (final candidate in candidates) {
      if (File(candidate).existsSync()) return candidate;
    }
    return null;
  }

  String _shortCommandOutput(String output) {
    final cleaned = output
        .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty) return 'команда завершилась без результата';
    if (cleaned.length <= 500) return cleaned;
    return '${cleaned.substring(0, 500)}...';
  }
}

class _InstallAttempt {
  const _InstallAttempt({
    required this.manager,
    required this.command,
    required this.args,
  });

  final String manager;
  final String command;
  final List<String> args;
}

class _CommandResult {
  const _CommandResult({required this.success, required this.output});

  final bool success;
  final String output;
}

class _AudioChunk {
  const _AudioChunk(this.start, this.end);

  final double start;
  final double end;
}

String _formatFfmpegSeconds(double seconds) => seconds.toStringAsFixed(3);
