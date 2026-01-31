// lib/admin/ui/users_page.dart
import 'package:flutter/material.dart';
import 'package:mone_task_app/admin/model/filial_model.dart';
import 'package:mone_task_app/admin/ui/add_worker.dart';
import 'package:mone_task_app/admin/ui/dialog.dart';
import 'package:mone_task_app/admin/ui/edit.dart';
import 'package:mone_task_app/admin/ui/user_servise.dart';
import 'package:mone_task_app/core/context_extension.dart';
import 'package:mone_task_app/worker/model/user_model.dart';

class UsersPage extends StatefulWidget {
  final List<FilialModel> filialModel;
  const UsersPage({super.key, required this.filialModel});

  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  late Future<List<UserModel>> usersFuture;
  final UserService _userService = UserService();

  @override
  void initState() {
    super.initState();
    usersFuture = _userService.fetchUsers();
  }

  void _refreshUsers() {
    setState(() {
      usersFuture = _userService.fetchUsers();
    });
  }

  String _getRoleText(String role) {
    switch (role) {
      case 'super_admin':
        return 'Super Admin';
      case 'checker':
        return 'Checker';
      case 'worker':
        return 'Worker';
      default:
        return role;
    }
  }

  Color _getRoleColor(String role) {
    switch (role) {
      case 'super_admin':
        return Colors.purple.shade100;
      case 'checker':
        return Colors.orange.shade100;
      case 'worker':
        return Colors.green.shade100;
      default:
        return Colors.grey.shade100;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Foydalanuvchilar'),
        actions: [
          IconButton(onPressed: _refreshUsers, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: FutureBuilder<List<UserModel>>(
        future: usersFuture,
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
                    onPressed: _refreshUsers,
                    child: const Text('Qayta urinish'),
                  ),
                ],
              ),
            );
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text("Foydalanuvchilar topilmadi"));
          }

          final users = snapshot.data!;

          return RefreshIndicator(
            onRefresh: () async {
              _refreshUsers();
            },
            child: ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: users.length,
              itemBuilder: (context, index) {
                final user = users[index];
                return UserListItem(
                  user: user,
                  onDelete: () async {
                    final isDelete = await NativeDialog.showDeleteDialog();
                    if (isDelete) {
                      final success = await _userService.deleteUser(
                        user.userId,
                      );
                      if (success) {
                        _refreshUsers();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Foydalanuvchi o\'chirildi'),
                            ),
                          );
                        }
                      }
                    }
                  },
                  onEdit: () {
                    context.push(
                      EditUserPage(user: user, category: widget.filialModel),
                    );
                    _refreshUsers();
                  },
                  getRoleText: _getRoleText,
                  getRoleColor: _getRoleColor,
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const AddWorkerPage()),
          ).then((result) {
            if (result == true) {
              _refreshUsers();
            }
          });
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

class UserListItem extends StatelessWidget {
  final UserModel user;
  final VoidCallback onDelete;
  final VoidCallback onEdit;
  final String Function(String) getRoleText;
  final Color Function(String) getRoleColor;

  const UserListItem({
    super.key,
    required this.user,
    required this.onDelete,
    required this.onEdit,
    required this.getRoleText,
    required this.getRoleColor,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      color: getRoleColor(user.role),
      child: InkWell(
        onTap: onEdit,
        onLongPress: onDelete,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.username,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Login: ${user.login}',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.black12),
                    ),
                    child: Text(
                      getRoleText(user.role),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              if (user.categories != null && user.categories!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: user.categories!.map((category) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        category,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.blue,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
              if (user.isLogin) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'Online',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
