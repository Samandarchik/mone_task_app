import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    
    // Method Channel'ni sozlash
    let controller = window?.rootViewController as! FlutterViewController
    let nativeDialogChannel = FlutterMethodChannel(
      name: "native_dialog",
      binaryMessenger: controller.binaryMessenger
    )
    
    nativeDialogChannel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
      if call.method == "showDeleteDialog" {
        self.showDeleteDialog(result: result)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  // Delete dialog ko'rsatish funksiyasi
  private func showDeleteDialog(result: @escaping FlutterResult) {
    // Root view controller'ni olish
    guard let viewController = window?.rootViewController else {
      result(false)
      return
    }
    
    // UIAlertController yaratish
    let alert = UIAlertController(
      title: "Удалить",
      message: "Вы действительно хотите это удалить?",
      preferredStyle: .alert
    )
    
    // Bekor qilish tugmasi
    let cancelAction = UIAlertAction(
      title: "Отмена",
      style: .cancel
    ) { _ in
      result(false)
    }
    
    // O'chirish tugmasi
    let deleteAction = UIAlertAction(
      title: "Удалить",
      style: .destructive
    ) { _ in
      result(true)
    }
    
    // Tugmalarni qo'shish
    alert.addAction(cancelAction)
    alert.addAction(deleteAction)
    
    // Dialog'ni ko'rsatish
    DispatchQueue.main.async {
      viewController.present(alert, animated: true, completion: nil)
    }
  }
}