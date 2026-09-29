import 'package:flutter/material.dart';
import 'package:mone_task_app/admin/model/filial_model.dart';
import 'package:mone_task_app/admin/service/get_excel_service.dart';
import 'package:mone_task_app/checker/service/task_worker_service.dart';
import 'package:mone_task_app/core/l10n/app_script.dart';
import 'package:mone_task_app/core/theme/app_theme.dart';
import 'package:mone_task_app/core/widgets/app_widgets.dart';
import 'package:share_plus/share_plus.dart';
import 'package:mone_task_app/core/utils/telegram_share.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';

class ExcelReportPage extends StatefulWidget {
  final List<FilialModel>? filials;
  final List<int>? filialIds; // Ishchi ko'ra oladigan filial ID'lari

  const ExcelReportPage({super.key, this.filials, this.filialIds});

  @override
  State<ExcelReportPage> createState() => _ExcelReportPageState();
}

class _ExcelReportPageState extends State<ExcelReportPage> {
  final ExcelReportService _reportService = ExcelReportService();
  final TaskViewService _adminService = TaskViewService();

  List<FilialModel>? _allFilials;
  List<FilialModel>? _availableFilials; // Faqat ko'ra oladigan filiallar
  FilialModel? selectedFilial;
  DateTimeRange? selectedDateRange;
  bool isLoading = false;
  bool isLoadingFilials = false;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // Standart davr — oxirgi 7 kun.
    selectedDateRange = DateTimeRange(
      start: today.subtract(Duration(days: 6)),
      end: today,
    );
    _initializeFilials();
  }

  Future<void> _initializeFilials() async {
    if (widget.filials != null && widget.filials!.isNotEmpty) {
      setState(() {
        _allFilials = widget.filials;
        _filterAvailableFilials();
      });
    } else {
      await _fetchFilials();
    }
  }

  void _filterAvailableFilials() {
    if (_allFilials == null) return;

    // Agar filialIds null yoki bo'sh bo'lsa, barcha filiallarni ko'rsatish
    if (widget.filialIds == null || widget.filialIds!.isEmpty) {
      _availableFilials = _allFilials;
    } else {
      // Faqat ruxsat berilgan filiallarni filter qilish
      _availableFilials = _allFilials!
          .where((filial) => widget.filialIds!.contains(filial.filialId))
          .toList();
    }
    // Bitta filial bo'lsa — avtomatik tanlanadi.
    if (selectedFilial == null && _availableFilials?.length == 1) {
      selectedFilial = _availableFilials!.first;
    }
  }

  Future<void> _fetchFilials() async {
    setState(() {
      isLoadingFilials = true;
      errorMessage = null;
    });

    try {
      final filials = await _adminService.fetchFilials();
      if (!mounted) return;
      setState(() {
        _allFilials = filials;
        _filterAvailableFilials();
        isLoadingFilials = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        errorMessage = _cleanError(e);
        isLoadingFilials = false;
      });
    }
  }

  String _cleanError(Object e) => e.toString().replaceFirst('Exception: ', '');

  String _formatDate(DateTime date) {
    return DateFormat('yyyy-MM-dd').format(date);
  }

  String _displayDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  void _setPreset(int days) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    setState(() {
      selectedDateRange = DateTimeRange(
        start: today.subtract(Duration(days: days - 1)),
        end: today,
      );
    });
  }

  bool _isPreset(int days) {
    final r = selectedDateRange;
    if (r == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return DateUtils.isSameDay(r.end, today) &&
        DateUtils.isSameDay(r.start, today.subtract(Duration(days: days - 1)));
  }

  Future<void> _selectDateRange(BuildContext context) async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      helpText: tr('Davrni tanlang'),
      cancelText: tr('Bekor qilish'),
      confirmText: tr('Tanlash'),
      saveText: tr('Tanlash'),
      fieldStartLabelText: tr('Boshlanish'),
      fieldEndLabelText: tr('Tugash'),
      initialDateRange:
          selectedDateRange ??
          DateTimeRange(
            start: DateTime.now().subtract(Duration(days: 7)),
            end: DateTime.now(),
          ),
    );

    if (picked != null) {
      setState(() {
        selectedDateRange = picked;
      });
    }
  }

  static const _xlsxMime =
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

  /// Hisobot tayyor — qayerga yuborishni tanlash oynasi.
  Future<void> _showShareOptions({
    required String filePath,
    required String subject,
    required String text,
  }) async {
    final hasTelegram = await TelegramShare.isInstalled();
    if (!mounted) return;

    Future<void> shareSystem() async {
      final result = await Share.shareXFiles(
        [XFile(filePath, mimeType: _xlsxMime)],
        subject: subject,
        text: text,
      );
      if (result.status == ShareResultStatus.success && mounted) {
        showAppSnack(context, tr('Hisobot yuborildi'), type: SnackType.success);
      }
    }

    Future<void> shareTelegram() async {
      final ok = await TelegramShare.shareFile(
        filePath,
        text: '$subject\n$text',
        mime: _xlsxMime,
      );
      if (!ok) {
        if (mounted) {
          showAppSnack(
            context,
            tr("Telegram ochilmadi — boshqa ilova orqali yuboring"),
            type: SnackType.error,
          );
        }
        await shareSystem();
      }
    }

    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) {
        final t = Theme.of(ctx).textTheme;
        Widget option({
          required String value,
          required IconData icon,
          required Color color,
          required String title,
          required String subtitle,
        }) {
          return ListTile(
            onTap: () => Navigator.pop(ctx, value),
            contentPadding: EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 4,
            ),
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: AppRadius.mdAll,
              ),
              child: Icon(icon, color: color),
            ),
            title: Text(title, style: t.titleSmall),
            subtitle: Text(subtitle),
            trailing: Icon(Icons.chevron_right_rounded),
          );
        }

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 4),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      color: AppColors.success,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(tr('Hisobot tayyor'), style: t.titleLarge),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(
                  tr('Qayerga yuborasiz?'),
                  style: t.bodyMedium?.copyWith(color: AppColors.textSecondary),
                ),
              ),
              if (hasTelegram)
                option(
                  value: 'telegram',
                  icon: Icons.send_rounded,
                  color: Color(0xFF229ED9),
                  title: tr('Telegram orqali yuborish'),
                  subtitle: tr('Chat yoki guruhni tanlaysiz'),
                ),
              option(
                value: 'other',
                icon: Icons.ios_share_rounded,
                color: AppColors.primary,
                title: hasTelegram
                    ? tr('Boshqa ilova orqali')
                    : tr('Yuborish yoki saqlash'),
                subtitle: tr('Telegram, email, Drive va boshqalar'),
              ),
              SizedBox(height: 12),
            ],
          ),
        );
      },
    );

    if (choice == 'telegram') {
      await shareTelegram();
    } else if (choice == 'other') {
      await shareSystem();
    }
  }

  Future<void> _downloadAndShareExcel() async {
    if (selectedFilial == null) {
      showAppSnack(context, tr('Filialni tanlang'), type: SnackType.error);
      return;
    }

    if (selectedDateRange == null) {
      showAppSnack(context, tr('Davrni tanlang'), type: SnackType.error);
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      final startDate = _formatDate(selectedDateRange!.start);
      final endDate = _formatDate(selectedDateRange!.end);

      final directory = await getTemporaryDirectory();
      final fileName =
          'hisobot_${selectedFilial!.name}_${startDate}_$endDate.xlsx';
      final filePath = '${directory.path}/$fileName';

      await _reportService.downloadAndSaveExcel(
        filialId: selectedFilial!.filialId,
        filialName: selectedFilial!.name,
        startDate: startDate,
        endDate: endDate,
        savePath: filePath,
      );

      if (!mounted) return;
      await _showShareOptions(
        filePath: filePath,
        subject: '${tr('Hisobot')} — ${displayName(selectedFilial!.name)}',
        text: '${tr('Davr')}: $startDate ${tr('dan')} $endDate ${tr('gacha')}',
      );
    } catch (e) {
      if (mounted) {
        showAppSnack(
          context,
          '${tr('Xatolik')}: ${_cleanError(e)}',
          type: SnackType.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Excel hisobot'))),
      body: isLoadingFilials
          ? AppLoader()
          : errorMessage != null
          ? AppErrorState(message: errorMessage, onRetry: _fetchFilials)
          : _availableFilials == null || _availableFilials!.isEmpty
          ? AppEmptyState(
              icon: Icons.storefront_outlined,
              title: tr("Sizga filial biriktirilmagan"),
              message: tr(
                "Hisobot olish uchun administratordan filialga ruxsat so'rang.",
              ),
            )
          : _buildForm(context),
    );
  }

  Widget _buildForm(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: EdgeInsets.all(16),
          children: [
            // Izoh
            Container(
              padding: EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: AppRadius.lgAll,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.table_chart_outlined,
                    color: AppColors.primary,
                  ),
                  SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      tr(
                        "Filial va davrni tanlang — hisobot Excel fayl ko'rinishida tayyorlanadi va uni ulashishingiz mumkin.",
                      ),
                      style: t.bodyMedium?.copyWith(
                        color: AppColors.primaryDark,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: AppSpacing.lg),

            // Filial tanlash
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      tr('Filial'),
                      style: t.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: AppSpacing.md),
                    DropdownButtonFormField<FilialModel>(
                      isExpanded: true,
                      initialValue: selectedFilial,
                      decoration: InputDecoration(
                        hintText: tr('Filialni tanlang'),
                        prefixIcon: Icon(Icons.storefront_outlined),
                      ),
                      items: _availableFilials?.map((filial) {
                        return DropdownMenuItem<FilialModel>(
                          value: filial,
                          child: Text(
                            displayName(filial.name),
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (FilialModel? value) {
                        setState(() {
                          selectedFilial = value;
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: AppSpacing.md),

            // Sana tanlash
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      tr('Davr'),
                      style: t.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: AppSpacing.md),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: Text(tr('Bugun')),
                          selected: _isPreset(1),
                          onSelected: (_) => _setPreset(1),
                        ),
                        ChoiceChip(
                          label: Text(tr('7 kun')),
                          selected: _isPreset(7),
                          onSelected: (_) => _setPreset(7),
                        ),
                        ChoiceChip(
                          label: Text(tr('30 kun')),
                          selected: _isPreset(30),
                          onSelected: (_) => _setPreset(30),
                        ),
                      ],
                    ),
                    SizedBox(height: AppSpacing.md),
                    InkWell(
                      onTap: () => _selectDateRange(context),
                      borderRadius: AppRadius.mdAll,
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.border),
                          borderRadius: AppRadius.mdAll,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.calendar_month_outlined,
                              color: AppColors.textSecondary,
                            ),
                            SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: Text(
                                selectedDateRange == null
                                    ? tr('Davrni tanlang')
                                    : '${_displayDate(selectedDateRange!.start)} ${tr('dan')} ${_displayDate(selectedDateRange!.end)} ${tr('gacha')}',
                                style: t.bodyLarge?.copyWith(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            Text(
                              tr("O'zgartirish"),
                              style: t.labelLarge?.copyWith(
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: AppSpacing.xl),

            // Yuklash tugmasi
            FilledButton.icon(
              onPressed: isLoading ? null : _downloadAndShareExcel,
              icon: isLoading
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(Icons.download_rounded),
              label: Text(
                isLoading
                    ? tr('Tayyorlanmoqda...')
                    : tr('Hisobotni yuklab olish'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
