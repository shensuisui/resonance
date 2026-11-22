import AVFAudio
import Flutter
import UIKit

/// 车载蓝牙状态桥（iOS）
///
/// 判定依据：AVAudioSession 当前输出端口类型——
///   * .carAudio → 车机（CarPlay/车载音频）；
///   * .bluetoothA2DP / .bluetoothHFP / .bluetoothLE → 普通蓝牙已连接。
/// iOS 不暴露蓝牙设备类，无法区分“车载蓝牙”与普通蓝牙音箱，故以 carAudio 为准。
final class CarLyricsBridge: NSObject, FlutterStreamHandler {
  private var sink: FlutterEventSink?
  private var observing = false

  static func currentState() -> [String: Any] {
    let session = AVAudioSession.sharedInstance()
    let outputs = session.currentRoute.outputs
    let car = outputs.contains { $0.portType == .carAudio }
    let bt = outputs.contains {
      $0.portType == .bluetoothA2DP || $0.portType == .bluetoothHFP || $0.portType == .bluetoothLE
    }
    return [
      "bluetoothConnected": bt,
      "carDetected": car,
      "deviceName": outputs.first?.portName ?? NSNull(),
    ]
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "current":
      result(CarLyricsBridge.currentState())
    case "ensurePermission":
      // iOS 路由检测无需权限
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func onListen(withArguments arguments: Any?, eventSink: @escaping FlutterEventSink) -> FlutterError? {
    sink = eventSink
    if !observing {
      NotificationCenter.default.addObserver(
        self,
        selector: #selector(routeChanged),
        name: AVAudioSession.routeChangeNotification,
        object: nil
      )
      observing = true
    }
    eventSink(CarLyricsBridge.currentState())
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    if observing {
      NotificationCenter.default.removeObserver(self)
      observing = false
    }
    sink = nil
    return nil
  }

  @objc private func routeChanged(_ notification: Notification) {
    sink?(CarLyricsBridge.currentState())
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let carLyricsBridge = CarLyricsBridge()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "CarLyricsBridge") else {
      return
    }
    let messenger = registrar.messenger()
    let method = FlutterMethodChannel(name: "resonance/car_lyrics", binaryMessenger: messenger)
    method.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterMethodNotImplemented)
        return
      }
      self.carLyricsBridge.handle(call, result: result)
    }
    let events = FlutterEventChannel(name: "resonance/car_lyrics_events", binaryMessenger: messenger)
    events.setStreamHandler(carLyricsBridge)
  }
}
