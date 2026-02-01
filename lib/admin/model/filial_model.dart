class FilialModel {
  final int filialId;
  final String name;

  FilialModel({required this.filialId, required this.name});

  factory FilialModel.fromJson(Map<String, dynamic> json) {
    return FilialModel(filialId: json['filialId'], name: json['name']);
  }
}
