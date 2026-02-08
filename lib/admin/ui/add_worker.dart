// lib/admin/ui/add_worker_page.dart
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mone_task_app/admin/model/filial_model.dart';
import 'package:mone_task_app/admin/ui/add_admin_task.dart';
import 'package:mone_task_app/admin/ui/user_servise.dart';
import 'package:mone_task_app/checker/service/task_worker_service.dart';

class AddWorkerPage extends StatefulWidget {
  const AddWorkerPage({super.key});

  @override
  State<AddWorkerPage> createState() => _AddWorkerPageState();
}

class _AddWorkerPageState extends State<AddWorkerPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _loginController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  String _selectedRole = 'worker';
  final List<int> _selectedFilialIds = [];
  final List<String> _selectedCategories = [];
  bool _isLoading = false;
  bool _obscurePassword = true;

  final UserService _userService = UserService();

  List<FilialModel>? _filials;
  List<CategoryModel>? _categories;
  bool _isLoadingData = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final results = await Future.wait([
        AdminTaskService().fetchFilials(),
        AdminTaskService().fetchCategories(),
      ]);

      setState(() {
        _filials = results[0] as List<FilialModel>;
        _categories = results[1] as List<CategoryModel>;
        _isLoadingData = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingData = false;
      });
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _loginController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _saveUser() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Role bo'yicha validatsiya
    if ((_selectedRole == 'worker') && _selectedFilialIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Выберите хотя бы один филиал')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final success = await _userService.createUser(
      username: _usernameController.text.trim(),
      login: _loginController.text.trim(),
      password: _passwordController.text.trim(),
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
        ).showSnackBar(const SnackBar(content: Text('Пользователь добавил')));
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
        title: const Text('Добавить пользователя'),
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
      body: _isLoadingData
          ? const Center(child: CircularProgressIndicator.adaptive())
          : Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Username
                    TextFormField(
                      controller: _usernameController,
                      decoration: const InputDecoration(
                        labelText: 'Имя *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Введите имя';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Login
                    TextFormField(
                      controller: _loginController,
                      decoration: const InputDecoration(
                        labelText: 'Авторизоваться *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.account_circle),
                        hintText: 'Номер телефона или логин',
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Введите свой логин';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Password
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'Пароль *',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.lock),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Введите пароль';
                        }
                        if (value.length < 6) {
                          return 'Пароль должен состоять как минимум из 6 символов.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Role
                    const Text(
                      'Роль *',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: _selectedRole,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.badge),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'super_admin',
                          child: Text('Super Admin'),
                        ),
                        DropdownMenuItem(
                          value: 'checker',
                          child: Text('Checker'),
                        ),
                        DropdownMenuItem(
                          value: 'worker',
                          child: Text('Worker'),
                        ),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _selectedRole = value!;
                          // Role o'zgarganda filiallar va kategoriyalarni tozalash
                          if (_selectedRole != 'worker') {
                            _selectedFilialIds.clear();
                            _selectedCategories.clear();
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 16),

                    // Filiallar (faqat worker uchun)
                    if (_selectedRole == 'worker' && _filials != null) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            'Филиаллар *',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (_selectedFilialIds.isEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.red.shade100,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'Выбирать',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.red,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (_filials!.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Text(
                            'Ветви не найдены',
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      else
                        ..._filials!.map((filial) {
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
                                        _selectedFilialIds.remove(
                                          filial.filialId,
                                        );
                                      }
                                    });
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
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
                                      _selectedFilialIds.remove(
                                        filial.filialId,
                                      );
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
                    if (_selectedRole == 'worker' && _categories != null) ...[
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
                      ..._categories!.map((category) {
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
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
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
                    ],
                  ],
                ),
              ),
            ),
    );
  }
}
