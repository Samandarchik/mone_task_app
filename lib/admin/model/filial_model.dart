class FilialModel {
  final int filialId;
  final String name;
  final List<String> categories;

  FilialModel({
    required this.filialId,
    required this.name,
    required this.categories,
  });

  factory FilialModel.fromJson(Map<String, dynamic> json) {
    return FilialModel(
      filialId: json['filialId'],
      name: json['name'],
      categories: List<String>.from(json['categories']),
    );
  }
}
