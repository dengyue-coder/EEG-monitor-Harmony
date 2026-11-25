/**
 * SLE SSAP server implementation, adapted from the SDK sle_uart sample:
 *   - service/property UUIDs changed to 0xEE01 / 0xEE02;
 *   - broadcast name changed to "EEG_Reader";
 *   - frames are sent via property notify (chunked to SLE_EEG_NOTIFY_CHUNK);
 *   - every board can get a unique announce address via EEG_DEVICE_ID.
 */

#include "common_def.h"
#include "securec.h"
#include "soc_osal.h"
#include "sle_errcode.h"
#include "sle_common.h"
#include "sle_low_latency.h"
#include "sle_connection_manager.h"
#include "sle_device_discovery.h"

#include "sle_eeg_server_adv.h"
#include "sle_eeg_server.h"

#define OCTET_BIT_LEN 8
#define UUID_LEN_2 2
#define UUID_INDEX 14
#define BT_INDEX_0 0
#define BT_INDEX_4 4
#define SLE_ADV_HANDLE_DEFAULT 1
#define SLE_EEG_NOTIFY_CHUNK 200
#define SLE_EEG_CHUNK_GAP_MS 4

#define SLE_EEG_SERVER_LOG "[sle eeg server]"

#ifndef EEG_DEVICE_ID
#define EEG_DEVICE_ID 0
#endif

/* sle server app uuid */
static char g_sle_eeg_app_uuid[UUID_LEN_2] = { 0xEE, 0x01 };
/* server notify property initial value */
static char g_sle_property_value[OCTET_BIT_LEN] = { 0x0, 0x0, 0x0, 0x0, 0x0, 0x0 };

static uint16_t g_sle_conn_hdl = 0;
static uint8_t g_server_id = 0;
static uint16_t g_service_handle = 0;
static uint16_t g_property_handle = 0;
static uint16_t g_sle_pair_hdl = 0;

static errcode_t g_sle_enable_ret = (errcode_t)0xFFFFFFFF;
static errcode_t g_sle_init_ret = (errcode_t)0xFFFFFFFF;

static uint8_t g_sle_eeg_base[] = {
    0x37, 0xBE, 0xA8, 0x80, 0xFC, 0x70, 0x11, 0xEA,
    0xB7, 0x20, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
};

static void encode2byte_little(uint8_t *ptr, uint16_t data)
{
    *(uint8_t *)(ptr + 1) = (uint8_t)(data >> 8);
    *(uint8_t *)(ptr) = (uint8_t)(data);
}

static void sle_uuid_set_base(sle_uuid_t *out)
{
    if (memcpy_s(out->uuid, SLE_UUID_LEN, g_sle_eeg_base, SLE_UUID_LEN) != EOK) {
        out->len = 0;
        return;
    }
    out->len = UUID_LEN_2;
}

static void sle_uuid_setu2(uint16_t u2, sle_uuid_t *out)
{
    sle_uuid_set_base(out);
    out->len = UUID_LEN_2;
    encode2byte_little(&out->uuid[UUID_INDEX], u2);
}

static void sle_eeg_uuid_print(sle_uuid_t *uuid)
{
    if (uuid == NULL) {
        return;
    }
    if (uuid->len == UUID_LEN_2) {
        osal_printk("%s uuid: %02x %02x\n", SLE_EEG_SERVER_LOG,
                    uuid->uuid[UUID_INDEX], uuid->uuid[UUID_INDEX + 1]);
    }
}

static void ssaps_mtu_changed_cbk(uint8_t server_id, uint16_t conn_id,
                                  ssap_exchange_info_t *mtu_size, errcode_t status)
{
    osal_printk("%s mtu changed conn_id:%x mtu:%x status:%x\n",
                SLE_EEG_SERVER_LOG, conn_id, mtu_size->mtu_size, status);
    if (g_sle_pair_hdl == 0) {
        g_sle_pair_hdl = (uint16_t)(conn_id + 1);
    }
}

static void ssaps_start_service_cbk(uint8_t server_id, uint16_t handle, errcode_t status)
{
    osal_printk("%s start service cbk server_id:%d handle:%x status:%x\n",
                SLE_EEG_SERVER_LOG, server_id, handle, status);
}

static void ssaps_add_service_cbk(uint8_t server_id, sle_uuid_t *uuid,
                                  uint16_t handle, errcode_t status)
{
    osal_printk("%s add service cbk handle:%x status:%x\n",
                SLE_EEG_SERVER_LOG, handle, status);
    sle_eeg_uuid_print(uuid);
}

static void ssaps_add_property_cbk(uint8_t server_id, sle_uuid_t *uuid,
                                   uint16_t service_handle, uint16_t handle,
                                   errcode_t status)
{
    osal_printk("%s add property cbk svc:%x handle:%x status:%x\n",
                SLE_EEG_SERVER_LOG, service_handle, handle, status);
    sle_eeg_uuid_print(uuid);
}

static void ssaps_add_descriptor_cbk(uint8_t server_id, sle_uuid_t *uuid,
                                     uint16_t service_handle, uint16_t property_handle,
                                     errcode_t status)
{
    osal_printk("%s add descriptor cbk svc:%x prop:%x status:%x\n",
                SLE_EEG_SERVER_LOG, service_handle, property_handle, status);
    sle_eeg_uuid_print(uuid);
}

static void ssaps_delete_all_service_cbk(uint8_t server_id, errcode_t status)
{
    osal_printk("%s delete all service cbk status:%x\n",
                SLE_EEG_SERVER_LOG, status);
}

static void ssaps_server_read_request_cbk(uint8_t server_id, uint16_t conn_id,
                                          ssaps_req_read_cb_t *read_cb_para,
                                          errcode_t status)
{
    osal_printk("%s read req server_id:%x conn_id:%x handle:%x status:%x\n",
                SLE_EEG_SERVER_LOG, server_id, conn_id, read_cb_para->handle, status);
}

static void ssaps_server_write_request_cbk(uint8_t server_id, uint16_t conn_id,
                                           ssaps_req_write_cb_t *write_cb_para,
                                           errcode_t status)
{
    osal_printk("%s write req server_id:%x conn_id:%x handle:%x status:%x\n",
                SLE_EEG_SERVER_LOG, server_id, conn_id, write_cb_para->handle, status);
}

static errcode_t sle_ssaps_register_cbks(ssaps_read_request_callback ssaps_read_callback,
                                         ssaps_write_request_callback ssaps_write_callback)
{
    ssaps_callbacks_t ssaps_cbk = { 0 };
    ssaps_cbk.add_service_cb = ssaps_add_service_cbk;
    ssaps_cbk.add_property_cb = ssaps_add_property_cbk;
    ssaps_cbk.add_descriptor_cb = ssaps_add_descriptor_cbk;
    ssaps_cbk.start_service_cb = ssaps_start_service_cbk;
    ssaps_cbk.delete_all_service_cb = ssaps_delete_all_service_cbk;
    ssaps_cbk.mtu_changed_cb = ssaps_mtu_changed_cbk;
    ssaps_cbk.read_request_cb = ssaps_read_callback;
    ssaps_cbk.write_request_cb = ssaps_write_callback;
    return ssaps_register_callbacks(&ssaps_cbk);
}

static errcode_t sle_uuid_server_service_add(void)
{
    sle_uuid_t service_uuid = { 0 };
    sle_uuid_setu2(SLE_EEG_UUID_SERVER_SERVICE, &service_uuid);
    return ssaps_add_service_sync(g_server_id, &service_uuid, 1, &g_service_handle);
}

static errcode_t sle_uuid_server_property_add(void)
{
    ssaps_property_info_t property = { 0 };
    ssaps_desc_info_t descriptor = { 0 };
    uint8_t ntf_value[] = { 0x01, 0x00 };
    errcode_t ret;

    property.permissions = SSAP_PERMISSION_READ | SSAP_PERMISSION_WRITE;
    property.operate_indication = SSAP_OPERATE_INDICATION_BIT_READ |
                                  SSAP_OPERATE_INDICATION_BIT_NOTIFY;
    sle_uuid_setu2(SLE_EEG_UUID_NTF_REPORT, &property.uuid);
    property.value = (uint8_t *)osal_vmalloc(sizeof(g_sle_property_value));
    if (property.value == NULL) {
        return ERRCODE_SLE_FAIL;
    }
    if (memcpy_s(property.value, sizeof(g_sle_property_value), g_sle_property_value,
                 sizeof(g_sle_property_value)) != EOK) {
        osal_vfree(property.value);
        return ERRCODE_SLE_FAIL;
    }
    ret = ssaps_add_property_sync(g_server_id, g_service_handle, &property,
                                  &g_property_handle);
    if (ret != ERRCODE_SLE_SUCCESS) {
        osal_vfree(property.value);
        return ret;
    }

    descriptor.permissions = SSAP_PERMISSION_READ | SSAP_PERMISSION_WRITE;
    descriptor.type = SSAP_DESCRIPTOR_USER_DESCRIPTION;
    descriptor.operate_indication = SSAP_OPERATE_INDICATION_BIT_READ |
                                    SSAP_OPERATE_INDICATION_BIT_WRITE;
    descriptor.value = ntf_value;
    descriptor.value_len = sizeof(ntf_value);

    ret = ssaps_add_descriptor_sync(g_server_id, g_service_handle,
                                    g_property_handle, &descriptor);
    if (ret != ERRCODE_SLE_SUCCESS) {
        osal_printk("%s add descriptor fail ret:%x\n", SLE_EEG_SERVER_LOG, ret);
        osal_vfree(property.value);
        return ret;
    }
    osal_vfree(property.value);
    return ERRCODE_SLE_SUCCESS;
}

static errcode_t sle_eeg_server_add(void)
{
    errcode_t ret;
    sle_uuid_t app_uuid = { 0 };

    app_uuid.len = sizeof(g_sle_eeg_app_uuid);
    if (memcpy_s(app_uuid.uuid, app_uuid.len, g_sle_eeg_app_uuid,
                 sizeof(g_sle_eeg_app_uuid)) != EOK) {
        return ERRCODE_SLE_FAIL;
    }
    ssaps_register_server(&app_uuid, &g_server_id);

    if (sle_uuid_server_service_add() != ERRCODE_SLE_SUCCESS) {
        ssaps_unregister_server(g_server_id);
        return ERRCODE_SLE_FAIL;
    }
    if (sle_uuid_server_property_add() != ERRCODE_SLE_SUCCESS) {
        ssaps_unregister_server(g_server_id);
        return ERRCODE_SLE_FAIL;
    }
    osal_printk("%s service added server_id:%x svc:%x prop:%x\n",
                SLE_EEG_SERVER_LOG, g_server_id, g_service_handle, g_property_handle);
    ret = ssaps_start_service(g_server_id, g_service_handle);
    if (ret != ERRCODE_SLE_SUCCESS) {
        osal_printk("%s start service fail ret:%x\n", SLE_EEG_SERVER_LOG, ret);
        return ret;
    }
    return ERRCODE_SLE_SUCCESS;
}

static void sle_connect_state_changed_cbk(uint16_t conn_id, const sle_addr_t *addr,
                                          sle_acb_state_t conn_state,
                                          sle_pair_state_t pair_state,
                                          sle_disc_reason_t disc_reason)
{
    osal_printk("%s connect state changed conn_id:%x conn_state:%x pair:%x reason:%x\n",
                SLE_EEG_SERVER_LOG, conn_id, conn_state, pair_state, disc_reason);
    if (conn_state == SLE_ACB_STATE_CONNECTED) {
        g_sle_conn_hdl = conn_id;
    } else if (conn_state == SLE_ACB_STATE_DISCONNECTED) {
        g_sle_conn_hdl = 0;
        g_sle_pair_hdl = 0;
    }
}

static void sle_pair_complete_cbk(uint16_t conn_id, const sle_addr_t *addr,
                                  errcode_t status)
{
    osal_printk("%s pair complete conn_id:%x status:%x\n",
                SLE_EEG_SERVER_LOG, conn_id, status);
    g_sle_pair_hdl = (uint16_t)(conn_id + 1);
    ssap_exchange_info_t parameter = { 0 };
    parameter.mtu_size = 520;
    parameter.version = 1;
    ssaps_set_info(g_server_id, &parameter);
}

static errcode_t sle_conn_register_cbks(void)
{
    sle_connection_callbacks_t conn_cbks = { 0 };
    conn_cbks.connect_state_changed_cb = sle_connect_state_changed_cbk;
    conn_cbks.pair_complete_cb = sle_pair_complete_cbk;
    return sle_connection_register_callbacks(&conn_cbks);
}

errcode_t sle_eeg_server_init(void)
{
    errcode_t ret;

    g_sle_enable_ret = enable_sle();
    if (g_sle_enable_ret != ERRCODE_SUCC) {
        osal_printk("%s enable_sle fail\n", SLE_EEG_SERVER_LOG);
        return ERRCODE_SLE_FAIL;
    }
    ret = sle_eeg_announce_register_cbks();
    if (ret != ERRCODE_SLE_SUCCESS) {
        g_sle_init_ret = ret;
        osal_printk("%s announce register cbks fail ret:%x\n", SLE_EEG_SERVER_LOG, ret);
        return ret;
    }
    ret = sle_conn_register_cbks();
    if (ret != ERRCODE_SLE_SUCCESS) {
        g_sle_init_ret = ret;
        osal_printk("%s conn register cbks fail ret:%x\n", SLE_EEG_SERVER_LOG, ret);
        return ret;
    }
    ret = sle_ssaps_register_cbks(ssaps_server_read_request_cbk,
                                  ssaps_server_write_request_cbk);
    if (ret != ERRCODE_SLE_SUCCESS) {
        g_sle_init_ret = ret;
        osal_printk("%s ssaps register cbks fail ret:%x\n", SLE_EEG_SERVER_LOG, ret);
        return ret;
    }
    ret = sle_eeg_server_add();
    if (ret != ERRCODE_SLE_SUCCESS) {
        g_sle_init_ret = ret;
        osal_printk("%s add service fail ret:%x\n", SLE_EEG_SERVER_LOG, ret);
        return ret;
    }
    ret = sle_eeg_server_adv_init();
    if (ret != ERRCODE_SLE_SUCCESS) {
        g_sle_init_ret = ret;
        osal_printk("%s adv init fail ret:%x\n", SLE_EEG_SERVER_LOG, ret);
        return ret;
    }
    g_sle_init_ret = ERRCODE_SLE_SUCCESS;
    osal_printk("%s init ok\n", SLE_EEG_SERVER_LOG);
    return ERRCODE_SLE_SUCCESS;
}

void sle_eeg_print_diag(void)
{
    osal_printk("%s diag enable=%x init=%x adv_start=%x adv_status=%x conn=%d\n",
                SLE_EEG_SERVER_LOG, g_sle_enable_ret, g_sle_init_ret,
                sle_eeg_adv_start_ret(), sle_eeg_adv_status(),
                sle_eeg_is_connected() ? 1 : 0);
}

errcode_t sle_eeg_send_frame(const eeg_frame_t *frame)
{
    uint16_t off = 0;

    if (!sle_eeg_is_connected() || frame == NULL || frame->len == 0) {
        return ERRCODE_SLE_FAIL;
    }

    while (off < frame->len) {
        uint16_t chunk = frame->len - off;
        if (chunk > SLE_EEG_NOTIFY_CHUNK) {
            chunk = SLE_EEG_NOTIFY_CHUNK;
        }
        ssaps_ntf_ind_t param = { 0 };
        param.handle = g_property_handle;
        param.type = SSAP_PROPERTY_TYPE_VALUE;
        param.value = (uint8_t *)(frame->text + off);
        param.value_len = chunk;
        errcode_t ret = ssaps_notify_indicate(g_server_id, g_sle_conn_hdl, &param);
        if (ret != ERRCODE_SLE_SUCCESS) {
            osal_printk("%s notify fail off:%d ret:%x\n",
                        SLE_EEG_SERVER_LOG, off, ret);
            return ret;
        }
        off += chunk;
        if (off < frame->len) {
            osal_msleep(SLE_EEG_CHUNK_GAP_MS);
        }
    }
    return ERRCODE_SLE_SUCCESS;
}

bool sle_eeg_is_connected(void)
{
    return (g_sle_conn_hdl != 0);
}
