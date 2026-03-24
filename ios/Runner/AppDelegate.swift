import Flutter
import UIKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate {
    
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)
        
        let controller = window?.rootViewController as! FlutterViewController
        
        // ── Native Dialog Channel ──
        let nativeDialogChannel = FlutterMethodChannel(
            name: "native_dialog",
            binaryMessenger: controller.binaryMessenger
        )
        nativeDialogChannel.setMethodCallHandler { (call, result) in
            if call.method == "showDeleteDialog" {
                self.showDeleteDialog(result: result)
            } else {
                result(FlutterMethodNotImplemented)
            }
        }
        
        // ── Native Camera Channel ──
        let cameraChannel = FlutterMethodChannel(
            name: "native_camera",
            binaryMessenger: controller.binaryMessenger
        )
        cameraChannel.setMethodCallHandler { (call, result) in
            switch call.method {
            case "getAvailableLenses":
                self.getAvailableLenses(result: result)
            case "getMinZoomForLens":
                if let args = call.arguments as? [String: Any],
                   let lensType = args["lensType"] as? String {
                    self.getMinZoomForLens(lensType: lensType, result: result)
                } else {
                    result(FlutterError(code: "INVALID_ARGS", message: nil, details: nil))
                }
            default:
                result(FlutterMethodNotImplemented)
            }
        }
        
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    // Universal Links handle — app_links plugin ishlashi uchun
    override func application(
        _ application: UIApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
    ) -> Bool {
        return super.application(application, continue: userActivity, restorationHandler: restorationHandler)
    }
    
    // ── Available lenslarni qaytarish ──
    // iPhone 15 Pro Max: ultraWide (0.5x), wide (1x), telephoto (2x/3x)
    private func getAvailableLenses(result: @escaping FlutterResult) {
        var lenses: [[String: Any]] = []
        
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .builtInUltraWideCamera,
                .builtInWideAngleCamera,
                .builtInTelephotoCamera
            ],
            mediaType: .video,
            position: .back
        )
        
        for device in discoverySession.devices {
            var lensType = "wide"
            var zoomLabel = "1×"
            var zoomValue = 1.0
            
            switch device.deviceType {
            case .builtInUltraWideCamera:
                lensType = "ultraWide"
                zoomLabel = "0.5×"
                zoomValue = 0.5
            case .builtInWideAngleCamera:
                lensType = "wide"
                zoomLabel = "1×"
                zoomValue = 1.0
            case .builtInTelephotoCamera:
                lensType = "telephoto"
                zoomLabel = "2×"
                // Telephoto ning haqiqiy zoom factor
                zoomValue = Double(device.minAvailableVideoZoomFactor)
                if zoomValue < 1.5 {
                    zoomValue = 2.0
                }
            default:
                continue
            }
            
            lenses.append([
                "lensType": lensType,
                "zoomLabel": zoomLabel,
                "zoomValue": zoomValue,
                "uniqueID": device.uniqueID,
                "position": "back",
                "minZoom": device.minAvailableVideoZoomFactor,
                "maxZoom": min(device.maxAvailableVideoZoomFactor, 16.0),
            ])
        }
        
        // Front kamera ham qo'shamiz
        if let frontCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) {
            lenses.append([
                "lensType": "front",
                "zoomLabel": "1×",
                "zoomValue": 1.0,
                "uniqueID": frontCamera.uniqueID,
                "position": "front",
                "minZoom": frontCamera.minAvailableVideoZoomFactor,
                "maxZoom": min(frontCamera.maxAvailableVideoZoomFactor, 16.0),
            ])
        }
        
        result(lenses)
    }
    
    // ── Berilgan lens uchun min zoom ──
    private func getMinZoomForLens(lensType: String, result: @escaping FlutterResult) {
        var deviceType: AVCaptureDevice.DeviceType = .builtInWideAngleCamera
        
        switch lensType {
        case "ultraWide":
            deviceType = .builtInUltraWideCamera
        case "telephoto":
            deviceType = .builtInTelephotoCamera
        default:
            deviceType = .builtInWideAngleCamera
        }
        
        if let device = AVCaptureDevice.default(deviceType, for: .video, position: .back) {
            result(device.minAvailableVideoZoomFactor)
        } else {
            result(1.0)
        }
    }
    
    // ── Delete Dialog ──
    private func showDeleteDialog(result: @escaping FlutterResult) {
        guard let viewController = window?.rootViewController else {
            result(false)
            return
        }
        
        let alert = UIAlertController(
            title: "Удалить",
            message: "Вы действительно хотите это удалить?",
            preferredStyle: .alert
        )
        
        let cancelAction = UIAlertAction(title: "Отмена", style: .cancel) { _ in
            result(false)
        }
        let deleteAction = UIAlertAction(title: "Удалить", style: .destructive) { _ in
            result(true)
        }
        
        alert.addAction(cancelAction)
        alert.addAction(deleteAction)
        
        DispatchQueue.main.async {
            viewController.present(alert, animated: true, completion: nil)
        }
    }
}