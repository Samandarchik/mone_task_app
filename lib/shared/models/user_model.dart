// lib/admin/model/user_model.dart
class UserModel {
  final int userId;
  final String username;
  final String login;
  final String role;
  final List<int>? filialIds;
  final List<String>? categories;
  final String? notificationId;
  final bool isLogin;

  UserModel({
    required this.userId,
    required this.username,
    required this.login,
    required this.role,
    this.filialIds,
    this.categories,
    this.notificationId,
    required this.isLogin,
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
      isLogin: json['isLogin'] ?? false,
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
      'isLogin': isLogin,
    };
  }

  UserModel copyWith({
    int? userId,
    String? username,
    String? login,
    String? role,
    List<int>? filialIds,
    List<String>? categories,
    String? notificationId,
    bool? isLogin,
  }) {
    return UserModel(
      userId: userId ?? this.userId,
      username: username ?? this.username,
      login: login ?? this.login,
      role: role ?? this.role,
      filialIds: filialIds ?? this.filialIds,
      categories: categories ?? this.categories,
      notificationId: notificationId ?? this.notificationId,
      isLogin: isLogin ?? this.isLogin,
    );
  }
}

class UsersResponse {
  final List<UserModel> data;
  final bool success;

  UsersResponse({required this.data, required this.success});

  factory UsersResponse.fromJson(Map<String, dynamic> json) {
    return UsersResponse(
      data:
          (json['data'] as List?)
              ?.map((user) => UserModel.fromJson(user))
              .toList() ??
          [],
      success: json['success'] ?? false,
    );
  }
}
