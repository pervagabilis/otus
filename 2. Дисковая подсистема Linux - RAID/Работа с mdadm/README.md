# Работа с mdadm

## Цель

научиться использовать утилиту для управления программными RAID-массивами в Linux;

## Текст задания

- Добавьте в виртуальную машину несколько дисков
- Соберите RAID-0/1/5/10 на выбор
- Сломайте и почините RAID
- Создайте GPT таблицу, пять разделов и смонтируйте их в системе.

## Формат сдачи

- скрипт для создания рейда
- отчет по командам для починки RAID и созданию разделов.

## Критерии оценки

✅ успешно сознан RAID-массив с использованием mdadm
✅ проведены манипуляции с восстановлением массива
✅ создана таблица GPT и разделы смонтированы в системе.

## Окружение

- Хостовая машина на Windows 11.
- VirtualBox версии 7.2.6 r172322 (Qt6.8.0 on windows)
- Виртуальная машина с Ubuntu Server 24.04.2

## Выполнение

### 1. Добавление дисков в виртуальную машину

В первую очередь в интерфейсе VirtualBox создал 2 виртуальных носителя по 1 Гб каждый.

После чего через оснастку подсоединил их к виртуальной машине.

Загружаюсь, после чего проверяю, что они появились:

```bash
❯ lsblk
NAME   MAJ:MIN RM  SIZE RO TYPE MOUNTPOINTS
sda      8:0    0  100G  0 disk 
├─sda1   8:1    0    1M  0 part 
└─sda2   8:2    0  100G  0 part /
sdb      8:16   0    1G  0 disk 
sdc      8:32   0    1G  0 disk 
sr0     11:0    1 1024M  0 rom  
```

Вижу, что появилось два новых блочных устройства: `sdb` и `sdc` по 1 гигабайту размером.

### 2. RAID

#### Сборка

Собирать буду зеркальный дисковый массив (RAID-1)

Сначала попытался занулить суперблоки, но так как эти диски ещё не использовались в RAID, команда `mdadm --zero-superblock --force /dev/sd{b,c}` сообщила, что суперблоков не найдено.

```bash
❯ sudo mdadm --zero-superblock --force /dev/sd{b,c}
mdadm: Unrecognised md component device - /dev/sdb
mdadm: Unrecognised md component device - /dev/sdc
```

Теперь собираю.

`mdadm` запускаю с флагом `--run`, что пропускает интерактивное подтверждение
`-l 1` - указывает уровень `RAID`, в моём случае `1`
`-n 2` - указывает количество устройств в массиве, в моём случае `2`

```bash
❯ sudo mdadm --create --verbose --run /dev/md0 -l 1 -n 2 /dev/sd{b,c}
mdadm: Note: this array has metadata at the start and
    may not be suitable as a boot device.  If you plan to
    store '/boot' on this device please ensure that
    your boot-loader understands md/v1.x metadata, or use
    --metadata=0.90
mdadm: size set to 1046528K
mdadm: creation continuing despite oddities due to --run
mdadm: Defaulting to version 1.2 metadata
mdadm: array /dev/md0 started.
```

#### Проверка, что RAID собрался успешно

```bash
❯ cat /proc/mdstat
Personalities : [raid0] [raid1] [raid6] [raid5] [raid4] [raid10] 
md0 : active raid1 sdc[1] sdb[0]
      1046528 blocks super 1.2 [2/2] [UU]

❯ sudo mdadm -D /dev/md0
/dev/md0:
  Raid Level : raid1
  Number   Major   Minor   RaidDevice  State
      0       8       16        0      active sync   /dev/sdb
      1       8       32        1      active sync   /dev/sdc
```

### Поломка и починка RAID

#### DESTROY

"Фейлим" одно из блочных устройств

```bash
❯ sudo mdadm /dev/md0 --fail /dev/sdc
mdadm: set /dev/sdc faulty in /dev/md0
```

Смотрим на результат

```bash
# вижу флаг (F) и отметку второго диска "_"
❯ cat /proc/mdstat
Personalities : [raid0] [raid1] [raid6] [raid5] [raid4] [raid10] 
md0 : active raid1 sdc[1](F) sdb[0]
      1046528 blocks super 1.2 [2/1] [U_]

❯ sudo mdadm -D /dev/md0

# вижу, что состояние degraded и устройсто 1 removed, а sdc faulty
/dev/md0:
  Raid Level : raid1
  State : clean, degraded

  Number   Major   Minor   RaidDevice   State
  0       8       16        0           active sync   /dev/sdb
  -       0        0        1           removed

  1       8       32        -           faulty   /dev/sdc
```

#### HEAL

Поломанный диск удаляю из массива
```bash
❯ sudo mdadm /dev/md0 --remove /dev/sdc
mdadm: hot removed /dev/sdc from /dev/md0
```

А теперь добавляю "новый" диск в RAID
```bash
❯ sudo mdadm /dev/md0 --add /dev/sdc
mdadm: added /dev/sdc
```

Ловлю процесс ребилда
```bash
# вижу процесс восстановления и скорость
❯ cat /proc/mdstat
Personalities : [raid0] [raid1] [raid6] [raid5] [raid4] [raid10] 
md0 : active raid1 sdc[2] sdb[0]
      1046528 blocks super 1.2 [2/1] [U_]
      [===>.................]  recovery = 19.1% (200704/1046528) finish=0.0min speed=200704K/sec

# вижу статус recovering и отдельно строку Rebuild
❯ sudo mdadm -D /dev/md0
/dev/md0:
  Raid Level : raid1
  State : clean, degraded, recovering 
  Rebuild Status : 0% complete
  Number   Major   Minor   RaidDevice State
    0       8       16        0       active sync   /dev/sdb
    2       8       32        1       spare rebuilding   /dev/sdc
```

#### Проверка

Убеждаюсь, что ребилд прошёл нормально

```bash
❯ cat /proc/mdstat
Personalities : [raid0] [raid1] [raid6] [raid5] [raid4] [raid10]
md0 : active raid1 sdc[2] sdb[0]
      1046528 blocks super 1.2 [2/2] [UU]

❯ sudo mdadm -D /dev/md0
/dev/md0:
  Raid Level : raid1
  State : clean
  Number   Major   Minor   RaidDevice State
    0       8       16        0       active sync   /dev/sdb
    2       8       32        1       active sync   /dev/sdc
```

Всё нормально, RAID вылечен.

### 3. GPT, разделы

#### GPT

Создам таблицу GPT на моём свеженьком RAID

```bash
❯ sudo parted -s /dev/md0 mklabel gpt

❯ sudo fdisk -l
Disk /dev/md0: 1022 MiB, 1071644672 bytes, 2093056 sectors
Disklabel type: gpt
```

#### Разделы

Теперь создам разделы
```bash
❯ sudo parted /dev/md0 mkpart primary ext4 0% 20%
❯ sudo parted /dev/md0 mkpart primary ext4 20% 40%
❯ sudo parted /dev/md0 mkpart primary ext4 40% 60%
❯ sudo parted /dev/md0 mkpart primary ext4 60% 80%
❯ sudo parted /dev/md0 mkpart primary ext4 80% 100%

Information: You may need to update /etc/fstab.
```

Проверю, что они появились
```bash
❯ lsblk
sdb         8:16   0    1G  0 disk
└─md0       9:0    0 1022M  0 raid1
  ├─md0p1 259:5    0  203M  0 part
  ├─md0p2 259:6    0  205M  0 part
  ├─md0p3 259:7    0  204M  0 part
  ├─md0p4 259:8    0  205M  0 part
  └─md0p5 259:9    0  203M  0 part
sdc         8:32   0    1G  0 disk
└─md0       9:0    0 1022M  0 raid1
  ├─md0p1 259:5    0  203M  0 part
  ├─md0p2 259:6    0  205M  0 part
  ├─md0p3 259:7    0  204M  0 part
  ├─md0p4 259:8    0  205M  0 part
  └─md0p5 259:9    0  203M  0 part
```

Вижу, что появились разделы `md0p{1,2,3,4,5}`

#### Файловая система

Теперь создаю на этих разделах файловую систему
```bash
❯ for i in $(seq 1 5); do sudo mkfs.ext4 /dev/md0p$i; done
mke2fs 1.47.0 (5-Feb-2023)
Creating filesystem with 51968 4k blocks and 51968 inodes
Filesystem UUID: b0b87df2-d50e-45da-8e52-f70b5e23f60f
Superblock backups stored on blocks:
        32768

Allocating group tables: done
Writing inode tables: done
Creating journal (4096 blocks): done
Writing superblocks and filesystem accounting information: done

```

#### Монтирование

После чего монтирую их в соответсвующие каталоги
```bash
# сначала создаю каталоги для монтирования
❯ sudo mkdir -p /raid/part{1,2,3,4,5}
# проверяю, что они появились
❯ ls /raid -l
total 20
drwxr-xr-x 2 root root 4096 Apr  9 13:48 part1
drwxr-xr-x 2 root root 4096 Apr  9 13:48 part2
drwxr-xr-x 2 root root 4096 Apr  9 13:48 part3
drwxr-xr-x 2 root root 4096 Apr  9 13:48 part4
drwxr-xr-x 2 root root 4096 Apr  9 13:48 part5

# монтирую
❯ for i in $(seq 1 5); do sudo mount /dev/md0p$i /raid/part$i; done

# смотрю, появились ли
❯ df -h
Filesystem      Size  Used Avail Use% Mounted on
/dev/md0p1      175M   24K  160M   1% /raid/part1
/dev/md0p2      176M   24K  162M   1% /raid/part2
/dev/md0p3      176M   24K  161M   1% /raid/part3
/dev/md0p4      176M   24K  162M   1% /raid/part4
/dev/md0p5      175M   24K  160M   1% /raid/part5
```

#### Автомонтирование

Для того, чтобы RAID поднялся после перезагрузки - сохрнаю текущую конфигурацию в `/etc/mdadm/mdadm.conf`
```bash
# сначала узнаю текущую конфигурацию массива
❯ sudo mdadm --detail --scan
ARRAY /dev/md0 metadata=1.2 UUID=3fecfc2c:02bbd399:c82ef32c:2dcf16c7

# после чего сохраняю её в файл /etc/mdadm/mdadm.conf
❯ sudo nano /etc/mdadm/mdadm.conf
### прописываю данные полученные прошлой командой ###

# обновляю initramfs
sudo update-initramfs -u
```

Чтобы после перезагрузки разделы автоматически монтировались в систему, пропишу их в `fstab`
```bash
# сначала узнаю UUID разделов
❯ sudo lsblk -f
sdb       linux_raid_member 1.2   otus:0 3fecfc2c-02bb-d399-c82e-f32c2dcf16c7
└─md0
  ├─md0p1 ext4              1.0          b0b87df2-d50e-45da-8e52-f70b5e23f60f  159.9M     0% /raid/part1
  ├─md0p2 ext4              1.0          fec3480e-86be-4ba2-a268-6325fa841b29  161.6M     0% /raid/part2
  ├─md0p3 ext4              1.0          cb9f8e38-61b8-45ec-9cdb-d0b7c1c65178  160.7M     0% /raid/part3
  ├─md0p4 ext4              1.0          47cc142d-7927-448f-b98e-30fbaf819d47  161.6M     0% /raid/part4      
  └─md0p5 ext4              1.0          ec9cdee9-ec20-419b-bafb-837aa7736f8a  159.9M     0% /raid/part5
  # после чего добавлю в /etc/fstab следующие записи
  ❯ sudo nano /etc/fstab
      UUID=b0b87df2-d50e-45da-8e52-f70b5e23f60f /raid/part1 ext4 defaults 0 2
      UUID=fec3480e-86be-4ba2-a268-6325fa841b29 /raid/part2 ext4 defaults 0 2
      UUID=cb9f8e38-61b8-45ec-9cdb-d0b7c1c65178 /raid/part3 ext4 defaults 0 2
      UUID=47cc142d-7927-448f-b98e-30fbaf819d47 /raid/part4 ext4 defaults 0 2
      UUID=ec9cdee9-ec20-419b-bafb-837aa7736f8a /raid/part5 ext4 defaults 0 2
```

#### Проверка

После всех предыдущий манипуляций, перезагружаюсь и проверяю, что всё смонтировалось нормально.
```bash
❯ lsblk
NAME      MAJ:MIN RM  SIZE RO TYPE  MOUNTPOINTS
sda         8:0    0  100G  0 disk  
├─sda1      8:1    0    1M  0 part  
└─sda2      8:2    0  100G  0 part  /
sdb         8:16   0    1G  0 disk  
└─md0       9:0    0 1022M  0 raid1 
  ├─md0p1 259:0    0  203M  0 part  /raid/part1
  ├─md0p2 259:1    0  205M  0 part  /raid/part2
  ├─md0p3 259:2    0  204M  0 part  /raid/part3
  ├─md0p4 259:3    0  205M  0 part  /raid/part4
  └─md0p5 259:4    0  203M  0 part  /raid/part5
sdc         8:32   0    1G  0 disk  
└─md0       9:0    0 1022M  0 raid1 
  ├─md0p1 259:0    0  203M  0 part  /raid/part1
  ├─md0p2 259:1    0  205M  0 part  /raid/part2
  ├─md0p3 259:2    0  204M  0 part  /raid/part3
  ├─md0p4 259:3    0  205M  0 part  /raid/part4
  └─md0p5 259:4    0  203M  0 part  /raid/part5
sr0        11:0    1 1024M  0 rom   

❯ df -h
Filesystem      Size  Used Avail Use% Mounted on
tmpfs           794M  1.2M  793M   1% /run
/dev/sda2        98G  2.9G   91G   4% /
tmpfs           3.9G     0  3.9G   0% /dev/shm
tmpfs           5.0M     0  5.0M   0% /run/lock
/dev/md0p2      176M   24K  162M   1% /raid/part2
/dev/md0p4      176M   24K  162M   1% /raid/part4
/dev/md0p5      175M   24K  160M   1% /raid/part5
/dev/md0p1      175M   24K  160M   1% /raid/part1
/dev/md0p3      176M   24K  161M   1% /raid/part3
tmpfs           794M   12K  794M   1% /run/user/1000
```

## Успех

В процессе выполнения задания:

- был создан RAID-1
- после чего искусственно разрушен, а затем восстановлен
- создана таблица GPT на моём RAID
- создано 5 разделов на моём RAID
- на этих разделах создана ФС
- созданы каталоги, как точки монтирования разделов
- разделы примонтированны к каталогам
- сохранена конфигурация raid и обновлён initramfs, чтобы raid поднялся после перезагрузки
- прописаны `UUID` разделов и точки их монтировнаия в `/etc/fstab `, чтобы они автоматически примонтировались после перезагрузки

Задание выполнено успешно.