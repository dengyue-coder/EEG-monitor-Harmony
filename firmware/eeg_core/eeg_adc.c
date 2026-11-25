/**
 * ADC direct-sampling backend (EXPERIMENTAL).
 *
 * Samples one ADC channel, keeps a ~1 s window, then:
 *   - RMS of the AC part -> contact gate (electrode touching skin);
 *   - 8 band powers computed with Goertzel filters (real DSP, not simulated).
 *
 * This mode only produces meaningful data when the electrode wiring and an
 * analog front-end (biasing + amplification) are correct. Until then it
 * honestly reports contact-lost (sig=200) and zero bands.
 */

#include <stdbool.h>
#include <math.h>
#include "common_def.h"
#include "securec.h"
#include "soc_osal.h"
#include "adc.h"
#include "adc_porting.h"

#include "eeg_sensor.h"
#include "eeg_adc.h"

#define EEG_ADC_LOG "[eeg adc]"
#define EEG_ADC_WINDOW 200          /* ~1 s at ~200 Hz nominal */
#define EEG_ADC_PERIOD_MS 5
#define EEG_ADC_PROCESS_MS 1000
#define EEG_ADC_MAX_BAND 0xFFFFFFU
#define EEG_ADC_PI 3.14159265358979323846

#ifndef CONFIG_EEG_SENSOR_ADC_CHANNEL
#define CONFIG_EEG_SENSOR_ADC_CHANNEL 0
#endif
#ifndef CONFIG_EEG_SENSOR_ADC_CONTACT_MV
#define CONFIG_EEG_SENSOR_ADC_CONTACT_MV 20
#endif

/* center frequencies of the 8 bands at 200 Hz sampling */
static const double g_band_freq[EEG_BAND_COUNT] = {
    2.5, 6.0, 9.0, 11.5, 15.0, 24.0, 35.0, 45.0
};

static int32_t g_window[EEG_ADC_WINDOW];
static uint16_t g_window_idx = 0;
static bool g_window_full = false;
static uint32_t g_last_sample_ms = 0;
static uint32_t g_last_proc_ms = 0;
static int32_t g_last_sample = 0;

static double eeg_goertzel_power(const int32_t *samples, uint16_t n,
                                 uint16_t fs, double freq, int32_t dc)
{
    double w = 2.0 * EEG_ADC_PI * freq / (double)fs;
    double coeff = 2.0 * cos(w);
    double s0 = 0.0;
    double s1 = 0.0;
    double s2 = 0.0;

    for (uint16_t i = 0; i < n; i++) {
        double x = (double)(samples[i] - dc);
        s2 = s1;
        s1 = s0;
        s0 = x + coeff * s1 - s2;
    }
    return s1 * s1 + s2 * s2 - coeff * s1 * s2;
}

static void eeg_adc_process(uint32_t uptime_ms)
{
    uint16_t n = g_window_full ? EEG_ADC_WINDOW : g_window_idx;
    int64_t sum = 0;
    int64_t sumsq = 0;
    int32_t dc;
    double rms;
    bool contact;

    if (n < 32) {
        return; /* not enough samples yet */
    }

    for (uint16_t i = 0; i < n; i++) {
        sum += g_window[i];
    }
    dc = (int32_t)(sum / n);

    for (uint16_t i = 0; i < n; i++) {
        int64_t d = (int64_t)g_window[i] - dc;
        sumsq += d * d;
    }
    rms = sqrt((double)sumsq / (double)n);
    contact = (rms >= (double)CONFIG_EEG_SENSOR_ADC_CONTACT_MV);

    g_eeg_sensor.valid = contact;
    g_eeg_sensor.poor_signal = contact ? 0 : 200;
    g_eeg_sensor.attention = 0;
    g_eeg_sensor.meditation = 0;
    g_eeg_sensor.raw = (int16_t)((g_last_sample > 32767) ? 32767 :
                                 ((g_last_sample < -32768) ? -32768 : g_last_sample));
    g_eeg_sensor.last_valid_ms = uptime_ms;

    for (uint8_t b = 0; b < EEG_BAND_COUNT; b++) {
        if (contact) {
            double power = eeg_goertzel_power(g_window, n, 200, g_band_freq[b], dc);
            double amp = sqrt(power) / ((double)n / 2.0);
            double scaled = amp * 1000.0;
            g_eeg_sensor.band[b] = (scaled >= (double)EEG_ADC_MAX_BAND) ?
                                   EEG_ADC_MAX_BAND : (uint32_t)scaled;
        } else {
            g_eeg_sensor.band[b] = 0;
        }
    }

    osal_printk("%s proc n=%u rms=%.1f contact=%d\r\n",
                EEG_ADC_LOG, n, rms, contact ? 1 : 0);
}

void eeg_adc_init(void)
{
    uapi_adc_init(ADC_CLOCK_500KHZ);
    uapi_adc_power_en(AFE_SCAN_MODE_MAX_NUM, true);
    (void)memset_s(g_window, sizeof(g_window), 0, sizeof(g_window));
    osal_printk("%s init ok channel=%d\r\n", EEG_ADC_LOG, CONFIG_EEG_SENSOR_ADC_CHANNEL);
}

void eeg_adc_poll(uint32_t uptime_ms)
{
    if ((uptime_ms - g_last_sample_ms) >= EEG_ADC_PERIOD_MS) {
        g_last_sample_ms = uptime_ms;
        int32_t v = uapi_adc_manual_sample(CONFIG_EEG_SENSOR_ADC_CHANNEL);
        if (v >= 0) {
            g_window[g_window_idx] = v;
            g_window_idx = (uint16_t)((g_window_idx + 1) % EEG_ADC_WINDOW);
            if (g_window_idx == 0) {
                g_window_full = true;
            }
            g_last_sample = v;
        }
    }

    if ((uptime_ms - g_last_proc_ms) >= EEG_ADC_PROCESS_MS) {
        g_last_proc_ms = uptime_ms;
        eeg_adc_process(uptime_ms);
    }
}
