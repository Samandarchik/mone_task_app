import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mone_task_app/worker/model/response_task_model.dart';

Future<RequestTaskModel?> showTaskCompleteDialog(
  BuildContext context,
  int id,
) async {
  TextEditingController textController = TextEditingController();
  XFile? selectedMedia;
  final picker = ImagePicker();

  return showDialog<RequestTaskModel>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        return AlertDialog(
          title: const Text("Taskni bajarish"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: textController,
                decoration: const InputDecoration(
                  labelText: "Izoh",
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),

              const SizedBox(height: 20),

              /// --- GALEREYA ---
              ElevatedButton(
                onPressed: () async {
                  final XFile? media = await picker.pickMedia();
                  if (media != null) {
                    setState(() => selectedMedia = media);
                  }
                },
                child: Row(
                  children: [
                    Icon(CupertinoIcons.photo_fill),
                    const Text(" Galereyadan tanlash"),
                  ],
                ),
              ),

              const SizedBox(height: 10),

              /// --- KAMERA ---
              ElevatedButton(
                onPressed: () async {
                  final XFile? media = await _pickFromCamera(context, picker);
                  if (media != null) {
                    setState(() => selectedMedia = media);
                  }
                },
                child: Row(
                  children: [
                    Icon(CupertinoIcons.camera_fill),
                    const Text(" Kamera orqali olish"),
                  ],
                ),
              ),

              const SizedBox(height: 15),

              if (selectedMedia != null) _buildMediaPreview(selectedMedia!),
            ],
          ),

          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text("Bekor qilish"),
            ),
            ElevatedButton(
              onPressed: () {
                final response = RequestTaskModel(
                  id: id,
                  text: textController.text,
                  file: selectedMedia,
                );
                Navigator.pop(context, response);
              },
              child: const Text("Yuborish"),
            ),
          ],
        );
      },
    ),
  );
}

/// Kamera orqali FOTO yoki VIDEO olish uchun bottom sheet
Future<XFile?> _pickFromCamera(BuildContext context, ImagePicker picker) async {
  return showModalBottomSheet<XFile>(
    context: context,
    builder: (ctx) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          leading: const Icon(Icons.camera_alt),
          title: const Text("Foto olish"),
          onTap: () async {
            final img = await picker.pickImage(source: ImageSource.camera);
            Navigator.pop(ctx, img);
          },
        ),
        ListTile(
          leading: const Icon(Icons.videocam),
          title: const Text("Video olish"),
          onTap: () async {
            final video = await picker.pickVideo(source: ImageSource.camera);
            Navigator.pop(ctx, video);
          },
        ),
      ],
    ),
  );
}

/// RASM yoki VIDEO preview
Widget _buildMediaPreview(XFile file) {
  final isImage =
      file.path.endsWith(".jpg") ||
      file.path.endsWith(".jpeg") ||
      file.path.endsWith(".png") ||
      file.path.endsWith(".gif") ||
      file.path.endsWith(".webp");

  if (isImage) {
    return SizedBox(
      height: 120,
      width: 120,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(File(file.path), fit: BoxFit.cover),
      ),
    );
  }

  return Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(8),
      color: Colors.grey.shade200,
    ),
    child: Row(
      children: [
        const Icon(Icons.videocam, size: 32, color: Colors.black54),
        const SizedBox(width: 10),
        Expanded(child: Text(file.name, overflow: TextOverflow.ellipsis)),
      ],
    ),
  );
}
