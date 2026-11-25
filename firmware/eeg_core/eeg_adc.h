#ifndef EEG_ADC_H
#define EEG_ADC_H

#include <stdint.h>

void eeg_adc_init(void);
void eeg_adc_poll(uint32_t uptime_ms);

#endif /* EEG_ADC_H */
