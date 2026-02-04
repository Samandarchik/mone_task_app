// import 'package:flutter/material.dart';
// import 'package:mone_task_app/not_get_service.dart';

// class HomePage extends StatefulWidget {
//   const HomePage({super.key});

//   @override
//   State<HomePage> createState() => _HomePageState();
// }

// class _HomePageState extends State<HomePage> {
//   late ApiService apiService;
//   bool isLoading = false;

//   @override
//   void initState() {
//     super.initState();
//     apiService = ApiService();

//     // initState tugangandan KEYIN chaqirish
//     WidgetsBinding.instance.addPostFrameCallback((_) {
//       _loadNotifications();
//     });
//   }

//   Future<void> _loadNotifications() async {
//     setState(() => isLoading = true);

//     try {
//       await apiService.fetchAndScheduleNotifications();

//       if (mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           const SnackBar(
//             content: Text('✅ Notifications o\'rnatildi'),
//             backgroundColor: Colors.green,
//           ),
//         );
//       }
//     } catch (e) {
//       if (mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(content: Text('❌ Xatolik: $e'), backgroundColor: Colors.red),
//         );
//       }
//     } finally {
//       setState(() => isLoading = false);
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: const Text('Vazifalar'),
//         actions: [
//           IconButton(
//             icon: const Icon(Icons.notifications_active),
//             onPressed: _loadNotifications,
//             tooltip: 'Notificationlarni yangilash',
//           ),
//         ],
//       ),
//       body: isLoading
//           ? const Center(child: CircularProgressIndicator())
//           : Center(
//               child: Column(
//                 mainAxisAlignment: MainAxisAlignment.center,
//                 children: [
//                   const Icon(Icons.notifications, size: 80, color: Colors.blue),
//                   const SizedBox(height: 20),
//                   const Text(
//                     'Vazifalar eslatmalari o\'rnatildi',
//                     style: TextStyle(fontSize: 18),
//                   ),
//                   const SizedBox(height: 20),
//                   ElevatedButton.icon(
//                     onPressed: _loadNotifications,
//                     icon: const Icon(Icons.refresh),
//                     label: const Text('Qayta yuklash'),
//                   ),
//                 ],
//               ),
//             ),
//     );
//   }
// }
