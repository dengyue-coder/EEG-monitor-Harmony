# 研究发现

## 项目结构

- `初始完整版工程（本地存档）`：初始完整版。独有 `components/`（DeviceManagerView、MultiMonitorView、SideBar、DeviceCard、AIAssistantCard）和 `service/GattServerService.ets`。
- `本仓库 app/ 工程（优化版 UI）`：优化版 UI。独有 RoleStore（个人/监护者角色）、AlertService、StudentDetailPage、GameHubPage、DigitalHumanRenderer。设备管理 UI 内联在 Index.ets。

## 小程序接收功能（要移植的核心）

`GattServerService` 行为：
1. `ble.createGattServer()` + `addService(EE01 service, EE02 characteristic, write: true)`。
2. `ble.startAdvertising({ serviceUuids: [SVC_UUID] })` 广播。
3. `characteristicWrite` 回调：先回 ACK（needRsp 时），再解析 JSON；整帧失败时按分片累积（jsonBuf）。
4. 数据到达时：`store.registerDevice('mini_program', '小程序')`、`setActiveDevice`、`updateDeviceData`，并停止 MockDataService。
5. 附带：日志（GattLogEvent）、状态回调、错误回调、500ms 自动重试、演示模式（DemoMode，用 MockDataService.startAs）。

## copy2 兼容性确认

- EEGDataStore 具备 registerDevice / setActiveDevice / updateDeviceData / connected setter / subscribe / subscribeGlobal / getLatestData（无 subscribeDevice，适配方案：定时轮询预览或 subscribe 全局）。
- MockDataService 具备 startAs / startMulti / stop。
- BleService 具备扫描/连接/多设备（copy2 自研版本更完善，不动）。
- module.json5 已含 `ohos.permission.ACCESS_BLUETOOTH`，string.json 已含 bluetooth_reason。
- 文件编码全部 UTF-8 无 BOM。

## 小程序现状

- `本地小程序模拟端（未纳入本仓库）`：mock 模拟器（DeviceManager/MockDevice），页面 index/dashboard/detail/devices/emotion/emotioninfo/game/motion/profile/training/brainwave。
- 全目录搜索 `openBluetoothAdapter/writeBLECharacteristicValue/createBLEConnection`：无结果。需要新增 BLE 发送能力。
- 桌面 `weixin-mini-program` 文件夹不存在（已搜 本机各磁盘）。

## 真实设备搜索不到的原因（2026-08-02 结论）

- BearPi H3863（WS63）为双模芯片：BLE 5.2 + 星闪 SLE 1.0。星闪与 BLE 是两套独立协议栈，BLE 扫描无法发现 SLE 设备。
- App 之前所有"扫描/连接"均为 `@ohos.bluetooth.ble`，没有任何 NearLink 调用 → 脑环若走 SLE 必然搜不到。
- 结论：需要新增 NearLink Kit（`@kit.NearLinkKit`）支持，权限为 `ohos.permission.ACCESS_NEARLINK`（user_grant，需 reason + usedScene + 动态请求）。

## NearLink 关键 API（已按官方文档核对）

- 导入：`import { scan, ssap, constant } from '@kit.NearLinkKit';`
- 扫描：`scan.on('deviceFound', (data: Array<scan.ScanResults>) => ...)`、`scan.startScan(filters: Array<scan.ScanFilters>, { scanMode: 2 })`、`scan.stopScan()`、`scan.off('deviceFound')`。
- 注意：API 18+ 不允许全空过滤器（否则 401），必须至少一个有效过滤条件（deviceName/address/manufacturerId 等）；扫描结果地址是随机地址。
- 连接：`ssap.createClient(addr)` → `client.on('connectionStateChange', (data: ssap.ConnectionChangeState) => ...)` → `client.connect()`。
- 收数：`client.on('propertyChange', ...)` + `client.getServices()` 找 NOTIFY 属性 + `client.setPropertyNotification(property, true)`。
- 状态枚举：`constant.ConnectionState.STATE_CONNECTED / STATE_DISCONNECTED`；操作位：`ssap.Operation.NOTIFY`。
- 官方示例工程：`nearlink-kit_-sample-code`（HarmonyOS_Samples）。

## 固件源码缺口（仍待用户提供）

- 脑环固件当前用 SLE 还是 BLE？SLE 的 service/property UUID？广播名？
- 本机 `本地硬件资料目录` 为空；`本地脑波 SDK 资料目录` 只有 TGAM（NeuroSky）串口 SDK，无 BearPi 固件源码。
- App 已做"自动找第一个可通知属性"兜底，但数据通道形态（SSAP 属性通知 vs Port 数据通道）需固件侧确认。

## 脑控游戏反应迟钝的根因（2026-08-02 补充）

- 数据源：小程序 blelink 原为 300ms/帧（3.3Hz）；游戏循环 50ms（20Hz）。
- 控制链路：`SMOOTH_A=0.20` 慢 EMA → `EMA_PLANE=0.28` 再平滑 → 死区 ±5，等效控制延迟约 500ms+，加上通道随机生成，撞墙频繁。
- 修复：小程序帧间隔 300→150ms；游戏改用快控制 EMA(0.50)、飞机 EMA 0.45、死区 ±3、速度系数 0.18、卷轴 2.2；障碍物通道偏向飞机当前位置 ±130。

## 蓝牙权限缺失（重大发现，2026-08-02）

- `ohos.permission.ACCESS_BLUETOOTH` 在鸿蒙 NEXT 是 **user_grant** 权限，必须 `requestPermissionsFromUser` 动态申请；不申请则 `ble.startBLEScan` / `createGattServer` 抛 201。
- 检查结论：**copy1 与 copy2 两个工程都从未在代码里动态申请过蓝牙权限**（仅声明在 module.json5）。这会导致"设备明明在广播却扫不到"或"扫描中…"卡死。
- 修复：`utils/PermissionUtils.ets` 统一管理权限检查/申请；EntryAbility 启动即申请；BleService 增加 onScanError（201→权限提示）；设备页链路自检面板显示权限状态。
- 若权限授权后仍搜不到：用平板系统"设置→蓝牙"、以及另一台手机验证小熊派是否真的在广播；星闪同理先看系统设置里有没有"星闪"选项（部分华为平板无星闪硬件）。

## UI/UX 审查结论（2026-08-02）

- 主要缺陷：① 游戏页无退出按钮（需切 Tab 才能退出）；② 个人模式无真实设备连接入口（扫描只在监护者模式设备页）；③ 多处触控目标 < 40px（返回键、导航胶囊、小按钮）；④ "我的"页设备信息停留在 BLE 时代。
- 已修复：游戏页加退出键；个人模式设备弹窗新增扫描入口 + 全屏扫描面板（复用星闪/蓝牙双协议扫描）；统一加大触控目标；更新设备信息文案。
- 其余结构评估：入口（欢迎→角色→主界面）、6-Tab 框架、监护者（监测/设备/学生详情）结构清晰，未做大改。

## BLE 连接反馈链路（2026-08-02 补充）

- 原问题：BleService 连接后"找不到 EE01/EE02 特征"等失败全部静默 return，UI 无任何反馈，用户不知道连没连上。
- 修复：连接状态机（连接中→成功/失败原因 Toast）、设备服务清单诊断（失败时提示设备提供的服务 UUID）、UART 透传兜底匹配、数据格式无法解析提示（区分"没连上/连上没数据/连上有数据但协议不匹配"）。
- 待用户实测：连接失败时的 Toast 会列出小熊派实际提供的服务，据此可确认固件协议是否为 EE01/EE02 或 UART 透传。

## 小程序滑条不实时同步（2026-08-02）

- 根因：mock.js 的 Device.generate() 每 20ms 用自动模拟插值覆盖 `data.att/med`，滑条写入的值下一帧就被冲掉；且已知小程序代码中没有任何 slider 控件（桌面也确认无 weixin-miniprogram 副本，代码在 本地小程序模拟端（未纳入本仓库））。
- 修复：mock.js 增加 manualAtt/manualMed 覆盖机制（`setManual()` 立即生效、每帧生成时优先于插值）；blelink 页新增专注度/冥想度滑条，bindchanging 实时更新数值并立即发送一帧，App 侧 150ms 内同步。

## 小熊派固件协议线索（2026-08-02）

- 在 WS63/H3863 官方 SDK（本地存档） 找到官方 H3863 SDK，`application/samples/products/ble_uart/ble_uart_server` 为 BLE 透传示例：服务 UUID 0xABCD、TX 通知 0xCDEF、RX 写入 0xEFEF，广播名"BLE_UART"相关（可查 ble_uart_server_adv.c）。
- SDK 无 EE01/EE02 定义 → 脑环固件是定制版；App 端兜底（自动匹配 UART 类/第一个可通知特征）可覆盖该协议。脑环走 BLE 而非 SLE，与"星闪搜不到、蓝牙搜得到"现象一致。

## 实际使用的小程序位置（2026-08-02 更正）

- 用户桌面在 **本地桌面目录**，真实使用的小程序为 **桌面小程序工程（本地存档）**（pages/login、pages/send，带预设场景与滑块调控），与 本地小程序模拟端（未纳入本仓库） 是两份不同代码。
- 滑条问题根因：send.js 的 onSliderChanging 用尾随节流（拖动结束后 150ms 才补发一帧），拖动全程 App 收不到变化；且不点"开始发送"就不发送。
- 修复：前沿节流 + 每 150ms 一帧 + 松手补发；拖动/点预设自动开启发送；ble.js 按 MTU 分片写入。

## 滑条值映射确认（2026-08-02）

- 小程序 att(注意力) → 帧字段 att → App 专注度；med(放松度) → 帧字段 med → App 冥想度。链路（send.js buildData → ble.js writeJSON → GattServerService.handleWrite → EEGDataStore.updateDeviceData）无任何字段重映射。
- 实时性：小程序拖动即发（150ms 节流）+ App 预览 200ms 刷新，数值一一对应。
