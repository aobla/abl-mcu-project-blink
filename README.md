# ABL MCU Project Template

Шаблон кроссплатформенного проекта для MCU на базе `abl-mcu-platform-core`.

## Архитектура

Проект использует `abl-mcu-platform-core` для унифицированного доступа к GPIO на различных архитектурах:
- STM32 (F103, F4, H743 и другие)
- ESP32
- AVR (ATmega328P и другие)

## Структура проекта

```
myproject/
├── CMakeLists.txt              # Универсальная сборка (не требует правок)
├── build.sh                    # Скрипт сборки (читает config)
├── setup.sh                    # Установка зависимостей
├── src/
│   └── main.c                  # Код приложения
├── include/
│   ├── app.h                   # Единый вход — все include приложения
│   └── stm32f1xx_hal_conf.h    # Конфиг HAL (для STM32)
├── target/
│   └── stm32/
│       ├── init/               # Инициализация платформы
│       ├── startup_*.s         # Векторы прерываний (из SDK)
│       ├── system_*.c          # SystemInit (из SDK)
│       └── *_FLASH.ld          # Линкер-скрипт (из SDK)
└── config/
    ├── myproject_config.yml    # ← Конфиг проекта (app-specific)
    └── platform/
        ├── stm32f103_board.yml # ← Hardware config (shared)
        ├── stm32f4_board.yml
        └── ...
```

## Конфигурация

### Project config (`config/myproject_config.yml`)

Описывает **конкретный проект**: имя, приложение, target-файлы.

```yaml
project:
  name: myproject-stm32f103
  description: "My application"
  version: "1.0.0"

hardware:
  board: { name: myboard, version: "1.0" }
  mcu:
    part: STM32F103C8T6
  platform: config/platform/stm32f103_board.yml  # ссылка на hardware config
  id: myboard-v1-stm32f103c8

build:
  type: Release
  output: myproject-stm32f103

features:                    # app-specific (не в hardware config)
  enable_log: true
  enable_cli: false

target:
  startup: target/stm32/startup_stm32f103x8.s
  linker:  target/stm32/STM32F103X8_FLASH.ld
  system:  target/stm32/system_stm32f1xx.c
```

### Platform config (`config/platform/<name>_board.yml`)

Описывает **железо** — частоты, память, пины. Переиспользуется между проектами.

```yaml
platform: stm32f103
cpu: cortex-m3
frequencies:
  hclk: 72000000
  pclk1: 36000000
  pclk2: 72000000
memory:
  flash: 65536      # 64KB
  ram: 20480        # 20KB
pins:
  led:
    port: GPIOC
    pin: 13
    mode: output
  uart_tx:
    port: GPIOA
    pin: 9
    mode: alt_function
  uart_rx:
    port: GPIOA
    pin: 10
    mode: alt_function
```

## Быстрый старт

### 1. Клонирование и установка зависимостей

```bash
git clone <repo-url>
cd myproject

# Установка git-зависимостей (core, drivers, system)
./setup.sh -d

# Установка тулчейна и SDK для платформы
./setup.sh -p stm32f103    # STM32F103 + stm32f1-hal
./setup.sh -p stm32f4      # STM32F4 + stm32f4-hal
./setup.sh -p esp32        # ESP32 (ESP-IDF)
./setup.sh -p avr          # AVR (avr-gcc + avr-libc)

# Только проверка без установки
./setup.sh --check-only -p stm32f103
```

### 2. Сборка

```bash
./build.sh                          # Берёт config из config/*_config.yml
./build.sh -c                       # Clean + rebuild
./build.sh -C config/other_config.yml  # Другой конфиг
./build.sh -p stm32f4 -t Debug      # Переопределение платформы и типа
```

`build.sh` автоматически:
1. Находит `*_config.yml` в `config/`
2. Читает платформу, тип сборки, имя проекта
3. Проверяет тулчейн и зависимости
4. Собирает в `build/<platform>/`

### 3. Результат

```
build/stm32f103/
├── release/
│   ├── myproject-stm32f103.elf   # ELF (GDB, отладка)
│   ├── myproject-stm32f103.bin   # Raw binary (st-flash, OpenOCD)
│   └── myproject-stm32f103.hex   # Intel HEX (программаторы)
└── generated/
    ├── hardware_config.h         # Сгенерировано из YAML
    ├── hardware_pins.h           # Сгенерировано из YAML
    └── generated_gpio_init.c     # Сгенерировано из YAML
```

## Создание нового проекта

1. Скопируйте шаблон:
   ```bash
   cp -r abl-mcu-project-blink my-new-project
   cd my-new-project
   ```

2. Создайте конфиг:
   ```bash
   cp config/blink-lcd-stm32f103_config.yml config/myproject_config.yml
   ```

3. Отредактируйте `config/myproject_config.yml`:
   - `project.name` — имя проекта
   - `hardware.mcu.part` — модель МК
   - `hardware.platform` — путь к platform config
   - `target.*` — startup, linker, system файлы

4. Соберите:
   ```bash
   ./build.sh -C config/myproject_config.yml
   ```

## Расположение зависимостей

```
~/.local/share/
├── abl-mcu-toolchains/               # кросс-компиляторы
│   ├── arm-none-eabi/current/        # STM32 тулчейн
│   ├── avr/current/                  # AVR тулчейн
│   └── esp-idf/v5.2.2/               # ESP-IDF
├── abl-mcu-sdks/                     # SDK для конкретных семейств
│   ├── stm32f1-hal/                  # CMSIS + HAL для STM32F1
│   ├── stm32f4-hal/                  # CMSIS + HAL для STM32F4
│   └── stm32h7-hal/                  # CMSIS + HAL для STM32H7
└── abl-mcu-deps/                     # глобальное хранилище (ABL_DEPS_PATH)
```

### Переопределение путей

```bash
# Глобальное хранилище зависимостей
export ABL_DEPS_PATH=~/.local/share/abl-mcu-deps

# Конкретный тулчейн
export ABL_TOOLCHAIN_PATH=/opt/my-toolchain

# Конкретный SDK
export STM32F1_HAL_ROOT=/opt/stm32f1-hal
```

Приоритет поиска тулчейна:
1. `$ABL_TOOLCHAIN_PATH/bin/`
2. Системный PATH
3. `~/.local/share/abl-mcu-toolchains/<platform>/current/bin/`

Приоритет поиска SDK:
1. CMake cache var (`STM32F1_HAL_ROOT`)
2. Env var (`$STM32F1_HAL_ROOT`)
3. `~/.local/share/abl-mcu-sdks/stm32f1-hal/`
4. `$ABL_DEPS_PATH/stm32f1-hal/`

## Требования

- CMake 3.20+
- Ninja
- Python 3.8+ (для генерации конфиов из YAML)
- Кросс-компилятор для целевой архитектуры

## Лицензия

MIT License
