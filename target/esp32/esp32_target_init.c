#include "app.h"

#ifdef PLATFORM_ESP32

#include <driver/gpio.h>

// Сгенерированная функция инициализации GPIO
extern void generated_gpio_init(void);

void abl_target_init(void)
{
    /* ESP-IDF инициализирует тактирование автоматически */
    target_gpio_init();
}

void abl_target_gpio_init(void)
{
    generated_gpio_init();
}

void abl_target_delay_ms(uint32_t ms)
{
    hal_delay_ms(ms);
}

#endif /* PLATFORM_ESP32 */
