import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mone_task_app/admin/model/category_model.dart';
import 'package:mone_task_app/admin/model/filial_model.dart';
import 'package:mone_task_app/admin/service/user_service.dart';
import 'package:mone_task_app/checker/service/task_worker_service.dart';
import 'package:mone_task_app/worker/model/user_model.dart';
import 'package:mone_task_app/worker/service/log_out.dart';

class EditUserPage extends StatefulWidget {
  final List<FilialModel> category;
  final UserModel user;

  const EditUserPage({super.key, required this.user, required this.category});

  @override
  State<EditUserPage> createState() => _EditUserPageState();
}

class _EditUserPageState extends State<EditUserPage> {
  late TextEditingController _usernameController;
  late String _selectedRole;
  late List<int> _selectedFilialIds;
  late List<String> _selectedCategories;

  final UserService _userService = UserService();
  late Future<List<dynamic>> _combinedFuture;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController(text: widget.user.username);
    _selectedRole = widget.user.role;
    _selectedFilialIds = widget.user.filialIds ?? [];
    _selectedCategories = widget.user.categories ?? [];
    _combinedFuture = Future.wait([
      TaskViewService().fetchFilials(),
      TaskViewService().fetchCategories(),
    ]);
  }

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _saveUser() async {
    if (_usernameController.text.trim().isEmpty) {
      _showError('Имя не указано');
      return;
    }
    if (_selectedRole == 'worker' && _selectedFilialIds.isEmpty) {
      _showError('Филиал не выбран');
      return;
    }

    setState(() => _isLoading = true);

    final success = await _userService.updateUser(
      userId: widget.user.userId,
      username: _usernameController.text.trim(),
      role: _selectedRole,
      filialIds: _selectedFilialIds.isNotEmpty ? _selectedFilialIds : null,
      categories: _selectedCategories.isNotEmpty ? _selectedCategories : null,
    );

    setState(() => _isLoading = false);

    if (success && mounted) {
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Сохранено')),
      );
    } else if (mounted) {
      _showError('Произошла ошибка');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Редактировать'),
        actions: [
          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                ),
              ),
            )
          else
            IconButton(onPressed: _saveUser, icon: const Icon(Icons.check)),
        ],
      ),
      body: FutureBuilder<List<dynamic>>(
        future: _combinedFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator.adaptive());
          }
          if (!snapshot.hasData) {
            return const Center(child: Text('Данные не загружены'));
          }

          final filials = snapshot.data![0] as List<FilialModel>;
          final categoryList = snapshot.data![1] as List<CategoryModel>;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _usernameController,
                  decoration: const InputDecoration(
                    labelText: 'Имя',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),

                if (_selectedRole == 'worker') ...[
                  _buildSectionTitle('Филиал'),
                  const SizedBox(height: 8),
                  ...filials.map((filial) => _buildSwitchRow(
                        title: filial.name,
                        value: _selectedFilialIds.contains(filial.filialId),
                        onChanged: (value) {
                          setState(() {
                            if (value) {
                              _selectedFilialIds.add(filial.filialId);
                            } else {
                              _selectedFilialIds.remove(filial.filialId);
                            }
                          });
                        },
                      )),
                  const SizedBox(height: 16),

                  _buildSectionTitle('Категории'),
                  const SizedBox(height: 8),
                  ...categoryList.map((category) => _buildSwitchRow(
                        title: category.name,
                        value: _selectedCategories.contains(category.name),
                        onChanged: (value) {
                          setState(() {
                            if (value) {
                              _selectedCategories.add(category.name);
                            } else {
                              _selectedCategories.remove(category.name);
                            }
                          });
                        },
                      )),
                  const SizedBox(height: 16),
                ],

                ElevatedButton(
                  onPressed: () async {
                    await LogOutService().logOutUser(widget.user.userId);
                  },
                  child: const Text("Выйти из аккаунта"),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Center(
      child: Text(
        title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildSwitchRow({
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () => onChanged(!value),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(title, style: const TextStyle(fontSize: 16)),
            ),
          ),
        ),
        CupertinoSwitch(value: value, onChanged: onChanged),
      ],
    );
  }
}
