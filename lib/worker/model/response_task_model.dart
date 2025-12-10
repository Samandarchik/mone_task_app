import 'package:image_picker/image_picker.dart';

class RequestTaskModel {
  int id;
  String? text;
  XFile? file;

  RequestTaskModel({required this.id, this.text, this.file});
}
