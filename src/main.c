#include "hal/gpio.h"
#include "hal/delay.h"
#include "target_init.h"
#include "hardware_config.h"
#include "hardware_pins.h"

#ifdef PLATFORM_STM32F103
#include <stm32f1xx_hal.h>
#endif

int main(void) {
    // Инициализация целевой платформы (тактирование, периферия)
    target_init();

    hal_gpio_pin_t led_pin = { LED_PORT, LED_PIN };

    // Инициализируем светодиод
    hal_gpio_init(&led_pin, HAL_GPIO_MODE_OUTPUT, HAL_GPIO_PULL_NONE);

    // Основной цикл мигания светодиодом
    while (1) {
        hal_gpio_toggle(&led_pin);
        hal_delay_ms(500);
    }

    return 0;
}
