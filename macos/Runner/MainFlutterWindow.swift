import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = CGRect(x: 200, y: 160, width: 1180, height: 760)
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    // 限制最小窗口尺寸,避免被拖成怪比例(否则 Dock 实时缩略图与图标槽位比例不一致)
    // 允许缩得更小:600x400(比例 1.5,接近默认 1180x760 的 1.55)
    self.contentMinSize = NSSize(width: 600, height: 400)

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
