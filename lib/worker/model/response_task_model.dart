import 'package:image_picker/image_picker.dart';

class RequestTaskModel {
  int id;
  XFile? file;

  RequestTaskModel({required this.id, this.file});
}
