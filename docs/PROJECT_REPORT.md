# 迁移项目报告

最后更新：2026-04-14

## 一、报告结论

这个项目已经从"React/Electron 前端 + Python 后端"的旧桌面结构，迁移为"Flutter 桌面为主、Python sidecar 兼容、Dart 集成运行时逐步接管"的新结构。

如果现在把它作为一个独立项目上传到 GitHub，对外应当把它视为：

- 一个已经完成桌面端重构迁移的项目
- 一个本地优先的互动叙事系统
- 一个正在持续把后端能力迁移到 Dart 的桌面应用基础设施

原始仓库：[ypcypc/WhatIf](https://github.com/ypcypc/WhatIf)

## 二、迁移后的主成果

### 1. 客户端层面

已完成：

- Flutter 桌面端成为主客户端
- `start.py` 切换为 Flutter 桌面启动流
- React/Electron 构建链从活跃目标中移除
- `frontend/` 被降级为迁移归档目录

### 2. Dart 运行时层面

已完成：

- 本地世界包加载
- 本地文本到世界包构建
- 游戏三阶段推进
- 存档 / 读档
- 本地叙事生成
- 偏离分析与 Delta 管理
- 记忆压缩与召回
- 跨事件桥接规划
- 场景适配回退
- integrated 模式下的本地 TTS
- 主继续路径的轻量预取

### 3. 本地工具链层面

已完成：

- Flutter 桌面本地启动
- Python sidecar 本地联动
- 项目内 Android SDK / JDK / Maven 镜像组织方式
- 本地 APK 导出脚本

## 三、验证情况

本轮迁移收尾期间，已经验证：

```powershell
cd flutter_client
flutter analyze
flutter test
```

其中 Flutter 测试已经覆盖：

- 本地后端 gameplay 与存档
- 世界包本地构建
- 事件/设定增强
- 上下文注入
- 记忆压缩
- bridge planner
- scene adaptation
- prefetch 参与的运行时推进

## 四、当前推荐的对外发布描述

如果要把仓库上传到 GitHub，建议以"迁移完成后的新项目"口径对外描述，而不是旧项目前端的延续包。

推荐的表述方式：

- 这是一个以 Flutter 桌面为主的互动叙事项目
- 旧 React/Electron 前端已归档，不再是主实现
- Python sidecar 保留用于兼容和稳妥运行
- 集成式 Dart 后端已经具备主链路能力
- 项目强调本地可运行，而不是远程依赖

## 五、仍然存在的技术差距

如果目标是"能在本地稳定运行并继续开发"，当前状态已经足够。

如果目标升级为"对 Python 旧运行时实现严格 1:1 复刻"，仍然有这些差距：

- Python 版更复杂的 scene adaptation orchestration 尚未完全迁移
- Python 版更完整的 prefetch / stream takeover 行为尚未完全迁移
- 某些 agent prompt 和异常恢复分支仍有差异
- Windows 原生打包链目前不是本次交付重点，也未作为阻塞项强制收口

## 六、发布成熟度判断

### 1. 对本地桌面使用而言

已经接近发布候选状态：

- 默认 sidecar 模式适合保守使用
- integrated 模式适合继续迁移和本地实验
- 文档、目录职责和忽略规则已经按新项目形态整理

### 2. 对继续迁移而言

已经具备继续把后端逻辑迁往 Dart 的基础：

- 统一 API 抽象已经存在
- 游戏引擎主状态机已经在 Dart 中落地
- 关键 agent 服务已经有本地等价物
- 测试已经不再只是 UI 壳，而是在验证运行时服务

## 七、建议的下一步

1. 用多个代表性世界包做更长流程的人工回归
2. 明确 sidecar 模式是否长期保留为兼容路径
3. 决定 scene adaptation 与高级 prefetch 的 1:1 迁移是否属于下一阶段目标
4. 如果 Android 要从"可导出"提升到"正式产品"，需要独立做移动端交互设计

## 八、许可证

本项目继续沿用原有许可证：

- [MIT License](../LICENSE)
