import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mone_task_app/admin/model/all_task_model.dart';
import 'package:mone_task_app/admin/model/category_model.dart';
import 'package:mone_task_app/admin/model/edit_task_ui_model.dart';
import 'package:mone_task_app/admin/service/task_worker_service.dart';
import 'package:mone_task_app/admin/ui/widgets/category_manager_dialog.dart';
import 'package:mone_task_app/utils/get_color.dart';

const _blue = Color(0xFF2563EB);
const _grey = Color(0xFF6B7280);
const _border = Color(0xFFE5E7EB);

/// Shablon vazifa kartasi — hamma narsa shu yerning o'zida tahrirlanadi
/// (matn, tur, kunlar, kategoriya, vaqt, videolar soni), alohida sahifa yo'q.
/// Har bir o'zgarish darhol serverga saqlanadi.
class TemplateTaskCard extends StatefulWidget {
  final TemplateTaskModel template;
  final List<CategoryModel> categories;
  final ValueChanged<TemplateTaskModel> onSaved;
  final VoidCallback onDeleted;
  final VoidCallback onCategoriesChanged;

  /// Kategoriya nomi o'zgardi — shablonlarni serverdan qayta olish kerak
  final VoidCallback? onTemplatesStale;
  final Color Function(int type) typeColor;

  /// Ro'yxatdagi tartib raqami (1 dan)
  final int number;

  /// Bosh sahifadan tahrirlash uchun ochilgan vazifa — ajratib ko'rsatiladi
  final bool highlighted;

  const TemplateTaskCard({
    super.key,
    required this.template,
    required this.categories,
    required this.onSaved,
    required this.onDeleted,
    required this.onCategoriesChanged,
    this.onTemplatesStale,
    required this.typeColor,
    required this.number,
    this.highlighted = false,
  });

  @override
  State<TemplateTaskCard> createState() => _TemplateTaskCardState();
}

class _TemplateTaskCardState extends State<TemplateTaskCard> {
  final TemplateService _service = TemplateService();
  final TextEditingController _textCtrl = TextEditingController();
  final FocusNode _textFocus = FocusNode();

  late String _task;
  late int _type;
  late List<int> _days;
  late String _category;
  int? _hour;
  int? _minute;
  late int _videoCount;

  bool _editingText = false;
  bool _showDays = false;
  bool _showTime = false;
  bool _saving = false;

  /// Saqlanmagan o'zgarish bor — «Отмена / Сохранить» ko'rinadi
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load(widget.template);
    _textFocus.addListener(() {
      if (!_textFocus.hasFocus && _editingText) _finishTextEdit();
    });
  }

  @override
  void didUpdateWidget(covariant TemplateTaskCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.template != widget.template && !_saving && !_changed) {
      _load(widget.template);
    }
  }

  void _load(TemplateTaskModel t) {
    _task = t.task;
    _type = t.type == 0 ? 1 : t.type;
    _days = List<int>.from(t.days ?? const []);
    _category = t.category;
    _videoCount = t.videoCount;
    _hour = null;
    _minute = null;
    final time = t.notificationTime;
    if (time != null && time.contains(':')) {
      final parts = time.split(':');
      _hour = int.tryParse(parts[0]);
      _minute = int.tryParse(parts[1]);
    }
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _textFocus.dispose();
    super.dispose();
  }

  bool get _needsDays => _type != 1 && _days.isEmpty;

  /// O'zgarish darhol saqlanmaydi — «Сохранить» bosilgandagina yuboriladi
  void _markChanged() {
    if (!_changed) setState(() => _changed = true);
  }

  /// «Отмена» — barcha o'zgarishlarni bekor qilish
  void _cancelChanges() {
    setState(() {
      _load(widget.template);
      _changed = false;
      _editingText = false;
      _showDays = false;
      _showTime = false;
    });
  }

  Future<void> _save() async {
    // Haftalik/oylik turda kun tanlanmaguncha saqlanmaydi
    if (_task.trim().isEmpty || _needsDays) return;

    final original = widget.template;
    final days = _type == 1 ? null : (List<int>.from(_days)..sort());
    final model = EditTaskUiModel(
      taskId: original.templateId,
      taskType: _type,
      filialsId: original.filialIds,
      task: _task,
      days: days,
      hour: _hour,
      minute: _minute,
      category: _category,
      // Eski "cheklanmagan" ko'p videoli task 1 qoldirilsa — shunday qoladi
      multiVideo:
          _videoCount > 1 ||
          (original.multiVideo && _videoCount == original.videoCount),
      videoCount: _videoCount,
    );

    setState(() => _saving = true);
    final ok = await _service.updateTaskStatus(model);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (ok) {
        _changed = false;
        _showDays = false;
        _showTime = false;
      }
    });

    if (!ok) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Не удалось сохранить')));
      return;
    }
    widget.onSaved(
      TemplateTaskModel(
        templateId: original.templateId,
        task: _task,
        type: _type,
        orderIndex: original.orderIndex,
        pinned: original.pinned,
        filialIds: original.filialIds,
        days: days,
        createdAt: original.createdAt,
        notificationTime: _hour == null ? null : _timeText,
        category: _category,
        multiVideo: model.multiVideo,
        videoCount: _videoCount,
      ),
    );
  }

  String get _timeText =>
      '${_hour.toString().padLeft(2, '0')}:${(_minute ?? 0).toString().padLeft(2, '0')}';

  // ---------- Matn ----------

  void _startTextEdit() {
    _textCtrl.text = _task;
    setState(() => _editingText = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _textFocus.requestFocus();
      _textCtrl.selection = TextSelection.collapsed(
        offset: _textCtrl.text.length,
      );
    });
  }

  void _finishTextEdit() {
    final text = _textCtrl.text.trim();
    setState(() => _editingText = false);
    if (text.isEmpty || text == _task) return;
    setState(() => _task = text);
    _markChanged();
  }

  // ---------- O'chirish ----------

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить задачу?'),
        content: Text(_task),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Нет'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    bool ok = false;
    try {
      ok = await _service.deleteTask(widget.template.templateId);
    } catch (_) {}
    if (!mounted) return;
    if (ok) {
      widget.onDeleted();
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Не удалось удалить')));
    }
  }

  // ---------- Kategoriya ----------

  Future<void> _addCategory() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Новая категория'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Название категории'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Добавить'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    await _service.addCategory(name);
    if (!mounted) return;
    setState(() => _category = name);
    widget.onCategoriesChanged();
    _markChanged();
  }

  Future<void> _manageCategories() async {
    final renamed = await showCategoryManager(context, widget.categories);
    if (renamed == null || !mounted) return;
    widget.onCategoriesChanged();
    final newName = renamed[_category];
    if (newName != null) setState(() => _category = newName);
    if (renamed.isNotEmpty) widget.onTemplatesStale?.call();
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: widget.highlighted ? 8 : 3,
      color: widget.typeColor(_type),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: widget.highlighted
            ? const BorderSide(color: Color(0xFF2563EB), width: 3)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 10),
            // Tur va uning kunlari — bitta blok: kunlar qaysi turga
            // tegishli ekani darhol ko'rinadi
            _buildTypeSegment(),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [_buildCategoryChip(), _buildTimeChip()],
            ),
            if (_showTime) ...[const SizedBox(height: 8), _buildTimePicker()],
            if (_changed) ...[const SizedBox(height: 10), _buildSaveBar()],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          constraints: const BoxConstraints(minWidth: 32),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '${widget.number}',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _editingText
              ? TextField(
                  controller: _textCtrl,
                  focusNode: _textFocus,
                  maxLines: null,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _finishTextEdit(),
                  style: const TextStyle(fontSize: 17, height: 1.3),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: _blue),
                    ),
                  ),
                )
              : GestureDetector(
                  onTap: _startTextEdit,
                  child: Text(
                    _task,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                      color: Color(0xFF111827),
                    ),
                  ),
                ),
        ),
        const SizedBox(width: 8),
        if (_saving)
          const Padding(
            padding: EdgeInsets.only(top: 4, right: 6),
            child: SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        _buildVideoCounter(),
        const SizedBox(width: 4),
        _iconButton(
          Icons.delete_outline,
          _delete,
          size: 24,
          color: Colors.red.shade300,
        ),
      ],
    );
  }

  Widget _buildVideoCounter() {
    return Tooltip(
      message: 'Количество видео',
      child: Container(
        height: 50,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(25),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _iconButton(
              Icons.remove,
              _videoCount > 1
                  ? () {
                      setState(() => _videoCount--);
                      _markChanged();
                    }
                  : null,
              size: 30,
              padding: 8,
            ),
            const Icon(Icons.videocam_outlined, size: 28, color: _blue),
            const SizedBox(width: 6),
            Text(
              '$_videoCount',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: _blue,
              ),
            ),
            _iconButton(
              Icons.add,
              _videoCount < 8
                  ? () {
                      setState(() => _videoCount++);
                      _markChanged();
                    }
                  : null,
              size: 30,
              padding: 8,
            ),
          ],
        ),
      ),
    );
  }

  /// Tur tanlovi. Haftalik/oylik turda tanlangan kunlar shu tugmaning
  /// o'zida yoziladi, bosilsa kunlar ro'yxati shu blok ichida ochiladi.
  Widget _buildTypeSegment() {
    const types = [
      (1, Icons.today_outlined, 'Каждый день'),
      (2, Icons.view_week_outlined, 'По неделям'),
      (3, Icons.calendar_month_outlined, 'По месяцам'),
    ];
    final open = _type != 1 && _showDays;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 2,
            runSpacing: 2,
            children: [
              for (final (id, icon, label) in types)
                _typeOption(id, icon, label),
            ],
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
              child: _type == 2 ? _buildWeekDays() : _buildMonthDays(),
            ),
        ],
      ),
    );
  }

  Widget _typeOption(int id, IconData icon, String label) {
    final selected = _type == id;
    final sorted = List<int>.from(_days)..sort();
    final needsDays = selected && id != 1;
    final noDays = needsDays && sorted.isEmpty;
    final daysLabel = !needsDays
        ? null
        : noDays
        ? 'выберите дни'
        : id == 2
        ? sorted.map(getWeekday).join(', ')
        : sorted.join(', ');
    final color = noDays ? Colors.red : (selected ? _blue : _grey);

    return GestureDetector(
      onTap: () {
        if (selected) {
          // Tanlangan turni qayta bosish — kunlarni ochish / yopish
          if (id != 1) setState(() => _showDays = !_showDays);
          return;
        }
        setState(() {
          _type = id;
          _days = [];
          _showDays = id != 1;
        });
        _markChanged();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          boxShadow: selected
              ? const [BoxShadow(color: Color(0x14000000), blurRadius: 3)]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: selected ? _blue : _grey,
              ),
            ),
            if (daysLabel != null) ...[
              Text(' · ', style: TextStyle(fontSize: 15, color: _grey)),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Text(
                  daysLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
              Icon(
                _showDays ? Icons.expand_less : Icons.expand_more,
                size: 18,
                color: color,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Saqlanmagan o'zgarishlar bo'lsa — «Отмена» va «Сохранить»
  Widget _buildSaveBar() {
    return Row(
      children: [
        if (_needsDays)
          const Expanded(
            child: Text(
              'Выберите дни, чтобы сохранить',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.red,
              ),
            ),
          )
        else
          const Spacer(),
        SizedBox(
          height: 36,
          child: OutlinedButton(
            onPressed: _saving ? null : _cancelChanges,
            style: OutlinedButton.styleFrom(
              foregroundColor: _grey,
              backgroundColor: Colors.white.withValues(alpha: 0.7),
              side: BorderSide.none,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Отмена',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          height: 36,
          child: FilledButton.icon(
            onPressed: _saving || _needsDays ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: _blue,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            icon: _saving
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check_rounded, size: 18),
            label: const Text(
              'Сохранить',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryChip() {
    return PopupMenuButton<int>(
      tooltip: 'Категория',
      position: PopupMenuPosition.under,
      constraints: const BoxConstraints(minWidth: 160, maxHeight: 320),
      onSelected: (id) {
        if (id == -1) {
          _addCategory();
          return;
        }
        if (id == -2) {
          _manageCategories();
          return;
        }
        final name = widget.categories.firstWhere((c) => c.id == id).name;
        if (name == _category) return;
        setState(() => _category = name);
        _markChanged();
      },
      itemBuilder: (_) => [
        for (final c in widget.categories)
          PopupMenuItem<int>(
            value: c.id,
            height: 40,
            child: Row(
              children: [
                Expanded(
                  child: Text(c.name, style: const TextStyle(fontSize: 15)),
                ),
                if (c.name == _category)
                  const Icon(Icons.check, size: 15, color: _blue),
              ],
            ),
          ),
        const PopupMenuDivider(height: 6),
        const PopupMenuItem<int>(
          value: -1,
          height: 40,
          child: Row(
            children: [
              Icon(Icons.add, size: 15, color: _blue),
              SizedBox(width: 6),
              Text('Новая', style: TextStyle(fontSize: 15, color: _blue)),
            ],
          ),
        ),
        const PopupMenuItem<int>(
          value: -2,
          height: 40,
          child: Row(
            children: [
              Icon(Icons.tune, size: 15, color: _grey),
              SizedBox(width: 6),
              Text('Настроить', style: TextStyle(fontSize: 15, color: _grey)),
            ],
          ),
        ),
      ],
      child: _chip(
        icon: Icons.label_outline,
        label: _category.isEmpty ? 'Категория' : _category,
        color: _grey,
        trailing: Icons.expand_more,
      ),
    );
  }

  Widget _buildTimeChip() {
    return _chip(
      icon: Icons.schedule,
      label: _hour == null ? '—:—' : _timeText,
      color: _hour == null ? _grey : _blue,
      onTap: () => setState(() {
        _showTime = !_showTime;
        if (_showTime && _hour == null) {
          _hour = DateTime.now().hour;
          _minute = DateTime.now().minute;
          _markChanged();
        }
      }),
    );
  }

  Widget _buildWeekDays() {
    const names = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (var i = 0; i < 7; i++) _dayToggle(i + 1, names[i], width: 42),
      ],
    );
  }

  Widget _buildMonthDays() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 7 * 38),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [for (var d = 1; d <= 31; d++) _dayToggle(d, '$d')],
      ),
    );
  }

  Widget _dayToggle(int value, String label, {double width = 34}) {
    final selected = _days.contains(value);
    return GestureDetector(
      onTap: () {
        setState(() => selected ? _days.remove(value) : _days.add(value));
        _markChanged();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: width,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          // Blok foni oq — tanlanmagan kunlar och kulrang
          color: selected ? _blue : const Color(0xFFF1F3F6),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : _grey,
          ),
        ),
      ),
    );
  }

  Widget _buildTimePicker() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 190,
          height: 120,
          decoration: BoxDecoration(
            border: Border.all(color: _border),
            borderRadius: BorderRadius.circular(10),
          ),
          child: CupertinoDatePicker(
            mode: CupertinoDatePickerMode.time,
            use24hFormat: true,
            itemExtent: 32,
            initialDateTime: DateTime(2026, 1, 1, _hour ?? 0, _minute ?? 0),
            onDateTimeChanged: (value) {
              setState(() {
                _hour = value.hour;
                _minute = value.minute;
              });
              _markChanged();
            },
          ),
        ),
        const SizedBox(width: 8),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _textButton('Готово', _blue, () {
              setState(() => _showTime = false);
            }),
            _textButton('Убрать', Colors.red, () {
              setState(() {
                _hour = null;
                _minute = null;
                _showTime = false;
              });
              _markChanged();
            }),
          ],
        ),
      ],
    );
  }

  // ---------- Kichik yordamchilar ----------

  Widget _chip({
    required IconData icon,
    required String label,
    required Color color,
    IconData? trailing,
    VoidCallback? onTap,
  }) {
    final body = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ),
          if (trailing != null) Icon(trailing, size: 18, color: color),
        ],
      ),
    );
    if (onTap == null) return body;
    return GestureDetector(onTap: onTap, child: body);
  }

  Widget _iconButton(
    IconData icon,
    VoidCallback? onTap, {
    double size = 17,
    Color color = _blue,
    double padding = 4,
  }) {
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.all(padding),
        child: Icon(
          icon,
          size: size,
          color: onTap == null ? const Color(0xFFD1D5DB) : color,
        ),
      ),
    );
  }

  Widget _textButton(String label, Color color, VoidCallback onTap) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: color,
        minimumSize: const Size(0, 30),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      child: Text(label),
    );
  }
}
