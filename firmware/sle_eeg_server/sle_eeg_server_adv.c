/**
 * SLE announce (advertising) for the EEG brain ring, name "EEG_Reader",
 * adapted from the SDK sle_uart adv sample.
 */

#include "common_def.h"
#include "securec.h"
#include "errcode.h"
#include "soc_osal.h"
#include "product.h"
#include "sle_common.h"
#include "sle_device_discovery.h"
#include "sle_errcode.h"

#include "sle_eeg_server_adv.h"

#define NAME_MAX_LENGTH 16
#define SLE_CONN_INTV_MIN_DEFAULT 0x64
#define SLE_CONN_INTV_MAX_DEFAULT 0x64
#define SLE_ADV_INTERVAL_MIN_DEFAULT 0xC8
#define SLE_ADV_INTERVAL_MAX_DEFAULT 0xC8
#define SLE_CONN_SUPERVISION_TIMEOUT_DEFAULT 0x1F4
#define SLE_CONN_MAX_LATENCY 0x1F3
#define SLE_ADV_TX_POWER 10
#define SLE_ADV_HANDLE_DEFAULT 1
#define SLE_ADV_DATA_LEN_MAX 251

#define SLE_EEG_ADV_LOG "[sle eeg adv]"

#ifndef EEG_DEVICE_ID
#define EEG_DEVICE_ID 0
#endif

static uint8_t sle_local_name[NAME_MAX_LENGTH] = "EEG_Reader";
static errcode_t g_sle_adv_start_ret = (errcode_t)0xFFFFFFFF;
static uint32_t g_sle_adv_status = 0xFFFFFFFF;

static uint16_t sle_set_adv_local_name(uint8_t *adv_data, uint16_t max_len)
{
    uint8_t index = 0;
    uint8_t local_name_len = (uint8_t)(sizeof(sle_local_name) - 1);

    adv_data[index++] = (uint8_t)(local_name_len + 1);
    adv_data[index++] = SLE_ADV_DATA_TYPE_COMPLETE_LOCAL_NAME;
    if (memcpy_s(&adv_data[index], max_len - index, sle_local_name,
                 local_name_len) != EOK) {
        return 0;
    }
    return (uint16_t)(index + local_name_len);
}

static uint16_t sle_set_adv_data(uint8_t *adv_data)
{
    uint16_t idx = 0;
    size_t len = sizeof(struct sle_adv_common_value);

    struct sle_adv_common_value adv_disc_level = {
        .length = len - 1,
        .type = SLE_ADV_DATA_TYPE_DISCOVERY_LEVEL,
        .value = SLE_ANNOUNCE_LEVEL_NORMAL,
    };
    if (memcpy_s(&adv_data[idx], SLE_ADV_DATA_LEN_MAX - idx, &adv_disc_level, len) != EOK) {
        return 0;
    }
    idx += (uint16_t)len;

    struct sle_adv_common_value adv_access_mode = {
        .length = len - 1,
        .type = SLE_ADV_DATA_TYPE_ACCESS_MODE,
        .value = 0,
    };
    if (memcpy_s(&adv_data[idx], SLE_ADV_DATA_LEN_MAX - idx, &adv_access_mode, len) != EOK) {
        return 0;
    }
    idx += (uint16_t)len;

    /* 将完整本地名称放入广播数据，便于上层按设备名过滤扫描时能直接匹配 */
    idx += sle_set_adv_local_name(&adv_data[idx], SLE_ADV_DATA_LEN_MAX - idx);
    return idx;
}

static uint16_t sle_set_scan_response_data(uint8_t *scan_rsp_data)
{
    uint16_t idx = 0;
    size_t scan_rsp_data_len = sizeof(struct sle_adv_common_value);

    struct sle_adv_common_value tx_power_level = {
        .length = scan_rsp_data_len - 1,
        .type = SLE_ADV_DATA_TYPE_TX_POWER_LEVEL,
        .value = SLE_ADV_TX_POWER,
    };
    if (memcpy_s(scan_rsp_data, SLE_ADV_DATA_LEN_MAX, &tx_power_level,
                 scan_rsp_data_len) != EOK) {
        return 0;
    }
    idx += (uint16_t)scan_rsp_data_len;

    idx += sle_set_adv_local_name(&scan_rsp_data[idx], SLE_ADV_DATA_LEN_MAX - idx);
    return idx;
}

static int sle_set_default_announce_param(void)
{
    sle_announce_param_t param = { 0 };
    unsigned char local_addr[SLE_ADDR_LEN] = {
        0x01, 0x02, 0x03, 0x04, 0x05, (unsigned char)(0x60 + EEG_DEVICE_ID)
    };

    param.announce_mode = SLE_ANNOUNCE_MODE_CONNECTABLE_SCANABLE;
    param.announce_handle = SLE_ADV_HANDLE_DEFAULT;
    param.announce_gt_role = SLE_ANNOUNCE_ROLE_T_CAN_NEGO;
    param.announce_level = SLE_ANNOUNCE_LEVEL_NORMAL;
    param.announce_channel_map = SLE_ADV_CHANNEL_MAP_DEFAULT;
    param.announce_interval_min = SLE_ADV_INTERVAL_MIN_DEFAULT;
    param.announce_interval_max = SLE_ADV_INTERVAL_MAX_DEFAULT;
    param.conn_interval_min = SLE_CONN_INTV_MIN_DEFAULT;
    param.conn_interval_max = SLE_CONN_INTV_MAX_DEFAULT;
    param.conn_max_latency = SLE_CONN_MAX_LATENCY;
    param.conn_supervision_timeout = SLE_CONN_SUPERVISION_TIMEOUT_DEFAULT;
    param.announce_tx_power = 18;
    param.own_addr.type = 0;
    if (memcpy_s(param.own_addr.addr, SLE_ADDR_LEN, local_addr, SLE_ADDR_LEN) != EOK) {
        return 0;
    }
    osal_printk("%s announce addr: %02x:%02x:%02x:%02x:%02x:%02x\n",
                SLE_EEG_ADV_LOG, local_addr[0], local_addr[1], local_addr[2],
                local_addr[3], local_addr[4], local_addr[5]);
    return sle_set_announce_param(param.announce_handle, &param);
}

static int sle_set_default_announce_data(void)
{
    uint8_t announce_data_len = 0;
    uint8_t seek_data_len = 0;
    sle_announce_data_t data = { 0 };
    uint8_t announce_data[SLE_ADV_DATA_LEN_MAX] = { 0 };
    uint8_t seek_rsp_data[SLE_ADV_DATA_LEN_MAX] = { 0 };

    announce_data_len = sle_set_adv_data(announce_data);
    data.announce_data = announce_data;
    data.announce_data_len = announce_data_len;

    seek_data_len = sle_set_scan_response_data(seek_rsp_data);
    data.seek_rsp_data = seek_rsp_data;
    data.seek_rsp_data_len = seek_data_len;

    osal_printk("%s announce_data_len:%d seek_data_len:%d\n",
                SLE_EEG_ADV_LOG, announce_data_len, seek_data_len);
    return sle_set_announce_data(SLE_ADV_HANDLE_DEFAULT, &data);
}

static void sle_announce_enable_cbk(uint32_t announce_id, errcode_t status)
{
    g_sle_adv_status = (uint32_t)status;
    osal_printk("%s announce enable id:%02x status:%x\n",
                SLE_EEG_ADV_LOG, announce_id, status);
}

static void sle_announce_disable_cbk(uint32_t announce_id, errcode_t status)
{
    osal_printk("%s announce disable id:%02x status:%x\n",
                SLE_EEG_ADV_LOG, announce_id, status);
}

static void sle_announce_terminal_cbk(uint32_t announce_id)
{
    osal_printk("%s announce terminal id:%02x\n", SLE_EEG_ADV_LOG, announce_id);
}

errcode_t sle_eeg_announce_register_cbks(void)
{
    sle_announce_seek_callbacks_t seek_cbks = { 0 };
    seek_cbks.announce_enable_cb = sle_announce_enable_cbk;
    seek_cbks.announce_disable_cb = sle_announce_disable_cbk;
    seek_cbks.announce_terminal_cb = sle_announce_terminal_cbk;
    return sle_announce_seek_register_callbacks(&seek_cbks);
}

errcode_t sle_eeg_server_adv_init(void)
{
    errcode_t ret;
    sle_set_default_announce_param();
    sle_set_default_announce_data();
    ret = sle_start_announce(SLE_ADV_HANDLE_DEFAULT);
    g_sle_adv_start_ret = ret;
    if (ret != ERRCODE_SLE_SUCCESS) {
        osal_printk("%s start announce fail ret:%x\n", SLE_EEG_ADV_LOG, ret);
        return ret;
    }
    return ERRCODE_SLE_SUCCESS;
}

errcode_t sle_eeg_adv_start_ret(void)
{
    return g_sle_adv_start_ret;
}

uint32_t sle_eeg_adv_status(void)
{
    return g_sle_adv_status;
}
