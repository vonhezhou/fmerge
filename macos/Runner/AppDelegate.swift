import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  var lifecycleChannel: FlutterMethodChannel?
  private var waitingForQuit = false
  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard let channel = lifecycleChannel else { return .terminateNow }
    if waitingForQuit { return .terminateCancel }
    waitingForQuit = true
    channel.invokeMethod("requestClose", arguments: nil) { [weak self] _ in
      self?.waitingForQuit = false
      sender.reply(toApplicationShouldTerminate: false)
    }
    return .terminateLater
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
