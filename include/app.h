#ifndef APP_H
#define APP_H

/* ─── Platform-specific headers (must come first for type definitions) ────── */
#if defined(PLATFORM_STM32F103)
#include <stm32f1xx_hal.h>
#elif defined(PLATFORM_STM32F4)
#include <stm32f4xx_hal.h>
#elif defined(PLATFORM_STM32H743)
#include <stm32h7xx_hal.h>
#elif defined(PLATFORM_ESP32)
#include <driver/gpio.h>
#endif

/* ─── Platform HAL ──────────────────────────────────────────────────────── */
#include "hal/gpio.h"
#include "hal/delay.h"

/* ─── Target init ───────────────────────────────────────────────────────── */
#include "target_init.h"

/* ─── Generated configs (from YAML) ─────────────────────────────────────── */
#include "hardware_config.h"
#include "hardware_pins.h"

#endif /* APP_H */
