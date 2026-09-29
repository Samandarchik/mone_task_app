import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mone_task_app/admin/model/edit_task_ui_model.dart';
import 'package:mone_task_app/admin/service/task_worker_service.dart';
import 'package:mone_task_app/admin/ui/widgets/category_selector.dart';
import 'package:mone_task_app/admin/ui/widgets/task_type_selector.dart';
import 'package:mone_task_app/checker/model/checker_check_task_model.dart';
import 'package:mone_task_app/core/l10n/app_script.dart';
import 'package:mone_task_app/core/theme/app_theme.dart';
import 'package:mone_task_app/core/widgets/app_widgets.dart';

class EditTaskUi extends StatefulWidget {
  final TaskModel task;
  const EditTaskUi({super.key, required this.task});

  @override
  State<EditTaskUi> createState() => _EditTaskUiState();
}

class _EditTaskUiState extends State<EditTaskUi> {
  final TemplateService _taskService = TemplateService();
  late TextEditingController _controller;
  final GlobalKey<CategorySelectorState> _categoryKey = GlobalKey();

  int? _selectedType;
  List<int> _selectedFilials = [];
  List<int> _selectedWeekDays = [];
  List<int> _selectedDays = [];
  int? _selectedCategoryId;
  int? _selectedHour;
  int? _selectedMinute;
  bool _showTimePicker = false;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    // Tahrirlash uchun serverdagi xom matn qo'yiladi (trData qilinmaydi).
    _controller = TextEditingController(text: widget.task.task);
    _selectedType = widget.task.type == 0 ? 1 : widget.task.type;
    _selectedFilials = [widget.task.filialId];
    _selectedDays = List<int>.from(widget.task.days ?? []);
    _selectedWeekDays = List<int>.from(widget.task.days ?? []);

    final time = widget.task.notificationTime;
    if (time != null && time != "null:null" && time.contains(':')) {
      final parts = time.split(':');
      _selectedHour = int.tryParse(parts[0]);
      _selectedMinute = int.tryParse(parts[1]);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initCategorySelection();
    });
  }

  void _initCategorySelection() {
    final state = _categoryKey.currentState;
    if (state == null) return;

    void trySelect() {
      if (!mounted) return;
      if (state.isLoading) {
        Future.delayed(Duration(milliseconds: 200), trySelect);
        return;
      }
      final taskCategory = widget.task.category;
      if (taskCategory.isNotEmpty) {
        final id = state.findCategoryIdByName(taskCategory);
        if (id != null) {
          setState(() => _selectedCategoryId = id);
        }
      }
    }

    trySelect();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submitTask() async {
    if (_controller.text.trim().isEmpty) {
      _showError(tr('Vazifa matnini kiriting'));
      return;
    }
    if (_selectedType == 2 && _selectedWeekDays.isEmpty) {
      _showError(tr('Hafta kunlarini tanlang'));
      return;
    }
    if (_selectedType == 3 && _selectedDays.isEmpty) {
      _showError(tr('Oyning kunlarini tanlang'));
      return;
    }
    if (_selectedCategoryId == null) {
      _showError(tr('Kategoriyani tanlang'));
      return;
    }

    final categoryName = _categoryKey.currentState?.getCategoryName(
      _selectedCategoryId!,
    );
    if (categoryName == null) {
      _showError(tr('Kategoriya topilmadi'));
      return;
    }

    setState(() => _isSubmitting = true);

    final model = EditTaskUiModel(
      taskId: widget.task.taskId,
      taskType: _selectedType ?? 1,
      filialsId: _selectedFilials,
      task: _controller.text,
      days: _selectedType == 1
          ? null
          : _selectedType == 2
          ? _selectedWeekDays
          : _selectedDays,
      hour: _selectedHour,
      minute: _selectedMinute,
      category: categoryName,
    );

    try {
      final ok = await _taskService.updateTaskStatus(model);
      if (!mounted) return;
      if (ok) {
        showAppSnack(context, tr('Saqlandi'), type: SnackType.success);
        Navigator.pop(context, true);
      } else {
        setState(() => _isSubmitting = false);
        _showError(tr('Saqlab boʻlmadi. Qayta urinib koʻring'));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        _showError('${tr('Xatolik')}: $e');
      }
    }
  }

  void _showError(String message) {
    showAppSnack(context, message, type: SnackType.error);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Vazifani tahrirlash'))),
      // SingleChildScrollView — CategorySelector (GlobalKey orqali o'qiladi)
      // pastga aylantirilganda ham o'chib ketmaydi.
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 720),
          child: SingleChildScrollView(
            padding: EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _FormCard(
                  children: [
                    TextField(
                      controller: _controller,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        labelText: tr('Vazifa'),
                        hintText: tr('Nima qilish kerakligini yozing'),
                        alignLabelWithHint: true,
                      ),
                      minLines: 2,
                      maxLines: 4,
                    ),
                    SizedBox(height: AppSpacing.lg),
                    CategorySelector(
                      key: _categoryKey,
                      selectedCategoryId: _selectedCategoryId,
                      onChanged: (id) =>
                          setState(() => _selectedCategoryId = id),
                    ),
                  ],
                ),
                SizedBox(height: AppSpacing.md),
                _FormCard(
                  children: [
                    TaskTypeSelector(
                      selectedType: _selectedType ?? 1,
                      onTypeChanged: (value) => setState(() {
                        _selectedType = value;
                        _selectedWeekDays = [];
                        _selectedDays = [];
                      }),
                      selectedWeekDays: _selectedWeekDays,
                      onWeekDaysChanged: (days) =>
                          setState(() => _selectedWeekDays = days),
                      selectedDays: _selectedDays,
                      onDaysChanged: (days) =>
                          setState(() => _selectedDays = days),
                    ),
                  ],
                ),
                SizedBox(height: AppSpacing.md),
                _FormCard(children: [_buildTimeSelector()]),
                SizedBox(height: AppSpacing.xl),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 720),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isSubmitting ? null : _submitTask,
                  child: _isSubmitting
                      ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.white,
                          ),
                        )
                      : Text(tr('Saqlash')),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTimeSelector() {
    final hasTime = _selectedHour != null;
    final timeText = hasTime
        ? "${_selectedHour.toString().padLeft(2, '0')}:${(_selectedMinute ?? 0).toString().padLeft(2, '0')}"
        : tr('Belgilanmagan');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr('Eslatma vaqti'),
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        SizedBox(height: 2),
        Text(
          tr('Ixtiyoriy — xodimga shu vaqtda eslatiladi'),
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        SizedBox(height: AppSpacing.sm),
        Material(
          color: hasTime ? AppColors.primarySoft : AppColors.surfaceMuted,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.mdAll,
            side: BorderSide(
              color: hasTime ? AppColors.primary : AppColors.border,
            ),
          ),
          child: InkWell(
            borderRadius: AppRadius.mdAll,
            onTap: () {
              setState(() {
                _showTimePicker = !_showTimePicker;
                if (_showTimePicker && _selectedHour == null) {
                  _selectedHour = DateTime.now().hour;
                  _selectedMinute = DateTime.now().minute;
                }
              });
            },
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: 52),
              child: Padding(
                padding: EdgeInsets.only(left: 14, right: 4),
                child: Row(
                  children: [
                    Icon(
                      Icons.schedule_rounded,
                      color: hasTime
                          ? AppColors.primary
                          : AppColors.textSecondary,
                    ),
                    SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        timeText,
                        style: TextStyle(
                          fontSize: hasTime ? 18 : 15,
                          fontWeight: FontWeight.w600,
                          color: hasTime
                              ? AppColors.primary
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                    if (hasTime)
                      IconButton(
                        tooltip: tr('Vaqtni olib tashlash'),
                        icon: Icon(
                          Icons.close_rounded,
                          color: AppColors.textSecondary,
                        ),
                        onPressed: () {
                          setState(() {
                            _selectedHour = null;
                            _selectedMinute = null;
                            _showTimePicker = false;
                          });
                        },
                      )
                    else
                      Padding(
                        padding: EdgeInsets.all(12),
                        child: Icon(
                          Icons.expand_more_rounded,
                          color: AppColors.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (_showTimePicker) ...[
          SizedBox(height: AppSpacing.md),
          Container(
            height: 180,
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border),
              borderRadius: AppRadius.mdAll,
            ),
            child: CupertinoDatePicker(
              mode: CupertinoDatePickerMode.time,
              use24hFormat: true,
              initialDateTime: DateTime(
                2026,
                1,
                1,
                _selectedHour ?? DateTime.now().hour,
                _selectedMinute ?? DateTime.now().minute,
              ),
              onDateTimeChanged: (value) {
                setState(() {
                  _selectedHour = value.hour;
                  _selectedMinute = value.minute;
                });
              },
            ),
          ),
        ],
      ],
    );
  }
}

class _FormCard extends StatelessWidget {
  const _FormCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}
