# agents.md — 项目交接指南

> 本文件用于让任何 AI（或开发者）快速接手本项目。读完本文件即可理解项目结构、功能、关键实现与历史坑点，避免重复踩坑。

## 1. 项目概述

**Flutter macOS 小说阅读器（应用名：阅读 / 书架）**：本地书架 + EPUB 解析 + 在线番茄小说导入下载 + 分页阅读 + 进度/设置持久化。

- 构建产物：`build/macos/Build/Products/Release/书架.app`
- GitHub：`MX-future/novels-read`（public，SSH 认证已配置）
- 纯桌面应用（macOS），无后端；仅"在线导入番茄小说"功能会发起出网请求（沙箱已加 `network.client`）

## 2. 构建环境（本机关键，必读）

⚠️ 这两点是本机最容易踩的坑，构建前必须了解：

1. **Xcode 路径**：`xcode-select` 默认指向 `/Library/Developer/CommandLineTools`，直接 `flutter build macos` 会报 `xcrun: unable to find xcodebuild`。必须 `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`（Xcode 16.4 已装）。
2. **pub.dev 网络**：默认代理下 502（`Proxy failed to establish tunnel`）。必须用国内镜像：`export PUB_HOSTED_URL=https://pub.flutter-io.cn FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn`。

### 构建命令

```bash
# Release 构建（推荐，脚本已自动处理上面两个坑）
bash scripts/build_macos.sh

# Debug 构建
bash scripts/build_macos.sh --debug

# 热重载运行
bash scripts/run_macos.sh
```

`build_macos.sh` 还包含 **post-build 钩子**：用 `iconutil` 重新打包 icns（修复 Xcode 资产目录把 PNG 错标 RGBA 的 bug，见坑 #3）。构建后脚本会输出 `==> icns 已用 iconutil 重新打包`。

## 3. 项目结构

```
lib/
├── main.dart                    # 入口，启动时加载设置/进度
├── models/book.dart             # Book / Chapter 模型（id, title, author, chapters, coverPath）
├── screens/
│   ├── library_screen.dart      # 书架页：侧边栏 + 书库网格 + 空状态 + 打开书切换 ReaderScreen
│   ├── fanqie_import_dialog.dart# 番茄在线导入对话框（链接/ID → 确认书籍与范围 → 可选登录Cookie → 进度下载）
│   └── reader_screen.dart       # 阅读页（1560 行，核心）：沉浸式布局 + 分页 + 键盘 + 搜索/设置/目录对话框
├── services/
│   ├── epub_service.dart        # EPUB 解析（epubx）：章节内容 → 纯文本、封面、元数据；另暴露 saveBook/saveCover 供番茄入库
│   ├── fanqie/
│   │   ├── fanqie_service.dart  # 番茄直连服务：目录/书页/正文抓取 + PUA 解码 + 范围下载(续传/跳过VIP/落盘)
│   │   └── fanqie_map.dart      # 362 项 PUA 码位→汉字 静态解码表 + decodeText/decodeChapterHtml
│   ├── progress_store.dart      # 进度持久化（JSON 文件 + SharedPreferences key）
│   └── reader_settings.dart     # 阅读设置（ValueNotifier 全局共享 + SharedPreferences 持久化）
├── theme/app_theme.dart         # 书架页主题常量（AppTheme：background/sidebarBg/primary 等）
├── utils/
│   ├── html_text.dart           # HTML → 纯文本（保留段落结构）
│   └── pagination.dart          # TextPaginator：TextPainter 按行分页
└── widgets/
    ├── book_grid_item.dart      # 书库网格卡片（封面 + 书名 + 进度条）
    └── book_sidebar_tile.dart   # 侧边栏书籍条目（进度百分比）
macos/
└── Runner/
    ├── MainFlutterWindow.swift  # 原生窗口：标题栏透明 + 全尺寸内容 + setTitle MethodChannel
    ├── AppDelegate.swift
    └── Info.plist               # CFBundleName=书架（PRODUCT_NAME）
assets/
└── icon/                        # 应用图标源（icon_warm_books.png 主用）+ README 截图
scripts/
├── build_macos.sh               # Release/Debug 构建 + icns 重打包
└── run_macos.sh                 # flutter run
test/                            # 101 个用例（pagination/settings/progress/html/models/widget/fanqie）
```

## 4. 功能点

### 书架页（library_screen.dart）
- 左侧侧边栏：书籍列表（含阅读进度 %），支持折叠；导入 EPUB 按钮（file_picker）+ 在线导入(番茄)次级按钮
- 右侧书库网格：封面 + 书名 + 阅读进度条（动态列数，`max(3, width/180)`）
- 键盘：`←/→` 翻页（书架网格）、`↑/↓` 切换章节、空格翻页
- 顶部留出 macOS 交通灯区域（40px）

### 在线导入番茄小说（services/fanqie/ + screens/fanqie_import_dialog.dart）
- 入口：侧边栏"在线导入(番茄)"按钮 / 空书架中央次级按钮；无关键词搜索（官方搜索被风控，见坑 #14）
- 流程：粘贴书籍链接或纯 ID → `fetchBookMeta`（目录 + 书页元信息）→ 展示封面/书名/作者/字数/章数/VIP 章数 → 选起始~结束章（留空=全本）→ `downloadBook` 下载入架
- 书籍落盘复用 `EpubService.saveBook/saveCover`，Book.id 带 `fanqie_` 前缀、`sourcePath='fanqie://{bookId}'`，自动出现在书架
- 容错：付费/VIP 章自动跳过；单章失败重试 2 次后计入 failed；每下载 10 章落盘一次，取消/中断后已下载部分保留，再次导入同名书自动续传

### 阅读页（reader_screen.dart）—— 核心
- **沉浸式布局**：macOS 标题栏透明（`titlebarAppearsTransparent + fullSizeContentView + titleVisibility.hidden`），Flutter 内容延伸至标题栏；顶部工具栏（返回/书名/搜索/设置/目录）**仅鼠标移到顶部 100px 区域时显示**，移开立即隐藏
- **章节标题**：每页顶部居中加粗（18px），分页时预留标题高度
- **正文分页**：TextPaginator 按行分页，正文填满整页
- **翻页按钮**：左右常驻半透明（alpha 0.35），hover 变明显
- **底部极简页码**：左 `X / Y 页`、右 `本章还剩 N 页`，常驻透明显示
- **4 种背景主题**：白 / 黄(sepia 橙金) / 夜 / 暖(暖白)，设置页切换，持久化
- **设置对话框**：字号(14-24)/行距(1.4-2.4)/边距(20-160)滑块 + 主题选择 + 方向键模式
- **方向键模式**（ArrowKeyMode）：`上下翻页·左右切章` 或 `上下切章·左右翻页`；空格/PageUp/PageDown 始终翻页，Esc 返回书架
- **搜索**：章节内关键字搜索 → 跳转到对应页，高亮 8 秒
- **目录**：打开时自动滚动定位到当前章节（居中显示）
- **窗口标题**：打开书 → MethodChannel 设置窗口标题为书名；返回书架 → 恢复"书架"
- **进度保存**：章节 + 页码，防抖写入，切章/退出时 flush

## 5. 关键技术实现

### 分页（utils/pagination.dart）
`TextPaginator.paginate(text, maxWidth, maxHeight, style)`：
- TextPainter 布局全文 → `computeLineMetrics()` 获取每行（ascent/descent/baseline）
- 按行分组：每页从 `lineTopY` 开始，**行尾（lineTopY + line.height）<= 页底**的行归入本页
- 用 `getLineBoundary` 截取字符范围，支持空行/连续换行

### 设置全局共享（services/reader_settings.dart）
- `ReaderSettings.current` 是 `ValueNotifier`，全局监听
- `ReaderSettings.save()` 更新 notifier + 写 SharedPreferences；阅读页 `ValueListenableBuilder` 响应
- **枚举 index 持久化**：`theme`/`arrowKeyMode` 存 index，新增枚举值**必须放末尾**（见坑 #11）

### 原生通信（MethodChannel）
- channel 名：`com.reader.novelReader/window`
- `setTitle(String)`：切换窗口标题（macOS 侧 `self.title = title`）
- macOS 侧在 `MainFlutterWindow.awakeFromNib` 注册 handler

### 番茄正文解码（services/fanqie/fanqie_map.dart）
- 番茄网页版正文做**字体混淆**：约 1/3 字符是 PUA 私用区码位（U+E000–U+F8FF），浏览器靠 @font-face 的字形表显示
- **关键发现**：PUA 码位十进制 == 该字在番茄全局字体里的字形编号，且映射站点级稳定（同一书两章共用字体，362/362 完全一致）
- 因此解码 = 纯静态查表：`FanqieMap.puaToChar[codePoint]`（362 项，源自 tianhuoDD/fanqie-novel-decryptor 的 font_map.py），**无需下载/解析 woff**。`decodeText` 替换字符、`decodeChapterHtml` 先解码再走 `HtmlText.convert` 去标签成段落
- ⚠️ 番茄若更换/分片字体，表会失效——届时需重新抓字体重生成表

### 番茄网络层（services/fanqie/fanqie_service.dart）
- 匿名可用的三个端点（实测 2026-09-03）：目录 `GET /api/reader/directory/detail?bookId=`、书页 `GET /page/{bookId}`（SSR）、正文 `GET /reader/{itemId}`（SSR 内嵌 `chapterData.content`）
- **VIP/付费章无匿名通道**：匿名请求 VIP 章时服务端只回约 200 字符试读（`content` 长度 200、而 `chapterWordNumber` 是全章真实字数，如 2484）。要下载 VIP 必须在导入对话框填入**浏览器登录番茄后的 Cookie**（带登录态请求 → 服务端按账号阅读权限返回全文）
- 正文完整性用 `isPreviewText` 判定：已知字数时明文 < `chapterWordNumber`×50% 判为试读（不入库）；字数未知时锁定章按 <400 字判。真实数据验证：VIP 匿名 155/2484→preview，免费章 2870/2870→全文
- 带 Cookie 时若 SSR 仍只给试读，会再尝试正文 JSON 接口 `GET /api/reader/full?itemId=`（匿名恒 200 空 body，仅带登录 Cookie 才可能有内容）作兜底
- 解析：HTML 里嵌的 JSON 用自研平衡括号扫描器 `readJsonObject/extractObjectWithKey` 抽取（按 `"key"` 找下一个 `{`，字符串内 `{}`/转义不误判），避免引入重型解析
- 章节抓取限速 350ms、单章 20s 超时、失败重试 2 次，避免触发限流

### 键盘控制
- `Focus(onKeyEvent: _handleKeyEvent)` 全局捕获
- 方向键按 `arrowKeyMode` 分发；Space/PageUp/PageDown 固定翻页；Esc 返回

## 6. 踩过的坑（重要！）

### 构建/环境
1. **xcode-select 指向 CommandLineTools** → `xcrun: unable to find xcodebuild`。必须 `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`。
2. **pub.dev 502** → 必须用国内镜像 `PUB_HOSTED_URL/FLUTTER_STORAGE_BASE_URL`。

### 图标（macOS）
3. **Xcode 资产目录把 PNG 错标 RGBA** → 生成的 `AppIcon.icns` 被识别为 256×256 + hasAlpha=yes，Dock/Launchpad 渲染异常。修复：`iconutil` 从 PNG iconset 重打包为 1024×1024 无 alpha 的 icns（已固化进 build_macos.sh）。
4. **"PNG" 实为 WebP**：在线图标生成器导出的 `*-mac.png` 签名是 `RIFF...WEBP`。PIL 能读但 **Xcode/iconutil 不认** → icns 错误压缩成 256×256、alpha 丢失、图标变直角。检测：`file xxx.png` 看签名；修复：PIL `Image.open().save('PNG')` 转真 PNG。AppIcon.appiconset 必须放真正的 RGBA PNG。
5. **多 .app 副本图标坑**：`flutter run`(Debug) 和 `flutter build macos`(Release) 生成两份同 bundle ID 的 .app。**macOS 按 bundle ID 注册 Launch Services**，Dock 图标可能来自任意一个版本（通常是旧的 Debug）。改图标后必须：同步 Release 的 `AppIcon.icns`+`Assets.car` 到 Debug → `lsregister -f` 重新注册 → 删缓存重启 Dock。

### 阅读分页
6. **分页文字截断/遮挡**（重要）：
   - 根因 A：分页用整个内容区高度，但页面渲染时文本上方还有章节标题（最多2行）+间距 → 文本实际可用高度更小，末行被截断。修复：分页前用 TextPainter 测量标题高度，`maxHeight = 总高 - 标题高 - 间距`。
   - 根因 B：页尾判断用"行首 < 页底"，某行行首在页内但行尾超出也会被包含 → 行尾截断。修复：改为"行尾(行首+行高) <= 页底"。

### macOS 原生（窗口/坐标系）
7. **NSView 坐标系默认原点在左下角**（`isFlipped = false`）！设置视图 y 坐标时如果按"距顶"理解，会把内容放到窗口**底部**。必须判断 `isFlipped`：flipped 用距顶距离，否则用 `高度 - 距顶 - 自身高/2`。⚠️ 这是阅读页顶部布局和交通灯反复出问题的根源。
8. **全屏时 `contentView.bounds` 滞后**：全屏切换瞬间 bounds 还是旧值，依赖它计算 y 会导致按钮瞬间跑到底部再回来。改用 `window.frame.height`（窗口 frame 更新及时）。
9. **全屏时 macOS 会强制重置交通灯按钮位置**（日志证实被系统移到左下角），自定义交通灯位置/显隐在**全屏场景无法稳定对抗系统行为**。结论：**放弃自定义交通灯，回归 macOS 默认**（系统管理位置与显隐）。
10. **沙箱限制日志写入**：Release 版启用了 app-sandbox（`com.apple.security.app-sandbox=true`），`/tmp` 和真实 `~/Library/Logs` 不可写！`NSHomeDirectory()` 返回**容器路径**（`~/Library/Containers/com.reader.novelReader/Data/`）。调试日志要写到容器内路径才能读到。

### 设置持久化
11. **枚举加值破坏存档**：`theme` 存的是 `enum.index`，在**中间插入**新枚举值会让旧存档的 index 指向错误主题。新增枚举值**必须放在末尾**（`ReaderTheme.warm` 就是加在 dark 之后）。

### 番茄在线导入
12. **出网需沙箱权限**：macOS app-sandbox 默认禁止联网，导入番茄报网络错误先查 `macos/Runner/{DebugProfile,Release}.entitlements` 是否含 `com.apple.security.network.client`（Debug 版还要看 DebugProfile 那份）。
13. **目录 JSON 是两层嵌套**：目录接口返回 `{code,message,data:{allItemIds,volumeNameList,chapterListWithVolume}}`，章节在 `data.chapterListWithVolume`（数组的数组：每卷=章对象数组）。**不要把顶层直接当目录解析**。章对象字段：`itemId/title/needPay/isChapterLock/isPaidStory/isPaidPublication/volume_name/realChapterOrder`。
14. **关键词搜索不可用（无后端）**：网页搜索接口 `search_book/v1` 匿名请求被字节安全 SDK（secsdk/captcha）风控，返回 HTTP 200 空 body；因此只能"链接/ID 导入"，不支持搜索。若将来要搜索，需走后端 + 风控（如云函数带 cookie）。
15. **封面 URL 常无 scheme**：书页 SSR 的 `thumbUri` 可能是 `//p6-...`，`Uri.parse` 会失败；入库前用 `_normalizeUrl` 补 `https:`。
16. **`originalAuthors` 是数组**：`[{AuthorId,AuthorName}]`，不是字符串；取作者优先 `authorName`，缺失时遍历该数组。
17. **正文 PUA 解码依赖静态表**：若发现整本正文解出来是乱码/方块，先怀疑番茄更换字体 → 需重新生成 `fanqie_map.dart`（抓 reader SSR 内嵌字体或用 tianhuoDD 字典比对）。
18. **VIP 下载必须带登录 Cookie，且是"权限换全文"不是破解**：匿名/无效 Cookie 下服务端只给约 200 字试读，`/api/reader/full` 匿名恒 200 空 body。参考仓库（POf-L/Fanqie-novel-Downloader）能下 VIP 是因其内置浏览器登录番茄账号（可到 SVIP）后自动同步 Cookie。本 App 落地方案：导入对话框展开"登录 Cookie(可选)"粘贴浏览器 Cookie（F12 → Network → 任意请求 → Cookie 请求头），请求自动带 `Cookie` 头；账号无该章权限时仍跳过。Cookie 仅内存传递、不落盘、不入书架。

## 7. 测试

```bash
flutter test   # 101 个用例，全部通过
```

覆盖：pagination（分页行高/拼接还原/空行）、reader_settings（默认值/copyWith/序列化/save-load/非法索引 clamp）、progress_store（JSON 结构/损坏容错）、html_text（段落提取）、fanqie_map（表完整性/解码/去标签）、fanqie_service（parseBookId/parseChapters 卷拼接与 VIP 标记/extractObjectWithKey 与 readJsonObject 的引号-转义-花括号扫描/normalizeCookie/isPreviewText 试读判定/hasLockedMark）、models、widget 冒烟。

## 8. 常见任务指引

| 任务 | 位置 |
|---|---|
| 改书架网格列数/卡片样式 | `lib/widgets/book_grid_item.dart` + `library_screen.dart` 的 GridView |
| 调整阅读分页（行距/字号生效） | `reader_settings.dart` 默认值 + `reader_screen.dart` 的 `_textStyle()` |
| 新增背景主题 | `reader_settings.dart` 的 `ReaderTheme`（**放末尾**）+ colors/label |
| 调整顶部工具栏显示逻辑 | `reader_screen.dart` 的 `_showTopBar/_hideTopBar` + onHover 区域（dy<100） |
| 改窗口最小尺寸/标题栏 | `MainFlutterWindow.swift`（contentMinSize / titlebar 配置） |
| 改应用图标 | `assets/icon/` 源图 → `.workbuddy/scripts/apply_app_icon.py`（SCALE 调主体大小） |
| 新增键盘快捷键 | `reader_screen.dart` 的 `_handleKeyEvent` |
| 加出网请求/改番茄端点 | `lib/services/fanqie/fanqie_service.dart`（host/端点/UA/限速都在顶部） |
| 番茄正文解不开（乱码） | 重新生成 `lib/services/fanqie/fanqie_map.dart`（字体表更新，见坑 #17） |
| 改在线导入对话框样式/流程 | `lib/screens/fanqie_import_dialog.dart` |

## 9. 注意事项

- 应用名显示为"书架"（PRODUCT_NAME），但 README/宣传叫"阅读"，勿混用
- 书架页打开书后由 `_buildMainArea()` 直接切换为 `ReaderScreen`（非路由跳转），返回用 `onBack` 回调
- 阅读页 `_pagesCache` 按章节缓存分页结果，字号/边距等设置变化时清缓存重新分页
- 书籍数据目录：`~/Library/Containers/com.reader.novelReader/Data/Library/Application Support/novel_reader_books/`（沙箱容器内），每书一个 `{id}.json` + 封面；番茄书 id 形如 `fanqie_7663...`
- git 用户：zhiqiang.shen / zhiqiang.shen@nufront.com；远程：`git@github.com:MX-future/novels-read.git`
