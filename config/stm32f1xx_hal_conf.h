/**
  ******************************************************************************
  * @file    stm32f1xx_hal_conf.h
  * @brief   HAL configuration file for STM32F103
  ******************************************************************************
  * Minimal configuration for ABL MCU Platform
  */

#ifndef __STM32F1xx_HAL_CONF_H
#define __STM32F1xx_HAL_CONF_H

#include "stm32f1xx.h"

/* ─── Modules ─────────────────────────────────────────────────────────────── */
#define HAL_MODULE_ENABLED
#define HAL_GPIO_MODULE_ENABLED
#define HAL_RCC_MODULE_ENABLED
#define HAL_CORTEX_MODULE_ENABLED
/* #define HAL_DMA_MODULE_ENABLED */
/* #define HAL_ADC_MODULE_ENABLED */
/* #define HAL_CAN_MODULE_ENABLED */
/* #define HAL_UART_MODULE_ENABLED */

/* ─── Oscillator ──────────────────────────────────────────────────────────── */
#if !defined  (HSE_VALUE)
  #define HSE_VALUE    8000000U  /*!< 8 MHz */
#endif

#if !defined  (HSI_VALUE)
  #define HSI_VALUE    8000000U  /*!< 8 MHz */
#endif

#if !defined  (LSE_VALUE)
  #define LSE_VALUE    32768U    /*!< 32.768 kHz */
#endif

#if !defined  (LSI_VALUE)
  #define LSI_VALUE    40000U    /*!< 40 kHz */
#endif

/* ─── Tick ────────────────────────────────────────────────────────────────── */
#define  TICK_INT_PRIORITY            0x0FU  /*!< SysTick priority */
#define  USE_RTOS                     0U
#define  PREFETCH_ENABLE              1U

/* ─── Assert ──────────────────────────────────────────────────────────────── */
#ifdef  USE_FULL_ASSERT
  #define assert_param(expr) ((expr) ? (void)0U : assert_failed((uint8_t *)__FILE__, __LINE__))
  void assert_failed(uint8_t *file, uint32_t line);
#else
  #define assert_param(expr) ((void)0U)
#endif

#include "stm32f1xx_hal_def.h"

#endif /* __STM32F1xx_HAL_CONF_H */
