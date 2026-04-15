# API 文档

这不是一个对外发布的 SDK 仓库，所以这里记录的是项目内部最关键的运行时入口。

## `createBackendApi({required ConfigStore store})`

- 文件：`lib/src/services/backend_api_io.dart`
- 说明：根据平台和运行模式选择实际后端实现

## `LocalBackendApi.create({required ConfigStore store, LocalBackendPaths? paths})`

- 文件：`lib/src/services/local_backend_api.dart`
- 说明：创建本地集成后端
- 负责：
  - 世界包扫描
  - 世界包加载
  - 存档读写
  - 游戏推进
  - 语音与封面读取

## `ConfigStore.open(...)`

- 文件：`lib/src/services/config_store.dart`
- 说明：初始化配置存储
- 能力：
  - 配置读写
  - SQLite 持久化
  - 旧版 SharedPreferences 配置迁移

## `LocalGameEngine`

- 文件：`lib/src/services/local_game_engine.dart`
- 说明：本地叙事主引擎
- 负责：
  - 开局
  - 回合推进
  - 行动提交
  - 存档恢复

## `LocalWorldPkg.inspect(File file)`

- 文件：`lib/src/services/local_worldpkg.dart`
- 说明：轻量检查 `.wpkg` 元数据，避免资料库全量解包

## `LocalWorldPkgBuilder.buildFromTextFile(String filePath)`

- 文件：`lib/src/services/local_worldpkg_builder.dart`
- 说明：从 `.txt` 或 `.md` 构建 `.wpkg`
