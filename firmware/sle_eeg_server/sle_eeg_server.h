/**
 * SLE (SparkLink) SSAP server of the EEG brain ring.
 *
 * Broadcast name : EEG_Reader
 * Service UUID   : 0xEE01
 * Property UUID  : 0xEE02 (read + notify)
 *
 * The HarmonyOS NearLinkService scans for the name, connects, finds the first
 * NOTIFY property and reassembles JSON frames from property-change events.
 */

#ifndef SLE_EEG_SERVER_H
#define SLE_EEG_SERVER_H

#include <stdint.h>
#include <stdbool.h>
#include "sle_ssap_server.h"
#include "errcode.h"
#include "eeg_frame.h"

#define SLE_EEG_UUID_SERVER_SERVICE 0xEE01
#define SLE_EEG_UUID_NTF_REPORT 0xEE02

errcode_t sle_eeg_server_init(void);
bool sle_eeg_is_connected(void);
errcode_t sle_eeg_send_frame(const eeg_frame_t *frame);
void sle_eeg_print_diag(void);

#endif /* SLE_EEG_SERVER_H */
