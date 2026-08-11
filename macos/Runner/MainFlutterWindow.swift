import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  /// UserDefaults 键:保存窗口 frame(位置 + 大小)。
  private static let frameKey = "windowFrame"

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = CGRect(x: 200, y: 160, width: 1180, height: 760)
    self.contentViewController = flutterViewController

    // 恢复上次的窗口大小与位置;否则用默认 1180x760
    let saved = UserDefaults.standard.string(forKey: Self.frameKey)
    if let saved, let rect = Self.visibleRect(NSRectFromString(saved)) {
      self.setFrame(rect, display: true)
    } else {
      self.setFrame(windowFrame, display: true)
    }

    // 限制最小窗口尺寸,避免被拖成怪比例(否则 Dock 实时缩略图与图标槽位比例不一致)
    // 允许缩得更小:600x400(比例 1.5,接近默认 1180x760 的 1.55)
    self.contentMinSize = NSSize(width: 600, height: 400)

    // 使用标准 macOS 标题栏,避免内容延伸到标题栏下方导致按钮被遮挡
    self.titlebarAppearsTransparent = false
    self.titleVisibility = .visible
    self.styleMask.insert(.titled)
    self.styleMask.insert(.miniaturizable)
    self.styleMask.insert(.resizable)

    // 监听窗口尺寸变化,保存 frame 供下次启动恢复
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(windowDidResize(_:)),
      name: NSWindow.didResizeNotification,
      object: self,
    )

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }

  /// 窗口尺寸变化时保存 frame(位置 + 大小)。
  @objc private func windowDidResize(_ notification: Notification) {
    UserDefaults.standard.set(NSStringFromRect(self.frame), forKey: Self.frameKey)
  }

  /// 把恢复的 frame 限制在可见屏幕内,避免显示器变化后窗口跑到屏幕外。
  private static func visibleRect(_ rect: NSRect) -> NSRect? {
    guard rect.width >= 100, rect.height >= 100 else { return nil }
    guard let screen = NSScreen.main else { return rect }
    let visible = screen.visibleFrame
    // 若窗口与可见区域完全不相交,则移动到可见区域左上角
    if rect.maxX <= visible.minX || rect.minX >= visible.maxX ||
       rect.maxY <= visible.minY || rect.minY >= visible.maxY {
      var fixed = rect
      fixed.origin.x = visible.minX + (visible.width - rect.width) / 2
      fixed.origin.y = visible.minY + (visible.height - rect.height) / 2
      return fixed
    }
    return rect
  }
}
