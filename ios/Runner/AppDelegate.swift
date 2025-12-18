import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {


override func application(
  _ application: UIApplication,
  didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
) -> Bool {

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
  return super.application(application, didFinishLaunchingWithOptions: launchOptions)
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
