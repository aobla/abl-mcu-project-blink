#ifndef APP_H
#define APP_H

/* ─── Vendor-заголовок платформы (предоставляется SoC-дефиницией) ───────── */
#include "soc_hal.h"

/* ─── Platform HAL + runtime ────────────────────────────────────────────── */
#include "abl_gpio.h"
#include "abl_delay.h"
#include "abl_runtime.h"

/* ─── Platform entry / target init ──────────────────────────────────────── */
#include "abl_app.h"
#include "abl_target_init.h"

/* ─── Generated configs (from YAML) ─────────────────────────────────────── */
#include "hardware_config.h"
#include "hardware_pins.h"

#endif /* APP_H */
