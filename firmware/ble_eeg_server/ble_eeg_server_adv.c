/**
 * BLE advertising for the EEG brain ring (name "EEG_Reader"),
 * adapted from the SDK ble_uart adv sample.
 */

#include "common_def.h"
#include "securec.h"
#include "errcode.h"
#include "soc_osal.h"
#include "bts_def.h"
#include "bts_le_gap.h"

#include "ble_eeg_server_adv.h"

#define BLE_ADV_FLAG_LEN 0x03
#define BLE_GENERAL_BYTE_1 1
#define BLE_ADV_APPEARANCE_LENGTH 4
#define BLE_ADV_APPEARANCE_DATA_TYPE 0x19
#define BLE_ADV_CATEGORY_UART_VALUE 0x0080
#define BLE_ADV_CATEGORY_LEN 2
#define BLE_ADV_PARAM_DATATYPE_LENGTH 1
#define BLE_ADV_LOCAL_NAME_DATA_TYPE 0x09
#define BLE_ADV_TX_POWER_LEVEL 0x0A
#define BLE_SCAN_RSP_TX_POWER_LEVEL_LEN 0x03
#define BLE_ADV_FLAG_DATA 0x05

#define BLE_ADV_MIN_INTERVAL 0x30
#define BLE_ADV_MAX_INTERVAL 0x60
#define BTH_GAP_BLE_ADV_HANDLE_DEFAULT 0x01
#define BTH_GAP_BLE_ADV_FOREVER_DURATION 0

#define EXT_ADV_OR_SCAN_RSP_DATA_LEN 251
#define ADV_APPEA_CATOGORY_HIGH 8

#define BLE_EEG_ADV_LOG "[ble eeg adv]"

typedef enum ble_adv_filter_policy {
    BLE_ADV_FILTER_POLICY_SCAN_ANY_CONNECT_ANY = 0x00,
    BLE_ADV_FILTER_POLICY_SCAN_WHITE_LIST_CONNECT_ANY = 0x01,
    BLE_ADV_FILTER_POLICY_SCAN_ANY_CONNECT_WHITE_LIST = 0x02,
    BLE_ADV_FILTER_POLICY_SCAN_WHITE_LIST_CONNECT_WHITE_LIST = 0x03
} ble_adv_filter_policy_t;

typedef enum ble_adverting_type {
    BLE_ADV_TYPE_CONNECTABLE_UNDIRECTED = 0x00,
    BLE_ADV_TYPE_CONNECTABLE_HIGH_DUTY_CYCLE_DIRECTED = 0x01,
    BLE_ADV_TYPE_SCANNABLE_UNDIRECTED = 0x02,
    BLE_ADV_TYPE_NON_CONNECTABLE_UNDIRECTED = 0x03,
    BLE_ADV_TYPE_CONNECTABLE_LOW_DUTY_CYCLE_DIRECTED = 0x04
} ble_adverting_type_t;

typedef enum ble_adv_channel_map {
    BLE_ADV_CHANNEL_MAP_CH_37 = 0x01,
    BLE_ADV_CHANNEL_MAP_CH_38 = 0x02,
    BLE_ADV_CHANNEL_MAP_CH_39 = 0x04,
    BLE_ADV_CHANNEL_MAP_CH_37_CH_38 = 0x03,
    BLE_ADV_CHANNEL_MAP_CH_37_CH_39 = 0x05,
    BLE_ADV_CHANNEL_MAP_CH_38_CH_39 = 0x06,
    BLE_ADV_CHANNEL_MAP_CH_DEFAULT = 0x07
} ble_adv_channel_map_t;

typedef struct {
    uint8_t length;
    uint8_t adv_data_type;
    uint8_t flags;
} ble_adv_flag;

typedef struct {
    uint8_t length;
    uint8_t adv_data_type;
    uint8_t catogory_id[BLE_ADV_CATEGORY_LEN];
} ble_appearance_t;

typedef struct {
    uint8_t length;
    uint8_t adv_data_type;
    int8_t *name;
} ble_local_name_t;

typedef struct {
    uint8_t length;
    uint8_t adv_data_type;
    uint8_t tx_power_value;
} ble_tx_power_level_t;

static uint8_t g_eeg_local_name[] = "EEG_Reader";

static inline uint8_t u16_low_u8(uint16_t val)
{
    return (uint8_t)((uint16_t)(val) & 0xff);
}

static inline uint8_t u16_high_u8(uint16_t val)
{
    return (uint8_t)(((uint16_t)(val) >> ADV_APPEA_CATOGORY_HIGH) & 0xff);
}

static uint8_t ble_set_adv_flag_data(uint8_t *pos, uint8_t max_len)
{
    ble_adv_flag adv_flags = {
        .length = BLE_ADV_FLAG_LEN - BLE_GENERAL_BYTE_1,
        .adv_data_type = 1,
        .flags = BLE_ADV_FLAG_DATA
    };
    if (memcpy_s(pos, max_len, &adv_flags, BLE_ADV_FLAG_LEN) != EOK) {
        return 0;
    }
    return BLE_ADV_FLAG_LEN;
}

static uint8_t ble_set_adv_appearance(uint8_t *pos, uint8_t max_len)
{
    ble_appearance_t data = {
        .length = BLE_ADV_APPEARANCE_LENGTH - BLE_GENERAL_BYTE_1,
        .adv_data_type = BLE_ADV_APPEARANCE_DATA_TYPE,
        .catogory_id = { u16_low_u8(BLE_ADV_CATEGORY_UART_VALUE),
                         u16_high_u8(BLE_ADV_CATEGORY_UART_VALUE) }
    };
    if (memcpy_s(pos, max_len, &data, BLE_ADV_APPEARANCE_LENGTH) != EOK) {
        return 0;
    }
    return BLE_ADV_APPEARANCE_LENGTH;
}

static uint8_t ble_set_adv_name(uint8_t *pos, uint8_t max_len)
{
    uint8_t len = BLE_ADV_PARAM_DATATYPE_LENGTH + BLE_ADV_PARAM_DATATYPE_LENGTH;
    ble_local_name_t data = {
        .length = (uint8_t)(BLE_ADV_PARAM_DATATYPE_LENGTH + sizeof(g_eeg_local_name)),
        .adv_data_type = BLE_ADV_LOCAL_NAME_DATA_TYPE
    };
    if (memcpy_s(pos, max_len, &data, len) != EOK) {
        return 0;
    }
    if (memcpy_s(pos + len, (size_t)(max_len - len), g_eeg_local_name,
                 sizeof(g_eeg_local_name)) != EOK) {
        return 0;
    }
    return (uint8_t)(len + sizeof(g_eeg_local_name));
}

static uint8_t ble_set_adv_appearance_data(uint8_t *pos, uint8_t max_len)
{
    uint8_t idx = 0;
    idx += ble_set_adv_appearance(pos, max_len);
    idx += ble_set_adv_name(pos + idx, (uint8_t)(max_len - idx));
    return idx;
}

static uint16_t ble_eeg_set_adv_data_raw(uint8_t *data, uint8_t max_len)
{
    uint8_t idx = 0;
    idx += ble_set_adv_flag_data(data, max_len);
    idx += ble_set_adv_appearance_data(&data[idx], (uint8_t)(max_len - idx));
    return idx;
}

static uint16_t ble_set_scan_response_data(uint8_t *data, uint8_t max_len)
{
    uint8_t idx = 0;
    ble_tx_power_level_t tx_power_level = {
        .length = BLE_SCAN_RSP_TX_POWER_LEVEL_LEN - BLE_GENERAL_BYTE_1,
        .adv_data_type = BLE_ADV_TX_POWER_LEVEL,
        .tx_power_value = 0
    };
    if (memcpy_s(data, max_len, &tx_power_level, sizeof(ble_tx_power_level_t)) != EOK) {
        return 0;
    }
    idx += BLE_SCAN_RSP_TX_POWER_LEVEL_LEN;

    data[idx++] = (uint8_t)(sizeof(g_eeg_local_name) + BLE_GENERAL_BYTE_1);
    data[idx++] = BLE_ADV_LOCAL_NAME_DATA_TYPE;
    if ((idx + sizeof(g_eeg_local_name)) > max_len) {
        return 0;
    }
    if (memcpy_s(&data[idx], max_len - idx, g_eeg_local_name,
                 sizeof(g_eeg_local_name)) != EOK) {
        return 0;
    }
    idx += (uint8_t)sizeof(g_eeg_local_name);
    return idx;
}

uint8_t ble_eeg_set_adv_data(void)
{
    uint8_t adv_data[EXT_ADV_OR_SCAN_RSP_DATA_LEN] = { 0 };
    uint8_t scan_rsp_data[EXT_ADV_OR_SCAN_RSP_DATA_LEN] = { 0 };
    gap_ble_config_adv_data_t cfg_adv_data;

    uint16_t adv_len = ble_eeg_set_adv_data_raw(adv_data, EXT_ADV_OR_SCAN_RSP_DATA_LEN);
    uint16_t rsp_len = ble_set_scan_response_data(scan_rsp_data, EXT_ADV_OR_SCAN_RSP_DATA_LEN);
    if ((adv_len == 0) || (rsp_len == 0)) {
        return 0;
    }

    cfg_adv_data.adv_data = adv_data;
    cfg_adv_data.adv_length = adv_len;
    cfg_adv_data.scan_rsp_data = scan_rsp_data;
    cfg_adv_data.scan_rsp_length = rsp_len;
    osal_printk("%s set adv data len:%d name:%s\n",
                BLE_EEG_ADV_LOG, adv_len, g_eeg_local_name);
    return gap_ble_set_adv_data(BTH_GAP_BLE_ADV_HANDLE_DEFAULT, &cfg_adv_data);
}

uint8_t ble_eeg_start_adv(void)
{
    errcode_t ret = ERRCODE_BT_SUCCESS;
    gap_ble_adv_params_t adv_para = {
        .min_interval = BLE_ADV_MIN_INTERVAL,
        .max_interval = BLE_ADV_MAX_INTERVAL,
        .duration = BTH_GAP_BLE_ADV_FOREVER_DURATION,
        .peer_addr.type = BT_ADDRESS_TYPE_PUBLIC_DEVICE_ADDRESS,
        .channel_map = BLE_ADV_CHANNEL_MAP_CH_DEFAULT,
        .adv_type = BLE_ADV_TYPE_CONNECTABLE_UNDIRECTED,
        .adv_filter_policy = BLE_ADV_FILTER_POLICY_SCAN_ANY_CONNECT_ANY
    };

    (void)memset_s(&adv_para.peer_addr.addr, BD_ADDR_LEN, 0, BD_ADDR_LEN);
    ret |= gap_ble_set_adv_param(BTH_GAP_BLE_ADV_HANDLE_DEFAULT, &adv_para);
    ret |= gap_ble_start_adv(BTH_GAP_BLE_ADV_HANDLE_DEFAULT);
    osal_printk("%s start adv ret:%d\n", BLE_EEG_ADV_LOG, ret);
    return ret;
}
