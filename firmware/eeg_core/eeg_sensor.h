/**
 * EEG sensor abstraction shared by the radio senders.
 *
 * The backend (NeuroSky UART parser or ADC sampler) fills this structure from
 * the main task context only (via eeg_sensor_poll), so no locking is needed.
 */

#ifndef EEG_SENSOR_H
#define EEG_SENSOR_H

#include <stdint.h>
#include <stdbool.h>

#define EEG_BAND_COUNT 8

typedef struct {
    /* true = the sensor reports the electrode is in contact (sig < 200) */
    bool valid;
    /* NeuroSky poor-signal level: 0 = excellent, >= 200 = no contact */
    uint8_t poor_signal;
    uint8_t attention;
    uint8_t meditation;
    int16_t raw;
    /* Delta, Theta, low-alpha, high-alpha, low-beta, high-beta, low-gamma, mid-gamma */
    uint32_t band[EEG_BAND_COUNT];
    /* monotonic ms timestamp of the last complete sensor packet/sample */
    uint32_t last_valid_ms;
} eeg_sensor_data_t;

extern eeg_sensor_data_t g_eeg_sensor;

void eeg_sensor_init(void);
void eeg_sensor_poll(uint32_t uptime_ms);

#endif /* EEG_SENSOR_H */
