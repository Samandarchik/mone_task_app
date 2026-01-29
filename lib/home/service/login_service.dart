import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mone_task_app/checker/ui/checker_home_ui.dart';
import 'package:mone_task_app/admin/ui/admin_ui.dart';
import 'package:mone_task_app/core/data/local/token_storage.dart';
import 'package:mone_task_app/core/di/di.dart';
import 'package:mone_task_app/worker/ui/task_worker_ui.dart';
import 'package:mone_task_app/core/context_extension.dart';
import 'package:mone_task_app/home/model/login_model.dart';
import 'package:mone_task_app/home/service/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _phoneController;
  late final TextEditingController _passwordController;
  TokenStorage tokenStorage = sl<TokenStorage>();

  bool _isLoading = false;
  bool _obscurePassword = true;
  List<Map<String, String>> _savedAccounts = [];

  @override
  void initState() {
    super.initState();
    _phoneController = TextEditingController();
    _passwordController = TextEditingController();
    _loadSavedAccounts();
  }

  Future<void> _loadSavedAccounts() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String>? accounts = prefs.getStringList('saved_accounts');
    if (accounts != null) {
      setState(() {
        _savedAccounts = accounts
            .map((account) => Map<String, String>.from(jsonDecode(account)))
            .toList();
      });
    }
  }

  Future<void> _saveAccount(String phone, String password) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();

    // Agar akkaunt allaqachon mavjud bo'lsa, uni o'chirish
    _savedAccounts.removeWhere((account) => account['phone'] == phone);

    // Yangi akkauntni boshiga qo'shish
    _savedAccounts.insert(0, {'phone': phone, 'password': password});

    // Faqat oxirgi 7 ta akkauntni saqlash
    if (_savedAccounts.length > 7) {
      _savedAccounts = _savedAccounts.sublist(0, 7);
    }

    List<String> accountsToSave = _savedAccounts
        .map((account) => jsonEncode(account))
        .toList();

    await prefs.setStringList('saved_accounts', accountsToSave);
  }

  Future<void> _deleteAccount(int index) async {
    setState(() {
      _savedAccounts.removeAt(index);
    });

    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String> accountsToSave = _savedAccounts
        .map((account) => jsonEncode(account))
        .toList();
    await prefs.setStringList('saved_accounts', accountsToSave);
  }

  void _selectAccount(Map<String, String> account) {
    setState(() {
      _phoneController.text = account['phone']!;
      _passwordController.text = account['password']!;
    });
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final result = await ApiService().login(
        LoginModel(
          username: _phoneController.text.trim(),
          password: _passwordController.text.trim(),
        ),
      );

      setState(() => _isLoading = false);
      if (result["success"] == false) {
        _showError(result["message"] ?? "Login yoki parol noto'g'ri");
        return;
      }
      // 🔍 SUCCESSNI TEKSHIRISH
      if (result["success"] == true && result["token"] != null) {
        await tokenStorage.putToken(result["token"]);
        await tokenStorage.putUserData(result['user']);

        // Login ma'lumotlarini saqlash
        await _saveAccount(
          _phoneController.text.trim(),
          _passwordController.text.trim(),
        );

        // 🔄 Role bo‘yicha navigatsiya
        final role = result["user"]["role"];

        if (role == "super_admin") {
          context.pushAndRemove(AdminTaskUi());
        } else if (role == "checker") {
          context.pushAndRemove(CheckerHomeUi());
        } else {
          context.pushAndRemove(TaskWorkerUi());
        }
      } else {
        _showError(result["error"] ?? "Login yoki parol noto'g'ri");
      }
    } catch (e) {
      setState(() => _isLoading = false);
      _showError("Xatolik: $e");
    }
  }

  Future<void> _createAccount() async {
    setState(() {
      _isLoading = true;
    });

    final result = await ApiService().login(
      LoginModel(username: "944560055", password: "112233"),
    );

    setState(() {
      _isLoading = false;
    });

    // TextInput.finishAutofillContext();

    await _saveAccount(_phoneController.text, _passwordController.text);

    if (result["success"] == true) {
      TokenStorage tokenStorage = sl<TokenStorage>();
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await tokenStorage.putToken(result['token']);
      await prefs.setString('role', result['user']["role"]);
      await prefs.setString('full_name', result['user']["username"]);
      context.push(TaskWorkerUi());
    }
    // 🔹 To'g'ri yo'naltirish logikasi:
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.blue.shade50,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(20),
            child: Card(
              elevation: 15,
              shadowColor: Colors.blue.withOpacity(0.3),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: EdgeInsets.all(30),
                child: AutofillGroup(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: EdgeInsets.all(15),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade100,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.person,
                            size: 40,
                            color: Colors.blue.shade700,
                          ),
                        ),
                        SizedBox(height: 20),
                        Text(
                          "Login",
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade800,
                          ),
                        ),
                        SizedBox(height: 30),
                        TextFormField(
                          controller: _phoneController,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.username],
                          decoration: InputDecoration(
                            labelText: "Login",
                            prefixIcon: Icon(Icons.person, color: Colors.blue),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: Colors.blue,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: 20),
                        TextFormField(
                          controller: _passwordController,
                          keyboardType: TextInputType.visiblePassword,
                          autofillHints: const [AutofillHints.password],
                          obscureText: _obscurePassword,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: Icon(Icons.lock, color: Colors.blue),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                                color: Colors.blue,
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: Colors.blue,
                                width: 2,
                              ),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'enter_password';
                            }
                            return null;
                          },
                        ),
                        SizedBox(height: 30),
                        SizedBox(
                          width: double.infinity,
                          height: 55,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _login,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 5,
                            ),
                            child: _isLoading
                                ? Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      SizedBox(
                                        width: 20,
                                        height: 20,
                                        child:
                                            CircularProgressIndicator.adaptive(),
                                      ),
                                      SizedBox(width: 10),
                                      Text('Loading...'),
                                    ],
                                  )
                                : Text(
                                    'Login',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                        ),
                        SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          height: 55,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _createAccount,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 5,
                            ),
                            child: _isLoading
                                ? Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      SizedBox(
                                        width: 20,
                                        height: 20,
                                        child:
                                            CircularProgressIndicator.adaptive(),
                                      ),
                                      SizedBox(width: 10),
                                      Text('Loading...'),
                                    ],
                                  )
                                : Text(
                                    'Попробуйте!',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                        ),
                        SizedBox(height: 20),
                        // Saqlangan akkauntlar ro'yxati
                        if (_savedAccounts.isNotEmpty) ...[
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Ранее вошедшие в систему учетные записи:',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ),
                          SizedBox(height: 10),
                          Container(
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ListView.separated(
                              shrinkWrap: true,
                              physics: NeverScrollableScrollPhysics(),
                              itemCount: _savedAccounts.length,
                              separatorBuilder: (context, index) =>
                                  Divider(height: 1),
                              itemBuilder: (context, index) {
                                final account = _savedAccounts[index];
                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: Colors.blue.shade100,
                                    child: Icon(
                                      Icons.person,
                                      color: Colors.blue,
                                    ),
                                  ),
                                  title: Text(
                                    account['phone']!,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  trailing: IconButton(
                                    icon: Icon(Icons.delete, color: Colors.red),
                                    onPressed: () => _deleteAccount(index),
                                  ),
                                  onTap: () => _selectAccount(account),
                                );
                              },
                            ),
                          ),
                          SizedBox(height: 20),
                        ],
                        Text(
                          "app version: 0.0.7",
                          style: TextStyle(fontSize: 12),
                        ),
                        SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _showError(String text) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(text), backgroundColor: Colors.red));
  }
}
