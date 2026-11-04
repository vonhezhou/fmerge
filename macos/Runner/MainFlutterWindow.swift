import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var fileAccess: FmergeAccess?
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    fileAccess = FmergeAccess(messenger: flutterViewController.engine.binaryMessenger)
    if let delegate = NSApp.delegate as? AppDelegate {
      delegate.lifecycleChannel = FlutterMethodChannel(name: "fmerge/lifecycle", binaryMessenger: flutterViewController.engine.binaryMessenger)
    }
    let windowFrame = NSRect(x: 0, y: 0, width: 1200, height: 800)
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.contentMinSize = NSSize(width: 920, height: 680)
    self.appearance = NSAppearance(named: .darkAqua)
    self.backgroundColor = NSColor(srgbRed: 0.067, green: 0.082, blue: 0.11, alpha: 1)
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}


/// 保存用户明确选择的文件与目录书签，权限随沙盒约束。
final class FmergeAccess {
  private let channel: FlutterMethodChannel
  private var active: [URL] = []
  private let key = "fmerge.authorizedDirectories"
  private let filesKey = "fmerge.authorizedFiles"
  #if FMERGE_INTEGRATION_TEST
  private var savedClipboard: [[NSPasteboard.PasteboardType: Data]]?
  #endif

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "fmerge/access", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, reply in
      guard let self = self else { return }
      #if FMERGE_INTEGRATION_TEST
      if self.handleTest(call, reply: reply) { return }
      #endif
      if call.method == "restore" {
        self.restore()
        reply(nil)
      } else if call.method == "grant",
                let args = call.arguments as? [String: String], let path = args["path"] {
        self.grant(path: path, reply: reply)
      } else if call.method == "rememberFiles",
                let args = call.arguments as? [String: Any], let paths = args["paths"] as? [String] {
        do {
          var saved = UserDefaults.standard.dictionary(forKey: self.filesKey) as? [String: Data] ?? [:]
          for path in paths {
            let url = URL(fileURLWithPath: path).standardizedFileURL
            let data = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            if url.startAccessingSecurityScopedResource() { self.active.append(url) }
            saved[url.path] = data
          }
          UserDefaults.standard.set(saved, forKey: self.filesKey)
          reply(nil)
        } catch { reply(FlutterError(code: "bookmarkFailed", message: error.localizedDescription, details: nil)) }
      } else if call.method == "revoke" {
        self.active.forEach { $0.stopAccessingSecurityScopedResource() }
        self.active.removeAll()
        UserDefaults.standard.removeObject(forKey: self.key)
        UserDefaults.standard.removeObject(forKey: self.filesKey)
        reply(nil)
      }
      else { reply(FlutterMethodNotImplemented) }
    }
  }
  #if FMERGE_INTEGRATION_TEST
  private func handleTest(_ call: FlutterMethodCall, reply: @escaping FlutterResult) -> Bool {
    if call.method == "backupClipboard" {
      savedClipboard = (NSPasteboard.general.pasteboardItems ?? []).map { item in
        var values: [NSPasteboard.PasteboardType: Data] = [:]
        for type in item.types { if let data = item.data(forType: type) { values[type] = data } }
        return values
      }
      reply(nil)
    } else if call.method == "restoreClipboard" {
      if let saved = savedClipboard {
        NSPasteboard.general.clearContents()
        let items = saved.map { values -> NSPasteboardItem in
          let item = NSPasteboardItem()
          for (type, data) in values { item.setData(data, forType: type) }
          return item
        }
        NSPasteboard.general.writeObjects(items)
        savedClipboard = nil
      }
      reply(nil)
    } else if call.method == "performMenuAction", let args = call.arguments as? [String:String], let label=args["label"] {
      if let root=NSApp.mainMenu, let found=findMenuItem(label,in:root) {
        found.0.performActionForItem(at:found.1)
        reply(nil)
      }else{reply(FlutterError(code:"missingMenu",message:label,details:nil))}
    } else if call.method == "requestSystemQuit" {
      reply(nil)
      DispatchQueue.main.async { NSApp.terminate(nil) }
    } else { return false }
    return true
  }
  private func findMenuItem(_ title:String,in menu:NSMenu)->(NSMenu,Int)? {
    for(index,item) in menu.items.enumerated(){
      if item.title==title{return (menu,index)}
      if let child=item.submenu,let found=findMenuItem(title,in:child){return found}
    }
    return nil
  }
  #endif
  private func restore() {
    let directories = UserDefaults.standard.array(forKey: key) as? [Data] ?? []
    var files = UserDefaults.standard.dictionary(forKey: filesKey) as? [String: Data] ?? [:]
    for data in directories + Array(files.values) {
      var stale = false
      if let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope],
                           relativeTo: nil, bookmarkDataIsStale: &stale),
         url.startAccessingSecurityScopedResource() {
        active.append(url)
        if stale, let renewed = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil),
           files.values.contains(data) {
          files = files.filter { $0.value != data }
          files[url.path] = renewed
        }
      }
    }
    UserDefaults.standard.set(files, forKey: filesKey)
  }
  private func grant(path: String, reply: @escaping FlutterResult) {
    let requested = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.directoryURL = requested
    panel.prompt = "授权此目录"
    panel.message = "请选择文件所在目录或它的父目录。fmerge 需要此权限来比较、创建备份和安全保存；授权可在设置中撤销。"
    NSApp.activate(ignoringOtherApps: true)
    panel.begin { response in
      guard response == .OK, let url = panel.url else { reply(false); return }
      let granted = url.standardizedFileURL.resolvingSymlinksInPath().path
      guard requested.path == granted || requested.path.hasPrefix(granted + "/") || granted == "/" else {
        reply(FlutterError(code: "wrongDirectory", message: "请选择目标文件所在目录或其父目录", details: nil))
        return
      }
      do {
        let data = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        if url.startAccessingSecurityScopedResource() { self.active.append(url) }
        var saved = UserDefaults.standard.array(forKey: self.key) as? [Data] ?? []
        if !saved.contains(data) { saved.append(data) }
        UserDefaults.standard.set(saved, forKey: self.key)
        reply(true)
      } catch { reply(FlutterError(code: "bookmarkFailed", message: error.localizedDescription, details: nil)) }
    }
  }
}
