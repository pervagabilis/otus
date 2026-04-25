# Работа с NFS

## Цель
научиться самостоятельно разворачивать сервис NFS и подключать к нему клиентов;

## Текст задания

🎯 Что нужно сделать?

- запустить 2 виртуальных машины (сервер NFS и клиента)
- на сервере NFS должна быть подготовлена и экспортирована директория
- в экспортированной директории должна быть поддиректория с именем upload с правами на запись в неё
- экспортированная директория должна автоматически монтироваться на клиенте при старте виртуальной машины (systemd, autofs или fstab — любым способом)
- монтирование и работа NFS на клиенте должна быть организована с использованием NFSv3.

⭐️ Задание со звездочкой*

настроить аутентификацию через KERBEROS с использованием NFSv4

## Окружение

- Хостовая машина на Windows 11.
- VirtualBox версии 7.2.6 r172322 (Qt6.8.0 on windows)
- Виртуальная машина с Ubuntu Server 24.04.2
- Vagrant 2.4.9

### Каталоги и файлы

В репозитории представлены следующие каталоги и файлы

|Файл/Каталог|Назначение|
|---|---|
|`README.md`| Этот файл. Пошагово описывает выполнение задания|
|vm|Каталог для Vagrant|
|vm/Vagrantfile|Файл для Vagrant, описывающий виртуальные машины тестового стенда под это задание|

## Выполнение

### 1. Подготовка, Vagrant

Подготавливаю Vagrant файл для развёртывания двух виртуалок.

В конфиге прописываю имена и виртуальную сеть, задаю статические адреса из одного диапазона:

|name|ip|
|---|---|
|nfs-server|192.168.56.10|
|nfs-client|192.168.56.20|

Запускаю стенд командой `vagrant up`

### 2. Настройка сервера

Захожу на сервер, повышаю привелегии через `sudo -i`

Устанавливаю сервер nfs
```bash
root@nfs-server:~# apt install nfs-kernel-server
```

Проверяю наличие слушающих портов
```bash
root@nfs-server:~# ss -tnplu | grep 2049
tcp   LISTEN 0      64              0.0.0.0:2049       0.0.0.0:*                              
tcp   LISTEN 0      64                 [::]:2049          [::]:*                              

root@nfs-server:~# ss -tnplu | grep 111
udp   UNCONN 0      0               0.0.0.0:111        0.0.0.0:*    
udp   UNCONN 0      0                  [::]:111           [::]:*    
tcp   LISTEN 0      4096            0.0.0.0:111        0.0.0.0:*    
tcp   LISTEN 0      4096               [::]:111           [::]:*    
```

Порты есть, сервисы готовы принимать внешние подключения.

Создаю и прописываю права для директории, которую буду экспортировать
```bash
root@nfs-server:~#  mkdir -p /srv/share/upload 
root@nfs-server:~#  chown -R nobody:nogroup /srv/share 
root@nfs-server:~#  chmod 0777 /srv/share/upload 
```

Теперь записываю в файл /etc/exports структуру, которая позволит экспортировать ранее 
```bash
root@nfs-server:~# echo "/srv/share 192.168.56.20/32(rw,sync,root_squash)" > /etc/exports
```

Экспортирую директорию
```bash
root@nfs-server:~# exportfs -r
```

Проверяю
```bash
root@nfs-server:~# exportfs -s
/srv/share  192.168.56.20/32(sync,wdelay,hide,no_subtree_check,sec=sys,rw,secure,root_squash,no_all_squash)
```

Судя по выводу, всё экспортировалось

### 3. Настройка клиента

Установлю пакет клиента NFS
```bash
root@nfs-client:~# apt install nfs-common
```

После чего добавлю в `fstab` строку для автомонтирования.
```bash
root@nfs-client:~# echo "192.168.56.10:/srv/share/ /mnt nfs vers=3,noauto,x-systemd.automount 0 0" >> /etc/fstab
```

Выполняю команды
```bash
root@nfs-client:~# systemctl daemon-reload
root@nfs-client:~# systemctl restart remote-fs.target
```

Перехожу в каталог `/mnt` для того, чтобы отработал `systemd units`, который смонтирует шару.

После чего проверяю успешность монтирования.
```bash
root@nfs-client:~# cd /mnt
root@nfs-client:/mnt# mount | grep mnt
systemd-1 on /mnt type autofs (rw,relatime,fd=66,pgrp=1,timeout=0,minproto=5,maxproto=5,direct,pipe_ino=18347)
192.168.56.10:/srv/share/ on /mnt type nfs (rw,relatime,vers=3,rsize=524288,wsize=524288,namlen=255,hard,proto=tcp,timeo=600,retrans=2,sec=sys,mountaddr=192.168.56.10,mountvers=3,mountport=53130,mountproto=udp,local_lock=none,addr=192.168.56.10)
```

Исходя из вывода, монтирования произошло успешно.

Из параметра `vers=3` видно, что используется NFSv3, как требует задание.

### 4. Проверка работоспособности

#### Первичная

##### На сервере

```bash
# захожу в расшареный каталог
root@nfs-server:~# cd /srv/share/upload/
# создаю файл для проверки
root@nfs-server:/srv/share/upload# touch check_file
```

Перехожу в клиент.

После действий на клиенте, проверяю наличие файла, который был создан клиентом.
```bash
root@nfs-server:/srv/share/upload# ls -l
total 0
-rw-r--r-- 1 root   root    0 Apr 23 13:19 check_file
-rw-r--r-- 1 nobody nogroup 0 Apr 23 13:20 client_file
```

Вижу файл созданный клиентом, всё работает, проблем с правами нет.

##### На клиенте

```bash
# после создания тестового файла на сервере
# захожу в примонтированный сетевой каталог
root@nfs-client:~# cd /mnt/upload
# проверяю наличие файла
root@nfs-client:/mnt/upload# ls -l
total 0
-rw-r--r-- 1 root root 0 Apr 23 13:19 check_file
```

Вижу, что файл появился, теперь с клиента создаю файл в шаре.
```bash
root@nfs-client:/mnt/upload# touch client_file
root@nfs-client:/mnt/upload# ls -l
total 0
-rw-r--r-- 1 root   root    0 Apr 23 13:19 check_file
-rw-r--r-- 1 nobody nogroup 0 Apr 23 13:20 client_file
```

Вижу, что файл виден клиентом, перехожу назад на сервер для проверки.

#### Расширеная

##### Предварительная проверка клиента

Перезагружаю клиент.
```bash
root@nfs-client:/mnt/upload# reboot
```

Снова захожу на клиент и перехожу в каталог `/mnt/upload` для проверки наличия ранее созданных файлов.

```bash
root@nfs-client:~# cd /mnt/upload/
root@nfs-client:/mnt/upload# ls -l
total 0
-rw-r--r-- 1 root   root    0 Apr 23 13:19 check_file
-rw-r--r-- 1 nobody nogroup 0 Apr 23 13:20 client_file
```

Вижу файлы, всё ок.

##### Проверка сервера

Теперь перезагружаю сервер, после перезагрузки подключаюсь и проверяю наличие файлов в каталоге `/srv/share/upload`

```bash
root@nfs-server:~# ls -l /srv/share/upload/
total 0
-rw-r--r-- 1 root   root    0 Apr 23 13:19 check_file
-rw-r--r-- 1 nobody nogroup 0 Apr 23 13:20 client_file
```

Вижу файлы, теперь проверяю экспорты
```bash
root@nfs-server:~# exportfs -s
/srv/share  192.168.56.20/32(sync,wdelay,hide,no_subtree_check,sec=sys,rw,secure,root_squash,no_all_squash)
```

Вижу экспорты, теперь проверяю работу RPC

```bash
root@nfs-server:~# showmount -a 192.168.56.10
All mount points on 192.168.56.10:
192.168.56.20:/srv/share
```

Сервер отдаёт информацию, что клиент `192.168.56.20` маунтит `/srv/share`

##### Проверка клиента

Опять перезагружаю клиент и захожу на него.

Проверяю работу RPC

```bash
root@nfs-client:~# showmount -a 192.168.56.10
All mount points on 192.168.56.10:
```

Я предполагаю, что пока я хотя бы раз не обращусь к `/mnt`, я не увижу точек монтирования.

Захожу в каталог `/mnt/upload`, проверяю ещё раз
```bash
root@nfs-client:~# cd /mnt/upload/
root@nfs-client:/mnt/upload# showmount -a 192.168.56.10
All mount points on 192.168.56.10:
192.168.56.20:/srv/share
```

Точка монтирования появилась.

Проверяю статус монтирования
```bash
root@nfs-client:/mnt/upload# mount | grep mnt
systemd-1 on /mnt type autofs (rw,relatime,fd=64,pgrp=1,timeout=0,minproto=5,maxproto=5,direct,pipe_ino=4588)
192.168.56.10:/srv/share/ on /mnt type nfs (rw,relatime,vers=3,rsize=524288,wsize=524288,namlen=255,hard,proto=tcp,timeo=600,retrans=2,sec=sys,mountaddr=192.168.56.10,mountvers=3,mountport=58389,mountproto=udp,local_lock=none,addr=192.168.56.10)
```

Проверяю наличие созданных ранее файлов
```bash
root@nfs-client:/mnt/upload# ls -l
total 0
-rw-r--r-- 1 nobody nogroup 0 Apr 23 13:31 aaa
-rw-r--r-- 1 root   root    0 Apr 23 13:19 check_file
-rw-r--r-- 1 nobody nogroup 0 Apr 23 13:20 client_file
```

Ранее созданные файлы на месте, создаю ещё один тестовый файл и проверяю, что файл действительно создан.

```bash
root@nfs-client:/mnt/upload# ls -l
total 0
-rw-r--r-- 1 nobody nogroup 0 Apr 23 13:31 aaa
-rw-r--r-- 1 root   root    0 Apr 23 13:19 check_file
-rw-r--r-- 1 nobody nogroup 0 Apr 23 13:20 client_file
-rw-r--r-- 1 nobody nogroup 0 Apr 23 13:52 final_test
```

#### Успех

Все проверки успешно пройдены.

Тестовый стенд работоспособен и готов к работе.

Описаные проверки проводились так же после правки файла `Vagrant`.

## Дополнение

После выполнения задания автоматизирую для Vagrant установку пакетов NFS-сервера и клиента.

Так же автоматизирую первичную настройку.

### Автоматизация создания и монтирования шары

#### Сервер

Так же сразу на сервере создам директорию и пропишу права на неё.

После чего запишу структуру для экспорта в `/etc/exports` и экспортирую ранее созданную директорию.

##### Клиент

В клиенте прописываю автомонтирование шары в `/etc/fstab`

Перезапускаю демонов и `remote-fs`.

## Успех

В ходе выполнения работы мной были созданы две виртуальные машины для сервера и клиента NFS.

Успешно создана директория на сервере, ей прописаны права.
Создана структура для последующего экспорта и проведён экспорт.

На клиенте для обеспечения автомонтирования был поправлен `fstab`, перезагружены демоны и проверен доступ к сетевой директории.

NFS использовался версии 3.

После успешного выполнения задания руками, мной был подготовлен Vagrantfile для автоматизации развёртывания стенда.

После чего я развернул стенд и ещё раз провёл проверки.

Учитывая всё вышеперечисленное и успешное прохождение проверок после развёртывания через Vagrant, считаю задание выполненным.

## Вопрос

По мере выполнения задания было выявлено неожиданное для меня поведение.

После чего для подтверждения была проведена проверка.

Я смонтировал в клиента ISO, внутри примонтировал его в `/mnt/cdrom`, прочитал файлы на ISO.

После чего выключил сервер и ещё раз попытался обратиться к примонтированному образу.

Сессия у меня зависла и я ничего не мог сделать пока не переподключился.

Таким образом, я полагаю, что в текущем виде, при недоступности шары, я не смогу получить доступ ни к чему смонтированному в `/mnt`.
Возможно даже клиентская виртуалка не сможет корректно загрузиться при недоступности шары.

Как этого можно избежать?
