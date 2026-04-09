# ABL MCU Project: Blink 

Простой проект мигания светодиодом, демонстрирующий использование кроссплатформенной MCU-платформы.

## Архитектура

Проект использует `abl-mcu-platform-core` для унифицированного доступа к GPIO на различных архитектурах:
- STM32 (F103, F4, H743 и другие)
- ESP32
- AVR (ATmega328P и другие)

## Структура

```
abl-mcu-project-blink/
├── CMakeLists.txt          # Сборка проекта
├── CMakePresets.json       # Presets для разных платформ
├── src/
│   └── main.c             # Основной код приложения
└── config/
    ├── stm32f4_board_config.yml
    ├── stm32f103_board_config.yml
    ├── stm32h743_board_config.yml
    ├── esp32_board_config.yml
    └── avr_board_config.yml
```

## Код приложения

Основной код находится в `src/main.c` и использует унифицированный HAL:

```c
#include "hal/gpio.h"
#include "hardware_config.h"
#include "hardware_pinmux.h"

int main(void) {
    // Инициализируем светодиод
    hal_gpio_pin_t led_pin = LED_HAL_PIN;
    hal_gpio_init(&led_pin, HAL_GPIO_MODE_OUTPUT, HAL_GPIO_PULL_NONE);
    
    // Основной цикл мигания светодиодом
    while (1) {
        hal_gpio_toggle(&led_pin);
        delay_ms(500);  // 500ms задержка
    }
    
    return 0;
}
```

## Сборка под разные платформы

### STM32F4
```bash
./build.sh -p stm32f4
```

### STM32F103
```bash
./build.sh -p stm32f103
```

### STM32H743
```bash
./build.sh -p stm32h743
```

### ESP32
```bash
./build.sh -p esp32
```

### AVR
```bash
./build.sh -p avr
```

## Конфигурация

Конфигурация для каждой платформы задается в соответствующих YAML-файлах:
- `*_board_config.yml` - частоты, память, включенные фичи, назначение пинов

## Требования

- CMake 3.20+
- Ninja
- Кросс-компиляторы для целевых архитектур

## Быстрый старт

### 1. Клонирование и установка зависимостей

```bash
git clone <repo-url>
cd abl-mcu-project-blink

# Установка git-зависимостей (core, drivers, system)
./setup.sh -d

# Установка тулчейна и SDK для платформы
./setup.sh -p stm32f4      # STM32F4 (arm-none-eabi-gcc + stm32f4-hal)
./setup.sh -p stm32f103    # STM32F103 + stm32f1-hal
./setup.sh -p stm32h743    # STM32H743 + stm32h7-hal
./setup.sh -p avr          # AVR (avr-gcc + avr-libc)
./setup.sh -p esp32        # ESP32 (ESP-IDF)

# Всё сразу
./setup.sh -d -p stm32f4

# Только проверка без установки
./setup.sh --check-only -p stm32f4
```

`setup.sh`:
- **`-d`** — клонирует `lib/abl-mcu-platform-core/`, `lib/abl-mcu-drivers/` и т.д.
- **`-p PLATFORM`** — ставит тулчейн + SDK для платформы
- Приоритет поиска зависимостей: `$ABL_DEPS_PATH` → `project/lib/` → `~/.local/share/abl-mcu-deps/`

### 2. Сборка

```bash
./build.sh -p stm32f4
./build.sh -p avr -t Debug
./build.sh -p esp32 -c    # clean build
```

`build.sh` автоматически проверяет:
1. Git-зависимости (lib/abl-mcu-platform-core/)
2. Тулчейн для платформы
3. Подскажет `./setup.sh -d` или `./setup.sh -p <platform>` если чего-то нет

### Расположение зависимостей

```
project-blink/
├── lib/                              # git-зависимости (setup.sh -d)
│   ├── abl-mcu-platform-core/        # ядро платформы
│   ├── abl-mcu-drivers/              # драйверы (опционально)
│   └── abl-mcu-system/               # системные компоненты (опционально)
└── config/                           # YAML-конфигурации плат

~/.local/share/
├── abl-mcu-toolchains/               # кросс-компиляторы
│   ├── arm-none-eabi/current/        # STM32 тулчейн
│   ├── avr/current/                  # AVR тулчейн
│   └── esp-idf/v5.2.2/               # ESP-IDF
├── abl-mcu-sdks/                     # SDK для конкретных семейств
│   ├── stm32f1-hal/                  # CMSIS для STM32F1
│   ├── stm32f4-hal/                  # CMSIS для STM32F4
│   └── stm32h7-hal/                  # CMSIS для STM32H7
└── abl-mcu-deps/                     # глобальное хранилище (ABL_DEPS_PATH)
```

### Переопределение путей

```bash
# Глобальное хранилище зависимостей
export ABL_DEPS_PATH=~/.local/share/abl-mcu-deps
./setup.sh -d

# Конкретный тулчейн
export ABL_TOOLCHAIN_PATH=/opt/my-toolchain
./build.sh -p stm32f4

# Конкретный SDK
export STM32F4_HAL_ROOT=/opt/stm32f4-hal
./build.sh -p stm32f4
```

Приоритет поиска тулчейна:
1. `$ABL_TOOLCHAIN_PATH/bin/`
2. Системный PATH (`arm-none-eabi-gcc`, `avr-gcc`, etc.)
3. `~/.local/share/abl-mcu-toolchains/<platform>/current/bin/`

Приоритет поиска SDK:
1. CMake cache var (`STM32F4_HAL_ROOT`)
2. Env var (`$STM32F4_HAL_ROOT`)
3. `~/.local/share/abl-mcu-sdks/stm32f4-hal/`
4. `$ABL_DEPS_PATH/stm32f4-hal/`

## Лицензия

MIT License