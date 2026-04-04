# Сборка ядра из исходных кодов

## Текст задания
Научиться собирать ядро самостоятельно из исходных кодов.

## Окружение
- Хостовая машина на Windows 11.
- VirtualBox версии 7.2.6 r172322 (Qt6.8.0 on windows)
- Виртуальная машина с Ubuntu Server 24.04.2
    - 2 ядра
    - 2 Гб ОЗУ
    - 10 Гб виртуальный диск

## Источники
https://losst.pro/sobiraem-yadro-linux#toc-6-sborka-yadra-i-ustanovka-vruchnuyu

https://davidaugustat.com/linux/how-to-compile-linux-kernel-on-ubuntu
## Выполнение

### 1. Подготовка

#### Конфигурация оборудования
Процесс сборки ядра ресрсоёмкий и текущая конфигурация (после выполнения первого задания) оборудования не подходит.

Поэтому создаю новую виртуальную машину со следующей конфигурацией оборудования:
- 12 ядер (все доступные для Ryzen 5 5600X)
- 8 Гб ОЗУ
- 40 Гб виртуальный диск

#### Снова настраиваю ssh доступ
#### Устанавливаю необходимые для сборки пакеты
```bash
sudo apt update
sudo apt install build-essential libncurses-dev bison flex libssl-dev libelf-dev bc dwarves
```
#### Скачиваю исходники с kernel.org
```bash
wget https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.19.11.tar.xz
```
#### Распаковываю их в папку
```bash
tar xvf linux-6.19.11.tar.xz
cd linux-6.19.11/
```
#### Создаю конфиг на основании текущей системы
```bash
cp /boot/config-$(uname -r) .config
make olddefconfig
```
`olddefconfig` автоматически ответит на все новые опции значениями по умолчанию
#### Отключаю проверку подписей модулей
Интернет рекомендует отключать, чтобы сборка не падала.
```bash
scripts/config --disable SYSTEM_TRUSTED_KEYS
scripts/config --disable SYSTEM_REVOCATION_KEYS
```
### 2. Сборка
#### Просто запускаю команду сборки
```bash
make
```
#### После запуска запросил ответа на некоторые параметры
```bash
make

<...>

Provide system-wide ring of trusted keys (SYSTEM_TRUSTED_KEYRING) [Y/?] y
  Additional X.509 keys for default system keyring (SYSTEM_TRUSTED_KEYS) [] (NEW)
# просто нажал Enter

<...>

Provide system-wide ring of revocation certificates (SYSTEM_REVOCATION_LIST) [Y/n/?] y
    X.509 certificates to be preloaded into the system blacklist keyring (SYSTEM_REVOCATION_KEYS) [] (NEW)
# просто нажал Enter
```
##### Погуглил, это можно было пропустить, сразу задав следующие строки:
```bash
$ scripts/config --set-str CONFIG_SYSTEM_TRUSTED_KEYS ""
$ scripts/config --set-str CONFIG_SYSTEM_REVOCATION_KEYS ""
```
#### Процесс пошёл
23:38 - Идёт
### 3. Установка
```bash
sudo make modules_install
sudo make install
sudo update-grub
```