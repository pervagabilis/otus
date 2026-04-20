# Практические навыки работы с ZFS

## Цель
научится самостоятельно устанавливать ZFS, настраивать пулы, изучить основные возможности ZFS;

## Текст задания

🎯 Что нужно сделать?

1. Определить алгоритм с наилучшим сжатием:

- определить, какие алгоритмы сжатия поддерживает zfs (gzip, zle, lzjb, lz4);
- создать 4 файловых системы, на каждой применить свой алгоритм сжатия;
- для сжатия использовать либо текстовый файл, либо группу файлов.

2. Определить настройки пула.

- С помощью команды zfs import собрать pool ZFS.
- Командами zfs определить настройки:

  - размер хранилища;
  - тип pool;
  - значение recordsize;
  - какое сжатие используется;
  - какая контрольная сумма используется.

3. Работа со снапшотами:

- скопировать файл из удаленной директории;
- восстановить файл локально. zfs receive;
- найти зашифрованное сообщение в файле secret_message.

## Окружение

- Хостовая машина на Windows 11.
- VirtualBox версии 7.2.6 r172322 (Qt6.8.0 on windows)
- Виртуальная машина с Ubuntu Server 24.04.2

## Выполнение

### 1. Подготовка, Vagrant

Установлю Vagrant для Windows 11, для этого скачиваю MSI с сайта. Устанавливаю. Перезагружаюсь.
VBox у меня уже есть, для удобства добавлю его в системный PATH.

Проверяю, что всё присутствует на хостовой системе.

```powershell
PS R:\DEV\education\otus> vagrant --version
Vagrant 2.4.9
PS R:\DEV\education\otus> VBoxManage --version                         
7.2.6r172322
```

Сначала проваливаюсь в директорию для виртуалки `> cd R:\DEV\education\otus\4. ZFS\vm\`, в ней создаю  файл конфигурации для Vagrant.

```Vagrantfile
Vagrant.configure("2") do |config|
  config.vm.box = "hashicorp-education/ubuntu-24-04"
  # имя ВМ - otus
  config.vm.hostname = "otus"

  # сетевой мост к интерфейсу Ethernet
  config.vm.network "public_network", bridge: "Ethernet"

  # отключаю вход только по ключам
  config.ssh.keys_only = false

  config.vm.provider "virtualbox" do |vb|
    vb.memory = "8192"
    vb.cpus = 4
    vb.name = "otus"
  end

  (1..8).each do |i|
    config.vm.disk :disk, name: "zfs-disk-#{i}", size: "512MB"
  end

  config.vm.provision "shell", inline: <<-SHELL
    echo "vagrant ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/vagrant
    # создаём пользователя enoch с паролем enoch
    useradd -m -s /bin/bash enoch
    echo 'enoch:enoch' | chpasswd
    # разрешаем выполнение команд без пароля
    echo 'enoch ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/enoch

    # разрешаем вход по паролю через SSH
    sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
    sed -i 's/^#*KbdInteractiveAuthentication.*/KbdInteractiveAuthentication yes/' /etc/ssh/sshd_config
    systemctl restart ssh

    # устанавливаю zfsutils в систему
    apt-get update
    apt-get install -y zfsutils-linux wget curl
  SHELL
end
```

Поднимаю машину командой `vagrant up`

```powershell
PS R:\DEV\education\otus\4. ZFS\vm\> vagrant up
```

Оказалось, что мой адаптер называется не Ethernet, Vagrant предлагает мне выбрать из существующих.

Выбираю 1, мой основной.

```powershell
PS R:\DEV\education\otus\4. ZFS\vm> vagrant up
Bringing machine 'default' up with 'virtualbox' provider...
==> default: Importing base box 'hashicorp-education/ubuntu-24-04'...
==> default: Matching MAC address for NAT networking...
==> default: Checking if box 'hashicorp-education/ubuntu-24-04' version '0.1.0' is up to date...
==> default: Setting the name of the VM: otus
==> default: Fixed port collision for 22 => 2222. Now on port 2200.
==> default: Clearing any previously set network interfaces...
==> default: Specific bridge 'Ethernet' not found. You may be asked to specify
==> default: which network to bridge to.
==> default: Available bridged network interfaces:
1) Intel(R) Ethernet Controller (3) I225-V
2) Realtek USB GbE Family Controller
3) Hyper-V Virtual Ethernet Adapter
==> default: When choosing an interface, it is usually the one that is
==> default: being used to connect to the internet.
==> default:
    default: Which interface should the network bridge to? 1
==> default: Preparing network interfaces based on configuration...
    default: Adapter 1: nat
    default: Adapter 2: bridged
==> default: Forwarding ports...
    default: 22 (guest) => 2200 (host) (adapter 1)
```

Далее машина поднялась нормально, я смог зайти по ssh с паролем.

Проверяю, что нужные диски появились и zfsutils установились в систему.
```bash
root@otus:~# lsblk
NAME                      MAJ:MIN RM  SIZE RO TYPE MOUNTPOINTS
sda                         8:0    0 19.5G  0 disk 
├─sda1                      8:1    0  931M  0 part /boot/efi
├─sda2                      8:2    0  1.8G  0 part /boot
└─sda3                      8:3    0 16.9G  0 part 
  └─ubuntu--vg-ubuntu--lv 252:0    0   10G  0 lvm  /
sdb                         8:16   0  512M  0 disk 
sdc                         8:32   0  512M  0 disk 
sdd                         8:48   0  512M  0 disk 
sde                         8:64   0  512M  0 disk 
sdf                         8:80   0  512M  0 disk 
sdg                         8:96   0  512M  0 disk 
sdh                         8:112  0  512M  0 disk 
sdi                         8:128  0  512M  0 disk

root@otus:~# zfs version
zfs-2.2.2-0ubuntu9.4
zfs-kmod-2.2.2-0ubuntu9.1
```

Всё на месте, перехожу к работе zfs.

## 2. Определение алгоритма с наилучшим сжатием

Создаю 4 пула из двух дисков с RAID-1:
```bash
root@otus:~# zpool create otus1 mirror /dev/sdb /dev/sdc
root@otus:~# zpool create otus2 mirror /dev/sdd /dev/sde
root@otus:~# zpool create otus3 mirror /dev/sdf /dev/sdg
root@otus:~# zpool create otus4 mirror /dev/sdh /dev/sdi
```

Проверяю пулы
```bash
root@otus:~# zpool list
NAME    SIZE  ALLOC   FREE  CKPOINT  EXPANDSZ   FRAG    CAP  DEDUP    HEALTH  ALTROOT
otus1   480M   108K   480M        -         -     0%     0%  1.00x    ONLINE  -
otus2   480M   106K   480M        -         -     0%     0%  1.00x    ONLINE  -
otus3   480M   110K   480M        -         -     0%     0%  1.00x    ONLINE  -
otus4   480M   117K   480M        -         -     0%     0%  1.00x    ONLINE  -
```

Все на месте.

Использую разные алгоритмы сжатия в каждом пуле.
```bash
root@otus:~# zfs set compression=lzjb otus1
root@otus:~# zfs set compression=lz4 otus2
root@otus:~# zfs set compression=gzip-9 otus3
root@otus:~# zfs set compression=zle otus4

# И сразу проверю, что везде используется свой метод сжатия.
root@otus:~# zfs get all | grep compression
otus1  compression           lzjb                       local
otus2  compression           lz4                        local
otus3  compression           gzip-9                     local
otus4  compression           zle                        local
```

У меня на хосте завалялись 4 текстовых файла "Война и Мир", закидываю их в свою папку на виртуалке.
```powershell
PS R:\DEV\education\otus\4. ZFS> scp .\voyna-i-mir-tom-1.txt enoch@192.168.107.145:/home/enoch
voyna-i-mir-tom-1.txt                100%  719KB  39.0MB/s   00:00
PS R:\DEV\education\otus\4. ZFS> scp .\voyna-i-mir-tom-2.txt enoch@192.168.107.145:/home/enoch
voyna-i-mir-tom-2.txt                100%  752KB  66.8MB/s   00:00
PS R:\DEV\education\otus\4. ZFS> scp .\voyna-i-mir-tom-3.txt enoch@192.168.107.145:/home/enoch
voyna-i-mir-tom-3.txt                100%  823KB  67.0MB/s   00:00
PS R:\DEV\education\otus\4. ZFS> scp .\voyna-i-mir-tom-4.txt enoch@192.168.107.145:/home/enoch
voyna-i-mir-tom-4.txt                100%  682KB  55.5MB/s   00:00
```

Проверяю их наличие:
```bash
root@otus:~# ls /home/enoch -l
total 2984
-rw-rw-r-- 1 enoch enoch 736519 апр 19 11:38 voyna-i-mir-tom-1.txt
-rw-rw-r-- 1 enoch enoch 770324 апр 19 11:39 voyna-i-mir-tom-2.txt
-rw-rw-r-- 1 enoch enoch 843205 апр 19 11:39 voyna-i-mir-tom-3.txt
-rw-rw-r-- 1 enoch enoch 697960 апр 19 11:39 voyna-i-mir-tom-4.txt
```

Теперь закидываю эти файлы во все пулы:
```bash
root@otus:~# for i in {1..4}; do cp /home/enoch/*voyna*.txt /otus$i; done
```

Проверяю, что появились:
```bash
root@otus:~# ls -l /otus*
/otus1:
total 2341
-rw-r--r-- 1 root root 736519 апр 19 11:44 voyna-i-mir-tom-1.txt
-rw-r--r-- 1 root root 770324 апр 19 11:44 voyna-i-mir-tom-2.txt
-rw-r--r-- 1 root root 843205 апр 19 11:44 voyna-i-mir-tom-3.txt
-rw-r--r-- 1 root root 697960 апр 19 11:44 voyna-i-mir-tom-4.txt

/otus2:
total 1959
-rw-r--r-- 1 root root 736519 апр 19 11:44 voyna-i-mir-tom-1.txt
-rw-r--r-- 1 root root 770324 апр 19 11:44 voyna-i-mir-tom-2.txt
-rw-r--r-- 1 root root 843205 апр 19 11:44 voyna-i-mir-tom-3.txt
-rw-r--r-- 1 root root 697960 апр 19 11:44 voyna-i-mir-tom-4.txt

/otus3:
total 1235
-rw-r--r-- 1 root root 736519 апр 19 11:44 voyna-i-mir-tom-1.txt
-rw-r--r-- 1 root root 770324 апр 19 11:44 voyna-i-mir-tom-2.txt
-rw-r--r-- 1 root root 843205 апр 19 11:44 voyna-i-mir-tom-3.txt
-rw-r--r-- 1 root root 697960 апр 19 11:44 voyna-i-mir-tom-4.txt

/otus4:
total 3007
-rw-r--r-- 1 root root 736519 апр 19 11:44 voyna-i-mir-tom-1.txt
-rw-r--r-- 1 root root 770324 апр 19 11:44 voyna-i-mir-tom-2.txt
-rw-r--r-- 1 root root 843205 апр 19 11:44 voyna-i-mir-tom-3.txt
-rw-r--r-- 1 root root 697960 апр 19 11:44 voyna-i-mir-tom-4.txt
```

Даже по этому выводу можно увидеть, что наибольшую компрессию обеспечивает otus3.

При оригиналном размере 4 файлов в папке `/home/enoch` в 2984 КБ, на `otus3` их размер составляет 1235 КБ.

Смотрю, сколько места занимают эти файлы в каждом из пулов и определю степень сжатия файлов:
```bash
root@otus:~# zfs list
NAME    USED  AVAIL  REFER  MOUNTPOINT
otus1  2.42M   350M  2.31M  /otus1
otus2  2.04M   350M  1.94M  /otus2
otus3  1.34M   351M  1.23M  /otus3
otus4  3.08M   349M  2.96M  /otus4

root@otus:~# zfs get all | grep compressratio | grep -v ref
otus1  compressratio         1.36x                      -
otus2  compressratio         1.62x                      -
otus3  compressratio         2.54x                      -
otus4  compressratio         1.06x                      -
```

### Выводы

В пуле `otus3` используется `gzip-9`, таким образом, эмпирически мы определили, что для текстовых файлов он самый эффективный по сжатию из использованных.

## 3. Определение настроек пула

### Скачивание и импорт

Скачиваю архив по ссылке из методички и разархивирую его:
```bash
root@otus:~# wget -O archive.tar.gz --no-check-certificate 'https://drive.usercontent.google.com/download?id=1MvrcEp-WgAQe57aDEzxSRalPAwbNN1Bb&export=download'
--2026-04-19 12:20:58--  https://drive.usercontent.google.com/download?id=1MvrcEp-WgAQe57aDEzxSRalPAwbNN1Bb&export=download
Resolving drive.usercontent.google.com (drive.usercontent.google.com)... 216.58.201.161, 2a00:1450:400f:806::2001
Connecting to drive.usercontent.google.com (drive.usercontent.google.com)|216.58.201.161|:443... connected.
HTTP request sent, awaiting response... 200 OK
Length: 7275140 (6,9M) [application/octet-stream]
Saving to: ‘archive.tar.gz’

archive.tar.gz    100%[==========>]   6,94M  4,07MB/s    in 1,7s    

2026-04-19 12:21:07 (4,07 MB/s) - ‘archive.tar.gz’ saved [7275140/7275140]

root@otus:~# tar -xzvf archive.tar.gz
zpoolexport/
zpoolexport/filea
zpoolexport/fileb
```

Проверяю возможность импорта каталога в пул:
```bash
root@otus:~# zpool import -d zpoolexport/
   pool: otus
     id: 6554193320433390805
  state: ONLINE
status: Some supported features are not enabled on the pool.
        (Note that they may be intentionally disabled if the
        'compatibility' property is set.)
 action: The pool can be imported using its name or numeric identifier, though
        some features will not be available without an explicit 'zpool upgrade'.
 config:

        otus                         ONLINE
          mirror-0                   ONLINE
            /root/zpoolexport/filea  ONLINE
            /root/zpoolexport/fileb  ONLINE
```

Судя по выводу пул имеет следующие свойства:
имя  - otus
raid - зеркало, состоящее из filea и fileb

Импортируем этот пул к нам в ОС и проверим статус:
```bash
root@otus:~# zpool import -d zpoolexport/ otus
root@otus:~# zpool status otus
  pool: otus
 state: ONLINE
status: Some supported and requested features are not enabled on the pool.
        The pool can still be used, but some features are unavailable.
action: Enable all features using 'zpool upgrade'. Once this is done,
        the pool may no longer be accessible by software that does not support
        the features. See zpool-features(7) for details.
config:

        NAME                         STATE     READ WRITE CKSUM
        otus                         ONLINE       0     0     0
          mirror-0                   ONLINE       0     0     0
            /root/zpoolexport/filea  ONLINE       0     0     0
            /root/zpoolexport/fileb  ONLINE       0     0     0

errors: No known data errors
```

Пул otus добавлен в систему.

### Настройки

Определяю настройки этого пула. Так как в методичке присутствует некоторая неясность, буду гуглить.

```bash
# настройки пула можно определить через zpool
# эта команда выводит список всех параметров
root@otus:~# zpool get all otus

# а параметры уровня ФС для этого пула через zfs
# all для получения списка всех параметров
root@otus:~# zfs get all otus
```

Точечными запросами определю интересующие меня парметры пула:
```bash
# размер хранилища
root@otus:~# zpool get size,allocated,free otus
NAME  PROPERTY   VALUE  SOURCE
otus  size       480M   -
otus  allocated  2.09M  -
otus  free       478M   -

# тип пула, в данном случае mirror-0
root@otus:~# zpool status otus
  pool: otus
 state: ONLINE
config:

        NAME                         STATE     READ WRITE CKSUM
        otus                         ONLINE       0     0     0
          mirror-0                   ONLINE       0     0     0
            /root/zpoolexport/filea  ONLINE       0     0     0
            /root/zpoolexport/fileb  ONLINE       0     0     0

errors: No known data errors

# значение recordsize
root@otus:~# zfs get recordsize otus
NAME  PROPERTY    VALUE    SOURCE
otus  recordsize  128K     local

# какое сжатие используется, сейчас zle
root@otus:~# zfs get compression otus
NAME  PROPERTY     VALUE           SOURCE
otus  compression  zle             local

# какая контрольная сумма используется, здесь sha256
root@otus:~# zfs get checksum otus
NAME  PROPERTY  VALUE      SOURCE
otus  checksum  sha256     local
```

## 4. Работа со снэпшотами

Скачиваю файл по ссылке из методички.
```bash
root@otus:~# wget -O otus_task2.file --no-check-certificate https://drive.usercontent.google.com/download?id=1wgxjih8YZ-cqLqaZVa0lA3h3Y029c3oI&export=download
[1] 4497
Redirecting output to ‘wget-log’.

[1]+  Done                    wget -O otus_task2.file --no-check-certificate https://drive.usercontent.google.com/download?id=1wgxjih8YZ-cqLqaZVa0lA3h3Y029c3oI

```

После чего восстановливаю ФС из снэпшота.
```bash
root@otus:~# zfs receive otus/test@today < otus_task2.file
```

Смотрю, что там восстановилось
```bash
root@otus:~# ls -l /otus/test/
total 2589
-rw-r--r-- 1 root  root        0 мая 15  2020 10M.file
-rw-r--r-- 1 root  root   727040 мая 15  2020 cinderella.tar
-rw-r--r-- 1 root  root       65 мая 15  2020 for_examaple.txt
-rw-r--r-- 1 root  root        0 мая 15  2020 homework4.txt
-rw-r--r-- 1 root  root   309987 мая 15  2020 Limbo.txt
-rw-r--r-- 1 root  root   509836 мая 15  2020 Moby_Dick.txt
drwxr-xr-x 3 enoch enoch       4 дек 18  2017 task1
-rw-r--r-- 1 root  root  1209374 мая  6  2016 War_and_Peace.txt
-rw-r--r-- 1 root  root   398635 мая 15  2020 world.sql
```

Ищу файл `secret_message`
```bash
root@otus:~# find /otus/test -name "secret_message"
/otus/test/task1/file_mess/secret_message
```

Вывод говорит, что он находится по пути `/otus/test/task1/file_mess/secret_message`, смотрю его содержимое
```bash
root@otus:~# cat /otus/test/task1/file_mess/secret_message
https://otus.ru/lessons/linux-hl/
```

Файл содержит одну строку "https://otus.ru/lessons/linux-hl/", это и есть искомое сообщение.

## Успех

