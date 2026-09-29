import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:mone_task_app/checker/ui/player2.dart';
import 'package:mone_task_app/core/constants/urls.dart';
import 'package:mone_task_app/core/context_extension.dart';
import 'package:mone_task_app/core/data/local/token_storage.dart';
import 'package:mone_task_app/core/di/di.dart';
import 'package:mone_task_app/core/l10n/app_script.dart';
import 'package:mone_task_app/deep_link_service.dart';
import 'package:mone_task_app/home/service/login_service.dart';
import 'package:mone_task_app/home/ui/role_home.dart';

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
  _DlError? _error;
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
            _error = _DlError.auth;
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
          _error = _DlError.notFound;
          _isLoading = false;
        });
      }
    } on DioException catch (e) {
      if (!mounted) return;
      if (e.response?.statusCode == 401) {
        setState(() {
          _error = _DlError.auth;
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = _DlError.server;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _DlError.unknown;
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
    context.pushAndRemove(landingForUser(user));
  }

  String _errorText(_DlError e) => switch (e) {
    _DlError.auth => tr('Videoni koʻrish uchun tizimga kiring'),
    _DlError.notFound => tr('Vazifa topilmadi'),
    _DlError.server => tr("Serverda xatolik yuz berdi. Keyinroq urinib koʻring."),
    _DlError.unknown => tr('Xatolik yuz berdi'),
  };

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
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.black,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_taskName != null)
                          Text(
                            trData(_taskName!),
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        if (_submittedBy != null)
                          Text(
                            trData(_submittedBy!),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white60,
                              fontSize: 13,
                            ),
                          ),
                      ],
                    ),
                  ),
                  SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _goToApp,
                    icon: Icon(Icons.arrow_forward, size: 18),
                    label: Text(tr('Ilovaga oʻtish')),
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
                  ? Center(
                      child: CircularProgressIndicator.adaptive(
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                  : _error != null
                  ? _Message(
                      icon: _error == _DlError.auth
                          ? Icons.lock_outline_rounded
                          : Icons.error_outline_rounded,
                      text: _errorText(_error!),
                      actionLabel: _error == _DlError.auth
                          ? tr('Kirish')
                          : tr('Qayta urinish'),
                      onAction: _error == _DlError.auth
                          ? _goToApp
                          : () {
                              setState(() {
                                _isLoading = true;
                                _error = null;
                              });
                              _loadTask();
                            },
                    )
                  : _videoUrl != null && _videoUrl!.isNotEmpty
                  ? Center(
                      child: CircleVideoPlayer2(
                        videoUrl: _fullVideoUrl(_videoUrl!),
                      ),
                    )
                  : _Message(
                      icon: Icons.videocam_off_outlined,
                      text: tr('Video hali yuborilmagan'),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _DlError { auth, notFound, server, unknown }

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white54, size: 44),
            SizedBox(height: 14),
            Text(
              text,
              style: TextStyle(color: Colors.white70, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null && onAction != null) ...[
              SizedBox(height: 20),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  minimumSize: Size(160, 48),
                ),
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
