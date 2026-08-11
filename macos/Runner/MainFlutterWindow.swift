import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = CGRect(x: 200, y: 160, width: 1180, height: 760)
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // 使用标准 macOS 标题栏,避免内容延伸到标题栏下方导致按钮被遮挡
    self.titlebarAppearsTransparent = false
    self.titleVisibility = .visible
    self.styleMask.insert(.titled)
    self.styleMask.insert(.miniaturizable)
    self.styleMask.insert(.resizable)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
