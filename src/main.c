#include "app.h"

int main(void) {
    target_init();

    hal_gpio_pin_t led_pin = { LED_PORT, LED_PIN };
    hal_gpio_init(&led_pin, HAL_GPIO_MODE_OUTPUT, HAL_GPIO_PULL_NONE);

    while (1) {
        hal_gpio_toggle(&led_pin);
        hal_delay_ms(500);
    }

    return 0;
}
