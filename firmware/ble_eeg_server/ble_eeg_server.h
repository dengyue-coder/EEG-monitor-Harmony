/**
 * BLE GATT server of the EEG brain ring.
 *
 * Device name : EEG_Reader
 * Service     : 0xEE01  (0000EE01-0000-1000-8000-00805F9B34FB)
 * Characteristic : 0xEE02 notify + read (0000EE02-...)
 *
 * The HarmonyOS app discovers this service and subscribes to 0xEE02
 * notifications, then reassembles JSON frames from the chunks.
 */

#ifndef BLE_EEG_SERVER_H
#define BLE_EEG_SERVER_H

#include <stdint.h>
#include <stdbool.h>
#include "errcode.h"
#include "eeg_frame.h"

void ble_eeg_server_init(void);
bool ble_eeg_is_connected(void);
errcode_t ble_eeg_send_frame(const eeg_frame_t *frame);

#endif /* BLE_EEG_SERVER_H */
