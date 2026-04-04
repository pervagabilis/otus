# Занятие 1. Обновление ядра системы

## Цель
Научиться обновлять ядро в ОС Linux.

## Задание
1. Запустить ВМ с Ubuntu.
2. Обновить ядро ОС на новейшую стабильную версию из mainline-репозитория.
3. Оформить отчет в данном файле.

## Окружение
- Хостовая машина на Windows 11.
- VirtualBox версии 7.2.6 r172322 (Qt6.8.0 on windows)
- Виртуальная машина с Ubuntu Server 24.04.2

## Выполнение

### 1. Настройка подключения через ssh
Для удобства копирования/вставки вводимых команд и вывода, установил openssh-server, запустил службу и добавил в автозагрузку.
Брандмауэр не активен, не настраивал.
Так же изменил для виртуальной машины тип подключения с NAT на сетевой мост.

```bash
sudo apt update
sudo apt install openssh-server -y
sudo systemctl enable --now ssh
```
```bash
# узнаю IP интерфейса
hostname -I
192.168.1.8 fd91:1984:51c0:0:a00:27ff:fed1:9bc1
```

```powershell
# подключаюсь из терминала Windows
PS D:\education\otus\alp> ssh enoch@192.168.1.8
enoch@192.168.1.8's password: 
Welcome to Ubuntu 24.04.2 LTS (GNU/Linux 6.8.0-107-generic x86_64)

...

Last login: Sat Apr  4 16:55:34 2026 from 192.168.1.111
```

### 2. Проверка текущей версии ядра
```bash
enoch@ubuntu-otus:~$ uname -r
6.8.0-107-generic
```

### 3. Поиск свежей версии ядра
Перехожу по ссылке https://kernel.ubuntu.com/mainline/
Ищу последнюю версию ядра, которая **НЕ** *-rc, на текущий момент это `v6.19.11`

### 4. Выяснение архитектуры процессора
```bash
enoch@ubuntu-otus:~$ uname -p
x86_64
```

Для это архитектуры требуется amd64

### 5. Скачиваем все необходимые пакеты
Скаичиваем все `*.deb` пакеты доступные по ссылке https://kernel.ubuntu.com/mainline/v6.19.11/amd64/

```bash
enoch@ubuntu-otus:~$ mkdir kernel && cd kernel

enoch@ubuntu-otus:~/kernel$ wget https://kernel.ubuntu.com/mainline/v6.19.11/amd64/linux-headers-6.19.11-061911-generic_6.19.11-061911.202604021147_amd64.deb

enoch@ubuntu-otus:~/kernel$ wget https://kernel.ubuntu.com/mainline/v6.19.11/amd64/linux-headers-6.19.11-061911_6.19.11-061911.202604021147_all.deb

enoch@ubuntu-otus:~/kernel$ wget https://kernel.ubuntu.com/mainline/v6.19.11/amd64/linux-image-unsigned-6.19.11-061911-generic_6.19.11-061911.202604021147_amd64.deb

enoch@ubuntu-otus:~/kernel$ wget https://kernel.ubuntu.com/mainline/v6.19.11/amd64/linux-modules-6.19.11-061911-generic_6.19.11-061911.202604021147_amd64.deb

```

### 6. Установка пакетов
```bash
# устанавливаем все необходимые пакеты сразу
enoch@ubuntu-otus:~/kernel$ sudo dpkg -i *.deb
```

#### Ошибка
При попытке массовой установки возникла ошибка:
```bash
enoch@ubuntu-otus:~/kernel$ sudo dpkg -i *.deb
Preparing to unpack linux-image-unsigned-6.19.11-061911-generic_6.19.11-061911.202604021147_amd64.deb ...
run-parts: missing operand
Try `run-parts --help' for more information.
dpkg: error processing archive linux-image-unsigned-6.19.11-061911-generic_6.19.11-061911.202604021147_amd64.deb (--install):
 new linux-image-unsigned-6.19.11-061911-generic package pre-installation script subprocess returned error exit status 1
run-parts: missing operand
Try `run-parts --help' for more information.
dpkg: error while cleaning up:
 new linux-image-unsigned-6.19.11-061911-generic package post-removal script subprocess returned error exit status 1

Setting up linux-headers-6.19.11-061911-generic (6.19.11-061911.202604021147) ...
dpkg: dependency problems prevent configuration of linux-modules-6.19.11-061911-generic:
 linux-modules-6.19.11-061911-generic depends on linux-main-modules-zfs-6.19.11-061911-generic; however:
  Package linux-main-modules-zfs-6.19.11-061911-generic is not installed.

dpkg: error processing package linux-modules-6.19.11-061911-generic (--install):
 dependency problems - leaving unconfigured
Errors were encountered while processing:
 linux-image-unsigned-6.19.11-061911-generic_6.19.11-061911.202604021147_amd64.deb
 linux-modules-6.19.11-061911-generic
```

Возможно не хватает `zfsutils-linux`
```bash
enoch@ubuntu-otus:~/kernel$ sudo apt install zfsutils-linux
```

Пробую ещё раз, но ошибка всё та же 🤔

Гуглёж показал, что при наличии проприетарных драйверов типа ZFS будет запускаться пересборка через `dkms`

```bash
# проверяю наличие dkms
enoch@ubuntu-otus:~/kernel$ sudo dkms status
sudo: dkms: command not found

# не найден, устанавливаю
enoch@ubuntu-otus:~/kernel$ sudo apt install dkms
```

#### Снова пытаюсь установить.
```bash
enoch@ubuntu-otus:~/kernel$ sudo dpkg -i *.deb
# снова ошибка run-parts
run-parts: missing operand
```

Возможно, какая-то ошибка в свежайшем пакете. Попробую версию `6.19`
```bash
# скачиваю пакеты по ссылке https://kernel.ubuntu.com/mainline/v6.19/amd64/

# пытаюсь установить
enoch@ubuntu-otus:~/kernel$ sudo dpkg -i *.deb
done
```

#### Успех!

#### Проверяю, что ядро появилось в boot
```bash
enoch@ubuntu-otus:~/kernel$ ls -al /boot
lrwxrwxrwx  1 root root       29 Apr  4 18:21 vmlinuz -> vmlinuz-6.19.0-061900-generic
-rw-------  1 root root 17469632 Feb  8 22:31 vmlinuz-6.19.0-061900-generic
-rw-------  1 root root 15042952 Mar 13 17:46 vmlinuz-6.8.0-107-generic
lrwxrwxrwx  1 root root       25 Apr  4 16:21 vmlinuz.old -> vmlinuz-6.8.0-107-generic
```

### 7. Обновляю конфигурацию загрузчика и выбираю загрузку нового ядра по-умолчанию
```bash
enoch@ubuntu-otus:~/kernel$ sudo update-grub
Adding boot menu entry for UEFI Firmware Settings ...
done
ii  linux-headers-6.19.0-061900                6.19.0-061900.202602082231              all          Header files related to Linux kernel version 6.19.0
ii  linux-headers-6.19.0-061900-generic        6.19.0-061900.202602082231              amd64        Linux kernel headers for version 6.19.0
ii  linux-image-unsigned-6.19.0-061900-generic 6.19.0-061900.202602082231              amd64        Linux kernel image for version 6.19.0
ii  linux-modules-6.19.0-061900-generic        6.19.0-061900.202602082231              amd64        Linux kernel modules for version 6.19.0
ii  lshw                                       02.19.git.2021.06.19.996aaad9c7-2build3 amd64        information about hardware configuration
enoch@ubuntu-otus:~/kernel$ sudo grub-set-default 0
```

### 8. Перезагрузка и проверка
```bash
enoch@ubuntu-otus:~$ sudo reboot
# после перезагрузки
enoch@ubuntu-otus:~$ uname -r
6.19.0-061900-generic
```

