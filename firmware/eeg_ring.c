/**
 * EEG Brain Ring sample - task entry.
 *
 * Initializes the EEG sensor and both radio links (BLE + SLE), then runs a
 * loop that:
 *   1. polls the sensor (consumes serial bytes / ADC samples),
 *   2. builds one JSON frame every EEG_RING_TX_INTERVAL_MS,
 *   3. sends it to every connected client over BLE and/or SLE.
 *
 * Data honesty rules (implemented in eeg_frame.c):
 *   - with valid contact: real values are sent (sig = poor-signal level);
 *   - without contact / sensor timeout: a contact-lost frame (sig=200, all
 *     values 0) is sent, old data is never replayed.
 */

#include "common_def.h"
#include "soc_osal.h"
#include "app_init.h"

#include "eeg_sensor.h"
#include "eeg_frame.h"
#include "ble_eeg_server.h"
#include "sle_eeg_server.h"

#define EEG_RING_TASK_STACK_SIZE  0x1800
#define EEG_RING_TASK_PRIO        28
#define EEG_RING_LOOP_MS          10

#ifndef CONFIG_EEG_RING_TX_INTERVAL_MS
#define CONFIG_EEG_RING_TX_INTERVAL_MS 500
#endif

static void *eeg_ring_task(const char *arg)
{
    unused(arg);
    uint32_t uptime_ms = 0;
    uint32_t last_tx_ms = 0;
    eeg_frame_t frame;

    osal_printk("[eeg ring] task start\r\n");

    /* Sensor first, then SLE, then BLE (BLE init waits for the SLE stack). */
    eeg_sensor_init();
    sle_eeg_server_init();
    ble_eeg_server_init();

    while (1) {
        uptime_ms += EEG_RING_LOOP_MS;

        eeg_sensor_poll(uptime_ms);
        /* 每 10ms 采集一次原始波形（约 100Hz），打包进下一帧的 r 数组 */
        eeg_frame_push_raw(g_eeg_sensor.raw);

        if ((uptime_ms - last_tx_ms) >= (uint32_t)CONFIG_EEG_RING_TX_INTERVAL_MS) {
            last_tx_ms = uptime_ms;
            if (eeg_frame_build(&frame, uptime_ms)) {
                if (ble_eeg_is_connected()) {
                    ble_eeg_send_frame(&frame);
                }
                if (sle_eeg_is_connected()) {
                    sle_eeg_send_frame(&frame);
                }
            }
        }

        if ((uptime_ms % 10000) < EEG_RING_LOOP_MS) {
            sle_eeg_print_diag();
            osal_printk("[eeg ring] ble_conn=%d\n", ble_eeg_is_connected() ? 1 : 0);
        }

        osal_msleep(EEG_RING_LOOP_MS);
    }
    return NULL;
}

static void eeg_ring_entry(void)
{
    osal_task *task_handle = NULL;

    osal_kthread_lock();
    task_handle = osal_kthread_create((osal_kthread_handler)eeg_ring_task, 0,
                                      "EEGRingTask", EEG_RING_TASK_STACK_SIZE);
    if (task_handle != NULL) {
        osal_kthread_set_priority(task_handle, EEG_RING_TASK_PRIO);
    }
    osal_kthread_unlock();
}

/* Run the eeg_ring_entry. */
app_run(eeg_ring_entry);
