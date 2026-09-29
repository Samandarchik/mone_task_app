import 'package:flutter/material.dart';
import 'package:mone_task_app/admin/model/filial_model.dart';
import 'package:mone_task_app/checker/service/task_worker_service.dart';
import 'package:mone_task_app/core/context_extension.dart';
import 'package:mone_task_app/core/data/local/active_filial.dart';
import 'package:mone_task_app/core/data/local/token_storage.dart';
import 'package:mone_task_app/core/di/di.dart';
import 'package:mone_task_app/core/l10n/app_script.dart';
import 'package:mone_task_app/core/theme/app_theme.dart';
import 'package:mone_task_app/core/widgets/app_widgets.dart';
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
  final _searchCtrl = TextEditingController();
  String _query = '';

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
    final ok = await showConfirmDialog(
      context,
      title: tr('Hisobdan chiqish'),
      message: tr('Ishonchingiz komilmi? Qayta kirish uchun parol kerak boʻladi.'),
      confirmLabel: tr('Chiqish'),
      destructive: true,
    );
    if (!ok) return;
    WsService().disconnect();
    await LogOutService().logOut();
    _tokenStorage.removeToken();
    _tokenStorage.putUserData({});
    await ActiveFilial.clear();
    if (mounted) context.pushAndRemove(LoginPage());
  }

  bool _matches(FilialModel f, String q) {
    if (q.isEmpty) return true;
    final lq = q.toLowerCase();
    return f.name.toLowerCase().contains(lq) ||
        displayName(f.name).toLowerCase().contains(trData(q).toLowerCase());
  }

  Future<void> _refresh() async {
    final f = _loadFilials();
    setState(() => _future = f);
    try {
      await f;
    } catch (_) {}
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        automaticallyImplyLeading: widget.isSwitch,
        title: Text(
          widget.isSwitch ? tr('Filialni almashtirish') : tr('Filialni tanlang'),
        ),
        actions: [
          Center(child: ThemeToggle(compact: true)),
          SizedBox(width: 8),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Center(child: ScriptToggle(compact: true)),
          ),
          if (!widget.isSwitch)
            IconButton(
              tooltip: tr('Chiqish'),
              icon: Icon(Icons.logout_rounded, color: AppColors.danger),
              onPressed: _handleLogout,
            ),
          SizedBox(width: 4),
        ],
      ),
      body: FutureBuilder<List<FilialModel>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return AppLoader();
          }
          if (snapshot.hasError) {
            return AppErrorState(
              onRetry: () => setState(() => _future = _loadFilials()),
            );
          }

          final all = snapshot.data ?? [];
          if (all.isEmpty) {
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                children: [
                  SizedBox(
                    height: 420,
                    child: AppEmptyState(
                      icon: Icons.storefront_rounded,
                      title: tr('Filiallar topilmadi'),
                      message: tr(
                        "Sizga hali filial biriktirilmagan. Rahbaringizga murojaat qiling.",
                      ),
                      actionLabel: tr('Yangilash'),
                      onAction: _refresh,
                    ),
                  ),
                ],
              ),
            );
          }

          final filials = all.where((f) => _matches(f, _query)).toList();

          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 720),
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    Text(
                      tr('Qaysi filialda ishlaysiz? Keyinroq uni almashtirishingiz mumkin.'),
                      style: t.bodyMedium?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    if (all.length > 5) ...[
                      SizedBox(height: AppSpacing.md),
                      TextField(
                        controller: _searchCtrl,
                        onChanged: (v) => setState(() => _query = v.trim()),
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          hintText: tr('Filial nomi boʻyicha qidirish'),
                          prefixIcon: Icon(Icons.search_rounded),
                          suffixIcon: _query.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: tr('Tozalash'),
                                  icon: Icon(Icons.close_rounded),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    setState(() => _query = '');
                                  },
                                ),
                        ),
                      ),
                    ],
                    SizedBox(height: AppSpacing.lg),
                    if (filials.isEmpty)
                      Padding(
                        padding: EdgeInsets.only(top: 32),
                        child: AppEmptyState(
                          icon: Icons.search_off_rounded,
                          title: tr('Hech narsa topilmadi'),
                          message: tr('Boshqa soʻz bilan qidirib koʻring.'),
                        ),
                      )
                    else
                      for (final f in filials) ...[
                        _FilialCard(
                          name: displayName(f.name),
                          isActive: ActiveFilial.id == f.filialId,
                          onTap: () => _onSelect(f),
                        ),
                        SizedBox(height: AppSpacing.sm + 2),
                      ],
                  ],
                ),
              ),
            ),
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
      color: AppColors.surface,
      borderRadius: AppRadius.lgAll,
      child: InkWell(
        borderRadius: AppRadius.lgAll,
        onTap: onTap,
        child: Container(
          constraints: BoxConstraints(minHeight: 68),
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: AppRadius.lgAll,
            border: Border.all(
              color: isActive ? AppColors.primary : AppColors.border,
              width: isActive ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isActive
                      ? AppColors.primarySoft
                      : AppColors.surfaceMuted,
                  borderRadius: AppRadius.mdAll,
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.storefront_rounded,
                  color: isActive ? AppColors.primary : AppColors.textSecondary,
                ),
              ),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (isActive) ...[
                      SizedBox(height: 2),
                      Text(
                        tr('Hozirgi filial'),
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (isActive)
                Icon(Icons.check_circle_rounded, color: AppColors.primary)
              else
                Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textTertiary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
