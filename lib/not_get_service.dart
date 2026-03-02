// import 'package:dio/dio.dart';
// import 'package:intl/intl.dart';
// import 'package:mone_task_app/core/constants/urls.dart';
// import 'package:mone_task_app/core/di/di.dart';
// import 'package:mone_task_app/local_not_service.dart';
// import 'package:mone_task_app/worker/model/task_worker_model.dart';

// class ApiService {
//   final Dio dio = sl<Dio>();

//   /// Notifications API dan ma'lumotlarni olib, local notification o'rnatish
//   Future<void> fetchAndScheduleNotifications() async {
//     try {
//       print('📡 Notifications yuklanmoqda...');

//       final response = await dio.get(AppUrls.notifications);

//       if (response.statusCode == 200) {
//         final data = response.data;

//         if (data['success'] == true) {
//           final List<dynamic> tasksJson = data['data'];
//           final int total = data['total'] ?? 0;

//           print('✅ Jami vazifalar: $total');

//           // Avval barcha eski notificationlarni o'chirish
//           await NotificationService.cancelAllNotifications();

//           // Har bir vazifa uchun notification o'rnatish
//           int scheduledCount = 0;

//           for (var taskJson in tasksJson) {
//             final task = TaskWorkerModel.fromJson(taskJson);

//             // Faqat notificationTime mavjud bo'lsa
//             if (task.notificationTime != null &&
//                 task.notificationTime!.isNotEmpty) {
//               // Date parse qilish
//               DateTime taskDate;
//               try {
//                 taskDate = DateFormat('yyyy-MM-dd').parse(taskJson['date']);
//               } catch (e) {
//                 print('❌ Date parse xatolik: ${taskJson['date']}');
//                 continue;
//               }

//               await NotificationService.scheduleTaskNotification(
//                 taskId: task.id,
//                 taskDescription: task.description,
//                 notificationTime: task.notificationTime!,
//                 taskDate: taskDate,
//                 category: taskJson['category'],
//               );

//               scheduledCount++;
//             }
//           }

//           print('✅ $scheduledCount ta notification o\'rnatildi');

//           // Debug: pending notificationlarni ko'rish
//           await _printPendingNotifications();
//         } else {
//           print('❌ API success: false');
//         }
//       } else {
//         print('❌ API xatolik: ${response.statusCode}');
//       }
//     } catch (e) {
//       print('❌ fetchAndScheduleNotifications xatolik: $e');
//       rethrow;
//     }
//   }

//   /// Pending notificationlarni console ga chiqarish (debug)
//   Future<void> _printPendingNotifications() async {
//     final pending = await NotificationService.getPendingNotifications();
//     print('\n📌 Pending Notifications: ${pending.length}');
//     for (var notification in pending) {
//       print('   ID: ${notification.id}');
//       print('   Title: ${notification.title}');
//       print('   Body: ${notification.body}');
//       print('   ---');
//     }
//   }
// }
