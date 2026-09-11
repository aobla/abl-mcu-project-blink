# ABL MCU Project Template

Шаблон кроссплатформенного проекта для MCU на базе `abl-mcu-platform`.

## Архитектура

Проект использует `abl-mcu-platform` для унифицированного доступа к GPIO на различных архитектурах:
- STM32 (F103, F4, H743 и другие)
- ESP32
- AVR (ATmega328P и другие)

## Структура проекта

```
myproject/                      # тонкий проект: код приложения + конфиги
├── CMakeLists.txt              # Универсальная сборка (не требует правок)
├── build.sh                    # Скрипт сборки (читает config)
├── setup.sh                    # Установка зависимостей
├── src/
│   └── main.c                  # Код приложения (abl_main)
├── include/
│   └── app.h                   # Единый вход — все include приложения
└── config/
    ├── blink_stm32f103.yml     # ← app-конфиг (продукт): board + overlay + фичи
    └── blink_stm32h743.yml     #    второй продукт на том же src/
```

Bring-up (startup, system, линкер-скрипт, `hal_conf`) в проекте **не лежит** — он
часть платформы (`abl-mcu-platform/soc/`) и выбирается по `mcu.part` (Шаг 2/3 миграции).

## Конфигурация

### App config (`config/<product>.yml`)

Описывает **конкретный проект**: имя, приложение, фичи.

```yaml
product:
  id: myproject-stm32f103
  description: "My application"
  version: "1.0.0"
  board: bluepill_stm32f103    # имя board-дефиниции из платформы
  runtime: bare                # bare | freertos

build:
  type: Release
  # output: myproject-stm32f103  # имя артефактов (по умолчанию = product.id)

# Overlay: что использует ИМЕННО этот проект (D9)
pins:
  led: { use: led0 }           # ссылка на распаянный ресурс платы
  # sensor: { port: GPIOB, pin: 6, mode: input, pull: up }  # своя обвязка

features:                      # → CONFIG_<NAME> 0/1
  enable_log: true
  enable_cli: false

params:                        # → CONFIG_<NAME> <value>
  blink_period_ms: 500
```

### Board (`abl-mcu-platform/boards/<name>.yml`)

Board-дефиниция живёт **в платформе** (D9) и описывает **физику платы**: МК, кварц,
частоты, память и распаянное железо (`onboard` с каноническими алиасами).
Переиспользуется всеми проектами; проект выбирает её по имени (`product.board`).

```yaml
board:  { name: bluepill_stm32f103, description: "Blue Pill" }
platform: stm32f103
mcu:
  part: STM32F103C6T6     # → SoC-дефиниция в платформе (soc/), R3
cpu: cortex-m3
frequencies: { hclk: 72000000, pclk1: 36000000, pclk2: 72000000 }
memory:      { flash: 32768, ram: 10240 }
onboard:
  led0:      { port: GPIOC, pin: 13, mode: output, state: low }
  usart1_tx: { port: GPIOA, pin: 9,  mode: alt_function }
  usart1_rx: { port: GPIOA, pin: 10, mode: alt_function }
```

Пины, которые использует приложение, описывает **проект** (overlay `pins:`), ссылаясь
на алиасы платы (`use: led0`) или задавая свою обвязку. Как добавить плату — см.
`abl-mcu-platform/boards/README.md`.

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
./build.sh                             # если в config/ один *.yml — берёт его
./build.sh -c                          # Clean + rebuild
./build.sh -C config/other.yml         # Другой продукт (app-конфиг)
./build.sh -p stm32f4 -t Debug         # Переопределение платформы и типа
```

`build.sh` автоматически:
1. Находит app-конфиг (`config/*.yml`)
2. По `product.board` находит board-дефиницию в платформе (`boards/<name>.yml`)
3. Из board берёт `mcu.part` и `platform`, проверяет тулчейн и зависимости
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

2. Создайте app-конфиг:
   ```bash
   cp config/blink_stm32f103.yml config/myconfig.yml
   ```

3. Отредактируйте `config/myproject_config.yml`:
   - `project.name` — имя проекта
   - `hardware.platform` — путь к board-конфигу (там же `mcu.part`)

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
