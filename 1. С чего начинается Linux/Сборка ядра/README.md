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
$ sudo apt update
$ sudo apt install build-essential libncurses-dev bison flex libssl-dev libelf-dev bc dwarves
```

#### Скачиваю исходники ядра версии `6.9.11` с kernel.org
```bash
$ wget https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.19.11.tar.xz
```

#### Распаковываю их в папку
```bash
$ tar xvf linux-6.19.11.tar.xz
$ cd linux-6.19.11/
```

#### Создаю конфиг на основании текущей системы
```bash
$ cp /boot/config-$(uname -r) .config
$ make olddefconfig
```
`olddefconfig` автоматически ответит на все новые опции значениями по умолчанию

#### Отключаю проверку подписей модулей
В статьях рекомендуют отключать, чтобы сборка не падала.
```bash
$ scripts/config --disable SYSTEM_TRUSTED_KEYS
$ scripts/config --disable SYSTEM_REVOCATION_KEYS
```

### 2. Сборка
#### Просто запускаю команду сборки
Для ускорения сборки указываю количество используемых для сборки ядер с помощью параметра `-j` 

```bash
$ make -j12
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
2026-04-04 23:38 - Началась

2026-04-05 00:23 - Увидел, что закончилась

#### Сборка модулей ядра
```bash
$ make modules -j12
```

### 3. Установка
#### Установка модулей ядра
```bash
$ sudo make modules_install
```

#### 3.1 **ОШИБКА**
##### В процессе установки модулей ядра вылезла ошибка
```bash
cp: error copying 'drivers/net/ethernet/alteon/acenic.ko' to '/lib/modules/6.19.11/kernel/drivers/net/ethernet/alteon/acenic.ko': No space left on device
make[2]: *** [scripts/Makefile.modinst:123: /lib/modules/6.19.11/kernel/drivers/net/ethernet/alteon/acenic.ko] Error 1
make[2]: *** Deleting file '/lib/modules/6.19.11/kernel/drivers/net/ethernet/alteon/acenic.ko'
make[1]: *** [/home/enoch/linux-6.19.11/Makefile:1971: modules_install] Error 2
make: *** [Makefile:248: __sub-make] Error 2
```

Судя по `No space left on device` - кончилось место. Проверяю.
```bash
$ df -h
Filesystem      Size  Used Avail Use% Mounted on
tmpfs           794M  1.1M  793M   1% /run
/dev/sda2        40G   40G     0 100% /
tmpfs           3.9G     0  3.9G   0% /dev/shm
tmpfs           5.0M     0  5.0M   0% /run/lock
tmpfs           794M   12K  794M   1% /run/user/1000
```
Действительно кончилось.

##### Увеличение диска
В VirtualBox увеличиваю размер виртуального диска до 100 Гб, потом внутри ВМ расширяю раздел с помощью утилиты cloud-guest-utils
```bash
$ sudo apt install cloud-guest-utils
$ sudo growpart /dev/sda 2
$ sudo resize2fs /dev/sda2

$ df -h
Filesystem      Size  Used Avail Use% Mounted on
tmpfs           794M  1.1M  793M   1% /run
/dev/sda2        99G   37G   58G  39% /
tmpfs           3.9G     0  3.9G   0% /dev/shm
tmpfs           5.0M     0  5.0M   0% /run/lock
tmpfs           794M   12K  794M   1% /run/user/1000
```

##### Ещё одна попытка
```bash
$ sudo make modules_install
```

#### Модули ядра успешно установились
#### Установка ядра
```bash
$ sudo make install
```

### 4. Проверка
#### Проверяю, что ядро появилось в /boot
```bash
$ ls -al /boot
lrwxrwxrwx  1 root root        15 Apr  4 22:59 vmlinuz -> vmlinuz-6.19.11
-rw-r--r--  1 root root  15958528 Apr  4 22:59 vmlinuz-6.19.11
-rw-------  1 root root  15042952 Mar 13 17:46 vmlinuz-6.8.0-107-generic
lrwxrwxrwx  1 root root        25 Apr  4 19:52 vmlinuz.old -> vmlinuz-6.8.0-107-generic
```

#### Перезагрузка и проверка используемого ядра
```bash
$ sudo reboot
```

### 5. ОШИБКА
#### Диагностика
После перезагрузки, система не стартанула и выпала в (initramfs).

По какой-то причине ядро не видит диска, с которого надо загружаться.

Исследование показало, что отсутствует драйвер SATA.

Попытки вручную его подключить не привели ни к чему.

Но я смог загрузиться с использованием старого ядра.

Предполагаю, что прошлый процесс сборки завершился некорректно, поэтому попробую пересобрать ядро заново.

#### Исправление
##### Сначала очищаю файлы предыдущей сборки
```bash
$ cd linux-6.19.11/
$ make clean
rm: cannot remove './arch/x86_64/boot/bzImage': Permission denied
make[1]: *** [arch/x86/Makefile:349: archclean] Error 1
make: *** [Makefile:248: __sub-make] Error 2

$ sudo rm ./arch/x86_64/boot/bzImage
$ make clean
rm: cannot remove './arch/x86_64/boot': Permission denied
make[1]: *** [arch/x86/Makefile:349: archclean] Error 1
make: *** [Makefile:248: __sub-make] Error 2
$ sudo rm -d ./arch/x86_64/boot
$ make clean
  CLEAN   modules.builtin modules.builtin.modinfo vmlinux.unstripped .vmlinux.objs .vmlinux.export.c
```

##### Источники
Поискал новые актуальны источники, нашёл

[https://www.kernel.org/doc/html/latest/admin-guide/README.html#](https://www.kernel.org/doc/html/latest/admin-guide/README.html#) 

[https://canonical-kernel-docs.readthedocs-hosted.com/latest/how-to/develop-customise/build-kernel/](https://canonical-kernel-docs.readthedocs-hosted.com/latest/how-to/develop-customise/build-kernel/)

Решил действовать по актуальной инструкции по сборке из исходных кодов.

##### Начинаю сборку заново
```bash
# удаляю папку с исходниками
rm -rf linux-6.19.11

# проверяю, что все необходимые пакеты установлены
sudo apt install build-essential libncurses-dev bison flex libssl-dev libelf-dev dwarves bc llvm dkms

# распаковываю архив с исходниками
tar xvf linux-6.19.11.tar.xz
cd linux-6.19.11/

# очищаю от остатков предыдущей сборки
make mrproper

# конфигурирую
make olddefconfig
scripts/config --disable SYSTEM_TRUSTED_KEYS
scripts/config --disable SYSTEM_REVOCATION_KEYS
scripts/config --set-str CONFIG_SYSTEM_TRUSTED_KEYS ""
scripts/config --set-str CONFIG_SYSTEM_REVOCATION_KEYS ""

# запускаю сборку заново и жду
make -j12

# устанавливаю модули
sudo make modules_install

# устанавливаю ядро, загрузчик по идее должен обновиться сам
$ sudo make install
  INSTALL /boot
run-parts: executing /etc/kernel/postinst.d/dkms 6.19.11 /boot/vmlinuz-6.19.11
 * dkms: running auto installation service for kernel 6.19.11
 * dkms: autoinstall for kernel 6.19.11                                                         [ OK ]
run-parts: executing /etc/kernel/postinst.d/initramfs-tools 6.19.11 /boot/vmlinuz-6.19.11
update-initramfs: Generating /boot/initrd.img-6.19.11
run-parts: executing /etc/kernel/postinst.d/unattended-upgrades 6.19.11 /boot/vmlinuz-6.19.11
run-parts: executing /etc/kernel/postinst.d/update-notifier 6.19.11 /boot/vmlinuz-6.19.11
run-parts: executing /etc/kernel/postinst.d/xx-update-initrd-links 6.19.11 /boot/vmlinuz-6.19.11
run-parts: executing /etc/kernel/postinst.d/zz-update-grub 6.19.11 /boot/vmlinuz-6.19.11
Sourcing file `/etc/default/grub'
Generating grub configuration file ...
Found linux image: /boot/vmlinuz-6.19.11
Found initrd image: /boot/initrd.img-6.19.11
Found linux image: /boot/vmlinuz-6.19.11.old
Found initrd image: /boot/initrd.img-6.19.11
Found linux image: /boot/vmlinuz-6.8.0-107-generic
Found initrd image: /boot/initrd.img-6.8.0-107-generic
Warning: os-prober will not be executed to detect other bootable partitions.
Systems on them will not be added to the GRUB boot configuration.
Check GRUB_DISABLE_OS_PROBER documentation entry.
Adding boot menu entry for UEFI Firmware Settings ...
done
```

Вроде бы прошло успешно, перезагружаюсь:
```bash
sudo reboot
```

### 6. Ещё одна проверка
Система успешно загрузилась, без ошибок. Проверяю версию ядра.
```bash
$ uname -r
6.19.11
```

## Успех
Ядро успешно собрано из исходников, система загрузилась корректно с новым ядром.

Задание выполнено.