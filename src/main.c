#include "app.h"

int main(void) {
    abl_target_init();

    while (1) {
        abl_gpio_toggle(PIN_GET(led));
        abl_delay_ms(500);
    }

    return 0;
}
