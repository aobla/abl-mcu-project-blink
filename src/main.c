#include "app.h"

/**
 * @brief Точка входа приложения (D7).
 *
 * Платформенный трaмполин (int main для STM32/AVR, app_main для ESP32)
 * вызывает эту функцию; здесь — инициализация платформы и бизнес-логика.
 */
void abl_main(void)
{
    abl_target_init();

    while (1) {
        abl_gpio_toggle(PIN_GET(led));
        abl_delay_ms(500);
    }
}
