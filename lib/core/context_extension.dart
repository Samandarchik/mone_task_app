import 'package:flutter/material.dart';

extension CustomContext on BuildContext {
  void get pop => Navigator.pop(this);
  void push(Widget page) =>
      Navigator.push(this, MaterialPageRoute(builder: (context) => page));
  void pushReplacement(Widget page) => Navigator.pushReplacement(
    this,
    MaterialPageRoute(builder: (context) => page),
  );
  void pushAndRemove(Widget page) => Navigator.pushAndRemoveUntil(
    this,
    MaterialPageRoute(builder: (context) => page),
    (route) => false,
  );
}
