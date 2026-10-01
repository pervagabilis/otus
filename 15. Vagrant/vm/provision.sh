#!/usr/bin/env bash
set -euo pipefail

# поиск добавленных дисков
DISKS=($(lsblk -dbno NAME,SIZE,TYPE | awk '$3=="disk" && $2 >= 1000000000 && $2 <= 1200000000 {print "/dev/"$1}' | sort))

if [ "${#DISKS[@]}" -lt 2 ]; then
  echo "ERROR: ожидалось 2 диска ~1ГБ, нашёл ${#DISKS[@]}"
  echo "----- lsblk полностью для диагностики -----"
  lsblk -bo NAME,SIZE,MOUNTPOINT,TYPE
  echo "-------------------------------------------"
  exit 1
fi

DISK1="${DISKS[0]}"
DISK2="${DISKS[1]}"
echo "Найдены диски: $DISK1 и $DISK2"

# форматирование
for D in "$DISK1" "$DISK2"; do
  if ! blkid "$D" >/dev/null 2>&1; then
    echo "Форматирую $D в ext4"
    mkfs.ext4 -F "$D"
  else
    echo "$D уже отформатирован: $(blkid -o value -s TYPE $D)"
  fi
done

# точки монитрования
mkdir -p /mnt/disk1 /mnt/disk2

UUID1=$(blkid -s UUID -o value "$DISK1")
UUID2=$(blkid -s UUID -o value "$DISK2")

# добавление в fstab
grep -q "$UUID1" /etc/fstab || echo "UUID=$UUID1 /mnt/disk1 ext4 defaults 0 2" >> /etc/fstab
grep -q "$UUID2" /etc/fstab || echo "UUID=$UUID2 /mnt/disk2 ext4 defaults 0 2" >> /etc/fstab

# монтирование
mount -a

# выворд итога
echo "===== df -h по точкам монтирования ====="
df -h | grep -E '/mnt/|Filesystem'
echo "===== /etc/fstab (наши строки) ====="
grep -E 'UUID.*mnt' /etc/fstab