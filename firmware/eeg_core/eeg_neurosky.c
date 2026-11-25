/**
 * NeuroSky TGAM1 / BMD101 serial protocol parser.
 *
 * Stream format (each packet):
 *   0xAA 0xAA <len> <payload...> <checksum>
 *   checksum = 1's complement of the sum of the payload bytes.
 *
 * Payload codes used here:
 *   0x02 poor signal (1B, >=200 = no contact)
 *   0x04 attention (1B)
 *   0x05 meditation (1B)
 *   0x16 raw wave (2B, signed big-endian)
 *   0x80 ASIC EEG power (24B = 8 bands x 3B unsigned big-endian)
 *
 * The UART RX callback only copies bytes into a lock-free ring buffer; all
 * parsing happens in the main task context (eeg_neurosky_poll).
 */

#include <stdbool.h>
#include "common_def.h"
#include "securec.h"
#include "errcode.h"
#include "soc_osal.h"
#include "pinctrl.h"
#include "uart.h"

#include "eeg_sensor.h"
#include "eeg_neurosky.h"

#define EEG_NEUROSKY_LOG "[eeg neurosky]"
#define EEG_UART_RX_RING_SIZE 1024
#define EEG_UART_RX_BUFFER_SIZE 256
#define EEG_PARSE_PAYLOAD_MAX 64

#ifndef CONFIG_EEG_SENSOR_UART_BUS
#define CONFIG_EEG_SENSOR_UART_BUS 2
#endif
#ifndef CONFIG_EEG_SENSOR_UART_TXD_PIN
#define CONFIG_EEG_SENSOR_UART_TXD_PIN 12
#endif
#ifndef CONFIG_EEG_SENSOR_UART_RXD_PIN
#define CONFIG_EEG_SENSOR_UART_RXD_PIN 13
#endif
#ifndef CONFIG_EEG_SENSOR_UART_BAUDRATE
#define CONFIG_EEG_SENSOR_UART_BAUDRATE 57600
#endif

/* ---------------- UART ring buffer ---------------- */

static uint8_t g_rx_ring[EEG_UART_RX_RING_SIZE];
static volatile uint16_t g_rx_head = 0; /* producer: UART callback */
static volatile uint16_t g_rx_tail = 0; /* consumer: main task */

static uint8_t g_uart_rx_buf[EEG_UART_RX_BUFFER_SIZE];
static uart_buffer_config_t g_uart_buffer_config = {
    .rx_buffer = g_uart_rx_buf,
    .rx_buffer_size = sizeof(g_uart_rx_buf)
};

static void eeg_uart_rx_callback(const void *buffer, uint16_t length, bool error)
{
    unused(error);
    const uint8_t *p = (const uint8_t *)buffer;
    for (uint16_t i = 0; i < length; i++) {
        uint16_t next = (uint16_t)((g_rx_head + 1) % EEG_UART_RX_RING_SIZE);
        if (next == g_rx_tail) {
            break; /* ring full, drop oldest incoming byte */
        }
        g_rx_ring[g_rx_head] = p[i];
        g_rx_head = next;
    }
}

/* ---------------- parser state machine ---------------- */

typedef enum {
    EEG_PARSER_SYNC1 = 0,
    EEG_PARSER_SYNC2,
    EEG_PARSER_LENGTH,
    EEG_PARSER_PAYLOAD,
    EEG_PARSER_CHECKSUM
} eeg_parser_state_t;

static eeg_parser_state_t g_parse_state = EEG_PARSER_SYNC1;
static uint8_t g_parse_payload[EEG_PARSE_PAYLOAD_MAX];
static uint8_t g_parse_len = 0;
static uint8_t g_parse_idx = 0;
static uint8_t g_parse_sum = 0;
static uint32_t g_last_packet_ms = 0;
static bool g_first_valid_logged = false;

static void eeg_parse_payload(uint32_t uptime_ms)
{
    uint8_t i = 0;

    while (i < g_parse_len) {
        uint8_t code = g_parse_payload[i++];
        uint8_t vlen;

        if ((code & 0x80) != 0) {
            /* extended code: the next byte is the value length */
            if (i >= g_parse_len) {
                break;
            }
            vlen = g_parse_payload[i++];
        } else if (code == 0x16) {
            vlen = 2; /* raw wave */
        } else {
            vlen = 1;
        }

        if ((i + vlen) > g_parse_len) {
            break;
        }

        switch (code) {
            case 0x02:
                g_eeg_sensor.poor_signal = g_parse_payload[i];
                break;
            case 0x04:
                g_eeg_sensor.attention = g_parse_payload[i];
                break;
            case 0x05:
                g_eeg_sensor.meditation = g_parse_payload[i];
                break;
            case 0x16:
                g_eeg_sensor.raw = (int16_t)(((uint16_t)g_parse_payload[i] << 8) |
                                             (uint16_t)g_parse_payload[i + 1]);
                break;
            case 0x80: {
                for (uint8_t b = 0; b < EEG_BAND_COUNT; b++) {
                    uint16_t o = (uint16_t)(i + b * 3);
                    g_eeg_sensor.band[b] = ((uint32_t)g_parse_payload[o] << 16) |
                                           ((uint32_t)g_parse_payload[o + 1] << 8) |
                                           (uint32_t)g_parse_payload[o + 2];
                }
                break;
            }
            default:
                break;
        }

        i = (uint8_t)(i + vlen);
    }

    g_last_packet_ms = uptime_ms;
    g_eeg_sensor.last_valid_ms = uptime_ms;
    g_eeg_sensor.valid = (g_eeg_sensor.poor_signal < 200);

    if (!g_first_valid_logged && g_eeg_sensor.valid) {
        g_first_valid_logged = true;
        osal_printk("%s first valid EEG packet sig=%u att=%u med=%u raw=%d\r\n",
                    EEG_NEUROSKY_LOG,
                    g_eeg_sensor.poor_signal,
                    g_eeg_sensor.attention,
                    g_eeg_sensor.meditation,
                    g_eeg_sensor.raw);
    }
}

static void eeg_parser_feed(uint8_t b, uint32_t uptime_ms)
{
    switch (g_parse_state) {
        case EEG_PARSER_SYNC1:
            if (b == 0xAA) {
                g_parse_state = EEG_PARSER_SYNC2;
            }
            break;
        case EEG_PARSER_SYNC2:
            g_parse_state = (b == 0xAA) ? EEG_PARSER_LENGTH : EEG_PARSER_SYNC1;
            break;
        case EEG_PARSER_LENGTH:
            g_parse_len = b;
            if (g_parse_len > sizeof(g_parse_payload)) {
                g_parse_len = sizeof(g_parse_payload);
            }
            g_parse_idx = 0;
            g_parse_sum = 0;
            g_parse_state = (g_parse_len == 0) ? EEG_PARSER_CHECKSUM : EEG_PARSER_PAYLOAD;
            break;
        case EEG_PARSER_PAYLOAD:
            g_parse_payload[g_parse_idx++] = b;
            g_parse_sum = (uint8_t)(g_parse_sum + b);
            if (g_parse_idx >= g_parse_len) {
                g_parse_state = EEG_PARSER_CHECKSUM;
            }
            break;
        case EEG_PARSER_CHECKSUM: {
            /* accept both documented checksum variants */
            uint8_t expect_ones = (uint8_t)(~g_parse_sum);
            uint8_t expect_twos = (uint8_t)(0x100U - g_parse_sum);
            if (b == expect_ones || b == expect_twos) {
                eeg_parse_payload(uptime_ms);
            }
            g_parse_state = EEG_PARSER_SYNC1;
            break;
        }
        default:
            g_parse_state = EEG_PARSER_SYNC1;
            break;
    }
}

/* ---------------- public API ---------------- */

void eeg_neurosky_init(void)
{
    errcode_t ret;
    uart_attr_t attr;
    uart_pin_config_t pin_config;

    (void)memset_s(&attr, sizeof(attr), 0, sizeof(attr));
    attr.baud_rate = CONFIG_EEG_SENSOR_UART_BAUDRATE;
    attr.data_bits = UART_DATA_BIT_8;
    attr.stop_bits = UART_STOP_BIT_1;
    attr.parity = UART_PARITY_NONE;

    (void)memset_s(&pin_config, sizeof(pin_config), 0, sizeof(pin_config));
    pin_config.tx_pin = CONFIG_EEG_SENSOR_UART_TXD_PIN;
    pin_config.rx_pin = CONFIG_EEG_SENSOR_UART_RXD_PIN;
    pin_config.cts_pin = PIN_NONE;
    pin_config.rts_pin = PIN_NONE;

    uapi_pin_set_mode(CONFIG_EEG_SENSOR_UART_TXD_PIN, PIN_MODE_1);
    uapi_pin_set_mode(CONFIG_EEG_SENSOR_UART_RXD_PIN, PIN_MODE_1);

    uapi_uart_deinit(CONFIG_EEG_SENSOR_UART_BUS);
    ret = uapi_uart_init(CONFIG_EEG_SENSOR_UART_BUS, &pin_config, &attr, NULL,
                         &g_uart_buffer_config);
    if (ret != ERRCODE_SUCC) {
        osal_printk("%s uart init fail ret=%x\r\n", EEG_NEUROSKY_LOG, ret);
        return;
    }

    uapi_uart_unregister_rx_callback(CONFIG_EEG_SENSOR_UART_BUS);
    ret = uapi_uart_register_rx_callback(CONFIG_EEG_SENSOR_UART_BUS,
                                         UART_RX_CONDITION_FULL_OR_IDLE,
                                         1, eeg_uart_rx_callback);
    if (ret != ERRCODE_SUCC) {
        osal_printk("%s uart rx callback register fail ret=%x\r\n", EEG_NEUROSKY_LOG, ret);
        return;
    }
    osal_printk("%s init ok bus=%d rx_pin=%d baud=%d\r\n",
                EEG_NEUROSKY_LOG, CONFIG_EEG_SENSOR_UART_BUS,
                CONFIG_EEG_SENSOR_UART_RXD_PIN, CONFIG_EEG_SENSOR_UART_BAUDRATE);
}

void eeg_neurosky_poll(uint32_t uptime_ms)
{
    while (g_rx_tail != g_rx_head) {
        uint8_t b = g_rx_ring[g_rx_tail];
        g_rx_tail = (uint16_t)((g_rx_tail + 1) % EEG_UART_RX_RING_SIZE);
        eeg_parser_feed(b, uptime_ms);
    }
}
