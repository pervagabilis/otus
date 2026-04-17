# Работа с LVM

## Цель

создавать и управлять логическими томами в LVM

## Текст задания

На виртуальной машине с Ubuntu 24.04 и LVM.

1. Уменьшить том под / до 8G.
2. Выделить том под /home.
3. Выделить том под /var - сделать в mirror.
4. Прописать монтирование в fstab
5. Работа со снапшотами:
   - сгенерить файлы в /home/
   - снять снапшот
   - удалить часть файлов
   - восстановиться со снапшота.

Формат сдачи: отчёт со списком команд для настройки LVM (/, /home, /var mirror, снапшоты, fstab) + создание/восстановление снапшотов

Задание считается выполненным, если проведены все манипуляции с разделами, прописано монтирование в /etc/fstab, проведена работа со снапшотами.

## Окружение

- Хостовая машина на Windows 11.
- VirtualBox версии 7.2.6 r172322 (Qt6.8.0 on windows)
- Виртуальная машина с Ubuntu Server 24.04.2
  - 4 ядра
  - 8 Гб ОЗУ
  - 5 виртуальных дисков
    1. Основной 64 Гб (на него установленя Ubuntu Server с LVM Group)
    2. 10 Гб
    3. 2 Гб
    4. 2 Гб
    5. 2 Гб

## Выполнение

### 1. Подготовка

Подготовил тестовый стенд согласно рекомендации методички.
Проверяю текущую конфигурацию устройств.
```bash
root@otus:~# lsblk
NAME                      MAJ:MIN RM  SIZE RO TYPE MOUNTPOINTS
sda                         8:0    0   64G  0 disk 
├─sda1                      8:1    0    1M  0 part 
├─sda2                      8:2    0    2G  0 part /boot
└─sda3                      8:3    0   62G  0 part 
  └─ubuntu--vg-ubuntu--lv 252:0    0   31G  0 lvm  /
sdb                         8:16   0   10G  0 disk 
sdc                         8:32   0    2G  0 disk 
sdd                         8:48   0    2G  0 disk 
sde                         8:64   0    2G  0 disk 
```

Соответствует рекомендуемому тестовому стенду.

### 2. Уменьшить том под / до 8G

Попробую пойти путём описанным в методичке, а именно уменьшить `/` до 8Гб, без использования LiveCD.

Сначала готовлю временный том для раздела `/`
```bash
root@otus:~# lsblk
NAME                      MAJ:MIN RM  SIZE RO TYPE MOUNTPOINTS
sda                         8:0    0   64G  0 disk 
├─sda1                      8:1    0    1M  0 part 
├─sda2                      8:2    0    2G  0 part /boot
└─sda3                      8:3    0   62G  0 part 
  └─ubuntu--vg-ubuntu--lv 252:2    0   31G  0 lvm  /
sdb                         8:16   0   10G  0 disk 
sdc                         8:32   0    2G  0 disk 
sdd                         8:48   0    2G  0 disk 
sde                         8:64   0    2G  0 disk

# мне подходит sdb
# инициализирую физический диск
root@otus:~# pvcreate /dev/sdb
  Physical volume "/dev/sdb" successfully created.

# создаю группу vg_root на /dev/sdb
root@otus:~# vgcreate vg_root /dev/sdb
  Volume group "vg_root" successfully created

# создаю логический том lv_root на vg_root, используя 100% от свободного места
root@otus:~# lvcreate -n lv_root -l +100%FREE /dev/vg_root
WARNING: ext4 signature detected on /dev/vg_root/lv_root at offset 1080. Wipe it? [y/n]: y
  Wiping ext4 signature on /dev/vg_root/lv_root.
  Logical volume "lv_root" created.

# создам на логическом томе ФС и смонтирую его для переноса данных
mkfs.ext4 /dev/vg_root/lv_root
root@otus:~# mkfs.ext4 /dev/vg_root/lv_root
mke2fs 1.47.0 (5-Feb-2023)
Creating filesystem with 2620416 4k blocks and 655360 inodes
Filesystem UUID: 52488890-3edb-4af0-ae4f-6c4d6083abde
Superblock backups stored on blocks: 
        32768, 98304, 163840, 229376, 294912, 819200, 884736, 1605632

Allocating group tables: done
Writing inode tables: done
Creating journal (16384 blocks): done
Writing superblocks and filesystem accounting information: done

# теперь копирую данные с раздела `/` в `mnt`
root@otus:~# rsync -avxHAX --progress / /mnt/
sent 7.017.773.274 bytes  received 1.588.112 bytes  36.275.769,44 bytes/sec
total size is 7.014.399.562  speedup is 1,00

# далее конфигурирую grub, чтобы при старте он использовал новый РУТ
# и имитирую, будто mount это новый РУТ
for i in /proc/ /sys/ /dev/ /run/ /boot/; \
 do mount --bind $i /mnt/$i; done

# меняю корневую директорию на /mnt/
chroot /mnt/

# использую утилиту grub-mkconfig с выводом результата в /boot/grub/grub.cfg
root@otus:/# grub-mkconfig -o /boot/grub/grub.cfg
Sourcing file '/etc/default/grub'
Generating grub configuration file ...
Found linux image: /boot/vmlinuz-6.8.0-110-generic
Found initrd image: /boot/initrd.img-6.8.0-110-generic
Warning: os-prober will not be executed to detect other bootable partitions.
Systems on them will not be added to the GRUB boot configuration.
Check GRUB_DISABLE_OS_PROBER documentation entry.
Adding boot menu entry for UEFI Firmware Settings ...
done

# обновляю какой-то initrd
root@otus:/# update-initramfs -u
update-initramfs: Generating /boot/initrd.img-6.8.0-110-generic

# какая-то ошибка
root@otus:/# reboot
Running in chroot, ignoring request.

# нужно выйти из chroot и перезагрузка прошла
root@otus:/# exit
exit
root@otus:~# reboot

# после перезагрузки смотрю что стало с дисками и вижу, что
# РУТ теперь живёт на sdb, vg_root-lv-root
root@otus:~# lsblk
NAME                      MAJ:MIN RM  SIZE RO TYPE MOUNTPOINTS
sda                         8:0    0   64G  0 disk 
├─sda1                      8:1    0    1M  0 part 
├─sda2                      8:2    0    2G  0 part /boot
└─sda3                      8:3    0   62G  0 part 
  └─ubuntu--vg-ubuntu--lv 252:1    0   31G  0 lvm  
sdb                         8:16   0   10G  0 disk 
└─vg_root-lv_root         252:0    0   10G  0 lvm  /
sdc                         8:32   0    2G  0 disk 
sdd                         8:48   0    2G  0 disk 
sde                         8:64   0    2G  0 disk

# теперь нужно поменять размер старой VG и вернуть на неё РУТ
# удалю предыдущий Логический том размером в 31Гб и создам
# вместо него новый на 8Гб
root@otus:~# lvremove /dev/ubuntu-vg/ubuntu-lv
Do you really want to remove and DISCARD active logical volume ubuntu-vg/ubuntu-lv? [y/n]: y
  Logical volume "ubuntu-lv" successfully removed.
root@otus:~# lvcreate -n ubuntu-vg/ubuntu-lv -L 8G /dev/ubuntu-vg
WARNING: ext4 signature detected on /dev/ubuntu-vg/ubuntu-lv at offset 1080. Wipe it? [y/n]: y
  Wiping ext4 signature on /dev/ubuntu-vg/ubuntu-lv.
  Logical volume "ubuntu-lv" created.

# файловая система
root@otus:~# mkfs.ext4 /dev/ubuntu-vg/ubuntu-lv
# монтирую
root@otus:~# mount /dev/ubuntu-vg/ubuntu-lv /mnt

# переношу данные обратно c lv-root, который смонтирован, как РУТ
# на ubuntu--lv, который смонтирован в /mnt/
root@otus:~# rsync -avxHAX --progress / /mnt/
sent 7.043.154.857 bytes  received 1.588.181 bytes  38.601.331,72 bytes/sec
total size is 7.039.773.802  speedup is 1,00

# теперь конфигурируем grub в обратную сторону
root@otus:~# for i in /proc/ /sys/ /dev/ /run/ /boot/; \
 do mount --bind $i /mnt/$i; done
root@otus:~# chroot /mnt/
root@otus:/# grub-mkconfig -o /boot/grub/grub.cfg
root@otus:/# update-initramfs -u
update-initramfs: Generating /boot/initrd.img-6.8.0-110-generic
W: Couldn\'t identify type of root file system for fsck hook
root@otus:/# exit
root@otus:~# reboot

# после перезагрузки смотрю на структуру
# раздел под рут теперь 8Гб на устройстве sda
root@otus:~# lsblk
NAME                      MAJ:MIN RM  SIZE RO TYPE MOUNTPOINTS
sda                         8:0    0   64G  0 disk 
├─sda1                      8:1    0    1M  0 part 
├─sda2                      8:2    0    2G  0 part /boot
└─sda3                      8:3    0   62G  0 part 
  └─ubuntu--vg-ubuntu--lv 252:1    0    8G  0 lvm  /
sdb                         8:16   0   10G  0 disk 
└─vg_root-lv_root         252:0    0   10G  0 lvm  
sdc                         8:32   0    2G  0 disk 
sdd                         8:48   0    2G  0 disk 
sde                         8:64   0    2G  0 disk 
sr0                        11:0    1 1024M  0 rom
```

Удаляю временные LV, VG, PV
```bash
root@otus:/# lvremove /dev/vg_root/lv_root
Do you really want to remove and DISCARD active logical volume vg_root/lv_root? [y/n]: y
  Logical volume "lv_root" successfully removed.

root@otus:/# vgremove /dev/vg_root
  Volume group "vg_root" successfully removed

root@otus:/# pvremove /dev/sdb
  Labels on physical volume "/dev/sdb" successfully wiped.

```

### 3. Выделить том под /home

Теперь делаем том под `home` в виртуальной группе `ubuntu-vg` размером 2Гб с именем `LogVol_Home`
```bash
root@otus:~# lvcreate -n LogVol_Home -L 2G /dev/ubuntu-vg
  Logical volume "LogVol_Home" created.
```

Потом как обычно создаём ФС, монтируем в `/mnt`, копируем данные из `/home/`, очищаем старый `/home`, размонтируем из `/mnt` и примонтируем в `/home`
```bash
root@otus:~# mkfs.ext4 /dev/ubuntu-vg/LogVol_Home
mke2fs 1.47.0 (5-Feb-2023)
Creating filesystem with 524288 4k blocks and 131072 inodes
Filesystem UUID: babf7fbd-be27-4e56-b8a4-d343aa0f7364
Superblock backups stored on blocks: 
        32768, 98304, 163840, 229376, 294912

Allocating group tables: done
Writing inode tables: done
Creating journal (16384 blocks): done
Writing superblocks and filesystem accounting information: done 

root@otus:~# mount /dev/ubuntu-vg/LogVol_Home /mnt/
root@otus:~# cp -aR /home/* /mnt/
root@otus:~# rm -rf /home/*
root@otus:~# umount /mnt
root@otus:~# mount /dev/ubuntu-vg/LogVol_Home /home/
```

После чего прописываем в `/etc/fstab` новую точку монтирования
```bash
root@otus:~# echo "`blkid | grep Home | awk '{print $2}'` \
 /home xfs defaults 0 0" >> /etc/fstab
```

#### ОШИБКА
После перезагрузки не примонтировалось, я думаю, что в команде из методички ошибка.

Мы создали ФС `ext4`, а в `fstab` прописываем `xfs`

Удаляю последнюю запись и пробую с другой командой
```bash
root@otus:~# echo "`blkid | grep Home | awk '{print $2}'` /home ext4 defaults 0 0" >> /etc/fstab
```

После перезагрузки проверяю и вижу, что теперь монтирование прошло успешно.
```bash
enoch@otus:~$ lsblk
NAME                       MAJ:MIN RM  SIZE RO TYPE MOUNTPOINTS
sda                          8:0    0   64G  0 disk 
├─sda1                       8:1    0    1M  0 part 
├─sda2                       8:2    0    2G  0 part /boot
└─sda3                       8:3    0   62G  0 part 
  ├─ubuntu--vg-ubuntu--lv  252:0    0    8G  0 lvm  /
  └─ubuntu--vg-LogVol_Home 252:1    0    2G  0 lvm  /home
sdb                          8:16   0   10G  0 disk 
sdc                          8:32   0    2G  0 disk 
├─vg_var-lv_var_rmeta_0    252:2    0    4M  0 lvm  
│ └─vg_var-lv_var          252:6    0  952M  0 lvm  /var
└─vg_var-lv_var_rimage_0   252:3    0  952M  0 lvm  
  └─vg_var-lv_var          252:6    0  952M  0 lvm  /var
sdd                          8:48   0    2G  0 disk 
├─vg_var-lv_var_rmeta_1    252:4    0    4M  0 lvm  
│ └─vg_var-lv_var          252:6    0  952M  0 lvm  /var
└─vg_var-lv_var_rimage_1   252:5    0  952M  0 lvm  
  └─vg_var-lv_var          252:6    0  952M  0 lvm  /var
sde                          8:64   0    2G  0 disk 
sr0                         11:0    1 1024M  0 rom
```

### 4. Выделить том под /var - сделать в mirror

Создадим зеркало
```bash
root@otus:~# pvcreate /dev/sdc /dev/sdd
  Physical volume "/dev/sdc" successfully created.
  Physical volume "/dev/sdd" successfully created.

root@otus:~# pvs
  PV         VG        Fmt  Attr PSize   PFree  
  /dev/sda3  ubuntu-vg lvm2 a--  <62,00g <54,00g
  /dev/sdb   vg_root   lvm2 a--  <10,00g      0 
  /dev/sdc             lvm2 ---    2,00g   2,00g
  /dev/sdd             lvm2 ---    2,00g   2,00g

root@otus:~# vgcreate vg_var /dev/sdc /dev/sdd
  Volume group "vg_var" successfully created

# создам логический том размером 950МБ
# -m1 RAID с одним зеркалом
root@otus:~# lvcreate -L 950M -m1 -n lv_var vg_var
  Rounding up size to full physical extent 952,00 MiB
  Logical volume "lv_var" created.
```

Создам на томе lv_var ФС, монтирую в `/mnt` и перемещаю туда `/var`

```bash
root@otus:~# mkfs.ext4 /dev/vg_var/lv_var
root@otus:~# mount /dev/vg_var/lv_var /mnt
root@otus:~# cp -aR /var/* /mnt/
```

Очищаю старый `/var`

```bash
root@otus:/# rm -rf /var/*
```

И монтирую новый var в каталог `/var` и прописываю в `fstab` точку монтирования

```bash
root@otus:/# mount /dev/vg_var/lv_var /var
root@otus:/# echo "`blkid | grep var: | awk '{print $2}'` \
 /var ext4 defaults 0 0"
UUID="ced1f0fc-a11d-4344-b6d5-d92f797cb22e"  /var ext4 defaults 0 0
```

Перезагружаюсь и проверяю, что всё корректно

```bash
root@otus:~# lsblk
NAME                       MAJ:MIN RM  SIZE RO TYPE MOUNTPOINTS
sda                          8:0    0   64G  0 disk 
├─sda1                       8:1    0    1M  0 part 
├─sda2                       8:2    0    2G  0 part /boot
└─sda3                       8:3    0   62G  0 part 
  ├─ubuntu--vg-ubuntu--lv  252:0    0    8G  0 lvm  /
  └─ubuntu--vg-LogVol_Home 252:1    0    2G  0 lvm  /home
sdb                          8:16   0   10G  0 disk 
sdc                          8:32   0    2G  0 disk 
├─vg_var-lv_var_rmeta_0    252:2    0    4M  0 lvm  
│ └─vg_var-lv_var          252:6    0  952M  0 lvm  /var
└─vg_var-lv_var_rimage_0   252:3    0  952M  0 lvm  
  └─vg_var-lv_var          252:6    0  952M  0 lvm  /var
sdd                          8:48   0    2G  0 disk 
├─vg_var-lv_var_rmeta_1    252:4    0    4M  0 lvm  
│ └─vg_var-lv_var          252:6    0  952M  0 lvm  /var
└─vg_var-lv_var_rimage_1   252:5    0  952M  0 lvm  
  └─vg_var-lv_var          252:6    0  952M  0 lvm  /var
sde                          8:64   0    2G  0 disk
```

### 6. Прописать монтирование в fstab

Выдержка из предыдущих пунктов

```bash
root@otus:~# echo "`blkid | grep Home | awk '{print $2}'` /home ext4 defaults 0 0" >> /etc/fstab
```

```bash
root@otus:/# echo "`blkid | grep var: | awk '{print $2}'` \
 /var ext4 defaults 0 0"
UUID="ced1f0fc-a11d-4344-b6d5-d92f797cb22e"  /var ext4 defaults 0 0
```

### 7. Работа со снапшотами

#### сгенерить файлы в /home/

Нагенерирую пустых файлов в `/home`

```bash
root@otus:~# touch /home/file{1..20}
root@otus:~# ls /home/ -l
total 20
drwxr-x--- 4 enoch enoch  4096 апр 15 13:42 enoch
-rw-r--r-- 1 root  root      0 апр 17 14:55 file1
-rw-r--r-- 1 root  root      0 апр 17 14:55 file10
-rw-r--r-- 1 root  root      0 апр 17 14:55 file11
-rw-r--r-- 1 root  root      0 апр 17 14:55 file12
-rw-r--r-- 1 root  root      0 апр 17 14:55 file13
-rw-r--r-- 1 root  root      0 апр 17 14:55 file14
-rw-r--r-- 1 root  root      0 апр 17 14:55 file15
-rw-r--r-- 1 root  root      0 апр 17 14:55 file16
-rw-r--r-- 1 root  root      0 апр 17 14:55 file17
-rw-r--r-- 1 root  root      0 апр 17 14:55 file18
-rw-r--r-- 1 root  root      0 апр 17 14:55 file19
-rw-r--r-- 1 root  root      0 апр 17 14:55 file2
-rw-r--r-- 1 root  root      0 апр 17 14:55 file20
-rw-r--r-- 1 root  root      0 апр 17 14:55 file3
-rw-r--r-- 1 root  root      0 апр 17 14:55 file4
-rw-r--r-- 1 root  root      0 апр 17 14:55 file5
-rw-r--r-- 1 root  root      0 апр 17 14:55 file6
-rw-r--r-- 1 root  root      0 апр 17 14:55 file7
-rw-r--r-- 1 root  root      0 апр 17 14:55 file8
-rw-r--r-- 1 root  root      0 апр 17 14:55 file9
drwx------ 2 root  root  16384 апр 17 14:36 lost+found
```

#### снять снапшот

Забацаю снэпшот.

То есть:

- создам логический том
- размером 100МБ
- с ключом `-s` (который подразумевает создание снимка)
- именем home_snap
- указанием исходного тома, снимок которого создадим

```bash
root@otus:~# lvcreate -L 100MB -s -n home_snap /dev/ubuntu-vg/LogVol_Home
  Logical volume "home_snap" created.
```

#### удалить часть файлов

Удалю часть файлов, чтобы сымитировать изменения на оригинальном томе.
```bash
root@otus:~# rm -f /home/file{11..20}
root@otus:~# ls /home/ -l
total 20
drwxr-x--- 4 enoch enoch  4096 апр 15 13:42 enoch
-rw-r--r-- 1 root  root      0 апр 17 14:55 file1
-rw-r--r-- 1 root  root      0 апр 17 14:55 file10
-rw-r--r-- 1 root  root      0 апр 17 14:55 file2
-rw-r--r-- 1 root  root      0 апр 17 14:55 file3
-rw-r--r-- 1 root  root      0 апр 17 14:55 file4
-rw-r--r-- 1 root  root      0 апр 17 14:55 file5
-rw-r--r-- 1 root  root      0 апр 17 14:55 file6
-rw-r--r-- 1 root  root      0 апр 17 14:55 file7
-rw-r--r-- 1 root  root      0 апр 17 14:55 file8
-rw-r--r-- 1 root  root      0 апр 17 14:55 file9
drwx------ 2 root  root  16384 апр 17 14:36 lost+found

root@otus:~# lvdisplay /dev/ubuntu-vg/home_snap
  --- Logical volume ---
  LV Path                /dev/ubuntu-vg/home_snap
  LV Name                home_snap
  VG Name                ubuntu-vg
  LV UUID                er7yHb-rkmR-WmOU-KPXd-Gc9N-jg3x-1Mb6ct
  LV Write Access        read/write
  LV Creation host, time otus, 2026-04-17 15:00:07 +0000
  LV snapshot status     active destination for LogVol_Home
  LV Status              available
  # open                 0
  LV Size                2,00 GiB
  Current LE             512
  COW-table size         100,00 MiB
  COW-table LE           25
  Allocated to snapshot  0,08%
  Snapshot chunk size    4,00 KiB
  Segments               1
  Allocation             inherit
  Read ahead sectors     auto
  - currently set to     256
  Block device           252:9
```
#### восстановиться со снапшота

Процесс восстановления чуть замороченней.

Размонтируем home
```bash
root@otus:~# umount /home
umount: /home: target is busy.

# попробую с ключём -l
root@otus:~# umount -l /home

# отмонтировано
root@otus:~# mount | grep /home
```
2
Восстанавливаем снэпшот.
```bash
root@otus:~# lvconvert --merge /dev/ubuntu-vg/home_snap
  Delaying merge since origin is open.
  Merging of snapshot ubuntu-vg/home_snap will occur on next activation of ubuntu-vg/LogVol_Home.
```

Монтируем назад
```bash
root@otus:~# mount /dev/ubuntu-vg/LogVol_Home /home/
root@otus:~# lsblk
NAME                            MAJ:MIN RM  SIZE RO TYPE MOUNTPOINTS
sda                               8:0    0   64G  0 disk 
├─sda1                            8:1    0    1M  0 part 
├─sda2                            8:2    0    2G  0 part /boot
└─sda3                            8:3    0   62G  0 part 
  ├─ubuntu--vg-ubuntu--lv       252:0    0    8G  0 lvm  /
  ├─ubuntu--vg-LogVol_Home-real 252:7    0    2G  0 lvm  
  │ ├─ubuntu--vg-LogVol_Home    252:1    0    2G  0 lvm  /home
  │ └─ubuntu--vg-home_snap      252:9    0    2G  0 lvm  
  └─ubuntu--vg-home_snap-cow    252:8    0  100M  0 lvm  
    └─ubuntu--vg-home_snap      252:9    0    2G  0 lvm  
sdb                               8:16   0   10G  0 disk 
sdc                               8:32   0    2G  0 disk 
├─vg_var-lv_var_rmeta_0         252:2    0    4M  0 lvm  
│ └─vg_var-lv_var               252:6    0  952M  0 lvm  /var
└─vg_var-lv_var_rimage_0        252:3    0  952M  0 lvm  
  └─vg_var-lv_var               252:6    0  952M  0 lvm  /var
sdd                               8:48   0    2G  0 disk 
├─vg_var-lv_var_rmeta_1         252:4    0    4M  0 lvm  
│ └─vg_var-lv_var               252:6    0  952M  0 lvm  /var
└─vg_var-lv_var_rimage_1        252:5    0  952M  0 lvm  
  └─vg_var-lv_var               252:6    0  952M  0 lvm  /var
sde                               8:64   0    2G  0 disk 
sr0                              11:0    1 1024M  0 rom
```

Почему-то после команды `ls -al /home` мне отображалось `total 28`, но при этом в списке файлов не было.

После перезагрузки появились. Что это было не имею представления.

```bash
root@otus:~# ls -al /home
total 28
drwxr-xr-x  4 root  root   4096 апр 17 14:55 .
drwxr-xr-x 24 root  root   4096 апр 17 14:27 ..
drwxr-x---  4 enoch enoch  4096 апр 15 13:42 enoch
-rw-r--r--  1 root  root      0 апр 17 14:55 file1
-rw-r--r--  1 root  root      0 апр 17 14:55 file10
-rw-r--r--  1 root  root      0 апр 17 14:55 file11
-rw-r--r--  1 root  root      0 апр 17 14:55 file12
-rw-r--r--  1 root  root      0 апр 17 14:55 file13
-rw-r--r--  1 root  root      0 апр 17 14:55 file14
-rw-r--r--  1 root  root      0 апр 17 14:55 file15
-rw-r--r--  1 root  root      0 апр 17 14:55 file16
-rw-r--r--  1 root  root      0 апр 17 14:55 file17
-rw-r--r--  1 root  root      0 апр 17 14:55 file18
-rw-r--r--  1 root  root      0 апр 17 14:55 file19
-rw-r--r--  1 root  root      0 апр 17 14:55 file2
-rw-r--r--  1 root  root      0 апр 17 14:55 file20
-rw-r--r--  1 root  root      0 апр 17 14:55 file3
-rw-r--r--  1 root  root      0 апр 17 14:55 file4
-rw-r--r--  1 root  root      0 апр 17 14:55 file5
-rw-r--r--  1 root  root      0 апр 17 14:55 file6
-rw-r--r--  1 root  root      0 апр 17 14:55 file7
-rw-r--r--  1 root  root      0 апр 17 14:55 file8
-rw-r--r--  1 root  root      0 апр 17 14:55 file9
drwx------  2 root  root  16384 апр 17 14:36 lost+found
```

## Успех

Задание выполнено успешно.