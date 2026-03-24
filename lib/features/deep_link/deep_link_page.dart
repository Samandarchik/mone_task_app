import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:mone_task_app/admin/provider/admin_task_ui.dart';
import 'package:mone_task_app/checker/ui/player2.dart';
import 'package:mone_task_app/core/constants/urls.dart';
import 'package:mone_task_app/core/context_extension.dart';
import 'package:mone_task_app/core/data/local/token_storage.dart';
import 'package:mone_task_app/core/di/di.dart';
import 'package:mone_task_app/deep_link_service.dart';
import 'package:mone_task_app/home/service/login_service.dart';
import 'package:mone_task_app/worker/ui/task_worker_ui.dart';

/// Deep link orqali kelganda ko'rinadigan sahifa.
/// Login so'ramasdan to'g'ridan-to'g'ri video ko'rsatadi.
/// Tepada "Ilovaga kirish" tugmasi — rolega qarab yo'naltiradi.
class DeepLinkPage extends StatefulWidget {
  final DeepLinkData data;
  const DeepLinkPage({super.key, required this.data});

  @override
  State<DeepLinkPage> createState() => _DeepLinkPageState();
}

class _DeepLinkPageState extends State<DeepLinkPage> {
  bool _isLoading = true;
  String? _error;
  String? _taskName;
  String? _videoUrl;
  String? _submittedBy;

  @override
  void initState() {
    super.initState();
    _loadTask();
  }

  Future<void> _loadTask() async {
    try {
      final token = await sl<TokenStorage>().getToken();
      if (token.isEmpty) {
        if (mounted) {
          setState(() {
            _error = 'Tizimga kiring';
            _isLoading = false;
          });
        }
        return;
      }

      final dio = sl<Dio>();
      final response = await dio.get(
        '${AppUrls.tasks}/${widget.data.taskId}',
        queryParameters: {'date': widget.data.date},
      );

      if (!mounted) return;

      if (response.data != null && response.data['success'] == true) {
        final task = response.data['data'];
        setState(() {
          _taskName = task['task'] ?? '';
          _videoUrl = task['videoUrl'];
          _submittedBy = task['submittedBy'];
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Task topilmadi';
          _isLoading = false;
        });
      }
    } on DioException catch (e) {
      if (!mounted) return;
      if (e.response?.statusCode == 401) {
        setState(() {
          _error = 'Tizimga kiring';
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Server xatosi';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Xatolik yuz berdi';
        _isLoading = false;
      });
    }
  }

  void _goToApp() {
    // Agar orqada sahifa bor bo'lsa — pop (ilova ochiq holatda link kelgan)
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }
    // Agar orqada hech narsa yo'q (ilova yopiq edi) — role ga qarab sahifa ochish
    final user = sl<TokenStorage>().getUserData();
    if (user == null) {
      context.pushAndRemove(LoginPage());
      return;
    }
    if (user.role == 'super_admin' || user.role == 'checker') {
      context.pushAndRemove(const AdminTaskUi());
    } else if (user.role == 'worker') {
      context.pushAndRemove(const TaskWorkerUi());
    } else {
      context.pushAndRemove(LoginPage());
    }
  }

  String _fullVideoUrl(String url) {
    if (url.startsWith('http')) return url;
    return '${AppUrls.baseUrl}/$url';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Tepada: task nomi + ilovaga kirish tugmasi
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.black,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_taskName != null)
                          Text(
                            _taskName!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        if (_submittedBy != null)
                          Text(
                            _submittedBy!,
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 13,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _goToApp,
                    icon: const Icon(Icons.arrow_forward, size: 18),
                    label: const Text('Ilovaga kirish'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Video yoki loading/error
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator.adaptive(
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                  : _error != null
                  ? Center(
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : _videoUrl != null && _videoUrl!.isNotEmpty
                  ? Center(
                      child: CircleVideoPlayer2(
                        videoUrl: _fullVideoUrl(_videoUrl!),
                      ),
                    )
                  : const Center(
                      child: Text(
                        'Video hali yuborilmagan',
                        style: TextStyle(color: Colors.white70, fontSize: 16),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
