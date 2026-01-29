class UserModel {
  final int userId;
  final String username;
  final String login;
  final String role;
  final List<int> filialIds;

  UserModel({
    required this.userId,
    required this.username,
    required this.login,
    required this.role,
    required this.filialIds,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      userId: json['userId'],
      username: json['username'],
      login: json['login'],
      role: json['role'],
      filialIds: List<int>.from(json['filialIds']),
    );
  }
}
