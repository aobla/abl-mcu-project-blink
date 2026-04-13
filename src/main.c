#include "app.h"

int main(void) {
    target_init();

    while (1) {
        hal_gpio_toggle(PIN_GET(led));
        hal_delay_ms(500);
    }

    return 0;
}
