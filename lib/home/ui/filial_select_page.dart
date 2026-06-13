import 'package:flutter/material.dart';
import 'package:mone_task_app/admin/model/filial_model.dart';
import 'package:mone_task_app/checker/service/task_worker_service.dart';
import 'package:mone_task_app/core/context_extension.dart';
import 'package:mone_task_app/core/data/local/active_filial.dart';
import 'package:mone_task_app/core/data/local/token_storage.dart';
import 'package:mone_task_app/core/di/di.dart';
import 'package:mone_task_app/home/service/login_service.dart';
import 'package:mone_task_app/home/ui/role_home.dart';
import 'package:mone_task_app/worker/service/log_out.dart';
import 'package:mone_task_app/core/network/ws_service.dart';

/// Foydalanuvchi bir nechta filialga biriktirilgan bo'lsa — login dan keyin
/// shu ekran chiqadi va u qaysi filialda ishlashini tanlaydi.
///
/// [allowedIds] — foydalanuvchiga biriktirilgan filial id lari.
/// [role]       — tanlangandan keyin qaysi asosiy ekranga o'tishni belgilaydi.
/// [isSwitch]   — asosiy ekrandan "filialni almashtirish" uchun ochilgan bo'lsa
///                true (orqaga qaytish mumkin).
class FilialSelectPage extends StatefulWidget {
  final List<int> allowedIds;
  final String role;
  final bool isSwitch;

  const FilialSelectPage({
    super.key,
    required this.allowedIds,
    required this.role,
    this.isSwitch = false,
  });

  @override
  State<FilialSelectPage> createState() => _FilialSelectPageState();
}

class _FilialSelectPageState extends State<FilialSelectPage> {
  late Future<List<FilialModel>> _future;
  final TokenStorage _tokenStorage = sl<TokenStorage>();

  @override
  void initState() {
    super.initState();
    _future = _loadFilials();
  }

  Future<List<FilialModel>> _loadFilials() async {
    // Backend /api/filials ni token egasining JORIY ruxsatlari bo'yicha
    // filtrlaydi — shu sahifa har ochilganda yangi ro'yxat keladi.
    // (allowedIds — faqat chaqiruvchi "tanlash kerakmi" qarorini olish uchun.)
    return TaskViewService().fetchFilials();
  }

  void _onSelect(FilialModel filial) async {
    await ActiveFilial.set(filial.filialId, filial.name);
    if (!mounted) return;
    // Tanlangan filial bilan asosiy ekranni toza qayta ochamiz
    context.pushAndRemove(roleHome(widget.role));
  }

  Future<void> _handleLogout() async {
    WsService().disconnect();
    await LogOutService().logOut();
    _tokenStorage.removeToken();
    _tokenStorage.putUserData({});
    await ActiveFilial.clear();
    if (mounted) context.pushAndRemove(LoginPage());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F3F7),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF2F3F7),
        elevation: 0,
        automaticallyImplyLeading: widget.isSwitch,
        title: const Text(
          'Выберите филиал',
          style: TextStyle(fontWeight: FontWeight.w700, color: Colors.black),
        ),
        centerTitle: true,
        actions: [
          if (!widget.isSwitch)
            IconButton(
              tooltip: 'Выйти',
              icon: const Icon(Icons.logout, color: Colors.red),
              onPressed: _handleLogout,
            ),
        ],
      ),
      body: FutureBuilder<List<FilialModel>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator.adaptive());
          }
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    'Ошибка: ${snapshot.error}',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () =>
                        setState(() => _future = _loadFilials()),
                    child: const Text('Повторить'),
                  ),
                ],
              ),
            );
          }

          final filials = snapshot.data ?? [];
          if (filials.isEmpty) {
            return const Center(child: Text('Филиалы не найдены'));
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
            itemCount: filials.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              final f = filials[i];
              final isActive = ActiveFilial.id == f.filialId;
              return _FilialCard(
                name: f.name,
                isActive: isActive,
                onTap: () => _onSelect(f),
              );
            },
          );
        },
      ),
    );
  }
}

class _FilialCard extends StatelessWidget {
  final String name;
  final bool isActive;
  final VoidCallback onTap;

  const _FilialCard({
    required this.name,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isActive
                  ? const Color(0xFF3699ff)
                  : const Color(0xFFE5E7EB),
              width: isActive ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFFE9EBF2),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.storefront,
                    color: Color(0xFF6B7280)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
              ),
              if (isActive)
                const Icon(Icons.check_circle, color: Color(0xFF3699ff))
              else
                const Icon(Icons.chevron_right, color: Color(0xFF9CA3AF)),
            ],
          ),
        ),
      ),
    );
  }
}
