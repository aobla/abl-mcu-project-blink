#include "app.h"

/**
 * @brief Blink task (D6): toggles the LED and sleeps through the runtime.
 *
 * The same source works on both runtimes: on the bare backend abl_sleep_ms()
 * blocks the cooperative loop, on FreeRTOS it yields the CPU.
 */
static void blink_task(void *arg)
{
    (void)arg;

    for (;;) {
        abl_gpio_toggle(PIN_GET(led));
        abl_sleep_ms(CONFIG_BLINK_PERIOD_MS);
    }
}

void abl_main(void)
{
    abl_target_init();

    abl_task_create(blink_task, "blink", NULL);
    abl_runtime_run();   /* never returns */
}
