# Systemd - создание unit-файла

## Цель

## Текст задания

## Окружение

- Хостовая машина: Windows 11.
- VirtualBox 7.2.6 r172322 (Qt6.8.0 on windows)
- Vagrant 2.4.9
  - Vagrant box: `bento/ubuntu-24.04` из локального файла `_boxes/bento-ubuntu-24.04.box`.
- Виртуальная машина Ubuntu 24.04:
  - 2 ядра
  - 4 ГБ ОЗУ

## Выполнение

### 1. Создаю сервис, который будет мониторить лог на наличие ключевого слова

#### Настраиваю сервис

Проделываю необходимые манпуляции согласно методичке.
```bash
# сначала файл конфигурации сервиса
# в котором прописываем слово, которое будет искаться в логе и путь до файла лога
root@otus-hw08:~# cat > /etc/default/watchlog
# Configuration file for my watchlog service
# Place it to /etc/default

# File and word in that file that we will be monit
WORD="ALERT"
LOG=/var/log/watchlog.log


# потом скрипт, который будет вызываться юнитом сервиса
root@otus-hw08:~# cat > /opt/watchlog.sh
#!/bin/bash

WORD=$1
LOG=$2
DATE=`date`

if grep $WORD $LOG &> /dev/null
then
logger "$DATE: I found word, Master!"
else
exit 0
fi


# делаю скрипт выполняемым (даём права на запуск файла)
root@otus-hw08:~# chmod +x /opt/watchlog.sh


# теперь создаю юнит для сервиса
root@otus-hw08:~# cat > /etc/systemd/system/watchlog.service
[Unit]
Description=My watchlog service

[Service]
Type=oneshot
# здесь указываю путь на файл конфигурации
# из которого берётся слово для поиска и путь к лога
EnvironmentFile=/etc/default/watchlog
# далее запускаю скрипт и передаю туда параметры из конфигурации
ExecStart=/opt/watchlog.sh $WORD $LOG


# теперь делаю юнит дл таймера, чтобы срабатывал каждые 30 секунд
root@otus-hw08:~# cat > /etc/systemd/system/watchlog.timer
[Unit]
Description=Run watchlog script every 30 second

[Timer]
# Run every 30 second
OnUnitActiveSec=30
# здесь указываю, какой сервис вызывать
Unit=watchlog.service

[Install]
WantedBy=multi-user.target


# записал пару строк в лог
root@otus-hw08:~# cat /var/log/watchlog.log 
Всё хорошо, просто замечательно, я очень рад, GOOD
Всё пропало, шеф, надо что-то делать! - ALERT

# теперь запускаю таймерЮ, который согласно конфигурации должен дёргать сервис каждые 30 секунд
root@otus-hw08:~# systemctl start watchlog.timer
```

#### Проверка

Теперь у меня должен быть результат работы
```bash
root@otus-hw08:~# tail -n 1000 /var/log/syslog  | grep word
```
И-и-и... ничего.

Лезу проверять, как там мой сервис.

#### Не работает

```bash
root@otus-hw08:~# systemctl status watchlog.timer
● watchlog.timer - Run watchlog script every 30 second
     Loaded: loaded (/etc/systemd/system/watchlog.timer; disabled; preset: enabled)
     Active: active (elapsed) since Mon 2026-05-25 05:24:30 UTC; 2min 7s ago
    Trigger: n/a
   Triggers: ● watchlog.service

May 25 05:24:30 otus-hw08 systemd[1]: Started watchlog.timer - Run watchlog script every 30 second.
root@otus-hw08:~# systemctl status watchlog.service
○ watchlog.service - My watchlog service
     Loaded: loaded (/etc/systemd/system/watchlog.service; static)
     Active: inactive (dead)
TriggeredBy: ● watchlog.timer
root@otus-hw08:~# 
root@otus-hw08:~# journalctl -u watchlog.service -n 20
-- No entries --
```

Я вижу, что таймер активен. Сервис тем временем не запускался и кода процесса не имеет.
Гугл показал, что строчка `OnUnitActiveSec=30` в таймере, говорит о том, что запуск произойдёт через 30 секунд после **последнего запуска связанного сервиса**.
Так как сервис я ещё не запускал, таймер и не отработает.

Запускаю сервис вручную и проверяю:
```bash
root@otus-hw08:~# systemctl start watchlog.service
root@otus-hw08:~# tail -n 1000 /var/log/syslog  | grep word
2026-05-25T05:45:16.744971+00:00 vagrant root: Mon May 25 05:45:16 AM UTC 2026: I found word, Master!
2026-05-25T05:45:47.048172+00:00 vagrant root: Mon May 25 05:45:47 AM UTC 2026: I found word, Master!
2026-05-25T05:46:32.104682+00:00 vagrant root: Mon May 25 05:46:32 AM UTC 2026: I found word, Master!
2026-05-25T05:47:06.503239+00:00 vagrant root: Mon May 25 05:47:06 AM UTC 2026: I found word, Master!
2026-05-25T05:48:02.257115+00:00 vagrant root: Mon May 25 05:48:02 AM UTC 2026: I found word, Master!

root@otus-hw08:~# systemctl status watchlog.timer
● watchlog.timer - Run watchlog script every 30 second
     Loaded: loaded (/etc/systemd/system/watchlog.timer; disabled; preset: enabled)
     Active: active (running) since Mon 2026-05-25 05:24:30 UTC; 24min ago
    Trigger: n/a
   Triggers: ● watchlog.service

May 25 05:24:30 otus-hw08 systemd[1]: Started watchlog.timer - Run watchlog script every 30 second.

root@otus-hw08:~# systemctl status watchlog.service
○ watchlog.service - My watchlog service
     Loaded: loaded (/etc/systemd/system/watchlog.service; static)
     Active: inactive (dead) since Mon 2026-05-25 05:48:02 UTC; 29s ago
TriggeredBy: ● watchlog.timer
    Process: 6803 ExecStart=/opt/watchlog.sh $WORD $LOG (code=exited, status=0/SUCCESS)
   Main PID: 6803 (code=exited, status=0/SUCCESS)
        CPU: 67ms

May 25 05:48:02 otus-hw08 systemd[1]: Starting watchlog.service - My watchlog service...
May 25 05:48:02 otus-hw08 systemd[1]: watchlog.service: Deactivated successfully.
May 25 05:48:02 otus-hw08 systemd[1]: Finished watchlog.service - My watchlog service.
```

Теперь вижу в логах строчки, у сервиса появился PID, значит работает.
Чтобы избежать необходимости ручного запуска, можно добавить в таймер строчку `OnBootSec=30`, что приведёт к однократному срабатыванию таймера и запуску связанного сервиса через 30 секунд после загрузки ядра.

Вкупе с `OnUnitActiveSec=30`, который отрабатывает через 30 секунд после последнего запуска связанного сервиса это даст автоматический периодический таймер.

### spawn-fcgi и создать unit-файл (spawn-fcgi.sevice)

Устанавливаю `spawn-fcgi` с зависимостями.

```bash
root@otus-hw08:~# apt-get update && apt install spawn-fcgi php php-cgi php-cli apache2 libapache2-mod-fcgid -y
```

Создаю конфигурационный файл для будущего сервиса.
Директория `/etc/spawn-fcgi/` сама не создалась, делаю вручную:

```bash
root@otus-hw08:~# mkdir /etc/spawn-fcgi
root@otus-hw08:~# cat > /etc/spawn-fcgi/fcgi.conf
# You must set some working options before the "spawn-fcgi" service will work.
# If SOCKET points to a file, then this file is cleaned up by the init script.
#
# See spawn-fcgi(1) for all possible options.
#
# Example :
SOCKET=/var/run/php-fcgi.sock
OPTIONS="-u www-data -g www-data -s $SOCKET -S -M 0600 -C 32 -F 1 -- /usr/bin/php-cgi"
```

Теперь создаю unit-файл сервиса.

```bash
root@otus-hw08:~# cat > /etc/systemd/system/spawn-fcgi.service
[Unit]
Description=Spawn-fcgi startup service by Otus
After=network.target

[Service]
Type=simple
PIDFile=/var/run/spawn-fcgi.pid
EnvironmentFile=/etc/spawn-fcgi/fcgi.conf
ExecStart=/usr/bin/spawn-fcgi -n $OPTIONS
KillMode=process

[Install]
WantedBy=multi-user.target
```

Запускаю сервис:

```bash
root@otus-hw08:~# systemctl start spawn-fcgi
root@otus-hw08:~# systemctl status spawn-fcgi
● spawn-fcgi.service - Spawn-fcgi startup service by Otus
     Loaded: loaded (/etc/systemd/system/spawn-fcgi.service; disabled; preset: enabled)
     Active: active (running) since Mon 2026-05-25 06:27:58 UTC; 2min 19s ago
   Main PID: 16509 (php-cgi)
      Tasks: 33 (limit: 9430)
     Memory: 14.3M (peak: 14.6M)
        CPU: 104ms
     CGroup: /system.slice/spawn-fcgi.service
             ├─16509 /usr/bin/php-cgi
             ├─16510 /usr/bin/php-cgi
             ...
             └─16541 /usr/bin/php-cgi
```

Сервис запустился, всё работает.

### Доработка unit-файл Nginx

Установлю nginx
```bash
root@otus-hw08:~# apt install nginx -y
```

Создаю шаблонный юнит-файл `/etc/systemd/system/nginx@.service`.

```bash
root@otus-hw08:~# cat > /etc/systemd/system/nginx@.service
[Unit]
Description=A high performance web server and a reverse proxy server
Documentation=man:nginx(8)
After=network.target nss-lookup.target

[Service]
Type=forking
PIDFile=/run/nginx-%I.pid
ExecStartPre=/usr/sbin/nginx -t -c /etc/nginx/nginx-%I.conf -q -g 'daemon on; master_process on;'
ExecStart=/usr/sbin/nginx -c /etc/nginx/nginx-%I.conf -g 'daemon on; master_process on;'
ExecReload=/usr/sbin/nginx -c /etc/nginx/nginx-%I.conf -g 'daemon on; master_process on;' -s reload
ExecStop=-/sbin/start-stop-daemon --quiet --stop --retry QUIT/5 --pidfile /run/nginx-%I.pid
TimeoutStopSec=5
KillMode=mixed

[Install]
WantedBy=multi-user.target
```

Создаю два конфигурационных файла на основе `/etc/nginx/nginx.conf`. В каждом три отличия от базового:
- уникальный путь к PID-файлу (`/run/nginx-first.pid` / `/run/nginx-second.pid`)
- уникальный порт прослушивания (9001 / 9002) в явном `server {}` блоке
- убраны `include /etc/nginx/conf.d/*.conf` и `include /etc/nginx/sites-enabled/*` — иначе оба инстанса подтянут один и тот же дефолтный порт

```bash
root@otus-hw08:~# cat > /etc/nginx/nginx-first.conf
user www-data;
worker_processes auto;
pid /run/nginx-first.pid;
error_log /var/log/nginx/error.log;
include /etc/nginx/modules-enabled/*.conf;

events {
        worker_connections 768;
}

http {
        server {
                listen 9001;
        }
        sendfile on;
        tcp_nopush on;
        types_hash_max_size 2048;
        include /etc/nginx/mime.types;
        default_type application/octet-stream;
        ssl_protocols TLSv1 TLSv1.1 TLSv1.2 TLSv1.3;
        ssl_prefer_server_ciphers on;
        access_log /var/log/nginx/access.log;
        gzip on;
}
```

Аналогично создаю `nginx-second.conf` с `pid /run/nginx-second.pid;` и `listen 9002;`.

Проверяю синтаксис конфигов:

```bash
root@otus-hw08:~# nginx -t -c /etc/nginx/nginx-first.conf
nginx: the configuration file /etc/nginx/nginx-first.conf syntax is ok
nginx: configuration file /etc/nginx/nginx-first.conf test is successful
root@otus-hw08:~# nginx -t -c /etc/nginx/nginx-second.conf
nginx: the configuration file /etc/nginx/nginx-second.conf syntax is ok
nginx: configuration file /etc/nginx/nginx-second.conf test is successful
```

Запускаю оба инстанса:

```bash
root@otus-hw08:~# systemctl start nginx@first
root@otus-hw08:~# systemctl start nginx@second
```

#### Проверка

```bash
root@otus-hw08:~# ss -tnulp | grep nginx
tcp   LISTEN 0      511           0.0.0.0:9001      0.0.0.0:*    users:(("nginx",pid=25003,fd=5),("nginx",pid=25002,fd=5),("nginx",pid=25001,fd=5),("nginx",pid=25000,fd=5),("nginx",pid=24999,fd=5))
tcp   LISTEN 0      511           0.0.0.0:9002      0.0.0.0:*    users:(("nginx",pid=25014,fd=5),("nginx",pid=25013,fd=5),("nginx",pid=25012,fd=5),("nginx",pid=25011,fd=5),("nginx",pid=25010,fd=5))
root@otus-hw08:~# ps afx | grep nginx
  24999 ?        Ss     0:00 nginx: master process /usr/sbin/nginx -c /etc/nginx/nginx-first.conf -g daemon on; master_process on;
  25000 ?        S      0:00  \_ nginx: worker process
  25001 ?        S      0:00  \_ nginx: worker process
  25002 ?        S      0:00  \_ nginx: worker process
  25003 ?        S      0:00  \_ nginx: worker process
  25010 ?        Ss     0:00 nginx: master process /usr/sbin/nginx -c /etc/nginx/nginx-second.conf -g daemon on; master_process on;
  25011 ?        S      0:00  \_ nginx: worker process
  25012 ?        S      0:00  \_ nginx: worker process
  25013 ?        S      0:00  \_ nginx: worker process
  25014 ?        S      0:00  \_ nginx: worker process
```

Два независимых процесс-дерева nginx, каждый на своём порту.

## Успех

В процессе выполнения я написал сервис, мониторящий лог на наличие ключевого слова.
Установил spawn-fcgi и сделал unit-файл для него.
Создал шаблонный Unit-файл Nginx для запуска нескольских инстансов, подготовил конфигурационные файлы для этих инстансов.