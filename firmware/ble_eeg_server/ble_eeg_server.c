/**
 * BLE GATT server implementation, adapted from the SDK ble_uart sample:
 *   - service UUID changed to 0xEE01, data characteristic to 0xEE02;
 *   - device name changed to "EEG_Reader";
 *   - frames are split into <=20-byte notifications (default BLE MTU 23);
 *   - every board can get a unique public address via EEG_DEVICE_ID.
 */

#include <string.h>
#include "common_def.h"
#include "soc_osal.h"
#include "product.h"
#include "securec.h"
#include "errcode.h"
#include "bts_def.h"
#include "bts_gatt_stru.h"
#include "bts_gatt_server.h"
#include "bts_le_gap.h"

#include "ble_eeg_server_adv.h"
#include "ble_eeg_server.h"

#define BLE_EEG_SERVER_ID 1
#define BLE_EEG_SINGLE_LINK_CONNECT_ID 1
#define BLE_EEG_UUID16_LEN 2
#define BLE_EEG_INVALID_ATT_HDL 0
#define BLE_EEG_INVALID_SERVER_ID 0
#define BLE_EEG_NOTIFY_CHUNK 20
#define BLE_EEG_CHUNK_GAP_MS 4
#define BLE_EEG_START_DELAY_MS 2000

#define BLE_EEG_SERVER_LOG "[ble eeg server]"
#define BLE_EEG_SERVER_ERROR "[ble eeg server error]"

#ifndef EEG_DEVICE_ID
#define EEG_DEVICE_ID 0
#endif

/* Service UUID */
#define BLE_EEG_UUID_SERVER_SERVICE 0xEE01
/* Characteristic UUID */
#define BLE_EEG_CHARACTERISTIC_UUID_TX 0xEE02
/* Client Characteristic Configuration UUID */
#define BLE_EEG_CLIENT_CHARACTERISTIC_CONFIGURATION 0x2902

static uint16_t g_ble_eeg_conn_id;
static uint8_t g_ble_eeg_name_value[] = "EEG_Reader";
static uint8_t g_ble_eeg_server_app_uuid[] = { 0x00, 0x00 };
static uint8_t g_ble_eeg_server_addr[] = {
    0x11, 0x22, 0x33, 0x44, 0x55, (uint8_t)(0x60 + EEG_DEVICE_ID)
};
static uint8_t g_server_id = BLE_EEG_INVALID_SERVER_ID;
static uint8_t g_connection_state = 0;
static uint16_t g_notify_indicate_handle = 0;
static bool g_adv_started = false;

static void bts_data_to_uuid_len2(uint16_t uuid_data, bt_uuid_t *out_uuid)
{
    out_uuid->uuid_len = BLE_EEG_UUID16_LEN;
    out_uuid->uuid[0] = (uint8_t)(uuid_data >> 8);
    out_uuid->uuid[1] = (uint8_t)(uuid_data);
}

static void ble_eeg_add_service(void)
{
    bt_uuid_t service_uuid = { 0 };
    bts_data_to_uuid_len2(BLE_EEG_UUID_SERVER_SERVICE, &service_uuid);
    gatts_add_service(BLE_EEG_SERVER_ID, &service_uuid, true);
}

static void ble_eeg_add_tx_characters_and_descriptors(uint8_t server_id, uint16_t srvc_handle)
{
    bt_uuid_t characters_uuid = { 0 };
    uint8_t characters_value[] = { 0x12, 0x34 };

    bts_data_to_uuid_len2(BLE_EEG_CHARACTERISTIC_UUID_TX, &characters_uuid);
    gatts_add_chara_info_t character;
    character.chara_uuid = characters_uuid;
    character.properties = GATT_CHARACTER_PROPERTY_BIT_NOTIFY | GATT_CHARACTER_PROPERTY_BIT_READ;
    character.permissions = GATT_ATTRIBUTE_PERMISSION_READ | GATT_ATTRIBUTE_PERMISSION_WRITE;
    character.value_len = sizeof(characters_value);
    character.value = characters_value;
    gatts_add_characteristic(server_id, srvc_handle, &character);
    osal_printk("%s TX uuid %02x %02x\n", BLE_EEG_SERVER_LOG,
                characters_uuid.uuid[0], characters_uuid.uuid[1]);

    static uint8_t ccc_val[] = { 0x01, 0x00 }; /* notify enabled by default */
    bt_uuid_t ccc_uuid = { 0 };
    bts_data_to_uuid_len2(BLE_EEG_CLIENT_CHARACTERISTIC_CONFIGURATION, &ccc_uuid);
    gatts_add_desc_info_t descriptor;
    descriptor.desc_uuid = ccc_uuid;
    descriptor.permissions = GATT_ATTRIBUTE_PERMISSION_READ |
                             GATT_ATTRIBUTE_PERMISSION_WRITE;
    descriptor.value_len = sizeof(ccc_val);
    descriptor.value = ccc_val;
    gatts_add_descriptor(server_id, srvc_handle, &descriptor);
    osal_printk("%s CCCD added\n", BLE_EEG_SERVER_LOG);
}

static bool bts_eeg_compare_uuid(bt_uuid_t *uuid1, bt_uuid_t *uuid2)
{
    if (uuid1->uuid_len != uuid2->uuid_len) {
        return false;
    }
    return memcmp(uuid1->uuid, uuid2->uuid, uuid1->uuid_len) == 0;
}

static void ble_eeg_server_service_add_cbk(uint8_t server_id, bt_uuid_t *uuid,
                                           uint16_t handle, errcode_t status)
{
    osal_printk("%s service add cbk service:%d srv_handle:%d status:%d\n",
                BLE_EEG_SERVER_LOG, server_id, handle, status);
    ble_eeg_add_tx_characters_and_descriptors(server_id, handle);
    gatts_start_service(server_id, handle);
}

static void ble_eeg_server_characteristic_add_cbk(uint8_t server_id, bt_uuid_t *uuid,
                                                  uint16_t service_handle,
                                                  gatts_add_character_result_t *result,
                                                  errcode_t status)
{
    bt_uuid_t tx_uuid = { 0 };
    bts_data_to_uuid_len2(BLE_EEG_CHARACTERISTIC_UUID_TX, &tx_uuid);
    tx_uuid.uuid_len = uuid->uuid_len;
    if (bts_eeg_compare_uuid(uuid, &tx_uuid)) {
        g_notify_indicate_handle = result->value_handle;
    }
    osal_printk("%s char add cbk service:%d char_val_hdl:%d status:%d ntf_hdl:%d\n",
                BLE_EEG_SERVER_LOG, service_handle, result->value_handle, status,
                g_notify_indicate_handle);
}

static void ble_eeg_server_descriptor_add_cbk(uint8_t server_id, bt_uuid_t *uuid,
                                              uint16_t service_handle, uint16_t handle,
                                              errcode_t status)
{
    osal_printk("%s desc add cbk service:%d desc_hdl:%d status:%d\n",
                BLE_EEG_SERVER_LOG, service_handle, handle, status);
}

static void ble_eeg_server_service_start_cbk(uint8_t server_id, uint16_t handle,
                                             errcode_t status)
{
    osal_printk("%s service start cbk service:%d hdl:%d status:%d\n",
                BLE_EEG_SERVER_LOG, server_id, handle, status);
    if (!g_adv_started && (status == ERRCODE_BT_SUCCESS)) {
        g_adv_started = true;
        ble_eeg_set_adv_data();
        ble_eeg_start_adv();
    }
}

static void ble_eeg_server_adv_enable_cbk(uint8_t adv_id, adv_status_t status)
{
    osal_printk("%s adv enable cbk adv_id:%d status:%d\n",
                BLE_EEG_SERVER_LOG, adv_id, status);
}

static void ble_eeg_server_adv_disable_cbk(uint8_t adv_id, adv_status_t status)
{
    osal_printk("%s adv disable adv_id:%d status:%d\n",
                BLE_EEG_SERVER_LOG, adv_id, status);
}

static void ble_eeg_server_connect_change_cbk(uint16_t conn_id, bd_addr_t *addr,
                                              gap_ble_conn_state_t conn_state,
                                              gap_ble_pair_state_t pair_state,
                                              gap_ble_disc_reason_t disc_reason)
{
    g_ble_eeg_conn_id = conn_id;
    g_connection_state = (uint8_t)conn_state;
    osal_printk("%s connect state change conn_id:%d state:%d pair:%d\n",
                BLE_EEG_SERVER_LOG, conn_id, conn_state, pair_state);
    if (conn_state == GAP_BLE_STATE_CONNECTED) {
        return;
    } else if (conn_state == GAP_BLE_STATE_DISCONNECTED) {
        /* restart advertising so other tablets can connect again */
        g_adv_started = false;
        ble_eeg_set_adv_data();
        ble_eeg_start_adv();
        g_adv_started = true;
    }
}

static void ble_eeg_server_pair_result_cb(uint16_t conn_id, const bd_addr_t *addr,
                                          errcode_t status)
{
    osal_printk("%s pair result conn_id:%d status:%d\n",
                BLE_EEG_SERVER_LOG, conn_id, status);
}

static void ble_eeg_server_register_callbacks(void)
{
    gap_ble_callbacks_t gap_cb = { 0 };
    gatts_callbacks_t service_cb = { 0 };

    gap_cb.start_adv_cb = ble_eeg_server_adv_enable_cbk;
    gap_cb.conn_state_change_cb = ble_eeg_server_connect_change_cbk;
    gap_cb.stop_adv_cb = ble_eeg_server_adv_disable_cbk;
    gap_cb.pair_result_cb = ble_eeg_server_pair_result_cb;
    (void)gap_ble_register_callbacks(&gap_cb);

    service_cb.add_service_cb = ble_eeg_server_service_add_cbk;
    service_cb.add_characteristic_cb = ble_eeg_server_characteristic_add_cbk;
    service_cb.add_descriptor_cb = ble_eeg_server_descriptor_add_cbk;
    service_cb.start_service_cb = ble_eeg_server_service_start_cbk;
    (void)gatts_register_callbacks(&service_cb);

#if (CORE_NUMS < 2)
    enable_ble();
#endif
}

void ble_eeg_server_init(void)
{
    errcode_t ret;
    bt_uuid_t app_uuid = { 0 };
    bd_addr_t ble_addr = { 0 };

    /* give the SLE stack time to settle on dual-mode boot */
    (void)osal_msleep(BLE_EEG_START_DELAY_MS);

    ble_eeg_server_register_callbacks();
    enable_ble();

    app_uuid.uuid_len = sizeof(g_ble_eeg_server_app_uuid);
    if (memcpy_s(app_uuid.uuid, app_uuid.uuid_len, g_ble_eeg_server_app_uuid,
                 sizeof(g_ble_eeg_server_app_uuid)) != EOK) {
        osal_printk("%s app uuid memcpy fail\n", BLE_EEG_SERVER_ERROR);
        return;
    }

    ble_addr.type = BT_ADDRESS_TYPE_PUBLIC_DEVICE_ADDRESS;
    if (memcpy_s(ble_addr.addr, BD_ADDR_LEN, g_ble_eeg_server_addr,
                 sizeof(g_ble_eeg_server_addr)) != EOK) {
        osal_printk("%s addr memcpy fail\n", BLE_EEG_SERVER_ERROR);
        return;
    }

    (void)gap_ble_set_local_name(g_ble_eeg_name_value, sizeof(g_ble_eeg_name_value));
    (void)gap_ble_set_local_addr(&ble_addr);

    ret = gatts_register_server(&app_uuid, &g_server_id);
    if ((ret != ERRCODE_BT_SUCCESS) || (g_server_id == BLE_EEG_INVALID_SERVER_ID)) {
        osal_printk("%s register server fail ret=%d\n", BLE_EEG_SERVER_ERROR, ret);
        return;
    }
    ble_eeg_add_service();
    osal_printk("%s init done server_id:%d\n", BLE_EEG_SERVER_LOG, g_server_id);
}

errcode_t ble_eeg_send_frame(const eeg_frame_t *frame)
{
    uint16_t off = 0;

    if (!ble_eeg_is_connected() || frame == NULL || frame->len == 0 ||
        g_notify_indicate_handle == BLE_EEG_INVALID_ATT_HDL) {
        return ERRCODE_BT_FAIL;
    }

    osal_printk("%s send frame len:%u\n", BLE_EEG_SERVER_LOG, frame->len);
    while (off < frame->len) {
        uint16_t chunk = frame->len - off;
        if (chunk > BLE_EEG_NOTIFY_CHUNK) {
            chunk = BLE_EEG_NOTIFY_CHUNK;
        }
        gatts_ntf_ind_t param = { 0 };
        param.attr_handle = g_notify_indicate_handle;
        param.value_len = chunk;
        param.value = (uint8_t *)(frame->text + off);
        gatts_notify_indicate(BLE_EEG_SERVER_ID, g_ble_eeg_conn_id, &param);
        off += chunk;
        if (off < frame->len) {
            osal_msleep(BLE_EEG_CHUNK_GAP_MS);
        }
    }
    return ERRCODE_BT_SUCCESS;
}

bool ble_eeg_is_connected(void)
{
    return (g_connection_state == (uint8_t)GAP_BLE_STATE_CONNECTED);
}
