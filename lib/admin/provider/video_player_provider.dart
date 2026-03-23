import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mone_task_app/checker/model/checker_check_task_model.dart';
import 'package:mone_task_app/checker/service/task_worker_service.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class VideoPlayerProvider extends ChangeNotifier {
  final List<String> videoUrls;
  final List<CheckerCheckTaskModel> tasks;
  final void Function(int taskId)? onHalfWatched;
  final Future<bool> Function(int taskId, int status)? onUpdateStatus;

  VideoPlayerController? _controller;
  int _currentIndex;
  bool _isInitialized = false;
  bool _isPlaying = false;
  bool _hasError = false;
  String? _errorMessage;
  bool _halfWatchedFired = false;
  bool _isMuted = false;
  double _playbackSpeed = 1.0;
  bool _isLoading = false;

  /// Status 1 bosilganda recording boshlash uchun signal
  bool _shouldStartRecording = false;
  bool get shouldStartRecording => _shouldStartRecording;

  void consumeRecordingSignal() {
    _shouldStartRecording = false;
  }

  static const List<double> speedOptions = [1.0, 1.5, 2.0];

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

  CheckerCheckTaskModel? get currentTask =>
      _currentIndex < tasks.length ? tasks[_currentIndex] : null;

  double get progress {
    if (!_isInitialized || _hasError || _controller == null) return 0.0;
    final total = _controller!.value.duration.inMilliseconds;
    final current = _controller!.value.position.inMilliseconds;
    if (total <= 0) return 0.0;
    return (current / total).clamp(0.0, 1.0);
  }

  Duration get duration => _controller?.value.duration ?? Duration.zero;
  Duration get position => _controller?.value.position ?? Duration.zero;

  String get speedLabel {
    if (_playbackSpeed == 1.0) return 'x1';
    if (_playbackSpeed == 1.5) return 'x1.5';
    return 'x2';
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
        // Provider orqali yangilash (local + backend, fetchTasks yo'q)
        success = await onUpdateStatus!(taskId, newStatus);
      } else {
        // Fallback: to'g'ridan-to'g'ri service chaqirish
        success = await AdminTaskService().updateTaskStatus(
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

    if (_isInitialized && _controller != null) {
      _controller!.removeListener(_onVideoListener);
      await _controller!.dispose();
    }

    _isInitialized = false;
    _hasError = false;
    _errorMessage = null;
    _halfWatchedFired = false;
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
        _controller = VideoPlayerController.file(file);
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
    } catch (e) {
      _setError(e.toString());
    }
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

    if (!_halfWatchedFired && total > 0 && current >= total * 0.5) {
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
    if (_controller == null || !_isInitialized) return;
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
    _controller?.setVolume(_isMuted ? 0.0 : 1.0);
    notifyListeners();
  }

  void cycleSpeed() {
    final nextIdx =
        (speedOptions.indexOf(_playbackSpeed) + 1) % speedOptions.length;
    _playbackSpeed = speedOptions[nextIdx];
    _controller?.setPlaybackSpeed(_playbackSpeed);
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
    if (_controller == null || !_isInitialized) return;

    final center = Offset(circleSize / 2, circleSize / 2);
    final dx = localPos.dx - center.dx;
    final dy = localPos.dy - center.dy;

    double angle = math.atan2(dy, dx) + math.pi / 2;
    if (angle < 0) angle += 2 * math.pi;

    final ratio = angle / (2 * math.pi);
    _controller!.seekTo(_controller!.value.duration * ratio);
  }

  String formatDuration(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inMinutes)}:${two(d.inSeconds % 60)}';
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    if (_controller != null) {
      _controller!.removeListener(_onVideoListener);
      _controller!.dispose();
    }
    super.dispose();
  }
}
