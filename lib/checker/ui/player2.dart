import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart' as mkv;
import 'package:mone_task_app/core/l10n/app_script.dart';
import 'package:mone_task_app/core/theme/app_theme.dart';
import 'package:video_player/video_player.dart';

class CircleVideoPlayer2 extends StatefulWidget {
  final String videoUrl;

  /// Video 50% ko'rilganda bir marta chaqiriladi
  final VoidCallback? onHalfWatched;

  const CircleVideoPlayer2({
    super.key,
    required this.videoUrl,
    this.onHalfWatched,
  });

  @override
  State<CircleVideoPlayer2> createState() => _CircleVideoPlayer2State();
}

class _CircleVideoPlayer2State extends State<CircleVideoPlayer2>
    with SingleTickerProviderStateMixin {
  static bool get _useMediaKit => Platform.isWindows;

  static const _networkErrorKey =
      'Internet aloqasini tekshirib, qayta urinib koʻring.';

  // ── video_player (iOS/Android/macOS) ──
  VideoPlayerController? _controller;

  // ── media_kit (Windows) ──
  mk.Player? _mkPlayer;
  mkv.VideoController? _mkController;
  StreamSubscription? _mkPlayingSub;
  StreamSubscription? _mkPositionSub;
  StreamSubscription? _mkDurationSub;
  StreamSubscription? _mkErrorSub;
  StreamSubscription? _mkBufferingSub;
  bool _mkBuffering = false;

  bool _isInitialized = false;
  bool _isPlaying = false;
  bool _hasError = false;

  /// O'zbek lotin kalit — ko'rsatishda tr() orqali o'giriladi.
  String? _errorKey;

  /// Har bir yuklash urinishi raqami (eskirgan yuklash natijasi tashlanadi).
  int _loadGen = 0;
  bool _disposed = false;

  // 50% callback bir marta chaqirilsin
  bool _halfWatchedFired = false;
  // Video real ijro vaqtini hisoblash uchun
  Duration _watchedDuration = Duration.zero;
  DateTime? _lastTickTime;

  // media_kit state
  Duration _mkPosition = Duration.zero;
  Duration _mkDuration = Duration.zero;

  late AnimationController _animationController;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 300),
    )..forward();
    // build ichida emas — har rebuild'da yangi listener qo'shilmasin.
    _scaleAnim = Tween(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    _initializeVideo();
  }

  bool _isCurrent(int gen) => mounted && !_disposed && gen == _loadGen;

  void _setError(String key, int gen) {
    if (!_isCurrent(gen)) return;
    setState(() {
      _hasError = true;
      _errorKey = key;
    });
  }

  Future<void> _initializeVideo() async {
    final gen = ++_loadGen;
    try {
      String videoPath = widget.videoUrl;

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
          debugPrint('Video fayl topilmadi: $videoPath');
          _setError('Video fayl topilmadi.', gen);
          return;
        }
        if (await file.length() == 0) {
          _setError('Video fayl boʻsh.', gen);
          return;
        }
      }

      // Fayl tekshiruvi paytida yangi yuklash boshlangan bo'lsa — to'xtaymiz.
      if (!_isCurrent(gen)) return;

      if (_useMediaKit) {
        await _initMkPlayer(videoPath, isLocal, gen);
      } else {
        await _initVideoPlayerController(videoPath, isLocal, gen);
      }
    } catch (e) {
      debugPrint('Video ochilmadi: $e');
      _setError(_networkErrorKey, gen);
    }
  }

  /// Xatodan keyin qayta yuklash.
  bool _retrying = false;

  Future<void> _retry() async {
    if (_retrying) return; // ikki marta bosilsa ikkita player ochilmasin
    _retrying = true;
    try {
      await _retryInner();
    } finally {
      _retrying = false;
    }
  }

  Future<void> _retryInner() async {
    await _releasePlayers();
    if (!mounted) return;
    setState(() {
      _hasError = false;
      _errorKey = null;
      _isInitialized = false;
      _isPlaying = false;
      _mkBuffering = false;
      _mkPosition = Duration.zero;
      _mkDuration = Duration.zero;
      _lastTickTime = null;
    });
    await _initializeVideo();
  }

  Future<void> _initVideoPlayerController(
    String videoPath,
    bool isLocal,
    int gen,
  ) async {
    final ctrl = isLocal
        ? VideoPlayerController.file(File(videoPath))
        : VideoPlayerController.networkUrl(Uri.parse(videoPath));
    _controller = ctrl;

    try {
      await ctrl.initialize();
      if (!_isCurrent(gen)) return _dropStale(ctrl);
      await ctrl.setLooping(true);
      await ctrl.play();
    } catch (e) {
      if (identical(_controller, ctrl)) _controller = null;
      await _disposeStale(ctrl);
      rethrow;
    }
    if (!_isCurrent(gen)) return _dropStale(ctrl);

    ctrl.addListener(_onVideoProgress);

    setState(() {
      _isInitialized = true;
      _isPlaying = true;
    });
  }

  /// Eskirgan yuklash controller'i: maydonni bo'shatib, yopadi.
  Future<void> _dropStale(VideoPlayerController c) {
    if (identical(_controller, c)) _controller = null;
    return _disposeStale(c);
  }

  Future<void> _disposeStale(VideoPlayerController c) async {
    try {
      c.removeListener(_onVideoProgress);
      await c.dispose();
    } catch (_) {}
  }

  Future<void> _initMkPlayer(String videoPath, bool isLocal, int gen) async {
    final player = mk.Player();
    _mkPlayer = player;
    _mkController = mkv.VideoController(player);

    _mkPlayingSub = player.stream.playing.listen((playing) {
      if (mounted) {
        setState(() => _isPlaying = playing);
        _updateHalfWatchMk();
      }
    });

    _mkPositionSub = player.stream.position.listen((pos) {
      if (mounted) {
        setState(() => _mkPosition = pos);
        _updateHalfWatchMk();
      }
    });

    _mkDurationSub = player.stream.duration.listen((dur) {
      if (mounted) setState(() => _mkDuration = dur);
    });

    _mkBufferingSub = player.stream.buffering.listen((b) {
      if (mounted) setState(() => _mkBuffering = b);
    });

    _mkErrorSub = player.stream.error.listen((error) {
      if (error.isNotEmpty && mounted) {
        debugPrint('media_kit xatosi: $error');
        _setError(_networkErrorKey, gen);
      }
    });

    final mediaUri = isLocal ? 'file://$videoPath' : videoPath;
    await player.open(mk.Media(mediaUri));
    if (!_isCurrent(gen)) return _dropStaleMk(player);
    await player.setPlaylistMode(mk.PlaylistMode.loop);
    if (!_isCurrent(gen)) return _dropStaleMk(player);

    setState(() {
      _isInitialized = true;
      _isPlaying = true;
    });
  }

  /// Eskirgan media_kit player — ovoz fonda o'ynab qolmasin.
  Future<void> _dropStaleMk(mk.Player player) async {
    if (identical(_mkPlayer, player)) {
      // Obunalar ham shu player'niki — hammasini yopamiz.
      await _releasePlayers();
      return;
    }
    try {
      await player.dispose();
    } catch (_) {}
  }

  void _updateHalfWatchMk() {
    if (_halfWatchedFired) return;
    if (_mkDuration.inMilliseconds == 0) return;

    if (_isPlaying) {
      final now = DateTime.now();
      if (_lastTickTime != null) {
        final delta = now.difference(_lastTickTime!);
        if (delta.inMilliseconds < 500) {
          _watchedDuration += delta;
        }
      }
      _lastTickTime = now;
    } else {
      _lastTickTime = null;
    }

    final halfDuration = _mkDuration ~/ 2;
    if (_watchedDuration >= halfDuration) {
      _halfWatchedFired = true;
      widget.onHalfWatched?.call();
    }
  }

  void _onVideoProgress() {
    final ctrl = _controller;
    if (ctrl == null) return;

    if (ctrl.value.hasError && !_hasError) {
      debugPrint('Video ijro xatosi: ${ctrl.value.errorDescription}');
      _setError(_networkErrorKey, _loadGen);
      return;
    }

    if (mounted) setState(() {});

    if (_halfWatchedFired) return;
    if (!ctrl.value.isInitialized) return;

    final duration = ctrl.value.duration;
    if (duration.inMilliseconds == 0) return;

    if (ctrl.value.isPlaying) {
      final now = DateTime.now();
      if (_lastTickTime != null) {
        final delta = now.difference(_lastTickTime!);
        if (delta.inMilliseconds < 500) {
          _watchedDuration += delta;
        }
      }
      _lastTickTime = now;
    } else {
      _lastTickTime = null;
    }

    final halfDuration = duration ~/ 2;
    if (_watchedDuration >= halfDuration) {
      _halfWatchedFired = true;
      widget.onHalfWatched?.call();
    }
  }

  /// Controller / player va obunalarni yopadi.
  Future<void> _releasePlayers() async {
    _mkPlayingSub?.cancel();
    _mkPositionSub?.cancel();
    _mkDurationSub?.cancel();
    _mkErrorSub?.cancel();
    _mkBufferingSub?.cancel();
    _mkPlayingSub = null;
    _mkPositionSub = null;
    _mkDurationSub = null;
    _mkErrorSub = null;
    _mkBufferingSub = null;
    final player = _mkPlayer;
    _mkPlayer = null;
    _mkController = null;
    final ctrl = _controller;
    _controller = null;
    try {
      await player?.dispose();
    } catch (_) {}
    if (ctrl != null) await _disposeStale(ctrl);
  }

  @override
  void dispose() {
    _disposed = true;
    _loadGen++;
    _releasePlayers();
    _animationController.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inMinutes)}:${two(d.inSeconds % 60)}';
  }

  Duration get _currentPosition {
    if (_useMediaKit) return _mkPosition;
    return _controller?.value.position ?? Duration.zero;
  }

  Duration get _currentDuration {
    if (_useMediaKit) return _mkDuration;
    return _controller?.value.duration ?? Duration.zero;
  }

  bool get _isBuffering {
    if (!_isInitialized || _hasError) return false;
    if (_useMediaKit) return _mkBuffering;
    return _controller?.value.isBuffering ?? false;
  }

  void _togglePlay() {
    if (!_isInitialized || _hasError) return;
    if (_useMediaKit) {
      _mkPlayer?.playOrPause();
      return;
    }
    final ctrl = _controller;
    if (ctrl == null) return;
    if (ctrl.value.isPlaying) {
      ctrl.pause();
      setState(() => _isPlaying = false);
    } else {
      ctrl.play();
      setState(() => _isPlaying = true);
    }
  }

  Widget _buildVideoWidget() {
    if (_useMediaKit && _mkController != null) {
      return mkv.Video(
        controller: _mkController!,
        fill: Colors.black,
      );
    }
    if (_controller != null) {
      return FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: _controller!.value.size.width,
          height: _controller!.value.size.height,
          child: VideoPlayer(_controller!),
        ),
      );
    }
    return SizedBox.shrink();
  }

  Widget _buildProgressBar(double circleSize) {
    final duration = _currentDuration;
    final position = _currentPosition;
    final progress = duration.inMilliseconds == 0
        ? 0.0
        : position.inMilliseconds / duration.inMilliseconds;
    final progressWidth = circleSize * 0.9;

    const timeStyle = TextStyle(
      color: Colors.white,
      fontSize: 13,
      fontWeight: FontWeight.w600,
      fontFeatures: [FontFeature.tabularFigures()],
    );

    return Container(
      width: progressWidth,
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.textPrimary.withValues(alpha: 0.78),
        borderRadius: AppRadius.xlAll,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_formatDuration(position), style: timeStyle),
              Text(
                _formatDuration(duration),
                style: timeStyle.copyWith(
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
          SizedBox(height: 6),
          GestureDetector(
            onHorizontalDragUpdate: (d) =>
                _seekTo(d.localPosition.dx, progressWidth - 32),
            onTapDown: (d) => _seekTo(d.localPosition.dx, progressWidth - 32),
            child: Container(
              height: 30,
              color: Colors.transparent,
              child: Stack(
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 12,
                    child: Container(
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 12,
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: progress.clamp(0.0, 1.0),
                      child: Container(
                        height: 5,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: (progressWidth - 32 - 16) * progress.clamp(0.0, 1.0),
                    top: 7,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _seekTo(double x, double width) {
    final d = _currentDuration;
    final ratio = (x - 16).clamp(0.0, width) / width;
    if (_useMediaKit) {
      _mkPlayer?.seek(d * ratio);
    } else {
      _controller?.seekTo(d * ratio);
    }
  }

  void _toggleVolume() {
    if (_useMediaKit) {
      final currentVol = _mkPlayer?.state.volume ?? 100.0;
      _mkPlayer?.setVolume(currentVol > 0 ? 0.0 : 100.0);
    } else {
      _controller?.setVolume((_controller!.value.volume > 0) ? 0 : 1);
    }
    setState(() {});
  }

  Widget _roundButton({
    required String tooltip,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: Material(
          color: AppColors.textPrimary.withValues(alpha: 0.78),
          shape: CircleBorder(),
          child: InkWell(
            customBorder: CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 48,
              height: 48,
              child: Icon(icon, color: Colors.white, size: 24),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorOverlay() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(28.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.videocam_off_rounded,
              color: Colors.white70,
              size: 44,
            ),
            SizedBox(height: AppSpacing.md),
            Text(
              tr('Videoni ochib boʻlmadi'),
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            if (_errorKey != null) ...[
              SizedBox(height: AppSpacing.sm),
              Text(
                tr(_errorKey!),
                style: TextStyle(color: Colors.white70, fontSize: 13),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: _retry,
              icon: Icon(Icons.refresh_rounded, size: 20),
              label: Text(tr('Qayta urinish')),
              style: FilledButton.styleFrom(
                minimumSize: Size(0, 44),
                padding: EdgeInsets.symmetric(horizontal: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final circleSize = size.width * 0.85;

    final bool volumeOn = _useMediaKit
        ? (_mkPlayer?.state.volume ?? 100.0) > 0
        : (_controller?.value.volume ?? 1.0) > 0;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(color: Colors.transparent),
            ),
          ),

          Align(
            alignment: Alignment.topCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(height: MediaQuery.of(context).size.height * 0.1),
                ScaleTransition(
                  scale: _scaleAnim,
                  child: GestureDetector(
                    onTap: _togglePlay,
                    child: Container(
                      width: circleSize,
                      height: circleSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black,
                        boxShadow: [
                          BoxShadow(
                            color: Color(0x40111827),
                            blurRadius: 24,
                            spreadRadius: 2,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      child: ClipOval(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (_isInitialized && !_hasError)
                              _buildVideoWidget(),

                            if ((!_isInitialized || _isBuffering) &&
                                !_hasError)
                              Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.6,
                                  color: Colors.white,
                                ),
                              ),

                            if (_hasError) _buildErrorOverlay(),

                            if (_isInitialized && !_isPlaying && !_hasError)
                              Container(
                                color: Colors.black26,
                                child: Center(
                                  child: Container(
                                    padding: EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(
                                        alpha: 0.5,
                                      ),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.play_arrow_rounded,
                                      size: 48,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                if (_isInitialized && !_hasError)
                  Padding(
                    padding: EdgeInsets.only(top: AppSpacing.xl),
                    child: _buildProgressBar(circleSize),
                  ),
              ],
            ),
          ),

          Positioned(
            top: MediaQuery.of(context).padding.top + AppSpacing.lg,
            right: AppSpacing.lg,
            child: _roundButton(
              tooltip: tr('Yopish'),
              icon: Icons.close_rounded,
              onTap: () => Navigator.pop(context),
            ),
          ),

          if (_isInitialized && !_hasError)
            Positioned(
              top: MediaQuery.of(context).padding.top + AppSpacing.lg,
              left: AppSpacing.lg,
              child: _roundButton(
                tooltip: volumeOn ? tr('Ovozni oʻchirish') : tr('Ovozni yoqish'),
                icon: volumeOn
                    ? Icons.volume_up_rounded
                    : Icons.volume_off_rounded,
                onTap: _toggleVolume,
              ),
            ),
        ],
      ),
    );
  }
}
