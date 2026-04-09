#!/bin/bash

# Скрипт для создания RAID-1
# Диски: sdb, sdc

# Обнуляем суперблоки на случай если диски уже использовались
mdadm --zero-superblock --force /dev/sd{b,c}

# Создаём RAID-1 из двух дисков
mdadm --create --verbose --run /dev/md0 -l 1 -n 2 /dev/sd{b,c}

# Проверяем что всё собралось
cat /proc/mdstat
mdadm -D /dev/md0