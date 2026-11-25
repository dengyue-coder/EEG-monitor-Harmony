#ifndef EEG_FRAME_H
#define EEG_FRAME_H

#include <stdbool.h>
#include <stdint.h>

#define EEG_FRAME_MAX_LEN 1024

/* 每帧最多携带的原始波形采样数（约 100Hz 采样，50 个/帧） */
#define EEG_FRAME_RAW_BATCH_MAX 64

typedef struct {
    char text[EEG_FRAME_MAX_LEN];
    uint16_t len;
    uint32_t seq;
    bool no_contact;
} eeg_frame_t;

bool eeg_frame_build(eeg_frame_t *frame, uint32_t uptime_ms);

/* 主循环每 10ms 调用一次，把最新原始采样压入帧缓冲 */
void eeg_frame_push_raw(int16_t raw);

#endif /* EEG_FRAME_H */
