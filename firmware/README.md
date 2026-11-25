# 脑环双模固件（EEG_Reader：BLE + 星闪 SLE）

这套固件是我们自己写的 BearPi-Pico H3863 脑环固件源码，替代脑环里原有的
“别人烧好的”固件。它同时开启两条无线链路，数据格式与本仓库的 HarmonyOS App
（见上一级 `app/` 目录）完全对齐：

| 链路 | 设备名 | 服务 | 数据特征 | 说明 |
|---|---|---|---|---|
| 蓝牙 BLE | `EEG_Reader` | `0000EE01` | `0000EE02`（Notify） | App 设备管理页 BLE 连接 |
| 星闪 SLE | `EEG_Reader` | `0xEE01` | `0xEE02`（Notify） | App 星闪扫描连接 |

数据帧（JSON，`\n` 结尾，带递增序号 `n`）：

```json
{"sig":0,"att":52,"med":48,"raw":1234,"d":500,"t":320,"aL":400,"aH":300,"bL":200,"bH":140,"gL":30,"gM":20,"n":123}
```

## 目录结构

```
firmware/eeg_ring/
├── eeg_ring.c                 任务入口：初始化传感器 + BLE + SLE，定时发帧
├── Kconfig                    示例配置（采样后端、串口、发送间隔…）
├── CMakeLists.txt             源码清单
├── board.json                 外设配置（UART2/UART3）
├── eeg_core/
│   ├── eeg_sensor.[ch]        传感器抽象层
│   ├── eeg_neurosky.[ch]      NeuroSky TGAM/BMD101 串口解析（默认）
│   ├── eeg_adc.[ch]           ADC 直采 + Goertzel 波段（实验）
│   └── eeg_frame.[ch]         JSON 组帧 + 无接触规则
├── ble_eeg_server/            BLE GATT 服务端（EE01/EE02）
└── sle_eeg_server/            星闪 SSAP 服务端（EE01/EE02）
```

## 集成到 SDK（3 步）

1. 把 `eeg_ring` 整个文件夹复制到 SDK 的
   `application/samples/products/` 下；
2. 在 `application/samples/products/Kconfig` 末尾加：

```kconfig
config SAMPLE_SUPPORT_EEG_RING
    bool
    prompt "Support EEG Brain Ring sample (BLE + SLE dual mode)."
    default n
    depends on ENABLE_PRODUCTS_SAMPLE

if SAMPLE_SUPPORT_EEG_RING
menu "EEG Brain Ring Sample Configuration"
    osource "application/samples/products/eeg_ring/Kconfig"
endmenu
endif
```

3. 在 `application/samples/products/CMakeLists.txt` 末尾加：

```cmake
if(DEFINED CONFIG_SAMPLE_SUPPORT_EEG_RING)
    add_subdirectory_if_exist(eeg_ring)
endif()
```

## 构建与烧录

SDK 需要在 Linux（Ubuntu）或 WSL 中构建，命令（SDK 根目录）：

```bash
python build.py menuconfig      # 勾选 SAMPLE_ENABLE → ENABLE_PRODUCTS_SAMPLE → SAMPLE_SUPPORT_EEG_RING
python build.py -j8             # 生成 bin
```

烧录用官方 HbBurn 工具（波特率 921600）或串口烧录脚本，参考小熊派官网
[下载烧录](http://bearpi.cn/core_board/bearpi/bm/h63/software/下载烧录.html)。

> 说明：本机实际上已在 Windows 上成功编译验证（HiSpark 工具链 + ninja），
> 见下节“编译验证结果”。

## 编译验证结果（2026-08-05）

已在 WS63/H3863 官方 SDK 副本中全量编译通过：

```
######### Build target:ws63_liteos_app success
```

固件里已确认包含：广播名 `EEG_Reader`、BLE 服务 `EE01/EE02`、SLE 服务
`EE01/EE02`、日志标记 `[eeg ring] [eeg neurosky] [ble eeg server] [sle eeg server]`
以及 JSON 帧。编译产物位于本地 SDK 的 `output/` 输出目录（未纳入公开仓库），主要文件：

| 文件 | 用途 |
|---|---|
| `ws63-liteos-app.bin` | 主固件（App + BLE + SLE） |
| `flashboot.bin` / `loaderboot.bin` / `ssb.bin` / `params.bin` | 引导链 |
| `ws63-liteos-app_all.fwpkg` | HbBurn / 升级工具整包 |
| `ws63-liteos-app_load_only.fwpkg` | 仅应用升级包 |

本次编译使用的配置（对应 Kconfig 默认值）：
`EEG_SENSOR_MODE_NEUROSKY`、UART bus=2、RXD=S_AGPIO13、波特率 57600、
发送间隔 500ms、无信号超时 2000ms。

## 关键 Kconfig 选项

- `EEG_SENSOR_MODE_NEUROSKY`（默认）：解析 NeuroSky TGAM/BMD101 串口协议，
  默认 UART bus=2、RXD=S_AGPIO13（board.json 里 UART3），波特率 57600。
  脑环里的采集芯片如果是 NeuroSky 系列（App 的 att/med/8 波段字段和
  NeuroSky eSense 一一对应，基本可以确定），直接可用。
- `EEG_SENSOR_MODE_ADC`（实验）：ADC 直采 + RMS 接触判断 + Goertzel 波段。
  需要你确认电极接在哪个 ADC 通道以及模拟前端电路，默认认为无接触。
- `EEG_SENSOR_NO_SIGNAL_TIMEOUT_MS`（默认 2000）：传感器超过该时长没有数据
  就发无接触帧。
- `EEG_RING_TX_INTERVAL_MS`（默认 500）：发送频率 2 Hz。
- `EEG_DEVICE_ID`（默认 0）：每台设备改成不同值，BLE/SLE 地址最后一位不同，
  保证 App 能区分多台脑环。

## 数据诚信规则（固件侧）

- 有接触：发真实值，`sig` = 信号质量原始值（0 优秀 → 199 较差）。
- 无接触（`poor_signal >= 200`）或传感器 2 秒没数据：只发
  `{"sig":200,...}` 全零帧，App 显示“等待接触 / --”，**绝不重发旧数据**。
- 每一帧带递增 `n`，App 不会把新帧误判成固件缓冲回环。

## 验证方法

1. 串口（115200）看日志：
   `[sle eeg server] init ok`、`[ble eeg server] init done`、
   `[eeg neurosky] first valid EEG packet ...`。
2. App 设备管理页：BLE 扫描到 `EEG_Reader` → 连接 → 看到数据；
3. App 星闪页：扫描到 `EEG_Reader` → 连接 → 看到数据（要求平板开启星闪）。

## 常见问题

- **星闪扫不到**：确认平板开了星闪开关；固件侧 `enable_sle()` 成功、
  `sle_start_announce` 成功（日志无 fail）。
- **BLE 扫不到**：看 `[ble eeg server]` 日志是否有 `init done`，以及
  `start adv` 是否成功。
- **一直“等待接触”**：传感器后端或接线不对，先看串口有没有
  `first valid EEG packet`；没有说明采集芯片协议/串口引脚需要适配。
- **多台脑环**：每台编译时改 `EEG_DEVICE_ID`（0、1、2…）。
