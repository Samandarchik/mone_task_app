import UIKit
import Flutter
import Firebase
import FirebaseMessaging
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    FirebaseApp.configure()
    
    // Messaging delegate'ni birinchi o'rnatish
    Messaging.messaging().delegate = self

    // Notification center delegate
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
    }

    let controller = window?.rootViewController as! FlutterViewController

    let channel = FlutterMethodChannel(
      name: "native_dialog",
      binaryMessenger: controller.binaryMessenger
    )

    channel.setMethodCallHandler { call, result in
      if call.method == "showDeleteDialog" {
        self.showDeleteDialog(controller: controller, result: result)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    GeneratedPluginRegistrant.register(with: self)

    return super.application(
      application,
      didFinishLaunchingWithOptions: launchOptions
    )
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    print("✅ APNS token received")
    Messaging.messaging().apnsToken = deviceToken
    
    // Token'ni log qilish (debug uchun)
    let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
    let token = tokenParts.joined()
    print("APNS Device Token: \(token)")
  }
  
  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    print("❌ Failed to register for remote notifications: \(error)")
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    let userInfo = notification.request.content.userInfo
    print("📱 Foreground notification received: \(userInfo)")
    
    if #available(iOS 14.0, *) {
      completionHandler([.banner, .sound, .badge])
    } else {
      completionHandler([.alert, .sound, .badge])
    }
  }
  
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let userInfo = response.notification.request.content.userInfo
    print("👆 Notification tapped: \(userInfo)")
    completionHandler()
  }

  func showDeleteDialog(
    controller: UIViewController,
    result: @escaping FlutterResult
  ) {
    let alert = UIAlertController(
      title: "Подтверждение",
      message: "Вы действительно хотите это удалить?",
      preferredStyle: .alert
    )

    let cancel = UIAlertAction(title: "Отмена", style: .cancel) { _ in
      result(false)
    }

    let delete = UIAlertAction(title: "Удалить", style: .destructive) { _ in
      result(true)
    }

    alert.addAction(cancel)
    alert.addAction(delete)

    DispatchQueue.main.async {
      controller.present(alert, animated: true)
    }
  }
}

// MUHIM: Messaging Delegate
extension AppDelegate: MessagingDelegate {
  func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
    print("🔥 Firebase registration token: \(String(describing: fcmToken))")
    
    let dataDict: [String: String] = ["token": fcmToken ?? ""]
    NotificationCenter.default.post(
      name: Notification.Name("FCMToken"),
      object: nil,
      userInfo: dataDict
    )
  }
}