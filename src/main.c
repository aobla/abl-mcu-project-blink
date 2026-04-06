#include "hal/gpio.h"
#include "hal/delay.h"
#include "target_init.h"
#include "hardware_config.h"
#include "generated/hardware_pins.h"

int main(void) {
    // Инициализация целевой платформы (тактирование, периферия)
    target_init();

    // Получаем пин светодиода из сгенерированного файла
    // LED_PORT уже содержит нужное значение:
    //   STM32: GPIOA (указатель на GPIO_TypeDef)
    //   AVR:   ((void*)(uintptr_t)0)  — индекс порта
    //   ESP32: ((void*)(uintptr_t)2)  — номер GPIO
    hal_gpio_pin_t led_pin = { LED_PORT, LED_PIN };

    // Инициализируем светодиод
    hal_gpio_init(&led_pin, HAL_GPIO_MODE_OUTPUT, HAL_GPIO_PULL_NONE);

    // Основной цикл мигания светодиодом
    while (1) {
        hal_gpio_toggle(&led_pin);
        hal_delay_ms(500);  // 500ms задержка через HAL
    }

    return 0;
}