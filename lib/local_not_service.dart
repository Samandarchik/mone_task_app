// import 'package:flutter_local_notifications/flutter_local_notifications.dart';
// import 'package:timezone/data/latest_all.dart' as tz;
// import 'package:timezone/timezone.dart' as tz;
// import 'package:permission_handler/permission_handler.dart';

// class NotificationService {
//   static final FlutterLocalNotificationsPlugin _notifications =
//       FlutterLocalNotificationsPlugin();

//   static bool _isInitialized = false;

//   static Future<void> initialize() async {
//     if (_isInitialized) return;

//     tz.initializeTimeZones();
//     tz.setLocalLocation(tz.getLocation('Asia/Tashkent'));

//     const AndroidInitializationSettings androidSettings =
//         AndroidInitializationSettings('@mipmap/ic_launcher');

//     const DarwinInitializationSettings iosSettings =
//         DarwinInitializationSettings(
//           requestAlertPermission: true,
//           requestBadgePermission: true,
//           requestSoundPermission: true,
//         );

//     const InitializationSettings settings = InitializationSettings(
//       android: androidSettings,
//       iOS: iosSettings,
//     );

//     await _notifications.initialize(settings);

//     // Ruxsat so'rash
//     if (await Permission.notification.isDenied) {
//       await Permission.notification.request();
//     }

//     _isInitialized = true;
//     print('✅ Notification Service initialized');
//   }

//   static Future<void> scheduleTaskNotification({
//     required int taskId,
//     required String taskDescription,
//     required String notificationTime,
//     required DateTime taskDate,
//     String? category,
//   }) async {
//     try {
//       // notificationTime parse qilish (masalan: "08:00")
//       final timeParts = notificationTime.split(':');
//       if (timeParts.length != 2) {
//         print('❌ Noto\'g\'ri vaqt formati: $notificationTime');
//         return;
//       }

//       final hour = int.parse(timeParts[0]);
//       final minute = int.parse(timeParts[1]);

//       // Notification vaqtini yaratish
//       var scheduledDate = DateTime(
//         taskDate.year,
//         taskDate.month,
//         taskDate.day,
//         hour,
//         minute,
//       );

//       // Agar vaqt o'tib ketgan bo'lsa, o'rnatmaslik
//       if (scheduledDate.isBefore(DateTime.now())) {
//         print('⏰ Vaqt o\'tib ketgan: Task $taskId - $notificationTime');
//         return;
//       }

//       // Notification body yaratish
//       String body = taskDescription;
//       if (category != null && category.isNotEmpty) {
//         body = taskDescription;
//       }

//       const AndroidNotificationDetails androidDetails =
//           AndroidNotificationDetails(
//             'task_channel',
//             'Vazifa Eslatmalari',
//             channelDescription: 'Kunlik vazifalar uchun eslatmalar',
//             importance: Importance.max,
//             priority: Priority.high,
//             showWhen: true,
//             icon: '@mipmap/ic_launcher',
//           );

//       const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
//         presentAlert: true,
//         presentBadge: true,
//         presentSound: true,
//       );

//       const NotificationDetails notificationDetails = NotificationDetails(
//         android: androidDetails,
//         iOS: iosDetails,
//       );

//       await _notifications.zonedSchedule(
//         taskId,
//         body,
//         "${scheduledDate.hour}:${scheduledDate.minute.toString().padLeft(2, '0')}",
//         tz.TZDateTime.from(scheduledDate, tz.local),
//         notificationDetails,
//         androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
//       );

//       print(
//         '✅ Notification o\'rnatildi: Task $taskId - ${scheduledDate.toString()}',
//       );
//     } catch (e) {
//       print('❌ Notification xatolik: $e');
//     }
//   }

//   static Future<void> cancelNotification(int taskId) async {
//     await _notifications.cancel(taskId);
//     print('🗑️ Notification bekor qilindi: Task $taskId');
//   }

//   static Future<void> cancelAllNotifications() async {
//     await _notifications.cancelAll();
//     print('🗑️ Barcha notificationlar bekor qilindi');
//   }

//   static Future<List<PendingNotificationRequest>>
//   getPendingNotifications() async {
//     return await _notifications.pendingNotificationRequests();
//   }
// }
