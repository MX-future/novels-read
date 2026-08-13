import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  /// UserDefaults 键:保存窗口 frame(位置 + 大小)。
  private static let frameKey = "windowFrame"

  /// 红黄绿交通灯按钮引用,沉浸式时隐藏、hover 顶部时显示。
  private var trafficLightButtons: [NSButton] = []

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
    // 沉浸式:标题栏透明 + 内容全尺寸延伸到标题栏,背景色由 Flutter 阅读背景决定,
    // 工具栏按钮(搜索/设置/目录)由 Flutter 渲染在标题栏区域
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden
    self.styleMask.insert(.fullSizeContentView)
    self.styleMask.insert(.titled)
    self.styleMask.insert(.miniaturizable)
    self.styleMask.insert(.resizable)

    // 保存交通灯按钮引用,初始隐藏(由 Flutter 阅读界面控制显示)
    trafficLightButtons = [
      standardWindowButton(.closeButton),
      standardWindowButton(.miniaturizeButton),
      standardWindowButton(.zoomButton),
    ].compactMap { $0 }
    setTrafficLightsVisible(false)
    // 首次布局后重挂交通灯,确保位置与 40px 工具栏对齐
    DispatchQueue.main.async { [weak self] in
      self?.reparentTrafficLights()
    }

    // 监听窗口尺寸变化,保存 frame + 调整交通灯对齐
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(windowDidResize(_:)),
      name: NSWindow.didResizeNotification,
      object: self,
    )

    // 注册窗口标题通道:Flutter 侧切换窗口标题与交通灯显示
    let channel = FlutterMethodChannel(
      name: "com.reader.novelReader/window",
      binaryMessenger: flutterViewController.engine.binaryMessenger,
    )
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "setTitle":
        if let title = call.arguments as? String, !title.isEmpty {
          self?.title = title
        }
        result(nil)
      case "setTrafficLightsVisible":
        if let visible = call.arguments as? Bool {
          self?.setTrafficLightsVisible(visible)
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }

  /// 控制红黄绿交通灯按钮的显示/隐藏(沉浸式时隐藏, hover 顶部时显示)。
  private func setTrafficLightsVisible(_ visible: Bool) {
    for btn in trafficLightButtons {
      btn.alphaValue = visible ? 1.0 : 0.0
    }
    if visible {
      reparentTrafficLights()
    }
  }

  /// 把交通灯按钮重挂到窗口 contentView:
  /// 与 Flutter 顶部工具栏条(40px 高, 上下间距对称各 8)垂直居中对齐。
  private func reparentTrafficLights() {
    guard let contentView = self.contentView, !trafficLightButtons.isEmpty else {
      return
    }
    let bounds = contentView.bounds
    // 工具栏条: 顶部留 8, 高 40 → 中心距窗口顶 28
    let topMargin: CGFloat = 8
    let toolbarHeight: CGFloat = 40
    let centerFromTop = topMargin + toolbarHeight / 2
    // 交通灯整体左边距与右侧按钮到右边缘一致(16), 按钮间间距 8
    let leftMargin: CGFloat = 16
    let spacing: CGFloat = 8
    var currentX = leftMargin

    for btn in trafficLightButtons {
      let size = btn.frame.size
      if btn.superview !== contentView {
        btn.removeFromSuperview()
        contentView.addSubview(btn)
      }
      let y: CGFloat
      if contentView.isFlipped {
        // 原点在左上:y 直接是距顶距离
        y = centerFromTop - size.height / 2
      } else {
        // 原点在左下:y 从窗口底部算起
        y = bounds.height - centerFromTop - size.height / 2
      }
      btn.frame = CGRect(x: currentX, y: y, width: size.width, height: size.height)
      currentX += size.width + spacing
    }
  }

  /// 窗口尺寸变化时保存 frame(位置 + 大小),并保持交通灯对齐。
  @objc private func windowDidResize(_ notification: Notification) {
    UserDefaults.standard.set(NSStringFromRect(self.frame), forKey: Self.frameKey)
    reparentTrafficLights()
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
