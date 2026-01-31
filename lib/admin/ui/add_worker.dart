// lib/admin/ui/add_worker_page.dart
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mone_task_app/admin/model/filial_model.dart';
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
  final TextEditingController _categoryController = TextEditingController();

  String _selectedRole = 'worker';
  final List<int> _selectedFilialIds = [];
  final List<String> _selectedCategories = [];
  bool _isLoading = false;
  bool _obscurePassword = true;

  final UserService _userService = UserService();
  late Future<List<FilialModel>> _categoriesFuture;

  @override
  void initState() {
    super.initState();
    _categoriesFuture = AdminTaskService().fetchCategories();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _loginController.dispose();
    _passwordController.dispose();
    _categoryController.dispose();
    super.dispose();
  }

  Future<void> _saveUser() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Role bo'yicha validatsiya
    if ((_selectedRole == 'worker') && _selectedFilialIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kamida bitta filial tanlang')),
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Foydalanuvchi qo\'shildi')),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Xatolik yuz berdi')));
      }
    }
  }

  void _addCategory() {
    final category = _categoryController.text.trim();
    if (category.isNotEmpty && !_selectedCategories.contains(category)) {
      setState(() {
        _selectedCategories.add(category);
        _categoryController.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Foydalanuvchi qo\'shish'),
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
      body: FutureBuilder<List<FilialModel>>(
        future: _categoriesFuture,
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
                  Text('Xatolik: ${snapshot.error}'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _categoriesFuture = AdminTaskService()
                            .fetchCategories();
                      });
                    },
                    child: const Text('Qayta urinish'),
                  ),
                ],
              ),
            );
          }

          final categories = snapshot.data ?? [];

          return Form(
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
                      labelText: 'Ism *',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.person),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Ism kiriting';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Login
                  TextFormField(
                    controller: _loginController,
                    decoration: const InputDecoration(
                      labelText: 'Login *',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.account_circle),
                      hintText: 'Telefon raqam yoki login',
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Login kiriting';
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
                      labelText: 'Parol *',
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
                        return 'Parol kiriting';
                      }
                      if (value.length < 6) {
                        return 'Parol kamida 6 ta belgidan iborat bo\'lishi kerak';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Role
                  const Text(
                    'Rol *',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
                      DropdownMenuItem(value: 'worker', child: Text('Worker')),
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

                  // Filiallar (faqat worker va checker uchun)
                  if (_selectedRole == 'worker') ...[
                    Row(
                      children: [
                        const Text(
                          'Filiallar *',
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
                              'Tanlang',
                              style: TextStyle(fontSize: 12, color: Colors.red),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (categories.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Text(
                          'Filiallar topilmadi',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    else
                      ...categories.map((category) {
                        final isSelected = _selectedFilialIds.contains(
                          category.filialId,
                        );
                        return Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    if (!isSelected) {
                                      _selectedFilialIds.add(category.filialId);
                                    } else {
                                      _selectedFilialIds.remove(
                                        category.filialId,
                                      );
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
                                    _selectedFilialIds.add(category.filialId);
                                  } else {
                                    _selectedFilialIds.remove(
                                      category.filialId,
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
                  if (_selectedRole == 'worker') ...[
                    const Text(
                      'Kategoriyalar',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _categoryController,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              hintText: 'Shef Povar, Ofitsiant...',
                              prefixIcon: Icon(Icons.category),
                            ),
                            onSubmitted: (_) => _addCategory(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          onPressed: _addCategory,
                          icon: const Icon(Icons.add),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_selectedCategories.isNotEmpty)
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _selectedCategories.map((category) {
                          return Chip(
                            label: Text(category),
                            deleteIcon: const Icon(Icons.close, size: 18),
                            onDeleted: () {
                              setState(() {
                                _selectedCategories.remove(category);
                              });
                            },
                          );
                        }).toList(),
                      ),
                    const SizedBox(height: 16),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
