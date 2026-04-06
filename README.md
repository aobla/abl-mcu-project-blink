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
    ├── stm32f4_board_pinmux.yml
    ├── stm32f103_board_config.yml
    ├── stm32f103_board_pinmux.yml
    ├── stm32h743_board_config.yml
    ├── stm32h743_board_pinmux.yml
    ├── esp32_board_config.yml
    ├── esp32_board_pinmux.yml
    ├── avr_board_config.yml
    └── avr_board_pinmux.yml
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
- `*_board_config.yml` - частоты, память, включенные фичи
- `*_board_pinmux.yml` - назначение пинов

## Требования

- CMake 3.20+
- Ninja
- Кросс-компиляторы для целевых архитектур

## Быстрый старт

### 1. Клонирование и установка зависимостей

```bash
git clone <repo-url>
cd abl-mcu-project-blink

# Установка зависимостей для выбранной платформы
./setup.sh -p stm32     # STM32 (arm-none-eabi-gcc)
./setup.sh -p avr       # AVR (avr-gcc)
./setup.sh -p esp32     # ESP32 (ESP-IDF)
./setup.sh -p stm32 -p avr  # Несколько платформ

# Или только проверка без установки
./setup.sh --check-only -p stm32
```

`setup.sh`:
- Проверяет системные пакеты (apt/pacman/brew)
- Если тулчейн уже установлен в системе — использует его
- Скачивает тулчейн в `~/.local/share/abl-mcu-toolchains/` если системного нет
- Устанавливает Python-зависимости (pyyaml, jinja2)

### 2. Сборка

```bash
./build.sh -p stm32f4
./build.sh -p avr -t Debug
./build.sh -p esp32 -c    # clean build
```

`build.sh` автоматически проверяет наличие тулчейна и подскажет запустить `setup.sh` если его нет.

### Переопределение пути тулчейна

```bash
# Использовать конкретный тулчейн
export ABL_TOOLCHAIN_PATH=/opt/my-toolchain
./build.sh -p stm32f4
```

Приоритет поиска тулчейна:
1. `$ABL_TOOLCHAIN_PATH/bin/`
2. Системный PATH (`arm-none-eabi-gcc`, `avr-gcc`, etc.)
3. `~/.local/share/abl-mcu-toolchains/<platform>/current/bin/`

## Лицензия

MIT License