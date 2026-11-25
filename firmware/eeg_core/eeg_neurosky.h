#ifndef EEG_NEUROSKY_H
#define EEG_NEUROSKY_H

#include <stdint.h>

void eeg_neurosky_init(void);
void eeg_neurosky_poll(uint32_t uptime_ms);

#endif /* EEG_NEUROSKY_H */
