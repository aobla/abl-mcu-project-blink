#include "target_init.h"
#include "hal/gpio.h"
#include "hal/delay.h"
#include "hardware_config.h"
#include "generated/hardware_pins.h"

#ifdef PLATFORM_AVR

#include <avr/io.h>

// Сгенерированная функция инициализации GPIO
extern void generated_gpio_init(void);

void target_init(void)
{
    /* Тактирование AVR задаётся fuse битами — инициализация не требуется */
    target_gpio_init();
}

void target_gpio_init(void)
{
    generated_gpio_init();
}

void target_delay_ms(uint32_t ms)
{
    hal_delay_ms(ms);
}

#endif /* PLATFORM_AVR */
