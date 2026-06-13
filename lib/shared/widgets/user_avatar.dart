import 'package:flutter/material.dart';
import 'package:mone_task_app/worker/model/user_model.dart';

/// Foydalanuvchi rasmi — rasm bo'lsa ko'rsatadi, bo'lmasa ism harfini.
class UserAvatar extends StatelessWidget {
  final UserModel? user;
  final double radius;

  const UserAvatar({super.key, required this.user, this.radius = 18});

  @override
  Widget build(BuildContext context) {
    final url = user?.photoUrl;
    final name = (user?.fullName ?? '').trim();
    final letter = name.isEmpty ? '?' : name[0].toUpperCase();

    return CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFF3699ff),
      backgroundImage: (url != null && url.isNotEmpty) ? NetworkImage(url) : null,
      child: (url == null || url.isEmpty)
          ? Text(
              letter,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: radius * 0.9,
              ),
            )
          : null,
    );
  }
}
