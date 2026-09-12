/**
 * @brief ESP-IDF entry point (D7).
 *
 * IDF calls app_main(); the application itself lives in the portable abl_main().
 */

#include "abl_app.h"

void app_main(void)
{
    abl_main();
}
