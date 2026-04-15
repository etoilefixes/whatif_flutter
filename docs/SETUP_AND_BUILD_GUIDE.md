# 环境配置与打包教程

这份文档面向第一次接手项目的人，目标是让你能从零完成：

1. 开发环境配置
2. Windows 运行
3. Web 运行
4. Android APK 打包
5. macOS 环境准备与桌面构建

---

## 1. 项目概览

当前仓库是一个 Flutter 客户端工程，名称为 `flutter_client`。

主要能力包括：

- Flutter 界面
- 本地集成运行时
- `.wpkg` 内容包导入与生成
- `sqflite` 本地持久化
- Android APK 打包

当前已存在的平台目录：

- `android/`
- `windows/`
- `web/`

当前尚未初始化：

- `macos/`

这意味着：

- Windows、Web、Android 可以直接按本文构建
- macOS 需要先在 Mac 上初始化平台目录，再进行桌面打包

---

## 2. 基础环境要求

### 2.1 通用要求

建议使用以下基础环境：

- Flutter 3.41.x 或兼容版本
- Dart 3.11.x 或兼容版本
- Git

检查方式：

```powershell
flutter --version
dart --version
git --version
```

### 2.2 Flutter 依赖安装

进入项目目录后执行：

```powershell
flutter pub get
```

如果依赖解析成功，说明项目依赖已准备完成。

---

## 3. 模式说明

项目支持两种主要运行模式。

### 3.1 默认模式

默认模式下走项目当前的默认后端选择逻辑。

直接运行：

```powershell
flutter run -d windows
```

### 3.2 集成模式

如果你想强制使用本地 Dart 集成运行时，可以设置环境变量：

Windows PowerShell：

```powershell
$env:WHATIF_BACKEND_MODE="integrated"
flutter run -d windows
```

macOS / Linux shell：

```bash
export WHATIF_BACKEND_MODE=integrated
flutter run -d macos
```

说明：

- `integrated` 模式不依赖远程 HTTP sidecar
- 更适合本地一体化调试和 APK 场景

---

## 4. Windows 开发环境配置

### 4.1 必备环境

Windows 下建议准备：

- Flutter SDK
- Git
- Chrome 或 Edge

如果你只做 Flutter 代码调试，优先保证 `flutter doctor` 中 Flutter 本身正常。

检查：

```powershell
flutter doctor -v
```

### 4.2 运行 Windows 桌面版

```powershell
flutter run -d windows
```

如果要使用集成模式：

```powershell
$env:WHATIF_BACKEND_MODE="integrated"
flutter run -d windows
```

### 4.3 常用调试命令

```powershell
flutter analyze
flutter test
flutter run -d chrome
flutter run -d windows
```

---

## 5. Web 运行

项目已包含 Web 平台目录，可以直接在浏览器运行。

### 5.1 Chrome

```powershell
flutter run -d chrome
```

### 5.2 Edge

```powershell
flutter run -d edge
```

说明：

- Web 端会使用兼容的存储后端
- 某些桌面或系统级能力在 Web 上不可用

---

## 6. Android 环境与 APK 打包

## 6.1 两种 Android 打包方式

你可以用两种方式打包：

### 方式 A：直接使用 `flutter build apk`

```powershell
flutter build apk --release
```

### 方式 B：使用仓库脚本

项目已带脚本：

- `tool/prepare_local_android.ps1`
- `tool/build_apk_local.ps1`

示例：

```powershell
.\tool\build_apk_local.ps1 -Mode debug
.\tool\build_apk_local.ps1 -Mode release
```

如果你需要在一台全新机器上把 Android 工具链也落到项目目录里，优先阅读并使用：

```powershell
.\tool\prepare_local_android.ps1
```

## 6.2 Android SDK / JDK 注意事项

这次打包验证中有一个实际踩坑点：

- 系统全局 `java` 是 JDK 26
- 当前 Android/Gradle/Kotlin 组合在 JDK 26 下会直接失败
- 构建 APK 时应使用 JDK 17

已经验证可用的方式是：

```powershell
$env:JAVA_HOME='D:\code\WhatIf\flutter_client\jdk-17\jdk-17.0.18+8'
$env:Path = 'D:\code\WhatIf\flutter_client\jdk-17\jdk-17.0.18+8\bin;' + $env:Path
flutter build apk --release
```

如果你的机器不是这个路径，请替换成自己的 JDK 17 实际路径。

### 推荐规则

- 开发时可用系统 JDK
- Android 构建时强制切到 JDK 17

## 6.3 Android 本地属性文件

Android 构建依赖 `android/local.properties`，里面通常包含：

```properties
sdk.dir=D:\\path\\to\\android_sdk
flutter.sdk=D:\\path\\to\\flutter
```

如果你的 Flutter SDK 或 Android SDK 不在默认位置，需要更新这个文件。

## 6.4 打包输出位置

Release APK 默认输出到：

```text
build/app/outputs/flutter-apk/app-release.apk
```

Debug APK 通常输出到：

```text
build/app/outputs/flutter-apk/app-debug.apk
```

---

## 7. macOS 环境与构建

## 7.1 当前状态

当前仓库没有 `macos/` 目录，所以不能在这台 Windows 机器上直接打 macOS 桌面包。

但你仍然可以在 Mac 上把这个项目初始化成可构建的 macOS Flutter 工程。

## 7.2 Mac 上的基础依赖

在 macOS 上建议准备：

- Flutter SDK
- Xcode
- CocoaPods
- Git

检查：

```bash
flutter doctor -v
```

## 7.3 初始化 macOS 平台

在 Mac 上进入项目根目录后执行：

```bash
flutter create . --platforms=macos
```

这一步会生成：

- `macos/`

注意：

- 如果仓库后续已经加入了正式的 `macos/` 目录，就不需要再执行这一步
- 执行前建议确认当前工作区干净，避免生成文件和现有改动混在一起

## 7.4 安装依赖并运行 macOS 桌面版

```bash
flutter pub get
flutter run -d macos
```

如果要启用集成模式：

```bash
export WHATIF_BACKEND_MODE=integrated
flutter run -d macos
```

## 7.5 构建 macOS Release

```bash
flutter build macos --release
```

常见产物位置：

```text
build/macos/Build/Products/Release/
```

---

## 8. 常见问题

## 8.1 `flutter doctor` 显示 Android licenses 未接受

先确认你的 Android SDK 目录有效，再执行：

```powershell
flutter doctor --android-licenses
```

如果你使用的是项目内工具链，也要确认 `sdk.dir` 指向的是正确目录。

## 8.2 Android 构建时报 `What went wrong: 26`

这通常是因为构建过程使用了 JDK 26。

解决方式：

- 切换到 JDK 17
- 重新执行 `flutter build apk --release`

## 8.3 Web 能跑，Windows 或 Android 不能跑

优先检查：

1. `flutter doctor -v`
2. `android/local.properties`
3. `JAVA_HOME`
4. 当前是否设置了 `WHATIF_BACKEND_MODE`

## 8.4 `.wpkg`、日志、存档是否应该提交到 Git

一般不应该。

项目已经通过 `.gitignore` 忽略了大部分运行时产物，例如：

- `*.log`
- `output/*`
- `logs/**/*.jsonl`
- `saves/*`
- `build/`

---

## 9. 推荐工作流

### 日常开发

```powershell
flutter pub get
flutter analyze
flutter test
flutter run -d windows
```

### Web 调试

```powershell
flutter run -d chrome
```

### Android Release 打包

```powershell
$env:JAVA_HOME='D:\path\to\jdk17'
$env:Path = 'D:\path\to\jdk17\bin;' + $env:Path
flutter build apk --release
```

### macOS 机器上的桌面打包

```bash
flutter create . --platforms=macos
flutter pub get
flutter build macos --release
```

---

## 10. 相关文档

- [README](../README.md)
- [项目架构说明](./ARCHITECTURE.md)
- [集成运行时说明](./INTEGRATED_RUNTIME.md)
- [`.wpkg` 生成、持久化与平板优化说明](./WPKG_GENERATION_AND_PERSISTENCE.md)
