# `.wpkg` 生成、持久化与平板优化说明

## 1. 目标

这个文档说明三件事：

1. `.wpkg` 文件现在是如何生成的。
2. 项目目前如何用 `sqflite` 做数据存储和持久化。
3. Android APK，尤其是平板设备上的性能优化方向和已落地实现。

## 2. `.wpkg` 是什么

`.wpkg` 本质上是一个 Zip 包，里面包含一个可游玩的世界包数据集。运行时不会直接依赖原始小说文本，而是消费 `.wpkg` 中的结构化数据。

当前包内的核心目录结构如下：

```text
metadata.json
source/full_text.txt
source/sentences.json
events/events.json
lorebook/characters.json
lorebook/locations.json
lorebook/items.json
lorebook/knowledge.json
transitions/transitions.json
cover.png / cover.jpg / cover.webp
images/<event-image>
```

对应代码入口：

- 生成：`lib/src/services/local_worldpkg_builder.dart`
- 读取：`lib/src/services/local_worldpkg.dart`
- 集成后端调度：`lib/src/services/local_backend_api.dart`

## 3. `.wpkg` 当前生成流程

### 3.1 输入来源

当前本地生成支持：

- `.txt`
- `.md`

入口方法：

- `LocalWorldPkgBuilder.buildFromTextFile(...)`

### 3.2 生成流水线

当前实现是“启发式为主，LLM 增强为辅”的本地流水线：

1. 读取原始文本文件。
2. 清洗章节标题、空行和格式噪音。
3. 自动识别中英文主语言。
4. 做句子切分，生成 `source/sentences.json`。
5. 按句子块生成事件，构建 `events/events.json`。
6. 生成 lorebook：
   - 角色
   - 地点
   - 物品
   - 知识
7. 根据事件和 lorebook 生成 `transitions/transitions.json`。
8. 如果配置了 LLM 抽取增强器，则对事件和 lorebook 做二次增强。
9. 最后统一打成 Zip，并以 `.wpkg` 扩展名输出到 `output/`。

### 3.3 关键技术点

- 文本切分逻辑在 `LocalWorldPkgBuilder._splitSentences(...)`
- 事件构建逻辑在 `LocalWorldPkgBuilder._buildEvents(...)`
- Lorebook 构建在 `local_lorebook_builder.dart`
- Transition 构建在 `local_transition_builder.dart`
- 可选的 LLM 增强在 `local_worldpkg_extraction_enhancer.dart`

## 4. `.wpkg` 的运行时消费方式

### 4.1 包扫描

现在库页不再每次都完整加载所有 `.wpkg`。新的流程是：

1. `LocalBackendApi._scanPackages()` 扫描 `output/` 目录。
2. 优先读取 SQLite 中缓存的包索引。
3. 只有新增或修改过的 `.wpkg` 才重新做元数据检查。
4. 真正进入游戏或读取封面时，才按需 `LocalWorldPkg.load(...)` 完整加载。

这次新增了一个轻量入口：

- `LocalWorldPkg.inspect(File file)`

它只负责提取标题、大小和封面存在性，避免库页首屏把所有 Zip 全量解开。

### 4.2 游戏阶段

运行时主链路：

1. `LocalBackendApi.loadWorldPkg(...)`
2. `LocalGameEngine.setWorld(...)`
3. `startGameStream / continueGameStream / submitActionStream`
4. 游戏推进过程中读取事件、图片、转场、Lorebook 和记忆压缩数据

## 5. `sqflite` 持久化实现

## 5.1 当前落地范围

这次已经把以下数据切到 SQLite：

- 应用设置
- 模型提供商配置
- LLM 配置
- 语音配置
- 最近选择的世界包
- 游戏存档快照
- `.wpkg` 包索引缓存

`.wpkg` 二进制文件本身仍然保留在文件系统中，不存进数据库。

## 5.2 存储层结构

新增文件：

- `lib/src/services/storage_backend_contract.dart`
- `lib/src/services/storage_backend.dart`
- `lib/src/services/storage_backend_io.dart`
- `lib/src/services/storage_backend_stub.dart`

分层如下：

- `ConfigStore`
  - 业务层统一入口
- `StorageBackend`
  - 存储抽象
- `SqliteStorageBackend`
  - IO 平台上的 `sqflite` 实现
- `SharedPrefsStorageBackend`
  - Web / stub 场景兼容实现

## 5.3 SQLite 表设计

当前表结构：

```sql
settings(
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at INTEGER NOT NULL
)

saves(
  slot INTEGER PRIMARY KEY,
  metadata_json TEXT NOT NULL,
  state_json TEXT NOT NULL,
  updated_at INTEGER NOT NULL
)

packages(
  filename TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  size INTEGER NOT NULL,
  has_cover INTEGER NOT NULL,
  modified_at INTEGER NOT NULL,
  indexed_at INTEGER NOT NULL
)
```

数据库打开时启用了：

- `PRAGMA journal_mode=WAL`
- `PRAGMA synchronous=NORMAL`

这对 Android 平板上的频繁读取、快速刷新和较长会话更友好。

## 5.4 存档迁移策略

当前存档策略是“SQLite 主存储 + 文件兼容兜底”：

1. 新存档写入 SQLite。
2. 同时保留旧的 `saves/save_xxx/{state.json, metadata.json}` 写法。
3. 加载存档时优先读 SQLite。
4. 如果 SQLite 没有，再回退读取旧文件。
5. 扫描到旧文件存档时，会自动迁移回 SQLite。

对应代码：

- `ConfigStore.saveGameSnapshot(...)`
- `ConfigStore.listSavedGames(...)`
- `ConfigStore.getSavedGame(...)`
- `LocalGameEngine.listSaves()`
- `LocalGameEngine.saveGame(...)`
- `LocalGameEngine.loadGame(...)`

这样做的好处是：

- 老存档不丢
- 测试和已有目录结构不需要一次性推翻
- 可以逐步把运行时从同步文件 IO 迁到结构化存储

## 5.5 配置迁移策略

`ConfigStore.open(...)` 现在会在首次打开时尝试迁移旧的 `SharedPreferences` 数据，包括：

- `locale`
- `backend_url`
- `voice_config`
- `llm_config`
- `last_pkg`
- 旧版 `api_keys`
- 新版 `model_providers`

这保证已有用户升级后不会丢配置。

## 6. Android APK / 平板优化

## 6.1 这次已经落地的优化

### 6.1.1 库页扫描优化

- 包列表改为 SQLite 索引缓存。
- 只有变更文件才重新检查元数据。
- 真正打开包时才做完整 `load`。

效果：

- 资料库首屏更快
- 世界包多时不会每次都卡一遍

### 6.1.2 封面读取优化

- 资料库页增加封面 `Future` 缓存。
- Grid 项加了 `RepaintBoundary`。
- Grid 设置更适合平板的断点和 `cacheExtent`。

效果：

- 滚动时重复请求封面更少
- 卡片重绘范围更小

### 6.1.3 剧情页滚动优化

- 流式输出时改成“每帧最多滚一次”
- 长距离时直接 `jumpTo`，避免每个 chunk 都做动画
- 故事列表增加 `cacheExtent`
- 列表区域加 `Scrollbar` 和 `RepaintBoundary`

效果：

- 长文本流式输出时明显更稳
- Android 平板上掉帧和滚动抖动会少很多

### 6.1.4 平板宽屏布局

已调整：

- `StartPage` 支持平板双栏
- `LibraryPage` 支持更大的网格断点
- `GameplayPage` 支持宽屏双区布局

效果：

- 平板横屏不再是单窄列
- 操作区和故事区分离，减少遮挡与频繁布局抖动

### 6.1.5 同步 IO 降低

存档读写从原来的大量同步文件 IO，改成：

- SQLite 主读写
- 文件回退时也尽量走异步 IO

这对 Flutter 主 isolate 的响应更有帮助。

## 6.2 下一步技术方向

如果后续继续深挖 Android / 平板体验，建议按这个顺序推进：

### 方向 A：把 `.wpkg` 解析继续异步化

当前已经做到“只检查变化包”，下一步建议：

1. 把 Zip 元数据检查放到 isolate。
2. 对超大世界包增加封面缩略图缓存表。
3. 对事件图片引入磁盘缓存或按尺寸缓存。

### 方向 B：把存档拆成结构化列

目前 `saves` 还是 `metadata_json + state_json` 方案，优点是迁移快。下一步可以继续拆：

- `slot`
- `save_time`
- `worldpkg_title`
- `worldpkg_filename`
- `phase`
- `turn`
- `player_name`

好处：

- 列表查询更快
- 后续可做筛选、排序、统计

### 方向 C：分离剧情流与控制流 rebuild

当前剧情页已经做了布局拆分，但还可以继续做：

1. 把故事流区域拆成单独状态源。
2. 操作按钮区只监听必要字段。
3. 让背景图层和文本层进一步解耦。

### 方向 D：平板专项交互

建议增加：

- 横屏常驻操作面板
- 更大的默认点击热区
- 外接键盘快捷键
- 双栏模式下的固定存档面板

## 7. 结论

当前项目已经完成了三个重要转向：

1. `.wpkg` 从“可导入文件”升级为“有索引缓存的本地内容包”。
2. 持久化从 `SharedPreferences + 文件目录` 升级为 `sqflite + 兼容迁移`。
3. 主页面开始按平板场景做宽屏布局和流式性能优化。

这套方案适合继续往“本地一体化 Flutter APK”方向演进，而不是把所有状态继续散落在文件系统中。
