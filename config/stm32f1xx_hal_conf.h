/**
  ******************************************************************************
  * @file    stm32f1xx_hal_conf.h
  * @brief   HAL configuration file for STM32F103
  ******************************************************************************
  * Minimal configuration for ABL MCU Platform
  *
  * This file is included by stm32f1xx_hal.h BEFORE stm32f1xx.h.
  * We include stm32f1xx.h here so that CMSIS types (__IO, etc.) are available.
  */

#ifndef __STM32F1xx_HAL_CONF_H
#define __STM32F1xx_HAL_CONF_H

/* ─── Select target device ────────────────────────────────────────────────── */
#if !defined(STM32F100xB) && !defined(STM32F100xE) && \
    !defined(STM32F101x6) && !defined(STM32F101xB) && !defined(STM32F101xE) && !defined(STM32F101xG) && \
    !defined(STM32F102x6) && !defined(STM32F102xB) && \
    !defined(STM32F103x6) && !defined(STM32F103xB) && !defined(STM32F103xE) && !defined(STM32F103xG) && \
    !defined(STM32F105xC) && !defined(STM32F107xC)
  #define STM32F103xB
#endif

/* ─── Include CMSIS + device header ───────────────────────────────────────── */
#include "stm32f1xx.h"
#include "stm32f1xx_hal_def.h"

/* ─── Module headers (only what we use) ───────────────────────────────────── */
#include "stm32f1xx_hal_gpio.h"
#include "stm32f1xx_hal_rcc.h"
#include "stm32f1xx_hal_rcc_ex.h"
#include "stm32f1xx_hal_cortex.h"
#include "stm32f1xx_hal_flash.h"
#include "stm32f1xx_hal_flash_ex.h"

/* ─── Modules ─────────────────────────────────────────────────────────────── */
#define HAL_MODULE_ENABLED
#define HAL_GPIO_MODULE_ENABLED
#define HAL_RCC_MODULE_ENABLED
#define HAL_CORTEX_MODULE_ENABLED

/* ─── Oscillator ──────────────────────────────────────────────────────────── */
#if !defined  (HSE_VALUE)
  #define HSE_VALUE    8000000U
#endif

#if !defined  (HSI_VALUE)
  #define HSI_VALUE    8000000U
#endif

#if !defined  (LSE_VALUE)
  #define LSE_VALUE    32768U
#endif

#if !defined  (LSI_VALUE)
  #define LSI_VALUE    40000U
#endif

/* ─── Startup timeouts ────────────────────────────────────────────────────── */
#define HSE_STARTUP_TIMEOUT    ((uint32_t)0x0500)
#define LSE_STARTUP_TIMEOUT    ((uint32_t)0x5000)

/* ─── Tick ────────────────────────────────────────────────────────────────── */
#define  TICK_INT_PRIORITY            0x0FU
#define  USE_RTOS                     0U
#define  PREFETCH_ENABLE              1U

/* ─── Assert ──────────────────────────────────────────────────────────────── */
#ifdef  USE_FULL_ASSERT
  #define assert_param(expr) ((expr) ? (void)0U : assert_failed((uint8_t *)__FILE__, __LINE__))
  void assert_failed(uint8_t *file, uint32_t line);
#else
  #define assert_param(expr) ((void)0U)
#endif

#endif /* __STM32F1xx_HAL_CONF_H */
