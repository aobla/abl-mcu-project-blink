#include "app.h"

int main(void) {
    target_init();

    hal_gpio_pin_t led_pin = { LED_PORT, LED_PIN };

    while (1) {
        hal_gpio_toggle(&led_pin);
        hal_delay_ms(500);
    }

    return 0;
}
