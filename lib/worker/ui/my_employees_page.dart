import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mone_task_app/worker/service/employee_service.dart';

String _errorText(Object e) => '$e'.replaceFirst('Exception: ', '');

void _showError(BuildContext context, Object e) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(_errorText(e)), backgroundColor: Colors.red),
  );
}

/// «Мои сотрудники» — worker o'z yordamchilarini qo'shadi, parolini
/// o'zgartiradi va o'chiradi. Vazifa biriktirish task kartasidan qilinadi.
class MyEmployeesPage extends StatefulWidget {
  const MyEmployeesPage({super.key});

  @override
  State<MyEmployeesPage> createState() => _MyEmployeesPageState();
}

class _MyEmployeesPageState extends State<MyEmployeesPage> {
  final EmployeeService _service = EmployeeService();
  List<EmployeeModel> _employees = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await _service.fetchEmployees();
      if (mounted) setState(() => _employees = list);
    } catch (e) {
      if (mounted) _showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openForm([EmployeeModel? employee]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _EmployeeFormDialog(employee: employee),
    );
    if (saved == true) _load();
  }

  Future<void> _delete(EmployeeModel e) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить'),
        content: Text(
          '${e.username} больше не сможет войти, его задачи вернутся к вам.',
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
    try {
      await _service.deleteEmployee(e.userId);
      _load();
    } catch (err) {
      if (mounted) _showError(context, err);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Мои сотрудники')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Добавить'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator.adaptive())
          : RefreshIndicator(
              onRefresh: _load,
              child: _employees.isEmpty
                  ? ListView(
                      children: const [
                        SizedBox(height: 160),
                        Icon(
                          Icons.groups_2_outlined,
                          size: 56,
                          color: Color(0xFF9CA3AF),
                        ),
                        SizedBox(height: 12),
                        Center(
                          child: Text(
                            'Добавьте сотрудника и поручите ему\nсвои задачи',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Color(0xFF6B7280)),
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 96),
                      itemCount: _employees.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _employeeCard(_employees[i]),
                    ),
            ),
    );
  }

  Widget _employeeCard(EmployeeModel e) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEDEEF1)),
      ),
      child: ListTile(
        onTap: () => _openForm(e),
        leading: CircleAvatar(
          backgroundColor: const Color(0xFFEFF4FF),
          child: Text(
            e.username.isNotEmpty ? e.username[0].toUpperCase() : '?',
            style: const TextStyle(
              color: Color(0xFF2563EB),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        title: Text(
          e.username,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          'Логин: ${e.login} · Пароль: ${e.password}\n'
          'Задач поручено: ${e.templateIds.length}',
          style: const TextStyle(fontSize: 12.5, color: Color(0xFF6B7280)),
        ),
        isThreeLine: true,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Скопировать логин и пароль',
              icon: const Icon(Icons.copy_rounded, size: 20),
              onPressed: () {
                Clipboard.setData(
                  ClipboardData(
                    text: 'Логин: ${e.login}\nПароль: ${e.password}',
                  ),
                );
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Скопировано')));
              },
            ),
            IconButton(
              tooltip: 'Удалить',
              icon: const Icon(
                Icons.delete_outline_rounded,
                size: 20,
                color: Colors.red,
              ),
              onPressed: () => _delete(e),
            ),
          ],
        ),
      ),
    );
  }
}

/// Yangi sotrudnik qo'shish yoki mavjudini tahrirlash (login o'zgarmaydi).
class _EmployeeFormDialog extends StatefulWidget {
  final EmployeeModel? employee;
  const _EmployeeFormDialog({this.employee});

  @override
  State<_EmployeeFormDialog> createState() => _EmployeeFormDialogState();
}

class _EmployeeFormDialogState extends State<_EmployeeFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.employee?.username);
  late final _login = TextEditingController(text: widget.employee?.login);
  late final _password = TextEditingController(text: widget.employee?.password);
  bool _saving = false;

  bool get _isEdit => widget.employee != null;

  @override
  void dispose() {
    _name.dispose();
    _login.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final service = EmployeeService();
    try {
      if (_isEdit) {
        final e = widget.employee!;
        await service.updateEmployee(
          e.userId,
          username: _name.text.trim() == e.username ? null : _name.text.trim(),
          password: _password.text.trim() == e.password
              ? null
              : _password.text.trim(),
        );
      } else {
        await service.createEmployee(
          username: _name.text.trim(),
          login: _login.text.trim(),
          password: _password.text.trim(),
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _showError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEdit ? 'Сотрудник' : 'Новый сотрудник'),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Имя'),
              validator: (v) => (v ?? '').trim().isEmpty ? 'Введите имя' : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _login,
              enabled: !_isEdit,
              decoration: const InputDecoration(labelText: 'Логин'),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Введите логин' : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _password,
              decoration: const InputDecoration(
                labelText: 'Пароль',
                helperText: 'По нему сотрудник входит в приложение',
              ),
              validator: (v) =>
                  (v ?? '').trim().length < 4 ? 'Минимум 4 символа' : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_isEdit ? 'Сохранить' : 'Добавить'),
        ),
      ],
    );
  }
}

/// Vazifani sotrudniklarga biriktirish oynasi. O'zgarish saqlansa — true.
Future<bool> showDelegateSheet(
  BuildContext context, {
  required int templateId,
  required String taskTitle,
  required List<int> delegatedTo,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _DelegateSheet(
      templateId: templateId,
      taskTitle: taskTitle,
      initial: delegatedTo.toSet(),
    ),
  );
  return saved == true;
}

class _DelegateSheet extends StatefulWidget {
  final int templateId;
  final String taskTitle;
  final Set<int> initial;
  const _DelegateSheet({
    required this.templateId,
    required this.taskTitle,
    required this.initial,
  });

  @override
  State<_DelegateSheet> createState() => _DelegateSheetState();
}

class _DelegateSheetState extends State<_DelegateSheet> {
  final EmployeeService _service = EmployeeService();
  List<EmployeeModel>? _employees;
  late final Set<int> _selected = {...widget.initial};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await _service.fetchEmployees();
      if (mounted) setState(() => _employees = list);
    } catch (e) {
      if (mounted) {
        setState(() => _employees = []);
        _showError(context, e);
      }
    }
  }

  Future<void> _addEmployee() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MyEmployeesPage()),
    );
    _load();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _service.setDelegation(widget.templateId, _selected.toList());
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _showError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final employees = _employees;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Поручить сотруднику',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              widget.taskTitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFF6B7280)),
            ),
            const SizedBox(height: 8),
            if (employees == null)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator.adaptive()),
              )
            else if (employees.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('У вас пока нет сотрудников'),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.45,
                ),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final e in employees)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _selected.contains(e.userId),
                        title: Text(e.username),
                        subtitle: Text('Логин: ${e.login}'),
                        onChanged: (v) => setState(
                          () => v == true
                              ? _selected.add(e.userId)
                              : _selected.remove(e.userId),
                        ),
                      ),
                  ],
                ),
              ),
            TextButton.icon(
              onPressed: _addEmployee,
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Добавить сотрудника'),
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving || employees == null ? null : _save,
                child: const Text('Сохранить'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
