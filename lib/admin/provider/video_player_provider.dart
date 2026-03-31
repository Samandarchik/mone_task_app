import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart' as mkv;
import 'package:mone_task_app/checker/model/checker_check_task_model.dart';
import 'package:mone_task_app/checker/service/task_worker_service.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class VideoPlayerProvider extends ChangeNotifier {
  final List<String> videoUrls;
  final List<TaskModel> tasks;
  final void Function(int taskId)? onHalfWatched;
  final Future<bool> Function(int taskId, int status)? onUpdateStatus;

  // ── video_player (iOS/Android/macOS) ──
  VideoPlayerController? _controller;

  // ── media_kit (Windows) ──
  mk.Player? _mkPlayer;
  mkv.VideoController? _mkController;
  StreamSubscription? _mkPlayingSub;
  StreamSubscription? _mkPositionSub;
  StreamSubscription? _mkDurationSub;
  StreamSubscription? _mkCompletedSub;
  StreamSubscription? _mkErrorSub;

  int _currentIndex;
  bool _isInitialized = false;
  bool _isPlaying = false;
  bool _hasError = false;
  String? _errorMessage;
  bool _halfWatchedFired = false;
  int _accumulatedWatchMs = 0; // haqiqiy ko'rish vaqti (ms)
  int _lastPositionMs = 0; // oxirgi listener dagi position
  bool _isMuted = false;
  double _playbackSpeed = 1.0;
  bool _isLoading = false;

  // ── media_kit state tracking ──
  Duration _mkPosition = Duration.zero;
  Duration _mkDuration = Duration.zero;

  /// Status 1 bosilganda recording boshlash uchun signal
  bool _shouldStartRecording = false;
  bool get shouldStartRecording => _shouldStartRecording;

  void consumeRecordingSignal() {
    _shouldStartRecording = false;
  }

  static const List<double> speedOptions = [1.0, 1.5, 2.0];

  static bool get _useMediaKit => Platform.isWindows;

  VideoPlayerProvider({
    required this.videoUrls,
    required this.tasks,
    int initialIndex = 0,
    this.onHalfWatched,
    this.onUpdateStatus,
  }) : _currentIndex = initialIndex {
    WakelockPlus.enable();
    initializeVideo();
  }

  // ── Getters ──────────────────────────────────────────────────────────────
  VideoPlayerController? get controller => _controller;
  mkv.VideoController? get mkVideoController => _mkController;
  int get currentIndex => _currentIndex;
  bool get isInitialized => _isInitialized;
  bool get isPlaying => _isPlaying;
  bool get hasError => _hasError;
  String? get errorMessage => _errorMessage;
  bool get isMuted => _isMuted;
  double get playbackSpeed => _playbackSpeed;
  bool get isLoading => _isLoading;

  bool get hasPrev => _currentIndex > 0;
  bool get hasNext => _currentIndex < videoUrls.length - 1;

  TaskModel? get currentTask =>
      _currentIndex < tasks.length ? tasks[_currentIndex] : null;

  double get progress {
    if (!_isInitialized || _hasError) return 0.0;
    if (_useMediaKit) {
      final total = _mkDuration.inMilliseconds;
      final current = _mkPosition.inMilliseconds;
      if (total <= 0) return 0.0;
      return (current / total).clamp(0.0, 1.0);
    }
    if (_controller == null) return 0.0;
    final total = _controller!.value.duration.inMilliseconds;
    final current = _controller!.value.position.inMilliseconds;
    if (total <= 0) return 0.0;
    return (current / total).clamp(0.0, 1.0);
  }

  Duration get duration {
    if (_useMediaKit) return _mkDuration;
    return _controller?.value.duration ?? Duration.zero;
  }

  Duration get position {
    if (_useMediaKit) return _mkPosition;
    return _controller?.value.position ?? Duration.zero;
  }

  String get speedLabel {
    if (_playbackSpeed == 1.0) return 'x1';
    if (_playbackSpeed == 1.5) return 'x1.5';
    return 'x2';
  }

  // ── Video size (for FittedBox) ──
  Size get videoSize {
    if (_useMediaKit) {
      final w = _mkPlayer?.state.width;
      final h = _mkPlayer?.state.height;
      if (w != null && h != null && w > 0 && h > 0) {
        return Size(w.toDouble(), h.toDouble());
      }
      return const Size(1920, 1080);
    }
    if (_controller != null && _controller!.value.isInitialized) {
      return _controller!.value.size;
    }
    return const Size(1920, 1080);
  }

  // ── Task status update ──────────────────────────────────────────────────
  Future<bool> updateTaskStatus(
    int taskId,
    int newStatus,
    String? selectedDate,
  ) async {
    try {
      bool success = false;

      if (onUpdateStatus != null) {
        success = await onUpdateStatus!(taskId, newStatus);
      } else {
        success = await TaskViewService().updateTaskStatus(
          taskId,
          newStatus,
          null,
          selectedDate,
        );
      }

      if (success) {
        final index = tasks.indexWhere((t) => t.taskId == taskId);
        if (index != -1) {
          tasks[index].status = newStatus;

          if (newStatus == 1 || newStatus == 2) {
            _shouldStartRecording = true;
          }

          notifyListeners();
        }
      }
      return success;
    } catch (e) {
      return false;
    }
  }

  // ── Initialize video ────────────────────────────────────────────────────
  Future<void> initializeVideo() async {
    if (_isLoading) return;
    _isLoading = true;

    // Dispose previous
    if (_useMediaKit) {
      await _disposeMkPlayer();
    } else {
      if (_isInitialized && _controller != null) {
        _controller!.removeListener(_onVideoListener);
        await _controller!.dispose();
      }
    }

    _isInitialized = false;
    _hasError = false;
    _errorMessage = null;
    _halfWatchedFired = false;
    _accumulatedWatchMs = 0;
    _lastPositionMs = 0;
    _mkPosition = Duration.zero;
    _mkDuration = Duration.zero;
    notifyListeners();

    try {
      String videoPath = videoUrls[_currentIndex];

      if (videoPath.contains('://') && videoPath.contains('/Users/')) {
        final m = RegExp(r'/Users/.*').firstMatch(videoPath);
        if (m != null) videoPath = m.group(0)!;
      } else if (videoPath.contains('://') && videoPath.contains('/data/')) {
        final m = RegExp(r'/data/.*').firstMatch(videoPath);
        if (m != null) videoPath = m.group(0)!;
      }

      final isLocal =
          !videoPath.startsWith('http://') && !videoPath.startsWith('https://');

      if (isLocal) {
        final file = File(videoPath);
        if (!await file.exists()) {
          _setError('Fayl topilmadi: $videoPath');
          return;
        }
        if (await file.length() == 0) {
          _setError("Video fayl bo'sh");
          return;
        }
      }

      if (_useMediaKit) {
        await _initMkPlayer(videoPath, isLocal);
      } else {
        await _initVideoPlayer(videoPath, isLocal);
      }
    } catch (e) {
      _setError(e.toString());
    }
  }

  // ── video_player initialization ──
  Future<void> _initVideoPlayer(String videoPath, bool isLocal) async {
    if (isLocal) {
      _controller = VideoPlayerController.file(File(videoPath));
    } else {
      _controller = VideoPlayerController.networkUrl(Uri.parse(videoPath));
    }

    await _controller!.initialize();
    await _controller!.setLooping(false);
    await _controller!.setVolume(_isMuted ? 0.0 : 1.0);
    await _controller!.setPlaybackSpeed(_playbackSpeed);
    await _controller!.play();

    _controller!.addListener(_onVideoListener);

    _isInitialized = true;
    _isPlaying = true;
    _isLoading = false;
    notifyListeners();
  }

  // ── media_kit initialization (Windows) ──
  Future<void> _initMkPlayer(String videoPath, bool isLocal) async {
    _mkPlayer = mk.Player();
    _mkController = mkv.VideoController(_mkPlayer!);

    // Subscribe to streams
    _mkPlayingSub = _mkPlayer!.stream.playing.listen((playing) {
      _isPlaying = playing;
      notifyListeners();
    });

    _mkPositionSub = _mkPlayer!.stream.position.listen((pos) {
      final current = pos.inMilliseconds;

      // Haqiqiy ko'rish vaqtini hisoblash
      if (_isPlaying && _lastPositionMs > 0) {
        final delta = current - _lastPositionMs;
        if (delta > 0 && delta < 500) {
          _accumulatedWatchMs += delta;
        }
      }
      _lastPositionMs = current;
      _mkPosition = pos;

      // 50% haqiqiy ko'rish vaqti
      final total = _mkDuration.inMilliseconds;
      if (!_halfWatchedFired && total > 0 && _accumulatedWatchMs >= total * 0.5) {
        _halfWatchedFired = true;
        if (onHalfWatched != null && _currentIndex < tasks.length) {
          onHalfWatched!(tasks[_currentIndex].taskId);
        }
      }

      notifyListeners();
    });

    _mkDurationSub = _mkPlayer!.stream.duration.listen((dur) {
      _mkDuration = dur;
      notifyListeners();
    });

    _mkCompletedSub = _mkPlayer!.stream.completed.listen((completed) {
      if (completed) {
        goToNext();
      }
    });

    _mkErrorSub = _mkPlayer!.stream.error.listen((error) {
      if (error.isNotEmpty) {
        _setError(error);
      }
    });

    // Open and play
    final mediaUri = isLocal ? 'file://$videoPath' : videoPath;
    await _mkPlayer!.open(mk.Media(mediaUri));
    await _mkPlayer!.setVolume(_isMuted ? 0.0 : 100.0);
    await _mkPlayer!.setRate(_playbackSpeed);

    _isInitialized = true;
    _isPlaying = true;
    _isLoading = false;
    notifyListeners();
  }

  void _setError(String message) {
    _hasError = true;
    _errorMessage = message;
    _isLoading = false;
    notifyListeners();
  }

  void _onVideoListener() {
    if (_controller == null || !_controller!.value.isInitialized) return;

    final value = _controller!.value;
    final total = value.duration.inMilliseconds;
    final current = value.position.inMilliseconds;

    if (value.isPlaying && _lastPositionMs > 0) {
      final delta = current - _lastPositionMs;
      if (delta > 0 && delta < 500) {
        _accumulatedWatchMs += delta;
      }
    }
    _lastPositionMs = current;

    if (!_halfWatchedFired && total > 0 && _accumulatedWatchMs >= total * 0.5) {
      _halfWatchedFired = true;
      if (onHalfWatched != null && _currentIndex < tasks.length) {
        onHalfWatched!(tasks[_currentIndex].taskId);
      }
    }

    if (!value.isPlaying && current >= total - 200 && total > 0) {
      goToNext();
    }

    notifyListeners();
  }

  // ── Playback controls ──────────────────────────────────────────────────
  void togglePlayPause() {
    if (!_isInitialized) return;
    if (_useMediaKit) {
      _mkPlayer?.playOrPause();
      return;
    }
    if (_controller == null) return;
    if (_isPlaying) {
      _controller!.pause();
    } else {
      _controller!.play();
    }
    _isPlaying = !_isPlaying;
    notifyListeners();
  }

  void toggleMute() {
    _isMuted = !_isMuted;
    if (_useMediaKit) {
      _mkPlayer?.setVolume(_isMuted ? 0.0 : 100.0);
    } else {
      _controller?.setVolume(_isMuted ? 0.0 : 1.0);
    }
    notifyListeners();
  }

  void cycleSpeed() {
    final nextIdx =
        (speedOptions.indexOf(_playbackSpeed) + 1) % speedOptions.length;
    _playbackSpeed = speedOptions[nextIdx];
    if (_useMediaKit) {
      _mkPlayer?.setRate(_playbackSpeed);
    } else {
      _controller?.setPlaybackSpeed(_playbackSpeed);
    }
    notifyListeners();
  }

  void goToNext() {
    if (!hasNext) return;
    _currentIndex++;
    _isLoading = false;
    initializeVideo();
  }

  void goToPrev() {
    if (!hasPrev) return;
    _currentIndex--;
    _isLoading = false;
    initializeVideo();
  }

  void seekFromCircleTouch(Offset localPos, double circleSize) {
    if (!_isInitialized) return;

    final center = Offset(circleSize / 2, circleSize / 2);
    final dx = localPos.dx - center.dx;
    final dy = localPos.dy - center.dy;

    double angle = math.atan2(dy, dx) + math.pi / 2;
    if (angle < 0) angle += 2 * math.pi;

    final ratio = angle / (2 * math.pi);

    if (_useMediaKit) {
      final target = _mkDuration * ratio;
      _mkPlayer?.seek(target);
    } else if (_controller != null) {
      _controller!.seekTo(_controller!.value.duration * ratio);
    }
  }

  String formatDuration(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inMinutes)}:${two(d.inSeconds % 60)}';
  }

  Future<void> _disposeMkPlayer() async {
    _mkPlayingSub?.cancel();
    _mkPositionSub?.cancel();
    _mkDurationSub?.cancel();
    _mkCompletedSub?.cancel();
    _mkErrorSub?.cancel();
    _mkPlayingSub = null;
    _mkPositionSub = null;
    _mkDurationSub = null;
    _mkCompletedSub = null;
    _mkErrorSub = null;
    await _mkPlayer?.dispose();
    _mkPlayer = null;
    _mkController = null;
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    if (_useMediaKit) {
      _disposeMkPlayer();
    } else if (_controller != null) {
      _controller!.removeListener(_onVideoListener);
      _controller!.dispose();
    }
    super.dispose();
  }
}
