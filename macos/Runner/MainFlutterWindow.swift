import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  /// UserDefaults 键:保存窗口 frame(位置 + 大小)。
  private static let frameKey = "windowFrame"

  /// UserDefaults 键:自动导入目录的 security-scoped bookmark 与原始路径。
  ///
  /// 沙盒 App 通过 NSOpenPanel 拿到的访问权限只在本进程内有效,进程退出即失效。
  /// 要让"每次启动自动扫描"成立,必须把目录存成 bookmark,下次启动再解析回 URL。
  private static let watchBookmarkKey = "watchFolderBookmark"
  private static let watchPathKey = "watchFolderPath"

  /// 当前持有授权的目录 URL,用于配对调用 stopAccessingSecurityScopedResource。
  private static var watchAccessingURL: URL?

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
    // 允许缩得很小:480x320(比例 1.5,接近默认 1180x760 的 1.55)
    self.contentMinSize = NSSize(width: 480, height: 320)

    // 沉浸式:标题栏透明 + 内容全尺寸延伸到标题栏,背景色由 Flutter 阅读背景决定,
    // 工具栏按钮(搜索/设置/目录)由 Flutter 渲染在标题栏区域。
    // 交通灯保持 macOS 默认配置(系统管理位置与显隐, 不做自定义重挂)
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden
    self.styleMask.insert(.fullSizeContentView)
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

    // 注册窗口标题通道:Flutter 侧切换窗口标题(阅读时显示小说名,返回显示应用名)
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
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // 注册自动导入目录通道:选目录 → 存 security-scoped bookmark → 下次启动恢复授权。
    // 沙盒下没有 bookmark,重开 App 再读该目录会被系统拒绝,所以这是必需的。
    let watchChannel = FlutterMethodChannel(
      name: "com.reader.novelReader/watchfolder",
      binaryMessenger: flutterViewController.engine.binaryMessenger,
    )
    watchChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "pick":
        MainFlutterWindow.pickWatchFolder(result: result)
      case "restore":
        result(MainFlutterWindow.restoreWatchFolder())
      case "clear":
        MainFlutterWindow.clearWatchFolder()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }

  /// 窗口尺寸变化时保存 frame(位置 + 大小)。
  @objc private func windowDidResize(_ notification: Notification) {
    UserDefaults.standard.set(NSStringFromRect(self.frame), forKey: Self.frameKey)
  }

  // MARK: - 自动导入目录

  /// 弹出目录选择框,保存 bookmark 后返回目录路径。用户取消返回 nil。
  private static func pickWatchFolder(result: @escaping FlutterResult) {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = true
    panel.prompt = "选择"
    panel.message = "选择存放小说的文件夹,之后每次启动会自动扫描其中的 epub / txt"

    panel.begin { response in
      guard response == .OK, let url = panel.url else {
        result(nil)
        return
      }
      do {
        let bookmark = try url.bookmarkData(
          options: .withSecurityScope,
          includingResourceValuesForKeys: nil,
          relativeTo: nil,
        )
        UserDefaults.standard.set(bookmark, forKey: watchBookmarkKey)
        UserDefaults.standard.set(url.path, forKey: watchPathKey)

        // 换目录时释放上一个目录的授权,避免持有多个 sandbox extension
        watchAccessingURL?.stopAccessingSecurityScopedResource()
        _ = url.startAccessingSecurityScopedResource()
        watchAccessingURL = url

        result(url.path)
      } catch {
        result(FlutterError(
          code: "bookmark_failed",
          message: "无法保存目录授权:\(error.localizedDescription)",
          details: nil,
        ))
      }
    }
  }

  /// 解析已保存的 bookmark 并恢复访问权限,返回目录路径。无配置或失效返回 nil。
  private static func restoreWatchFolder() -> String? {
    guard let data = UserDefaults.standard.data(forKey: watchBookmarkKey) else {
      return nil
    }

    var stale = false
    do {
      let url = try URL(
        resolvingBookmarkData: data,
        options: [.withSecurityScope],
        relativeTo: nil,
        bookmarkDataIsStale: &stale,
      )

      if watchAccessingURL?.path != url.path {
        watchAccessingURL?.stopAccessingSecurityScopedResource()
        _ = url.startAccessingSecurityScopedResource()
        watchAccessingURL = url
      }

      // 目录被移动/改名后 bookmark 会变 stale,顺手刷新一份
      if stale, let fresh = try? url.bookmarkData(
        options: .withSecurityScope,
        includingResourceValuesForKeys: nil,
        relativeTo: nil,
      ) {
        UserDefaults.standard.set(fresh, forKey: watchBookmarkKey)
        UserDefaults.standard.set(url.path, forKey: watchPathKey)
      }

      var isDir: ObjCBool = false
      guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
            isDir.boolValue
      else {
        return nil
      }
      return url.path
    } catch {
      return nil
    }
  }

  /// 关闭自动导入:释放授权并清除 bookmark。
  private static func clearWatchFolder() {
    watchAccessingURL?.stopAccessingSecurityScopedResource()
    watchAccessingURL = nil
    UserDefaults.standard.removeObject(forKey: watchBookmarkKey)
    UserDefaults.standard.removeObject(forKey: watchPathKey)
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
