# 常见问题

## Android 构建时报 `What went wrong: 26`

原因通常是构建时使用了 JDK 26。请切换到 JDK 17 后重新执行：

```powershell
flutter build apk --release
```

## `flutter doctor` 提示 Android licenses 未接受

执行：

```powershell
flutter doctor --android-licenses
```

同时确认 `android/local.properties` 中的 `sdk.dir` 指向正确目录。

## 为什么没有 `macos/` 目录

当前仓库尚未初始化 macOS Runner。请在 Mac 上执行：

```bash
flutter create . --platforms=macos
```

## 哪些文件不应该提交

通常不应提交：

- `*.log`
- `output/*`
- `logs/**/*.jsonl`
- `saves/*`
- `build/`
