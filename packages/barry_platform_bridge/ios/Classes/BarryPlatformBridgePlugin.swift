import Flutter
import UIKit

public class BarryPlatformBridgePlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "barry_platform_bridge/litert_lm", binaryMessenger: registrar.messenger())
    let instance = BarryPlatformBridgePlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "infer" { result("[ios-mock]") } else { result(FlutterMethodNotImplemented) }
  }
}
