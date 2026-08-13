# novel_reader (阅读)

Flutter macOS 小说阅读器：本地书架、EPUB 解析、分页阅读、阅读进度与设置持久化。

应用名：**阅读**

## 截图

### 书架主页
左侧侧边栏展示书籍列表与阅读进度,右侧书籍封面网格显示当前已读百分比。

<img src="assets/icon/1_compressed.jpg" width="820" alt="书架主页">

### 阅读界面
沉浸式阅读视图:顶部 macOS 标题栏 + 搜索/设置/目录按钮,正文居中显示,左右半透明翻页按钮,底部极简页码。

<img src="assets/icon/2_compressed.jpg" width="820" alt="阅读界面">

### 阅读设置
悬浮对话框:字号/行距/边距滑块、4 种背景主题(白/黄/夜/暖)、方向键控制模式(上下翻页/左右切章 或 上下切章/左右翻页)。

<img src="assets/icon/3_compressed.jpg" width="820" alt="阅读设置">

## 构建与运行

使用项目脚本（自动处理国内 pub 镜像 + Xcode 路径）：

```bash
# 构建 Release 版本到 build/macos/Bßuild/Products/Release/书架.app
bash scripts/build_macos.sh

# Debug 构建
bash scripts/build_macos.sh --debug

# 开发热重载运行
bash scripts/run_macos.sh
```

> 这两个脚本会自动设置：
> - `PUB_HOSTED_URL=https://pub.flutter-io.cn`
> - `FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn`
> - `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`（如果 Xcode.app 已安装）
>
> 不需要手动 export 环境变量。

## 目录结构

```
lib/                Flutter 业务代码（书架/分页/进度/主题）
assets/icon/        合规应用图标源文件（1024×1024, RGB 无 alpha）
macos/              Flutter 生成的 macOS 工程
scripts/            构建脚本（build_macos.sh, run_macos.sh）
```

## 应用图标

- 合规源文件位于 `assets/icon/`（暖色书本主用、夜色月光备用，均 1024×1024）
- macOS AppIcon 位于 `macos/Runner/Assets.xcassets/AppIcon.appiconset/`（已自动生成 16/32/64/128/256/512/1024 全套）
- 切换图标：编辑 `.workbuddy/scripts/apply_app_icon.py` 的 `SRC` 路径再执行；如需调整主体大小（"内边距"），编辑 `.workbuddy/scripts/redo_app_icon.py` 的 `SCALE`