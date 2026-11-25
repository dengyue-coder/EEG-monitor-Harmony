/**
 * Builds one JSON EEG frame for the HarmonyOS app.
 *
 * Honest-data rules:
 *   - contact OK: send real values, sig = raw poor-signal level;
 *   - no contact OR sensor silent for > timeout: send sig=200 with all values
 *     zero (the app shows "等待接触" / "--"), never replay old values;
 *   - every frame carries an incrementing "n" so the app never mistakes a
 *     fresh frame for a replayed/looped buffer.
 */

#include <string.h>
#include "securec.h"
#include "eeg_sensor.h"
#include "eeg_frame.h"

#ifndef CONFIG_EEG_SENSOR_NO_SIGNAL_TIMEOUT_MS
#define CONFIG_EEG_SENSOR_NO_SIGNAL_TIMEOUT_MS 2000
#endif

/* 原始波形采集缓冲：主循环每 10ms 压入一个采样（约 100Hz） */
static int16_t g_raw_buf[EEG_FRAME_RAW_BATCH_MAX];
static uint16_t g_raw_cnt = 0;

void eeg_frame_push_raw(int16_t raw)
{
    if (g_raw_cnt < EEG_FRAME_RAW_BATCH_MAX) {
        g_raw_buf[g_raw_cnt++] = raw;
        return;
    }
    /* 缓冲满（帧间隔内采样超过上限）：丢弃最旧，保留最新 */
    (void)memmove_s(&g_raw_buf[0], sizeof(g_raw_buf) - sizeof(int16_t),
                    &g_raw_buf[1], sizeof(g_raw_buf) - sizeof(int16_t));
    g_raw_buf[EEG_FRAME_RAW_BATCH_MAX - 1] = raw;
}

bool eeg_frame_build(eeg_frame_t *frame, uint32_t uptime_ms)
{
    static uint32_t seq = 0;
    uint32_t timeout = (uint32_t)CONFIG_EEG_SENSOR_NO_SIGNAL_TIMEOUT_MS;
    uint32_t elapsed;
    bool fresh;
    bool contact;
    uint8_t sig;
    int16_t raw;
    uint32_t band[EEG_BAND_COUNT];
    uint8_t att = 0;
    uint8_t med = 0;

    if (frame == NULL) {
        return false;
    }
    (void)memset_s(frame, sizeof(eeg_frame_t), 0, sizeof(eeg_frame_t));
    seq++;
    frame->seq = seq;

    elapsed = (uptime_ms >= g_eeg_sensor.last_valid_ms) ?
              (uptime_ms - g_eeg_sensor.last_valid_ms) : 0;
    fresh = (elapsed <= timeout);
    contact = fresh && g_eeg_sensor.valid;

    if (contact) {
        sig = (g_eeg_sensor.poor_signal < 200) ? g_eeg_sensor.poor_signal : 200;
        raw = g_eeg_sensor.raw;
        att = g_eeg_sensor.attention;
        med = g_eeg_sensor.meditation;
        for (uint8_t i = 0; i < EEG_BAND_COUNT; i++) {
            band[i] = g_eeg_sensor.band[i];
        }
        frame->no_contact = false;
    } else {
        sig = 200;
        raw = 0;
        for (uint8_t i = 0; i < EEG_BAND_COUNT; i++) {
            band[i] = 0;
        }
        frame->no_contact = true;
    }

    uint16_t raw_n = g_raw_cnt;
    frame->len = (uint16_t)snprintf_s(frame->text, sizeof(frame->text),
                                      sizeof(frame->text) - 1,
            "{\"sig\":%u,\"att\":%u,\"med\":%u,\"raw\":%d,"
            "\"d\":%u,\"t\":%u,\"aL\":%u,\"aH\":%u,"
            "\"bL\":%u,\"bH\":%u,\"gL\":%u,\"gM\":%u,\"r\":[",
            (unsigned int)sig, (unsigned int)att, (unsigned int)med, (int)raw,
            (unsigned int)band[0], (unsigned int)band[1],
            (unsigned int)band[2], (unsigned int)band[3],
            (unsigned int)band[4], (unsigned int)band[5],
            (unsigned int)band[6], (unsigned int)band[7]);

    /* 追加原始波形采样：r:[v0,v1,...] */
    for (uint16_t i = 0; i < raw_n; i++) {
        if ((uint32_t)frame->len >= (uint32_t)(sizeof(frame->text) - 16)) {
            break;
        }
        int ret = snprintf_s(frame->text + frame->len,
                             (size_t)(sizeof(frame->text) - frame->len),
                             (size_t)(sizeof(frame->text) - frame->len - 1),
                             i == 0 ? "%d" : ",%d", (int)g_raw_buf[i]);
        if (ret <= 0) {
            break;
        }
        frame->len = (uint16_t)(frame->len + (uint16_t)ret);
    }
    g_raw_cnt = 0;

    /* 收尾：],\"n\":seq}\n */
    {
        int ret = snprintf_s(frame->text + frame->len,
                             (size_t)(sizeof(frame->text) - frame->len),
                             (size_t)(sizeof(frame->text) - frame->len - 1),
                             "],\"n\":%u}\n", (unsigned int)seq);
        if (ret > 0) {
            frame->len = (uint16_t)(frame->len + (uint16_t)ret);
        }
    }
    if (frame->len >= sizeof(frame->text)) {
        frame->len = (uint16_t)(sizeof(frame->text) - 1);
    }
    return true;
}
