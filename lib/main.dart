import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const PhraseCutterApp());
}

class PhraseCutterApp extends StatelessWidget {
  const PhraseCutterApp({super.key, this.enablePlayback = true});

  final bool enablePlayback;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Phrase Slicer',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2F6F73),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F7F6),
        useMaterial3: true,
      ),
      home: SplitterPage(enablePlayback: enablePlayback),
    );
  }
}

class SplitterPage extends StatefulWidget {
  const SplitterPage({super.key, required this.enablePlayback});

  final bool enablePlayback;

  @override
  State<SplitterPage> createState() => _SplitterPageState();
}

class _SplitterPageState extends State<SplitterPage> {
  final _phrasesController = TextEditingController();
  final _ffmpeg = FfmpegService();

  Player? _player;
  final List<double> _waveform = [];
  final List<double> _boundaries = [];

  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<bool>? _playingSub;

  String? _audioPath;
  String? _outputDir;
  String _status = 'Добавьте MP3 и список фраз.';
  String _ffmpegStatus = 'Проверяю ffmpeg...';
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  Duration? _previewEnd;
  bool _isPlaying = false;
  bool _isBusy = false;
  bool _isInstallingDependencies = false;
  bool _isDraggingOver = false;
  bool _ffmpegReady = false;
  int? _selectedSegment;
  int? _dragBoundaryIndex;

  List<String> get _phrases => _phrasesController.text
      .split(RegExp(r'\r?\n'))
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();

  List<PhraseSegment> get _segments {
    final phrases = _phrases;
    if (_boundaries.length != phrases.length + 1) {
      return const [];
    }

    return [
      for (var i = 0; i < phrases.length; i++)
        PhraseSegment(
          phrase: phrases[i],
          start: _boundaries[i],
          end: _boundaries[i + 1],
        ),
    ];
  }

  @override
  void initState() {
    super.initState();
    _phrasesController.addListener(_handlePhrasesChanged);
    if (widget.enablePlayback) {
      final player = Player();
      _player = player;
      _positionSub = player.stream.position.listen((position) {
        if (!mounted) return;
        if (_previewEnd != null && position >= _previewEnd!) {
          player.pause();
          _previewEnd = null;
        }
        setState(() => _position = position);
      });
      _durationSub = player.stream.duration.listen((duration) {
        if (!mounted) return;
        if (duration > Duration.zero) {
          setState(() => _duration = duration);
        }
      });
      _playingSub = player.stream.playing.listen((playing) {
        if (!mounted) return;
        setState(() => _isPlaying = playing);
      });
    }
    if (widget.enablePlayback) {
      unawaited(_checkFfmpeg());
    } else {
      _ffmpegStatus = 'ffmpeg check disabled';
    }
  }

  @override
  void dispose() {
    _phrasesController.removeListener(_handlePhrasesChanged);
    _phrasesController.dispose();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _playingSub?.cancel();
    _player?.dispose();
    super.dispose();
  }

  Future<void> _checkFfmpeg() async {
    final available = await _ffmpeg.isAvailable();
    if (!mounted) return;
    setState(() {
      _ffmpegReady = available;
      _ffmpegStatus = available
          ? 'ffmpeg найден'
          : 'ffmpeg не найден: авторазметка и экспорт недоступны';
    });
  }

  Future<void> _installFfmpeg() async {
    if (_isInstallingDependencies) return;

    setState(() {
      _isInstallingDependencies = true;
      _isBusy = true;
      _ffmpegStatus = 'Устанавливаю ffmpeg...';
      _status = 'Запущена установка ffmpeg. Это может занять несколько минут.';
    });

    final result = await _ffmpeg.install((message) {
      if (!mounted) return;
      setState(() {
        _ffmpegStatus = message;
        _status = message;
      });
    });

    final available = await _ffmpeg.isAvailable();
    if (!mounted) return;
    setState(() {
      _ffmpegReady = available;
      _isInstallingDependencies = false;
      _isBusy = false;
      _ffmpegStatus = available ? 'ffmpeg найден' : 'ffmpeg не найден';
      _status = available
          ? 'ffmpeg установлен. Можно загружать MP3 и делать авторазметку.'
          : result.message;
    });
  }

  void _handlePhrasesChanged() {
    if (_duration > Duration.zero && _boundaries.isNotEmpty) {
      _fitBoundaryCount(_phrases.length);
    }
    setState(() {});
  }

  Future<void> _pickAudio() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['mp3'],
    );
    final path = result?.files.single.path;
    if (path != null) {
      await _loadAudio(path);
    }
  }

  Future<void> _pickOutputDir() async {
    final path = await FilePicker.getDirectoryPath();
    if (path == null) return;
    setState(() => _outputDir = path);
  }

  Future<void> _loadAudio(String path) async {
    if (!path.toLowerCase().endsWith('.mp3')) {
      setState(() => _status = 'Можно добавить только MP3 файл.');
      return;
    }

    setState(() {
      _audioPath = path;
      _waveform.clear();
      _boundaries.clear();
      _duration = Duration.zero;
      _position = Duration.zero;
      _selectedSegment = null;
      _status = 'Загружаю аудио...';
      _isBusy = true;
    });

    await _player?.open(Media(path), play: false);

    if (!_ffmpegReady) {
      if (!mounted) return;
      setState(() {
        _status =
            'Аудио загружено. Для формы волны, авторазметки и экспорта нужен ffmpeg.';
        _isBusy = false;
      });
      return;
    }

    try {
      final duration = await _ffmpeg.duration(path);
      final waveform = await _ffmpeg.waveform(path);
      final phrases = _phrases;
      final boundaries = phrases.isEmpty
          ? <double>[0, duration.inMilliseconds / 1000]
          : await _ffmpeg.detectBoundaries(path, duration, phrases.length);

      if (!mounted) return;
      setState(() {
        _duration = duration;
        _waveform
          ..clear()
          ..addAll(waveform);
        _boundaries
          ..clear()
          ..addAll(boundaries);
        _fitBoundaryCount(phrases.length);
        _status = phrases.isEmpty
            ? 'Аудио загружено. Вставьте фразы, затем нажмите "Авторазметка".'
            : 'Аудио загружено и размечено. Проверьте границы на дорожке.';
        _isBusy = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _status = 'Не удалось проанализировать аудио: $error';
        _isBusy = false;
      });
    }
  }

  Future<void> _autoMark() async {
    final path = _audioPath;
    final phraseCount = _phrases.length;
    if (path == null || phraseCount == 0) {
      setState(() => _status = 'Нужны MP3 файл и хотя бы одна фраза.');
      return;
    }
    if (!_ffmpegReady) {
      setState(() => _status = 'Для авторазметки нужен ffmpeg.');
      return;
    }

    setState(() {
      _isBusy = true;
      _status = 'Ищу паузы между фразами...';
    });

    try {
      final duration = _duration > Duration.zero
          ? _duration
          : await _ffmpeg.duration(path);
      final boundaries = await _ffmpeg.detectBoundaries(
        path,
        duration,
        phraseCount,
      );
      final waveform = _waveform.isEmpty
          ? await _ffmpeg.waveform(path)
          : _waveform;

      if (!mounted) return;
      setState(() {
        _duration = duration;
        _boundaries
          ..clear()
          ..addAll(boundaries);
        if (_waveform.isEmpty) {
          _waveform.addAll(waveform);
        }
        _status =
            'Авторазметка готова. Внутренние границы можно перетащить мышью.';
        _isBusy = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _status = 'Не удалось выполнить авторазметку: $error';
        _isBusy = false;
      });
    }
  }

  void _fitBoundaryCount(int phraseCount) {
    if (phraseCount <= 0 || _duration <= Duration.zero) {
      _boundaries.clear();
      return;
    }

    final totalSeconds = _duration.inMilliseconds / 1000;
    if (_boundaries.length == phraseCount + 1) return;
    if (_boundaries.length < 2) {
      _boundaries
        ..clear()
        ..addAll(_evenBoundaries(totalSeconds, phraseCount));
      return;
    }

    final old = List<double>.from(_boundaries)..sort();
    _boundaries
      ..clear()
      ..add(0);
    for (var i = 1; i < phraseCount; i++) {
      final ratio = i / phraseCount;
      final oldIndex = (ratio * (old.length - 1))
          .round()
          .clamp(1, old.length - 2)
          .toInt();
      _boundaries.add(old[oldIndex]);
    }
    _boundaries.add(totalSeconds);
    _normalizeBoundaries();
  }

  List<double> _evenBoundaries(double totalSeconds, int phraseCount) {
    return [
      for (var i = 0; i <= phraseCount; i++) totalSeconds * i / phraseCount,
    ];
  }

  void _normalizeBoundaries() {
    if (_boundaries.length < 2) return;
    final totalSeconds = _duration.inMilliseconds / 1000;
    _boundaries[0] = 0;
    _boundaries[_boundaries.length - 1] = totalSeconds;
    for (var i = 1; i < _boundaries.length - 1; i++) {
      final min = _boundaries[i - 1] + 0.05;
      final max = _boundaries[i + 1] - 0.05;
      _boundaries[i] = _boundaries[i].clamp(min, math.max(min, max)).toDouble();
    }
  }

  Future<void> _togglePlay() async {
    if (_audioPath == null) return;
    final player = _player;
    if (player == null) return;
    _previewEnd = null;
    if (_isPlaying) {
      await player.pause();
    } else {
      await player.play();
    }
  }

  Future<void> _seekToSeconds(double seconds) async {
    final player = _player;
    if (player == null) return;
    _previewEnd = null;
    await player.seek(Duration(milliseconds: (seconds * 1000).round()));
  }

  Future<void> _previewSegment(int index) async {
    final player = _player;
    if (player == null) return;
    final segments = _segments;
    if (index < 0 || index >= segments.length) return;
    final segment = segments[index];
    setState(() => _selectedSegment = index);
    _previewEnd = Duration(milliseconds: (segment.end * 1000).round());
    await player.seek(Duration(milliseconds: (segment.start * 1000).round()));
    await player.play();
  }

  Future<void> _exportSegments() async {
    final path = _audioPath;
    final outputDir = _outputDir;
    final segments = _segments;

    if (path == null || outputDir == null || segments.isEmpty) {
      setState(
        () => _status = 'Нужны MP3, список фраз и папка для результата.',
      );
      return;
    }
    if (!_ffmpegReady) {
      setState(() => _status = 'Для экспорта нужен ffmpeg.');
      return;
    }

    setState(() {
      _isBusy = true;
      _status = 'Экспортирую 0 из ${segments.length}...';
    });

    final usedNames = <String, int>{};
    try {
      for (var i = 0; i < segments.length; i++) {
        final segment = segments[i];
        final fileName = _uniqueFileName(
          _safeFileStem(segment.phrase),
          usedNames,
        );
        final outputPath = p.join(outputDir, '$fileName.mp3');
        await _ffmpeg.exportSegment(
          path,
          outputPath,
          segment.start,
          segment.end,
        );
        if (!mounted) return;
        setState(
          () => _status = 'Экспортирую ${i + 1} из ${segments.length}...',
        );
      }
      if (!mounted) return;
      setState(() {
        _status = 'Готово: ${segments.length} MP3 файлов в $outputDir';
        _isBusy = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _status = 'Экспорт остановлен: $error';
        _isBusy = false;
      });
    }
  }

  String _safeFileStem(String phrase) {
    final safe = phrase
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final trimmed = safe.length > 150 ? safe.substring(0, 150).trim() : safe;
    return trimmed.isEmpty ? 'phrase' : trimmed;
  }

  String _uniqueFileName(String base, Map<String, int> usedNames) {
    final key = base.toLowerCase();
    final count = usedNames.update(
      key,
      (value) => value + 1,
      ifAbsent: () => 1,
    );
    return count == 1 ? base : '$base ($count)';
  }

  @override
  Widget build(BuildContext context) {
    final segments = _segments;
    final canExport =
        !_isBusy &&
        _audioPath != null &&
        _outputDir != null &&
        segments.isNotEmpty;

    return Scaffold(
      body: SafeArea(
        child: DropTarget(
          onDragEntered: (_) => setState(() => _isDraggingOver = true),
          onDragExited: (_) => setState(() => _isDraggingOver = false),
          onDragDone: (details) async {
            setState(() => _isDraggingOver = false);
            final mp3Files = details.files
                .map((file) => file.path)
                .where((path) => path.toLowerCase().endsWith('.mp3'))
                .toList();
            final mp3 = mp3Files.isEmpty ? null : mp3Files.first;
            if (mp3 != null) {
              await _loadAudio(mp3);
            }
          },
          child: Stack(
            children: [
              Column(
                children: [
                  _Header(
                    ffmpegStatus: _ffmpegStatus,
                    ffmpegReady: _ffmpegReady,
                    busy: _isBusy,
                    installingDependencies: _isInstallingDependencies,
                    onPickAudio: _pickAudio,
                    onPickOutput: _pickOutputDir,
                    onInstallDependencies: _ffmpegReady ? null : _installFfmpeg,
                    onAutoMark: _autoMark,
                    onExport: canExport ? _exportSegments : null,
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final compact = constraints.maxWidth < 980;
                          final leftPane = _InputPane(
                            audioPath: _audioPath,
                            outputDir: _outputDir,
                            phrasesController: _phrasesController,
                            phraseCount: _phrases.length,
                            onPickAudio: _pickAudio,
                            onPickOutput: _pickOutputDir,
                          );
                          final rightPane = _WorkspacePane(
                            status: _status,
                            busy: _isBusy,
                            duration: _duration,
                            position: _position,
                            playing: _isPlaying,
                            waveform: _waveform,
                            boundaries: _boundaries,
                            segments: segments,
                            selectedSegment: _selectedSegment,
                            onTogglePlay: _togglePlay,
                            onSeek: _seekToSeconds,
                            onSelectSegment: (index) =>
                                setState(() => _selectedSegment = index),
                            onPreviewSegment: _previewSegment,
                            onBoundaryDragStart: (index) =>
                                _dragBoundaryIndex = index,
                            onBoundaryDragUpdate: _updateBoundary,
                            onBoundaryDragEnd: () => _dragBoundaryIndex = null,
                          );

                          if (compact) {
                            final inputHeight = (constraints.maxHeight * 0.40)
                                .clamp(170.0, 260.0)
                                .toDouble();
                            return Column(
                              children: [
                                SizedBox(height: inputHeight, child: leftPane),
                                const SizedBox(height: 14),
                                Expanded(child: rightPane),
                              ],
                            );
                          }

                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(width: 390, child: leftPane),
                              const SizedBox(width: 16),
                              Expanded(child: rightPane),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
              if (_isDraggingOver)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xFF2F6F73).withValues(alpha: 0.12),
                      border: Border.all(
                        color: const Color(0xFF2F6F73),
                        width: 3,
                      ),
                    ),
                    child: const Center(
                      child: Text(
                        'Отпустите MP3 файл',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _updateBoundary(int index, double seconds) {
    if (_dragBoundaryIndex == null ||
        index <= 0 ||
        index >= _boundaries.length - 1) {
      return;
    }
    final min = _boundaries[index - 1] + 0.05;
    final max = _boundaries[index + 1] - 0.05;
    setState(
      () => _boundaries[index] = seconds
          .clamp(min, math.max(min, max))
          .toDouble(),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
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

class _InputPane extends StatelessWidget {
  const _InputPane({
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

class _WorkspacePane extends StatelessWidget {
  const _WorkspacePane({
    required this.status,
    required this.busy,
    required this.duration,
    required this.position,
    required this.playing,
    required this.waveform,
    required this.boundaries,
    required this.segments,
    required this.selectedSegment,
    required this.onTogglePlay,
    required this.onSeek,
    required this.onSelectSegment,
    required this.onPreviewSegment,
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
  final List<PhraseSegment> segments;
  final int? selectedSegment;
  final VoidCallback onTogglePlay;
  final ValueChanged<double> onSeek;
  final ValueChanged<int> onSelectSegment;
  final ValueChanged<int> onPreviewSegment;
  final ValueChanged<int> onBoundaryDragStart;
  final void Function(int index, double seconds) onBoundaryDragUpdate;
  final VoidCallback onBoundaryDragEnd;

  @override
  Widget build(BuildContext context) {
    final totalSeconds = duration.inMilliseconds / 1000;
    final waveformHeight = MediaQuery.sizeOf(context).height < 760
        ? 90.0
        : 220.0;

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
                Text(_formatDuration(position)),
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
                Text(_formatDuration(duration)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: SizedBox(
              height: waveformHeight,
              child: _WaveformEditor(
                waveform: waveform,
                boundaries: boundaries,
                duration: duration,
                position: position,
                selectedSegment: selectedSegment,
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
                            '${_formatSeconds(segment.start)} - ${_formatSeconds(segment.end)}'
                            '  (${_formatSeconds(segment.end - segment.start)})',
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

class _WaveformEditor extends StatefulWidget {
  const _WaveformEditor({
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
  State<_WaveformEditor> createState() => _WaveformEditorState();
}

class _WaveformEditorState extends State<_WaveformEditor> {
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

class PhraseSegment {
  const PhraseSegment({
    required this.phrase,
    required this.start,
    required this.end,
  });

  final String phrase;
  final double start;
  final double end;
}

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
      final result = await _runCommand(attempt.command, attempt.args);
      if (await isAvailable()) {
        return FfmpegInstallResult(
          success: true,
          message: 'ffmpeg установлен через ${attempt.manager}.',
        );
      }
      errors.add(
        '${attempt.manager}: ${result.output.isEmpty ? 'команда завершилась без результата' : result.output}',
      );
    }

    return FfmpegInstallResult(
      success: false,
      message:
          'Не удалось автоустановить ffmpeg. Установите winget, Chocolatey или Scoop, затем повторите. Детали: ${errors.join(' | ')}',
    );
  }

  Future<String?> _findTool(String name) async {
    final executable = Platform.isWindows ? '$name.exe' : name;
    final candidates = <String>[
      executable,
      p.join(Directory.current.path, executable),
      p.join(p.dirname(Platform.resolvedExecutable), executable),
    ];
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
    final check = Platform.isWindows
        ? await _runCommand('where', [name])
        : await _runCommand('/bin/sh', ['-lc', 'command -v $name']);
    if (!check.success) return null;

    final output = check.output.split(RegExp(r'\r?\n')).first.trim();
    return output.isEmpty ? name : output;
  }

  Future<_CommandResult> _runCommand(String command, List<String> args) async {
    try {
      final result = await Process.run(
        command,
        args,
        runInShell: Platform.isWindows,
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

String _formatDuration(Duration duration) {
  final totalSeconds = duration.inSeconds;
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

String _formatSeconds(double seconds) {
  final wholeSeconds = seconds.floor();
  final minutes = wholeSeconds ~/ 60;
  final rest = wholeSeconds % 60;
  final tenths = ((seconds - wholeSeconds) * 10).round().clamp(0, 9).toInt();
  return '$minutes:${rest.toString().padLeft(2, '0')}.$tenths';
}

String _formatFfmpegSeconds(double seconds) => seconds.toStringAsFixed(3);
