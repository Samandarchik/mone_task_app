// lib/admin/ui/edit_user_page.dart
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mone_task_app/admin/model/filial_model.dart';
import 'package:mone_task_app/admin/ui/add_admin_task.dart';
import 'package:mone_task_app/admin/ui/user_servise.dart';
import 'package:mone_task_app/checker/service/task_worker_service.dart';
import 'package:mone_task_app/worker/model/user_model.dart';

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
  late Future<List<FilialModel>> filial;
  late Future<List<CategoryModel>> categories;

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController(text: widget.user.username);
    _selectedRole = widget.user.role;
    _selectedFilialIds = widget.user.filialIds ?? [];
    _selectedCategories = widget.user.categories ?? [];
    filial = AdminTaskService().fetchFilials();
    categories = AdminTaskService().fetchCategories();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _saveUser() async {
    if (_usernameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Имя не указано')));
      return;
    }

    if (_selectedRole == 'worker' && _selectedFilialIds.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Ветвь не выбрана')));
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final success = await _userService.updateUser(
      userId: widget.user.userId,
      username: _usernameController.text.trim(),
      role: _selectedRole,
      filialIds: _selectedFilialIds.isNotEmpty ? _selectedFilialIds : null,
      categories: _selectedCategories.isNotEmpty ? _selectedCategories : null,
    );

    setState(() {
      _isLoading = false;
    });

    if (success) {
      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Сохранено')));
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Произошла ошибка.')));
      }
    }
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
                padding: EdgeInsets.all(16.0),
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
        future: Future.wait([filial, categories]),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator.adaptive());
          }

          if (!snapshot.hasData) {
            return const Center(child: Text('Ma\'lumot yuklanmadi'));
          }

          final filials = snapshot.data![0] as List<FilialModel>;
          final categoryList = snapshot.data![1] as List<CategoryModel>;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Username
                TextField(
                  controller: _usernameController,
                  decoration: const InputDecoration(
                    labelText: 'Имя',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),

                // Role
                const Text(
                  'Роль',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _selectedRole,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'super_admin',
                      child: Text('Супер администратор'),
                    ),
                    DropdownMenuItem(
                      value: 'checker',
                      child: Text('Инспектор'),
                    ),
                    DropdownMenuItem(value: 'worker', child: Text('Рабочий')),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedRole = value!;
                    });
                  },
                ),
                const SizedBox(height: 16),

                // Filiallar (faqat worker uchun)
                if (_selectedRole == 'worker') ...[
                  Center(
                    child: const Text(
                      'Филиал',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...filials.map((filial) {
                    final isSelected = _selectedFilialIds.contains(
                      filial.filialId,
                    );

                    return Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                if (!isSelected) {
                                  _selectedFilialIds.add(filial.filialId);
                                } else {
                                  _selectedFilialIds.remove(filial.filialId);
                                }
                              });
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                filial.name,
                                style: const TextStyle(fontSize: 16),
                              ),
                            ),
                          ),
                        ),
                        CupertinoSwitch(
                          value: isSelected,
                          onChanged: (value) {
                            setState(() {
                              if (value == true) {
                                _selectedFilialIds.add(filial.filialId);
                              } else {
                                _selectedFilialIds.remove(filial.filialId);
                              }
                            });
                          },
                        ),
                      ],
                    );
                  }),
                  const SizedBox(height: 16),
                ],

                // Categories (faqat worker uchun)
                if (_selectedRole == 'worker') ...[
                  Center(
                    child: const Text(
                      'Категории',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...categoryList.map((category) {
                    final isSelected = _selectedCategories.contains(
                      category.name,
                    );

                    return Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                if (!isSelected) {
                                  _selectedCategories.add(category.name);
                                } else {
                                  _selectedCategories.remove(category.name);
                                }
                              });
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                category.name,
                                style: const TextStyle(fontSize: 16),
                              ),
                            ),
                          ),
                        ),
                        CupertinoSwitch(
                          value: isSelected,
                          onChanged: (value) {
                            setState(() {
                              if (value == true) {
                                _selectedCategories.add(category.name);
                              } else {
                                _selectedCategories.remove(category.name);
                              }
                            });
                          },
                        ),
                      ],
                    );
                  }),
                  const SizedBox(height: 16),
                  ElevatedButton(onPressed: () {}, child: Text("Выпускать")),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
