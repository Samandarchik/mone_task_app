import 'dart:convert';

class UserModel {
  final int userId;
  final String username;
  final String login;
  final String role;
  final List<int>? filialIds;
  final List<String>? categories;
  final String? notificationId;
  final String? phoneNumber;
  final String? profileJson;
  final String password;

  UserModel({
    required this.userId,
    required this.username,
    required this.login,
    required this.role,
    this.filialIds,
    this.categories,
    this.notificationId,
    this.phoneNumber,
    this.profileJson,
    this.password = '',
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      userId: json['userId'] ?? 0,
      username: json['username'] ?? '',
      login: json['login'] ?? '',
      role: json['role'] ?? '',
      filialIds: json['filialIds'] != null
          ? List<int>.from(json['filialIds'])
          : null,
      categories: json['categories'] != null
          ? List<String>.from(json['categories'])
          : null,
      notificationId: json['notificationId'],
      phoneNumber: json['phoneNumber'],
      profileJson: json['profileJson'],
      password: json['password'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'username': username,
      'login': login,
      'role': role,
      if (filialIds != null) 'filialIds': filialIds,
      if (categories != null) 'categories': categories,
      if (notificationId != null) 'notificationId': notificationId,
      if (phoneNumber != null) 'phoneNumber': phoneNumber,
      if (profileJson != null) 'profileJson': profileJson,
      'password': password,
    };
  }

  Map<String, dynamic>? get profile {
    if (profileJson == null || profileJson!.isEmpty) return null;
    try {
      return jsonDecode(profileJson!) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  String get fullName {
    final p = profile;
    if (p == null) return username;
    final familiya = (p['familiya'] ?? '').toString().trim();
    final ism = (p['ism'] ?? '').toString().trim();
    final sharif = (p['sharif'] ?? '').toString().trim();
    final fio = [familiya, ism, sharif].where((s) => s.isNotEmpty).join(' ');
    return fio.isNotEmpty ? fio : username;
  }

  String? get photoUrl {
    final p = profile;
    if (p == null) return null;
    final rasm = (p['rasm_url'] ?? '').toString();
    if (rasm.isEmpty) return null;
    if (rasm.startsWith('http')) return rasm;
    return 'https://hr.monebakeryuz.uz$rasm';
  }

  String? get position => profile?['lavozim']?.toString();
  String? get telegram => profile?['tg_username']?.toString();

  UserModel copyWith({
    int? userId,
    String? username,
    String? login,
    String? role,
    List<int>? filialIds,
    List<String>? categories,
    String? notificationId,
    String? phoneNumber,
    String? profileJson,
    String? password,
  }) {
    return UserModel(
      userId: userId ?? this.userId,
      username: username ?? this.username,
      login: login ?? this.login,
      role: role ?? this.role,
      filialIds: filialIds ?? this.filialIds,
      categories: categories ?? this.categories,
      notificationId: notificationId ?? this.notificationId,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      profileJson: profileJson ?? this.profileJson,
      password: password ?? this.password,
    );
  }
}

class UsersResponse {
  final List<UserModel> data;
  final bool success;

  UsersResponse({required this.data, required this.success});

  factory UsersResponse.fromJson(Map<String, dynamic> json) {
    return UsersResponse(
      data: (json['data'] as List?)
              ?.map((user) => UserModel.fromJson(user))
              .toList() ??
          [],
      success: json['success'] ?? false,
    );
  }
}
