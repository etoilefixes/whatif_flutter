# 快速开始

如果你只想尽快把项目跑起来，按这个顺序即可。

## 1. 拉取代码

```bash
git clone https://github.com/etoilefixes/whatif_flutter.git
cd whatif_flutter
```

## 2. 安装依赖

```powershell
flutter pub get
```

## 3. 运行 Windows 桌面版

```powershell
flutter run -d windows
```

## 4. 运行 Web 版

```powershell
flutter run -d chrome
```

## 5. 运行本地集成模式

```powershell
$env:WHATIF_BACKEND_MODE="integrated"
flutter run -d windows
```

## 6. 打包 Android APK

```powershell
$env:JAVA_HOME='D:\path\to\jdk17'
$env:Path = 'D:\path\to\jdk17\bin;' + $env:Path
flutter build apk --release
```

更多细节见：

- [安装指南](./installation.md)
- [配置说明](./configuration.md)
- [环境配置与打包教程](./SETUP_AND_BUILD_GUIDE.md)
