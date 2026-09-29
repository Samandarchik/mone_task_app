import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
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
  bool _connecting = false;

  final _controller = StreamController<Map<String, dynamic>>.broadcast();

  /// Stream of WS events (e.g. {"event": "task_updated", "data": {...}})
  Stream<Map<String, dynamic>> get onEvent => _controller.stream;

  Future<void> connect() async {
    _disposed = false;
    // Allaqachon ulangan / ulanayotgan bo'lsa — qayta ulanmaymiz
    // (aks holda eski kanal yopilib, cheksiz qayta ulanish boshlanadi).
    if (_channel != null || _connecting) return;
    await _connectInternal();
  }

  Future<void> _connectInternal() async {
    if (_disposed) return;
    _connecting = true;

    final old = _channel;
    _channel = null;
    try {
      old?.sink.close();
    } catch (_) {}

    try {
      final token = await sl<TokenStorage>().getToken();
      if (token.isEmpty || _disposed) return;

      final uri = Uri.parse('${AppUrls.wsUrl}?token=$token');
      final ch = WebSocketChannel.connect(uri);
      _channel = ch;

      // Faqat joriy kanal qayta ulanishni boshlaydi — eski kanalning
      // onDone hodisasi yangi ulanishni buzmasin.
      void onLost() {
        if (identical(ch, _channel)) {
          _channel = null;
          _scheduleReconnect();
        }
      }

      ch.stream.listen(
        (message) {
          try {
            final data = jsonDecode(message as String) as Map<String, dynamic>;
            _controller.add(data);
          } catch (_) {}
        },
        onDone: onLost,
        onError: (_) => onLost(),
        cancelOnError: true,
      );

      // Internet yo'q bo'lsa `ready` xato bilan tugaydi — ushlaymiz.
      try {
        await ch.ready;
      } catch (e) {
        debugPrint('WS ulanmadi: $e');
        onLost();
      }
    } catch (_) {
      _scheduleReconnect();
    } finally {
      _connecting = false;
    }
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: 3), _connectInternal);
  }

  void disconnect() {
    _disposed = true;
    _reconnectTimer?.cancel();
    final ch = _channel;
    _channel = null;
    try {
      ch?.sink.close();
    } catch (_) {}
  }
}
