import 'dart:async';
import 'dart:convert';

import 'package:mone_task_app/core/constants/urls.dart';
import 'package:mone_task_app/core/data/local/token_storage.dart';
import 'package:mone_task_app/core/di/di.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class WsService {
  static final WsService _instance = WsService._internal();
  factory WsService() => _instance;
  WsService._internal();

  WebSocketChannel? _channel;
  Timer? _reconnectTimer;
  bool _disposed = false;

  final _controller = StreamController<Map<String, dynamic>>.broadcast();

  /// Stream of WS events (e.g. {"event": "task_updated", "data": {...}})
  Stream<Map<String, dynamic>> get onEvent => _controller.stream;

  Future<void> connect() async {
    _disposed = false;
    await _connectInternal();
  }

  Future<void> _connectInternal() async {
    if (_disposed) return;

    try {
      _channel?.sink.close();
    } catch (_) {}

    try {
      final token = await sl<TokenStorage>().getToken();
      if (token.isEmpty) return;

      final uri = Uri.parse('${AppUrls.wsUrl}?token=$token');
      _channel = WebSocketChannel.connect(uri);

      _channel!.stream.listen(
        (message) {
          try {
            final data = jsonDecode(message as String) as Map<String, dynamic>;
            _controller.add(data);
          } catch (_) {}
        },
        onDone: () => _scheduleReconnect(),
        onError: (_) => _scheduleReconnect(),
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), _connectInternal);
  }

  void disconnect() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _channel = null;
  }
}
