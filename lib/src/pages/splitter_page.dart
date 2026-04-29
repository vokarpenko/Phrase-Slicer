import 'dart:async';
import 'dart:math' as math;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;

import '../models/phrase_segment.dart';
import '../services/ffmpeg_service.dart';
import '../widgets/header.dart';
import '../widgets/input_pane.dart';
import '../widgets/segments_pane.dart';
import '../widgets/workspace_pane.dart';

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
  double _exportVolumeMultiplier = 1.0;
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
      _initializePlayback();
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

  void _initializePlayback() {
    try {
      MediaKit.ensureInitialized();
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
    } on Object catch (error) {
      _player = null;
      _status =
          'Встроенный плеер недоступен: $error. Авторазметка и экспорт могут работать через ffmpeg.';
    }
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

    final player = _player;
    if (player != null) {
      try {
        await player.open(Media(path), play: false);
      } on Object catch (error) {
        _player = null;
        if (!mounted) return;
        setState(() {
          _status =
              'Аудио загружено, но встроенный плеер недоступен: $error. Продолжаю анализ через ffmpeg.';
        });
      }
    }

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
          _exportVolumeMultiplier,
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
                  Header(
                    ffmpegStatus: _ffmpegStatus,
                    ffmpegReady: _ffmpegReady,
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final compact = constraints.maxWidth < 1100;
                          final inputPane = InputPane(
                            audioPath: _audioPath,
                            outputDir: _outputDir,
                            phrasesController: _phrasesController,
                            phraseCount: _phrases.length,
                            ffmpegReady: _ffmpegReady,
                            busy: _isBusy,
                            installingDependencies: _isInstallingDependencies,
                            exportVolumeMultiplier: _exportVolumeMultiplier,
                            onPickAudio: _pickAudio,
                            onPickOutput: _pickOutputDir,
                            onInstallDependencies: _ffmpegReady
                                ? null
                                : _installFfmpeg,
                            onAutoMark: _autoMark,
                            onExport: canExport ? _exportSegments : null,
                            onExportVolumeChanged: (value) =>
                                setState(() => _exportVolumeMultiplier = value),
                          );
                          final workspacePane = WorkspacePane(
                            status: _status,
                            busy: _isBusy,
                            duration: _duration,
                            position: _position,
                            playing: _isPlaying,
                            waveform: _waveform,
                            boundaries: _boundaries,
                            onTogglePlay: _togglePlay,
                            onSeek: _seekToSeconds,
                            onBoundaryDragStart: (index) =>
                                _dragBoundaryIndex = index,
                            onBoundaryDragUpdate: _updateBoundary,
                            onBoundaryDragEnd: () => _dragBoundaryIndex = null,
                          );
                          final segmentsPane = SegmentsPane(
                            segments: segments,
                            selectedSegment: _selectedSegment,
                            onSelectSegment: (index) =>
                                setState(() => _selectedSegment = index),
                            onPreviewSegment: _previewSegment,
                          );

                          if (compact) {
                            return Column(
                              children: [
                                SizedBox(height: 290, child: workspacePane),
                                const SizedBox(height: 14),
                                Expanded(
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Expanded(child: inputPane),
                                      const SizedBox(width: 14),
                                      Expanded(child: segmentsPane),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          }

                          return Column(
                            children: [
                              SizedBox(
                                height: 320,
                                width: double.infinity,
                                child: workspacePane,
                              ),
                              const SizedBox(height: 16),
                              Expanded(
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    SizedBox(width: 420, child: inputPane),
                                    const SizedBox(width: 16),
                                    Expanded(child: segmentsPane),
                                  ],
                                ),
                              ),
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
