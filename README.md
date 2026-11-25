# EEG Monitor · 鸿蒙脑电监测应用（BLE + 星闪 SLE 双模）

面向 HarmonyOS 的脑电信号监测应用，搭配自研 WS63/H3863 脑环固件，通过 **蓝牙 BLE 5.2** 与 **星闪 NearLink SLE 1.0** 双模无线链路接收前端采集的 EEG 数据，在端侧完成专注度/情绪等指标的呈现与训练交互。

> 嵌入式设计竞赛作品。应用层与固件层分目录存放，数据帧格式两端对齐。

## 项目组成

| 目录 | 内容 | 技术 |
| --- | --- | --- |
| `app/` | HarmonyOS 应用工程（ArkTS / Stage 模型） | ArkTS · HarmonyOS API · BLE GATT · NearLink |
| `firmware/` | BearPi-Pico H3863 脑环固件源码（BLE + SLE 服务端、EEG 采集与组帧） | C · CMake · LiteOS · WS63 SDK |
| `docs/` | 联调说明、研究发现与进度日志 | Markdown |

## 功能概览

- **双模设备连接**：设备管理页同时扫描蓝牙与星闪设备，列表合并并标注协议标签；
- **脑电数据接收**：通过 GATT Notify / SSAP 特征订阅接收 JSON 数据帧，带递增序号防止回环误判；
- **指标与波形**：呈现信号质量、专注度、冥想度及 α/β/θ/δ 等波段指标，并提供波形与情绪页面；
- **训练与小游戏**：内置专注训练、互动小游戏等页面，用于状态反馈与演示；
- **数据诚信**：传感器无接触或超时未收到数据时，前端只下发全零「等待接触」帧，不重发旧数据。

## 数据协议

设备广播/服务标识：

| 链路 | 设备名 | 服务 | 特征 |
| --- | --- | --- | --- |
| 蓝牙 BLE | `EEG_Reader` | `0000EE01` | `0000EE02`（Notify） |
| 星闪 SLE | `EEG_Reader` | `0xEE01` | `0xEE02`（Notify） |

数据帧为以 `\n` 结尾的 JSON，示例：

```json
{"sig":0,"att":52,"med":48,"raw":1234,"d":500,"t":320,"aL":400,"aH":300,"bL":200,"bH":140,"gL":30,"gM":20,"n":123}
```

字段说明详见 [`firmware/README.md`](./firmware/README.md)。

## 快速开始

### 应用（app/）

前置条件：安装 [DevEco Studio](https://developer.huawei.com/) 与对应 HarmonyOS SDK。

1. 用 DevEco Studio 打开 `app/` 目录；
2. 首次打开会自动生成调试签名（仓库内签名材料已脱敏为空占位，无需手动配置）；
3. 连接 HarmonyOS 设备或启动模拟器，点击运行。

> 说明：本工程不依赖三方 npm 包，依赖在 `oh-package.json5` 中声明。

### 固件（firmware/）

固件需在 WS63/H3863 官方 SDK 的 **Linux（Ubuntu）或 WSL** 环境中编译，集成步骤、Kconfig 选项与烧录方式见 [`firmware/README.md`](./firmware/README.md)。

## 目录概览

```
eeg-monitor-harmony/
├── app/
│   ├── AppScope/            # 应用配置（bundleName: com.eeg.monitor）
│   ├── entry/src/main/ets/
│   │   ├── pages/           # 首页、波形、情绪、训练、游戏等页面
│   │   ├── service/         # BLE / 星闪连接服务
│   │   ├── store/           # 数据状态与本地存储
│   │   ├── detectors/      # 信号 / 状态识别
│   │   ├── renderers/       # 波形与可视化渲染
│   │   ├── components/      # 复用组件
│   │   └── utils/
│   └── tools/              # 情绪模型权重与训练脚本
├── firmware/
│   ├── eeg_ring.c           # 任务入口
│   ├── eeg_core/            # 传感器抽象、协议解析、组帧
│   ├── ble_eeg_server/       # BLE GATT 服务端
│   ├── sle_eeg_server/       # 星闪 SSAP 服务端
│   └── README.md
└── docs/                    # 联调说明与开发日志
```

## 未纳入公开仓库的内容

- **第三方芯片 SDK**：WS63/H3863 官方 SDK（编译器、静态库、开源证书等）版权归原厂商，体积庞大，未随仓库提供；
- **本地调试签名**：证书、Profile、密钥口令等本地路径与凭据已在 `app/build-profile.json5` 中置空；
- **编译产物**：固件 `.bin` / `.fwpkg` 等烧录产物与构建中间文件未纳入；
- **本地工程配置**：`local.properties` 等机器相关配置已排除。

## 备注

- 星闪（SLE）扫描与连接需要设备/平板开启星闪开关；BLE 与 SLE 是两套独立链路，BLE 扫描不到 SLE 设备属正常现象。
- 联调排障（真机蓝牙、小程序模拟数据）见 `docs/` 下两份联调说明。
