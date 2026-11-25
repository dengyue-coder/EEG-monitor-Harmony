# 任务规划：copy2 UI + copy1 功能合并

## 目标

保留 `本仓库 app/ 工程（优化版 UI）`（优化版 UI）的界面，把 `初始完整版工程（本地存档）`（初始完整版）中的"小程序蓝牙发送数据到 App"功能移植过去，并确保端到端可用。

## 关键事实（发现）

- copy2 缺 `service/GattServerService.ets`（App 端 BLE GATT 服务端，接收小程序写入的 EEG JSON）。
- copy2 已有 BleService（更完善）、EEGDataStore（接口兼容）、MockDataService（含 startAs/startMulti）、蓝牙权限声明。
- 小程序代码实际在 `本地小程序模拟端（未纳入本仓库）`（桌面无 weixin-mini-program 文件夹），且当前版本没有蓝牙发送代码，只有模拟数据逻辑。要端到端跑通需要补充 BLE 发送页。
- 协议：App 广播 service `0000EE01-...`，小程序向 characteristic `0000EE02-...`（write with response）写 EEG JSON 帧。

## 阶段

| 阶段 | 内容 | 状态 |
|------|------|------|
| 1 | 对比两个项目，定位差异 | 完成 |
| 2 | 移植 GattServerService 到 copy2 | 完成 |
| 3 | 在 copy2 教师模式设备页 + 个人模式头部集成"小程序接收"UI | 完成 |
| 4 | 为小程序补充 BLE 发送页（扫描→连接→写数据） | 完成 |
| 5 | 一致性检查 + 使用说明 | 完成 |
| 6 | 按真实设备（星闪）+ 演示（小程序）重构 UI 架构 | 完成 |
| 7 | 排查"真实设备搜索不到"：确认 H3863 双模（BLE5.2 + 星闪 SLE1.0），BLE 扫描看不到 SLE | 完成 |
| 8 | 新增 NearLinkService（星闪扫描 + SSAP 连接 + 属性通知收数）+ ACCESS_NEARLINK 权限 | 完成 |
| 9 | 设备管理页改双协议扫描（星闪 + 蓝牙），合并设备列表与协议标签 | 完成 |

## 验证方式

- 编译前静态检查：import 路径、store 接口、资源引用。
- 说明文档：如何用 DevEco 打开、如何用微信开发者工具导入小程序、两端 UUID 对应关系。
