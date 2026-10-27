import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:mone_task_app/core/constants/urls.dart';
import 'package:mone_task_app/core/utils/video_cache_dir.dart';
import 'package:video_player/video_player.dart';

/// Video URL (to'liq yoki nisbiy) → to'liq URL.
String fullVideoUrl(String url) {
  if (url.startsWith('http')) return url;
  return '${AppUrls.baseUrl}${url.startsWith('/') ? '' : '/'}$url';
}

/// Video URL (to'liq yoki nisbiy) → backend /thumbs endpointidagi kichik JPG.
String videoThumbUrl(String url) {
  var path = url.startsWith('http') ? Uri.parse(url).path : url;
  if (!path.startsWith('/')) path = '/$path';
  return '${AppUrls.baseUrl}/thumbs$path';
}

/// Katta player ishlatadigan xotiradagi joy — VideoDownloadProvider bilan
/// bitta papka (Windowsda AppData, boshqa joyda Documents/videos).
Future<File> videoCacheFile(String fullUrl) async {
  final directory = await getVideoCacheDir();
  final fileName = fullUrl
      .split('/')
      .last
      .replaceAll(RegExp(r'[^\w\s\-\.]'), '_');
  return File('${directory.path}/$fileName');
}

/// Hozir fonda yuklanayotgan videolar (bir videoni ikki marta yuklamaslik uchun)
final Set<String> _downloading = {};

/// Videoni xotiraga yuklab qo'yadi — keyingi safar internetdan emas,
/// shu fayldan ochiladi. Yarim yuklangan fayl `.tmp` bo'lib qoladi.
Future<void> cacheVideoInBackground(String fullUrl, File file) async {
  if (!_downloading.add(fullUrl)) return;
  // O'z vaqtinchalik fayli — VideoDownloadProvider ham bir vaqtda yuklashi mumkin
  final temp = File(
    '${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
  );
  try {
    await file.parent.create(recursive: true);
    await Dio().download(fullUrl, temp.path);
    if (await file.exists() && await file.length() > 0) {
      await temp.delete();
    } else if (await temp.length() > 0) {
      await temp.rename(file.path);
    }
  } catch (_) {
    if (await temp.exists()) await temp.delete();
  } finally {
    _downloading.remove(fullUrl);
  }
}

/// Vazifa tagidagi kichik videolar qatori.
///
/// [slotCount] — super admin belgilagan videolar soni. Yuborilgan videolar
/// thumbnail bo'lib, qolgan joylar bo'sh slot sifatida ko'rinadi.
/// Bir qatorda 4 tagacha, ko'p bo'lsa keyingi qatorga o'tadi.
///
/// Bir marta bosish — video shu joyda biroz kattalashib o'ynaydi,
/// tugagach shu taskning keyingi videosi, oxirgisidan keyin esa
/// [nextVideoUrl] (keyingi taskning videosi) avtomatik boshlanadi.
/// Bosib turish — [onOpenVideo] (katta player).
/// [onRerecordVideo] berilsa, o'ynayotgan videoda "qayta yozish" tugmasi chiqadi.
/// [onAddVideo] berilsa, majburiy videolar yuklangach "Ещё видео" tugmasi
/// chiqadi — xodim xohlasa qo'shimcha video qo'shadi ([maxVideos] gacha).
class TaskVideoStrip extends StatelessWidget {
  final List<String> videoUrls;
  final int slotCount;
  final void Function(int index)? onOpenVideo;
  final void Function(int index)? onRerecordVideo;
  final void Function(int index)? onTapEmpty;
  final VoidCallback? onAddVideo;
  final int maxVideos;

  /// Keyingi (videoli) vazifaning birinchi videosi — shu vazifaning oxirgi
  /// videosi tugagach o'sha video avtomatik boshlanadi.
  final String? nextVideoUrl;

  const TaskVideoStrip({
    super.key,
    required this.videoUrls,
    required this.slotCount,
    this.onOpenVideo,
    this.onRerecordVideo,
    this.onTapEmpty,
    this.onAddVideo,
    this.maxVideos = 10,
    this.nextVideoUrl,
  });

  static const double _gap = 8;
  static const int _perRow = 4;
  static const double _maxTile = 92;
  static const double _expandScale = 1.6;

  @override
  Widget build(BuildContext context) {
    final total = slotCount > videoUrls.length ? slotCount : videoUrls.length;
    // Qo'shimcha video — faqat majburiylari to'lgach (bo'sh slot qolmaganda)
    final canAddMore =
        onAddVideo != null &&
        videoUrls.isNotEmpty &&
        videoUrls.length >= slotCount &&
        videoUrls.length < maxVideos;
    if (total == 0 && !canAddMore) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final fit = (constraints.maxWidth - _gap * (_perRow - 1)) / _perRow;
        final size = fit > _maxTile ? _maxTile : fit;
        final expanded = (size * _expandScale).clamp(
          size,
          constraints.maxWidth,
        );
        return Wrap(
          spacing: _gap,
          runSpacing: _gap,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            for (var i = 0; i < total; i++)
              i < videoUrls.length
                  ? _VideoThumb(
                      key: ValueKey(videoUrls[i]),
                      url: videoUrls[i],
                      number: i + 1,
                      showNumber: total > 1,
                      size: size,
                      expandedSize: expanded,
                      onOpen: onOpenVideo == null
                          ? null
                          : () => onOpenVideo!(i),
                      onRerecord: onRerecordVideo == null
                          ? null
                          : () => onRerecordVideo!(i),
                      // Tugagach keyingi video o'zi boshlanadi
                      // keyingi vazifaning videosiga o'tadi
                      onEnded: i + 1 < videoUrls.length
                          ? () => _VideoThumb.playing.value = videoUrls[i + 1]
                          : nextVideoUrl == null
                          ? null
                          : () => _VideoThumb.playing.value = nextVideoUrl,
                    )
                  : SizedBox.square(
                      dimension: size,
                      child: _EmptySlot(
                        number: i + 1,
                        onTap: onTapEmpty == null ? null : () => onTapEmpty!(i),
                      ),
                    ),
            if (canAddMore)
              SizedBox.square(
                dimension: size,
                child: _AddVideoTile(onTap: onAddVideo!),
              ),
          ],
        );
      },
    );
  }
}

class _VideoThumb extends StatefulWidget {
  final String url;
  final int number;
  final bool showNumber;
  final double size;
  final double expandedSize;
  final VoidCallback? onOpen;
  final VoidCallback? onRerecord;

  /// Video oxirigacha ko'rilganda (null bo'lsa — shunchaki to'xtaydi)
  final VoidCallback? onEnded;

  const _VideoThumb({
    super.key,
    required this.url,
    required this.number,
    required this.showNumber,
    required this.size,
    required this.expandedSize,
    this.onOpen,
    this.onRerecord,
    this.onEnded,
  });

  /// Bir vaqtda faqat bitta video inline o'ynaydi
  static final ValueNotifier<String?> playing = ValueNotifier(null);

  @override
  State<_VideoThumb> createState() => _VideoThumbState();
}

class _VideoThumbState extends State<_VideoThumb> {
  VideoPlayerController? _controller;
  bool _active = false;

  // video_player Windows'da ishlamaydi — u yerda bir bosish katta playerni ochadi
  bool get _inlineSupported => !Platform.isWindows;

  @override
  void initState() {
    super.initState();
    _VideoThumb.playing.addListener(_onPlayingChanged);
  }

  @override
  void dispose() {
    _VideoThumb.playing.removeListener(_onPlayingChanged);
    if (_VideoThumb.playing.value == widget.url) {
      _VideoThumb.playing.value = null;
    }
    _controller?.dispose();
    super.dispose();
  }

  void _onPlayingChanged() {
    final current = _VideoThumb.playing.value;
    if (_active && current != widget.url) {
      _stop();
    } else if (!_active && current == widget.url && _inlineSupported) {
      // Oldingi video tugadi — navbat shu videoga keldi. Keyingi vazifa
      // ekrandan pastda bo'lsa, unga scroll qilamiz.
      Scrollable.ensureVisible(
        context,
        alignment: 0.3,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
      _start();
    }
  }

  Future<void> _start() async {
    _VideoThumb.playing.value = widget.url;
    setState(() => _active = true);
    // Avval yuklab olingan bo'lsa — xotiradan, aks holda internetdan
    // o'ynaymiz va keyingi safar uchun fonda xotiraga yuklab qo'yamiz.
    final fullUrl = fullVideoUrl(widget.url);
    final file = await videoCacheFile(fullUrl);
    if (!mounted || _VideoThumb.playing.value != widget.url) return;
    final VideoPlayerController controller;
    if (await file.exists() && await file.length() > 0) {
      controller = VideoPlayerController.file(file);
    } else {
      controller = VideoPlayerController.networkUrl(Uri.parse(fullUrl));
      cacheVideoInBackground(fullUrl, file);
    }
    if (!mounted || !_active || _controller != null) {
      controller.dispose();
      return;
    }
    _controller = controller;
    try {
      await controller.initialize();
    } catch (_) {
      if (mounted && _controller == controller) _stop();
      return;
    }
    if (!mounted || _controller != controller) return;
    controller.addListener(_onTick);
    await controller.play();
    setState(() {});
  }

  void _onTick() {
    final c = _controller;
    if (c == null) return;
    final v = c.value;
    if (v.isInitialized &&
        !v.isPlaying &&
        v.duration > Duration.zero &&
        v.position >= v.duration) {
      c.removeListener(_onTick);
      final next = widget.onEnded;
      next != null ? next() : _stop();
    }
  }

  void _stop() {
    final c = _controller;
    _controller = null;
    c?.removeListener(_onTick);
    // VideoPlayer widgeti daraxtdan chiqqandan keyin o'chiramiz
    if (c != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => c.dispose());
    }
    if (_VideoThumb.playing.value == widget.url) {
      _VideoThumb.playing.value = null;
    }
    if (mounted) setState(() => _active = false);
  }

  void _handleTap() {
    if (!_inlineSupported) {
      widget.onOpen?.call();
      return;
    }
    _active ? _stop() : _start();
  }

  void _handleLongPress() {
    if (_active) _stop();
    widget.onOpen?.call();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final ready = controller != null && controller.value.isInitialized;
    final dim = _active ? widget.expandedSize : widget.size;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: dim,
      height: dim,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_active ? 18 : 14),
        boxShadow: _active
            ? const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 14,
                  offset: Offset(0, 6),
                ),
              ]
            : const [],
      ),
      child: Material(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(_active ? 18 : 14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _handleTap,
          onLongPress: widget.onOpen == null ? null : _handleLongPress,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                videoThumbUrl(widget.url),
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF374151), Color(0xFF111827)],
                    ),
                  ),
                ),
              ),
              if (ready)
                FittedBox(
                  fit: BoxFit.cover,
                  clipBehavior: Clip.hardEdge,
                  child: SizedBox(
                    width: controller.value.size.width,
                    height: controller.value.size.height,
                    child: VideoPlayer(controller),
                  ),
                ),
              if (!_active)
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0x99000000)],
                    ),
                  ),
                ),
              if (!_active)
                Center(
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.9),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      size: 20,
                      color: Color(0xFF111827),
                    ),
                  ),
                ),
              if (_active && !ready)
                const Center(
                  child: SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                ),
              if (ready)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: VideoProgressIndicator(
                    controller,
                    allowScrubbing: true,
                    padding: EdgeInsets.zero,
                    colors: const VideoProgressColors(
                      playedColor: Colors.white,
                      bufferedColor: Colors.white38,
                      backgroundColor: Colors.white12,
                    ),
                  ),
                ),
              if (_active && widget.onRerecord != null)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Material(
                    color: Colors.black54,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () {
                        _stop();
                        widget.onRerecord!();
                      },
                      child: const Padding(
                        padding: EdgeInsets.all(6),
                        child: Icon(
                          Icons.replay_rounded,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              if (widget.showNumber)
                Positioned(
                  left: 6,
                  bottom: 5,
                  child: Text(
                    '${widget.number}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      shadows: [Shadow(blurRadius: 4)],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptySlot extends StatelessWidget {
  final int number;
  final VoidCallback? onTap;

  const _EmptySlot({required this.number, this.onTap});

  @override
  Widget build(BuildContext context) {
    final active = onTap != null;
    final color = active ? const Color(0xFF2563EB) : const Color(0xFF9CA3AF);
    return Material(
      color: active ? const Color(0xFFEFF4FF) : const Color(0xFFF3F4F6),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: color.withValues(alpha: 0.35),
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                active
                    ? Icons.add_a_photo_outlined
                    : Icons.videocam_off_outlined,
                size: 20,
                color: color,
              ),
              const SizedBox(height: 4),
              Text(
                '$number',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// «Ещё видео» — majburiy videolardan tashqari qo'shimcha video qo'shish.
class _AddVideoTile extends StatelessWidget {
  final VoidCallback onTap;

  const _AddVideoTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3B82F6), Color(0xFF8B5CF6)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6366F1).withValues(alpha: 0.35),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.22),
                ),
                child: const Icon(
                  Icons.add_rounded,
                  size: 22,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Ещё видео',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
