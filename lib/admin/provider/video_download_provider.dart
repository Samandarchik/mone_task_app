import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:mone_task_app/checker/model/checker_check_task_model.dart';
import 'package:mone_task_app/core/constants/urls.dart';
import 'package:mone_task_app/core/utils/video_cache_dir.dart';

enum VideoStatus { notStarted, downloading, cached, error }

class VideoDownloadState {
  final VideoStatus status;
  final double progress;
  final String? localPath;

  const VideoDownloadState({
    this.status = VideoStatus.notStarted,
    this.progress = 0.0,
    this.localPath,
  });

  VideoDownloadState copyWith({
    VideoStatus? status,
    double? progress,
    String? localPath,
  }) {
    return VideoDownloadState(
      status: status ?? this.status,
      progress: progress ?? this.progress,
      localPath: localPath ?? this.localPath,
    );
  }
}

class VideoDownloadProvider extends ChangeNotifier {
  /// url → download state
  final Map<String, VideoDownloadState> _states = {};
  bool _isSequenceRunning = false;

  VideoDownloadState getState(String url) {
    return _states[url] ?? const VideoDownloadState();
  }

  bool isCached(String url) => _states[url]?.status == VideoStatus.cached;

  String? getLocalPath(String url) => _states[url]?.localPath;

  /// Resolved video path: local if cached, otherwise original URL
  String resolvedPath(String url) {
    return _states[url]?.localPath ?? url;
  }

  /// Build full URL from relative or absolute path
  String getFullUrl(String originalUrl) {
    if (originalUrl.startsWith('http://') ||
        originalUrl.startsWith('https://')) {
      return originalUrl;
    }
    // "/videos/..." — ikkita "/" bo'lmasin (server 301 bilan qaytaradi)
    final path = originalUrl.startsWith('/') ? originalUrl : '/$originalUrl';
    return '${AppUrls.baseUrl}$path';
  }

  /// Start sequential download for a list of tasks
  Future<void> startDownloadsForTasks(
    List<TaskModel> tasks,
    int filialId,
  ) async {
    if (_isSequenceRunning) return;

    final urls = tasks
        .where((t) => t.filialId == filialId)
        .expand(
          (t) => t.videoUrls.isNotEmpty
              ? t.videoUrls
              : [if (t.videoUrl != null && t.videoUrl!.isNotEmpty) t.videoUrl!],
        )
        .map(getFullUrl)
        .toSet() // unique
        .where(
          (url) =>
              !isCached(url) && getState(url).status != VideoStatus.downloading,
        )
        .toList();

    if (urls.isEmpty) return;

    _isSequenceRunning = true;

    for (final url in urls) {
      await _downloadVideo(url);
    }

    _isSequenceRunning = false;
  }

  Future<void> _downloadVideo(String videoUrl) async {
    if (isCached(videoUrl)) return;

    if (getState(videoUrl).status == VideoStatus.downloading) {
      // Wait for existing download
      while (getState(videoUrl).status == VideoStatus.downloading) {
        await Future.delayed(const Duration(milliseconds: 300));
      }
      return;
    }

    _updateState(
      videoUrl,
      const VideoDownloadState(status: VideoStatus.downloading, progress: 0.0),
    );

    try {
      final localPath = await _getLocalFilePath(videoUrl);
      final file = File(localPath);

      // Check existing file on disk
      if (await file.exists() && await file.length() > 0) {
        final isComplete = await _verifyFileComplete(videoUrl, file);
        if (isComplete) {
          _updateState(
            videoUrl,
            VideoDownloadState(
              status: VideoStatus.cached,
              progress: 1.0,
              localPath: localPath,
            ),
          );
          return;
        }
        await file.delete();
      }

      // Har bir yuklash o'z vaqtinchalik fayliga yozadi: kartadagi video
      // ham shu videoni bir vaqtda keshlashi mumkin (task_video_strip.dart)
      final tempPath =
          '$localPath.${DateTime.now().microsecondsSinceEpoch}.tmp';
      final dio = Dio();

      await dio.download(
        videoUrl,
        tempPath,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            _updateState(
              videoUrl,
              VideoDownloadState(
                status: VideoStatus.downloading,
                progress: received / total,
              ),
            );
          }
        },
      );

      final tempFile = File(tempPath);
      if (await tempFile.exists() && await tempFile.length() > 0) {
        try {
          // Windowsda mavjud faylga rename xato berishi mumkin
          if (await file.exists()) await file.delete();
          await tempFile.rename(localPath);
        } on FileSystemException {
          // Fayl band (o'ynayapti) yoki boshqa yuklash allaqachon qo'ygan —
          // tayyor fayl bo'lsa shuni ishlatamiz
          if (await tempFile.exists()) await tempFile.delete();
          if (!(await file.exists() && await file.length() > 0)) rethrow;
        }
        _updateState(
          videoUrl,
          VideoDownloadState(
            status: VideoStatus.cached,
            progress: 1.0,
            localPath: localPath,
          ),
        );
      } else {
        if (await tempFile.exists()) await tempFile.delete();
        _updateState(
          videoUrl,
          const VideoDownloadState(status: VideoStatus.error),
        );
      }
    } catch (e) {
      debugPrint('Video yuklab bo\'lmadi ($videoUrl): $e');
      // Shu orada video boshqa yo'l bilan to'liq yuklangan bo'lishi mumkin
      try {
        final localPath = await _getLocalFilePath(videoUrl);
        final file = File(localPath);
        if (await file.exists() && await file.length() > 0) {
          _updateState(
            videoUrl,
            VideoDownloadState(
              status: VideoStatus.cached,
              progress: 1.0,
              localPath: localPath,
            ),
          );
          return;
        }
      } catch (_) {}

      _updateState(
        videoUrl,
        const VideoDownloadState(status: VideoStatus.error),
      );
    }
  }

  Future<bool> _verifyFileComplete(String videoUrl, File file) async {
    try {
      final dio = Dio();
      final head = await dio.head(videoUrl);
      final serverSize = int.tryParse(
        head.headers.value('content-length') ?? '',
      );
      final localSize = await file.length();
      return serverSize == null || localSize >= serverSize;
    } catch (_) {
      return true; // Assume complete if can't verify
    }
  }

  Future<String> _getLocalFilePath(String videoUrl) async {
    final videosDir = await getVideoCacheDir();
    final fileName = videoUrl
        .split('/')
        .last
        .replaceAll(RegExp(r'[^\w\s\-\.]'), '_');
    return '${videosDir.path}/$fileName';
  }

  void _updateState(String url, VideoDownloadState state) {
    _states[url] = state;
    _safeNotify();
  }

  /// Build/layout paytida notifyListeners chaqirilsa Flutter assertion beradi —
  /// bunday holatda frame tugagach xabar beramiz.
  bool _notifyScheduled = false;
  void _safeNotify() {
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks) {
      if (_notifyScheduled) return;
      _notifyScheduled = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _notifyScheduled = false;
        notifyListeners();
      });
    } else {
      notifyListeners();
    }
  }

  /// Get all video paths for a filial (resolved: local if cached, URL otherwise)
  List<String> getAllVideoPaths(List<TaskModel> tasks, int filialId) {
    return tasks
        .where(
          (t) =>
              t.filialId == filialId &&
              t.videoUrl != null &&
              t.videoUrl!.isNotEmpty,
        )
        .map((t) {
          final fullUrl = getFullUrl(t.videoUrl!);
          return resolvedPath(fullUrl);
        })
        .toList();
  }

  /// «Ошибка» bosilganda — videoni qayta yuklab ko'rish
  Future<void> retry(String url) async {
    if (getState(url).status == VideoStatus.downloading) return;
    _states.remove(url);
    await _downloadVideo(url);
  }

  /// Clear all cached states (not files)
  void clearCache() {
    _states.clear();
    notifyListeners();
  }
}
