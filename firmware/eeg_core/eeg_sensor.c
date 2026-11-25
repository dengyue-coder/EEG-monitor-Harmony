#include "eeg_sensor.h"

#if defined(CONFIG_EEG_SENSOR_MODE_NEUROSKY)
#include "eeg_neurosky.h"
#elif defined(CONFIG_EEG_SENSOR_MODE_ADC)
#include "eeg_adc.h"
#endif

eeg_sensor_data_t g_eeg_sensor = { 0 };

void eeg_sensor_init(void)
{
#if defined(CONFIG_EEG_SENSOR_MODE_NEUROSKY)
    eeg_neurosky_init();
#elif defined(CONFIG_EEG_SENSOR_MODE_ADC)
    eeg_adc_init();
#else
    /* no backend selected: sensor stays "no contact" forever */
#endif
}

void eeg_sensor_poll(uint32_t uptime_ms)
{
#if defined(CONFIG_EEG_SENSOR_MODE_NEUROSKY)
    eeg_neurosky_poll(uptime_ms);
#elif defined(CONFIG_EEG_SENSOR_MODE_ADC)
    eeg_adc_poll(uptime_ms);
#endif
}
