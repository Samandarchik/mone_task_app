import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:permission_handler/permission_handler.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Timezone sozlash
  tz.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('Asia/Tashkent'));

  // Bildirishnoma sozlamalari
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  const DarwinInitializationSettings initializationSettingsIOS =
      DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
    iOS: initializationSettingsIOS,
  );

  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  // Android uchun ruxsat so'rash
  if (await Permission.notification.isDenied) {
    await Permission.notification.request();
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vaqt Eslatma',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  TimeOfDay selectedTime = TimeOfDay.now();
  final TextEditingController messageController = TextEditingController();
  List<ReminderItem> reminders = [];

  Future<void> _selectTime(BuildContext context) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: selectedTime,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            timePickerTheme: TimePickerThemeData(
              backgroundColor: Colors.white,
              hourMinuteShape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && picked != selectedTime) {
      setState(() {
        selectedTime = picked;
      });
    }
  }

  Future<void> _scheduleNotification() async {
    if (messageController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Iltimos, eslatma matnini kiriting!'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final now = DateTime.now();
    var scheduledDate = DateTime(
      now.year,
      now.month,
      now.day,
      selectedTime.hour,
      selectedTime.minute,
    );

    // Agar tanlangan vaqt o'tib ketgan bo'lsa, ertangi kunga o'tkazish
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'eslatma_channel',
          'Eslatmalar',
          channelDescription: 'Vaqt bo\'yicha eslatmalar kanali',
          importance: Importance.max,
          priority: Priority.high,
          showWhen: true,
        );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
    );

    await flutterLocalNotificationsPlugin.zonedSchedule(
      reminders.length,
      'Eslatma',
      messageController.text,
      tz.TZDateTime.from(scheduledDate, tz.local),
      notificationDetails,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );

    setState(() {
      reminders.add(
        ReminderItem(
          time: selectedTime,
          message: messageController.text,
          id: reminders.length,
        ),
      );
      messageController.clear();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Eslatma ${selectedTime.format(context)} vaqtiga o\'rnatildi',
        ),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _deleteReminder(int id) async {
    await flutterLocalNotificationsPlugin.cancel(id);
    setState(() {
      reminders.removeWhere((reminder) => reminder.id == id);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Eslatma o\'chirildi'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Vaqt Eslatma',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              elevation: 3,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    const Text(
                      'Yangi eslatma',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),
                    InkWell(
                      onTap: () => _selectTime(context),
                      child: Container(
                        padding: const EdgeInsets.all(15),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.blue, width: 2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.access_time, color: Colors.blue),
                                SizedBox(width: 10),
                                Text(
                                  'Vaqtni tanlang:',
                                  style: TextStyle(fontSize: 16),
                                ),
                              ],
                            ),
                            Text(
                              selectedTime.format(context),
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: messageController,
                      decoration: InputDecoration(
                        labelText: 'Eslatma matni',
                        hintText: 'Masalan: Ish vaqti boshlandi',
                        prefixIcon: const Icon(Icons.message),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: Colors.blue,
                            width: 2,
                          ),
                        ),
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: _scheduleNotification,
                      icon: const Icon(Icons.add_alert),
                      label: const Text(
                        'Eslatma qo\'shish',
                        style: TextStyle(fontSize: 16),
                      ),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.all(15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Aktiv eslatmalar',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: reminders.isEmpty
                  ? const Center(
                      child: Text(
                        'Hozircha eslatmalar yo\'q',
                        style: TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      itemCount: reminders.length,
                      itemBuilder: (context, index) {
                        final reminder = reminders[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: ListTile(
                            leading: CircleAvatar(
                              child: Text(
                                '${reminder.time.hour}:${reminder.time.minute.toString().padLeft(2, '0')}',
                              ),
                            ),
                            title: Text(
                              reminder.message,
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            subtitle: Text(
                              'Vaqt: ${reminder.time.format(context)}',
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _deleteReminder(reminder.id),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    messageController.dispose();
    super.dispose();
  }
}

class ReminderItem {
  final TimeOfDay time;
  final String message;
  final int id;

  ReminderItem({required this.time, required this.message, required this.id});
}
