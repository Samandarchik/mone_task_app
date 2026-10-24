import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mone_task_app/admin/model/filial_model.dart';
import 'package:mone_task_app/admin/service/get_excel_service.dart';
import 'package:mone_task_app/checker/service/task_worker_service.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

class ExcelReportPage extends StatefulWidget {
  final List<FilialModel>? filials;
  final List<int>? filialIds; // Ishchi ko'ra oladigan filial ID'lari

  const ExcelReportPage({Key? key, this.filials, this.filialIds})
    : super(key: key);

  @override
  State<ExcelReportPage> createState() => _ExcelReportPageState();
}

class _ExcelReportPageState extends State<ExcelReportPage> {
  final ExcelReportService _reportService = ExcelReportService();
  final TaskViewService _adminService = TaskViewService();
  final GlobalKey _buttonKey = GlobalKey();

  List<FilialModel>? _allFilials;
  List<FilialModel>? _availableFilials; // Faqat ko'ra oladigan filiallar
  final Set<int> _selectedIds = {};
  late DateTime _start;
  late DateTime _end;
  bool isLoading = false;
  bool isLoadingFilials = false;
  String? errorMessage;
  String? _progress;

  static bool get _isDesktop =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  @override
  void initState() {
    super.initState();
    // Standart: oxirgi 7 kun
    final today = _dateOnly(DateTime.now());
    _end = today;
    _start = today.subtract(const Duration(days: 6));
    _initializeFilials();
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

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
    // Bitta filial bo'lsa — avtomatik tanlanadi
    if (_availableFilials!.length == 1) {
      _selectedIds.add(_availableFilials!.first.filialId);
    }
  }

  Future<void> _fetchFilials() async {
    setState(() {
      isLoadingFilials = true;
      errorMessage = null;
    });

    try {
      final filials = await _adminService.fetchFilials();
      setState(() {
        _allFilials = filials;
        _filterAvailableFilials();
        isLoadingFilials = false;
      });
    } catch (e) {
      setState(() {
        errorMessage = 'Ошибка при загрузке филиалов: $e';
        isLoadingFilials = false;
      });
      _showSnackBar('Ошибка при загрузке филиалов', isError: true);
    }
  }

  String _formatDate(DateTime date) {
    return DateFormat('yyyy-MM-dd').format(date);
  }

  String _formatHuman(DateTime date) {
    return DateFormat('dd.MM.yyyy').format(date);
  }

  // ---------------- Sana tanlash (Cupertino) ----------------

  void _applyPreset(DateTime start, DateTime end) {
    setState(() {
      _start = _dateOnly(start);
      _end = _dateOnly(end);
    });
  }

  Future<void> _pickDate({required bool isStart}) async {
    final today = _dateOnly(DateTime.now());
    DateTime temp = isStart ? _start : _end;

    final picked = await showCupertinoModalPopup<DateTime>(
      context: context,
      builder: (ctx) => Container(
        height: 320,
        color: CupertinoColors.systemBackground.resolveFrom(ctx),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CupertinoButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Отмена'),
                  ),
                  Text(
                    isStart ? 'Начало' : 'Конец',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  CupertinoButton(
                    onPressed: () => Navigator.of(ctx).pop(temp),
                    child: const Text('Выбрать'),
                  ),
                ],
              ),
              Expanded(
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.date,
                  initialDateTime: temp,
                  minimumDate: DateTime(2020),
                  maximumDate: today,
                  dateOrder: DatePickerDateOrder.dmy,
                  onDateTimeChanged: (d) => temp = _dateOnly(d),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (picked == null) return;
    setState(() {
      if (isStart) {
        _start = picked;
        if (_end.isBefore(_start)) _end = _start;
      } else {
        _end = picked;
        if (_start.isAfter(_end)) _start = _end;
      }
    });
  }

  // ---------------- Yuklab olish ----------------

  String _safeName(String s) =>
      s.replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_');

  Future<Directory> _targetDir() async {
    if (_isDesktop) {
      final downloads = await getDownloadsDirectory();
      if (downloads != null) {
        await downloads.create(recursive: true);
        return downloads;
      }
    }
    return getTemporaryDirectory();
  }

  Rect? _shareOrigin() {
    final box = _buttonKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> _downloadAndShareExcel() async {
    final selected = _availableFilials!
        .where((f) => _selectedIds.contains(f.filialId))
        .toList();
    if (selected.isEmpty) {
      _showSnackBar('Выберите филиал', isError: true);
      return;
    }

    setState(() => isLoading = true);

    try {
      final startDate = _formatDate(_start);
      final endDate = _formatDate(_end);
      final dir = await _targetDir();
      final paths = <String>[];

      for (var i = 0; i < selected.length; i++) {
        final filial = selected[i];
        if (selected.length > 1) {
          setState(() => _progress = '${i + 1}/${selected.length}');
        }
        final fileName =
            'hisobot_${_safeName(filial.name)}_${startDate}_$endDate.xlsx';
        Future<void> save(String path) => _reportService.downloadAndSaveExcel(
              filialId: filial.filialId,
              filialName: filial.name,
              startDate: startDate,
              endDate: endDate,
              savePath: path,
            );
        var filePath = '${dir.path}/$fileName';
        try {
          await save(filePath);
        } on FileSystemException {
          // Downloads'ga ruxsat bo'lmasa — ilova papkasiga saqlaymiz
          final fallback = await getApplicationDocumentsDirectory();
          filePath = '${fallback.path}/$fileName';
          await save(filePath);
        }
        paths.add(filePath);
      }

      if (_isDesktop) {
        // Desktop: fayllar Downloads'ga saqlanadi va har biri avtomatik ochiladi
        for (final path in paths) {
          await launchUrl(Uri.file(path));
        }
        _showSnackBar(
          paths.length == 1
              ? 'Сохранено и открыто: ${paths.first}'
              : 'Сохранено и открыто ${paths.length} файлов',
        );
        return;
      }

      final result = await SharePlus.instance.share(
        ShareParams(
          files: paths.map((p) => XFile(p)).toList(),
          subject: 'Отчёт: ${selected.map((f) => f.name).join(', ')}',
          text: 'Период: с $startDate по $endDate',
          sharePositionOrigin: _shareOrigin(),
        ),
      );

      if (result.status == ShareResultStatus.success) {
        _showSnackBar('Успешно отправлено');
      }
    } catch (e) {
      _showSnackBar('Ошибка: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
          _progress = null;
        });
      }
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ---------------- UI ----------------

  Widget _sectionTitle(String text, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Row(
        children: [
          Text(
            text,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget _filialSection() {
    final filials = _availableFilials!;
    final allSelected = _selectedIds.length == filials.length;
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle(
          'ФИЛИАЛЫ (${_selectedIds.length}/${filials.length})',
          trailing: filials.length > 1
              ? CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 24),
                  onPressed: () => setState(() {
                    if (allSelected) {
                      _selectedIds.clear();
                    } else {
                      _selectedIds.addAll(filials.map((f) => f.filialId));
                    }
                  }),
                  child: Text(
                    allSelected ? 'Снять все' : 'Выбрать все',
                    style: const TextStyle(fontSize: 14),
                  ),
                )
              : null,
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: filials.map((f) {
            final selected = _selectedIds.contains(f.filialId);
            return FilterChip(
              label: Text(f.name),
              selected: selected,
              showCheckmark: true,
              selectedColor: scheme.primaryContainer,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              onSelected: (v) => setState(() {
                if (v) {
                  _selectedIds.add(f.filialId);
                } else {
                  _selectedIds.remove(f.filialId);
                }
              }),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _dateTile({
    required String label,
    required DateTime value,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatHuman(value),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(CupertinoIcons.calendar, color: Colors.grey.shade600),
            ],
          ),
        ),
      ),
    );
  }

  Widget _periodSection() {
    final today = _dateOnly(DateTime.now());
    final presets = <String, (DateTime, DateTime)>{
      '7 дней': (today.subtract(const Duration(days: 6)), today),
      'Эта неделя': (
        today.subtract(Duration(days: today.weekday - 1)),
        today,
      ),
      'Прошлая неделя': (
        today.subtract(Duration(days: today.weekday + 6)),
        today.subtract(Duration(days: today.weekday)),
      ),
      'Этот месяц': (DateTime(today.year, today.month, 1), today),
      'Прошлый месяц': (
        DateTime(today.year, today.month - 1, 1),
        DateTime(today.year, today.month, 0),
      ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle('ПЕРИОД'),
        Row(
          children: [
            _dateTile(
              label: 'С',
              value: _start,
              onTap: () => _pickDate(isStart: true),
            ),
            const SizedBox(width: 10),
            _dateTile(
              label: 'По',
              value: _end,
              onTap: () => _pickDate(isStart: false),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: presets.entries.map((e) {
            final (s, en) = e.value;
            final active = s == _start && en == _end;
            return ChoiceChip(
              label: Text(e.key),
              selected: active,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              onSelected: (_) => _applyPreset(s, en),
            );
          }).toList(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final buttonLabel = isLoading
        ? (_progress != null ? 'Загрузка $_progress...' : 'Загрузка...')
        : _isDesktop
        ? 'Скачать'
        : 'Скачать и отправить';

    return Scaffold(
      appBar: AppBar(title: const Text('Excel отчёт'), centerTitle: true),
      body: isLoadingFilials
          ? const Center(child: CupertinoActivityIndicator())
          : errorMessage != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    errorMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _fetchFilials,
                    child: const Text('Повторить'),
                  ),
                ],
              ),
            )
          : _availableFilials == null || _availableFilials!.isEmpty
          ? const Center(
              child: Text(
                'У вас нет филиалов, доступных для просмотра',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _filialSection(),
                      const SizedBox(height: 24),
                      _periodSection(),
                    ],
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        key: _buttonKey,
                        onPressed: isLoading || _selectedIds.isEmpty
                            ? null
                            : _downloadAndShareExcel,
                        icon: isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Icon(
                                _isDesktop
                                    ? CupertinoIcons.arrow_down_doc
                                    : CupertinoIcons.share,
                              ),
                        label: Text(
                          buttonLabel,
                          style: const TextStyle(fontSize: 16),
                        ),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
