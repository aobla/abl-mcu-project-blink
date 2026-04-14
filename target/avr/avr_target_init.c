#include "app.h"

#ifdef PLATFORM_AVR

#include <avr/io.h>

// Сгенерированная функция инициализации GPIO
extern void generated_gpio_init(void);

void abl_target_init(void)
{
    /* Тактирование AVR задаётся fuse битами — инициализация не требуется */
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

#endif /* PLATFORM_AVR */
