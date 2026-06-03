import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

class VideoCacheManagerPage extends StatefulWidget {
  const VideoCacheManagerPage({super.key});

  @override
  State<VideoCacheManagerPage> createState() => _VideoCacheManagerPageState();
}

class _VideoCacheManagerPageState extends State<VideoCacheManagerPage> {
  bool _isLoading = true;
  int _totalVideos = 0;
  double _totalSize = 0; // MB da
  List<VideoFileInfo> _videoFiles = [];

  @override
  void initState() {
    super.initState();
    _loadCacheInfo();
  }

  Future<void> _loadCacheInfo() async {
    setState(() => _isLoading = true);

    try {
      final directory = await getApplicationDocumentsDirectory();
      final videosDir = Directory('${directory.path}/videos');

      if (!await videosDir.exists()) {
        setState(() {
          _isLoading = false;
          _totalVideos = 0;
          _totalSize = 0;
          _videoFiles = [];
        });
        return;
      }

      final files = videosDir.listSync();
      final videoFiles = <VideoFileInfo>[];
      double totalBytes = 0;

      for (var file in files) {
        if (file is File) {
          final stat = await file.stat();
          final sizeInMB = stat.size / (1024 * 1024);
          totalBytes += stat.size;

          videoFiles.add(VideoFileInfo(
            name: file.path.split('/').last,
            path: file.path,
            size: sizeInMB,
            date: stat.modified,
          ));
        }
      }

      // Sanaga ko'ra saralash (eng yangi birinchi)
      videoFiles.sort((a, b) => b.date.compareTo(a.date));

      setState(() {
        _totalVideos = videoFiles.length;
        _totalSize = totalBytes / (1024 * 1024);
        _videoFiles = videoFiles;
        _isLoading = false;
      });
    } catch (e) {
      print('Cache info yuklashda xatolik: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _clearAllCache() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Очистить весь кэш'),
        content: Text(
          'Действительно удалить ${_totalVideos} видео (${_totalSize.toStringAsFixed(2)} MB)?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);

    try {
      final directory = await getApplicationDocumentsDirectory();
      final videosDir = Directory('${directory.path}/videos');

      if (await videosDir.exists()) {
        await videosDir.delete(recursive: true);
        await videosDir.create();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Кэш успешно очищен'),
            backgroundColor: Colors.green,
          ),
        );
      }

      await _loadCacheInfo();
    } catch (e) {
      print('Cache tozalashda xatolik: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteVideo(VideoFileInfo video) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить видео'),
        content: Text('Удалить ${video.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final file = File(video.path);
      if (await file.exists()) {
        await file.delete();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Видео удалено'),
            backgroundColor: Colors.green,
          ),
        );
      }

      await _loadCacheInfo();
    } catch (e) {
      print('Video o\'chirishda xatolik: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return 'Сегодня ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays == 1) {
      return 'Вчера ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} дн. назад';
    } else {
      return '${date.day}.${date.month}.${date.year}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Управление кэшем видео'),
        actions: [
          if (_totalVideos > 0)
            IconButton(
              onPressed: _clearAllCache,
              icon: const Icon(CupertinoIcons.trash),
              tooltip: 'Удалить всё',
            ),
          IconButton(
            onPressed: _loadCacheInfo,
            icon: const Icon(CupertinoIcons.refresh),
            tooltip: 'Обновить',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator.adaptive())
          : Column(
              children: [
                // Statistika kartasi
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.blue.shade400,
                        Colors.blue.shade600,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blue.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _StatCard(
                            icon: CupertinoIcons.videocam_fill,
                            label: 'Видео',
                            value: '$_totalVideos шт.',
                          ),
                          Container(
                            width: 1,
                            height: 50,
                            color: Colors.white30,
                          ),
                          _StatCard(
                            icon: CupertinoIcons.arrow_down_circle_fill,
                            label: 'Размер',
                            value: '${_totalSize.toStringAsFixed(2)} MB',
                          ),
                        ],
                      ),
                      if (_totalVideos > 0) ...[
                        const SizedBox(height: 20),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                CupertinoIcons.info_circle_fill,
                                color: Colors.white,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  'В среднем на видео: ${(_totalSize / _totalVideos).toStringAsFixed(2)} MB',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Video ro'yxati
                Expanded(
                  child: _totalVideos == 0
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                CupertinoIcons.folder,
                                size: 80,
                                color: Colors.grey.shade400,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Видео не загружены',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _videoFiles.length,
                          itemBuilder: (context, index) {
                            final video = _videoFiles[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              elevation: 2,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                leading: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.shade50,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    CupertinoIcons.play_circle_fill,
                                    color: Colors.blue.shade600,
                                    size: 28,
                                  ),
                                ),
                                title: Text(
                                  video.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Row(
                                    children: [
                                      Icon(
                                        CupertinoIcons.clock,
                                        size: 14,
                                        color: Colors.grey.shade600,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        _formatDate(video.date),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Icon(
                                        CupertinoIcons.arrow_down_circle,
                                        size: 14,
                                        color: Colors.grey.shade600,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${video.size.toStringAsFixed(2)} MB',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                trailing: IconButton(
                                  onPressed: () => _deleteVideo(video),
                                  icon: const Icon(
                                    CupertinoIcons.trash,
                                    color: Colors.red,
                                  ),
                                  tooltip: 'Удалить',
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

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(
          icon,
          color: Colors.white,
          size: 32,
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class VideoFileInfo {
  final String name;
  final String path;
  final double size; // MB da
  final DateTime date;

  VideoFileInfo({
    required this.name,
    required this.path,
    required this.size,
    required this.date,
  });
}
