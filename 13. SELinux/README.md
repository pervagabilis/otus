# SELinux

## Цель

Работать с SELinux: диагностировать проблемы и модифицировать политики SELinux для корректной работы приложений, не отключая SELinux.

## Критерии задания

1. Запустить nginx на нестандартном порту тремя разными способами — описать, реализовать и продемонстрировать каждый:
   - переключатели `setsebool`;
   - добавление нестандартного порта в имеющийся тип;
   - формирование и установка модуля SELinux.
2. Обеспечить работоспособность приложения при включённом SELinux на стенде `selinux_dns_problems`:
   - описать причину неработоспособности механизма обновления зоны;
   - предложить решения и обосновать выбор одного из них;
   - реализовать и продемонстрировать выбранное решение.

## Окружение

- Хостовая машина: Windows 11.
- VirtualBox 7.2.8 r173730
- Vagrant 2.4.9
  - Vagrant box: `almalinux/9` версии 9.4.20240805 из Vagrant Cloud.
- Виртуальные машины AlmaLinux 9.4, ядро 5.14.0-427.28.1.el9_4, SELinux в режиме Enforcing, политика targeted, по 2 ядра и 2 ГБ ОЗУ:
  - задание 1 — `selinux` (стенд [Nickmob/vagrant_selinux](https://github.com/Nickmob/vagrant_selinux), каталог `vm/`), nginx на порту 4881, проброшенном на хост. Провижининг обновил пакеты SELinux из актуальных репозиториев: `selinux-policy-targeted-38.1.75-2.el9_8`, `policycoreutils-3.6-5.el9`;
  - задание 2 — `ns01` (192.168.50.10) и `client` (192.168.50.15) (стенд [Nickmob/vagrant_selinux_dns_problems](https://github.com/Nickmob/vagrant_selinux_dns_problems), каталог `dns_problems/`): `bind-9.16.23-40.el9_8.9`, `selinux-policy-targeted-38.1.35-2.el9_4.2`.

## Выполнение

Стенды по 2 ГБ ОЗУ, три VM одновременно на хост не помещаются, поэтому поднимаю их по очереди:

```powershell
PS C:\DEV\otus\13. SELinux\vm> vagrant up
PS C:\DEV\otus\13. SELinux\vm> vagrant halt
PS C:\DEV\otus\13. SELinux\dns_problems> vagrant up
```

### Задание 1. Nginx на нестандартном порту

#### 1. Исходное состояние

Уже при провижининге стенда nginx не стартует:

```bash
    selinux: Sep 28 19:05:10 selinux nginx[6735]: nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
    selinux: Sep 28 19:05:10 selinux nginx[6735]: nginx: [emerg] bind() to 0.0.0.0:4881 failed (13: Permission denied)
    selinux: Sep 28 19:05:10 selinux nginx[6735]: nginx: configuration file /etc/nginx/nginx.conf test failed
```

Захожу на стенд и проверяю, что мешает не файервол и не конфиг nginx, а SELinux в режиме Enforcing:

```bash
[root@selinux ~]# systemctl status firewalld
○ firewalld.service - firewalld - dynamic firewall daemon
     Loaded: loaded (/usr/lib/systemd/system/firewalld.service; disabled; preset: enabled)
     Active: inactive (dead)
       Docs: man:firewalld(1)
[root@selinux ~]# nginx -t
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful
[root@selinux ~]# getenforce
Enforcing
```

#### 2. Ищу причину в логе аудита

```bash
[root@selinux ~]# grep denied /var/log/audit/audit.log | grep nginx
type=AVC msg=audit(1790622310.835:478): avc:  denied  { name_bind } for  pid=6735 comm="nginx" src=4881 scontext=system_u:system_r:httpd_t:s0 tcontext=system_u:object_r:unreserved_port_t:s0 tclass=tcp_socket permissive=0
type=AVC msg=audit(1790666453.221:333): avc:  denied  { name_bind } for  pid=1804 comm="nginx" src=4881 scontext=system_u:system_r:httpd_t:s0 tcontext=system_u:object_r:unreserved_port_t:s0 tclass=tcp_socket permissive=0
type=AVC msg=audit(1790666461.652:337): avc:  denied  { name_bind } for  pid=1821 comm="nginx" src=4881 scontext=system_u:system_r:httpd_t:s0 tcontext=system_u:object_r:unreserved_port_t:s0 tclass=tcp_socket permissive=0
type=AVC msg=audit(1790666511.844:344): avc:  denied  { name_bind } for  pid=1833 comm="nginx" src=4881 scontext=system_u:system_r:httpd_t:s0 tcontext=system_u:object_r:unreserved_port_t:s0 tclass=tcp_socket permissive=0
[root@selinux ~]# grep 1790666511.844:344 /var/log/audit/audit.log | audit2why
type=AVC msg=audit(1790666511.844:344): avc:  denied  { name_bind } for  pid=1833 comm="nginx" src=4881 scontext=system_u:system_r:httpd_t:s0 tcontext=system_u:object_r:unreserved_port_t:s0 tclass=tcp_socket permissive=0

        Was caused by:
        The boolean nis_enabled was set incorrectly. 
        Description:
        Allow nis to enabled

        Allow access by executing:
        # setsebool -P nis_enabled 1
```

Домен `httpd_t` пытается занять (`name_bind`) TCP-порт 4881, а у этого порта тип `unreserved_port_t`. Правила, разрешающего `httpd_t` занимать порты этого типа, в политике нет. Порт 4881 не входит в `http_port_t`, поэтому считается «обычным» непривилегированным портом.

Каждый способ проверяю одинаково: применяю, перезапускаю nginx, открываю http://127.0.0.1:4881 на хосте. Потом откатываю и убеждаюсь, что nginx снова не стартует, чтобы следующий способ не работал за счёт предыдущего.

#### 3. Способ 1: переключатель `setsebool`

Включаю переключатель, который предложил `audit2why`. Ключ `-P` записывает значение в политику, чтобы оно пережило перезагрузку:

```bash
[root@selinux ~]# setsebool -P nis_enabled on
[root@selinux ~]# systemctl restart nginx
[root@selinux ~]# systemctl status nginx
● nginx.service - The nginx HTTP and reverse proxy server
     Loaded: loaded (/usr/lib/systemd/system/nginx.service; disabled; preset: disabled)
     Active: active (running) since Tue 2026-09-29 17:32:13 UTC; 3s ago
    Process: 2046 ExecStartPre=/usr/bin/rm -f /run/nginx.pid (code=exited, status=0/SUCCESS)
    Process: 2047 ExecStartPre=/usr/sbin/nginx -t (code=exited, status=0/SUCCESS)
    Process: 2048 ExecStart=/usr/sbin/nginx (code=exited, status=0/SUCCESS)
   Main PID: 2049 (nginx)
...
Sep 29 17:32:13 selinux systemd[1]: Started The nginx HTTP and reverse proxy server.
[root@selinux ~]# getsebool -a | grep nis_enabled
nis_enabled --> on
```

Страница открывается с хоста:

![Страница nginx на порту 4881](nginx-4881.png)

Откатываю. Выключить переключатель мало: уже запущенный nginx держит сокет и продолжит работать. Запрет срабатывает на следующем `bind()`, поэтому нужен `restart`:

```bash
[root@selinux ~]# setsebool -P nis_enabled off
[root@selinux ~]# systemctl restart nginx
Job for nginx.service failed because the control process exited with error code.
See "systemctl status nginx.service" and "journalctl -xeu nginx.service" for details.
```

Смотрю, что на самом деле разрешает `nis_enabled`:

```bash
[root@selinux ~]# sesearch -A -b nis_enabled | grep name_bind | head
allow auditadm_su_t rpc_port_type:tcp_socket name_bind; [ nis_enabled ]:True
allow auditadm_su_t rpc_port_type:udp_socket name_bind; [ nis_enabled ]:True
allow checkpc_t ephemeral_port_t:tcp_socket name_bind; [ nis_enabled ]:True
allow checkpc_t ephemeral_port_t:udp_socket name_bind; [ nis_enabled ]:True
allow checkpc_t port_t:tcp_socket name_bind; [ nis_enabled ]:True
allow checkpc_t port_t:udp_socket name_bind; [ nis_enabled ]:True
allow checkpc_t unreserved_port_t:tcp_socket name_bind; [ nis_enabled ]:True
allow checkpc_t unreserved_port_t:udp_socket name_bind; [ nis_enabled ]:True
allow chfn_t rpc_port_type:tcp_socket name_bind; [ nis_enabled ]:True
allow chfn_t rpc_port_type:udp_socket name_bind; [ nis_enabled ]:True
```

Переключатель не про nginx: он открывает `name_bind` на незарезервированные, ephemeral- и RPC-порты десяткам доменов сразу.

#### 4. Способ 2: добавляю порт в существующий тип

Ищу тип, которым политика помечает HTTP-порты, и добавляю в него 4881:

```bash
[root@selinux ~]# semanage port -l | grep http
http_cache_port_t              tcp      8080, 8118, 8123, 10001-10010
http_cache_port_t              udp      3130
http_port_t                    tcp      80, 81, 443, 488, 8008, 8009, 8443, 9000
pegasus_http_port_t            tcp      5988
pegasus_https_port_t           tcp      5989
[root@selinux ~]# semanage port -a -t http_port_t -p tcp 4881
[root@selinux ~]# semanage port -l | grep http_port_t
http_port_t                    tcp      4881, 80, 81, 443, 488, 8008, 8009, 8443, 9000
pegasus_http_port_t            tcp      5988
[root@selinux ~]# systemctl restart nginx
[root@selinux ~]# systemctl status nginx
● nginx.service - The nginx HTTP and reverse proxy server
     Loaded: loaded (/usr/lib/systemd/system/nginx.service; disabled; preset: disabled)
     Active: active (running) since Tue 2026-09-29 17:35:03 UTC; 3s ago
...
Sep 29 17:35:03 selinux systemd[1]: Started The nginx HTTP and reverse proxy server.
```

Страница снова открывается. Откатываю:

```bash
[root@selinux ~]# semanage port -d -t http_port_t -p tcp 4881
[root@selinux ~]# semanage port -l | grep http_port_t
http_port_t                    tcp      80, 81, 443, 488, 8008, 8009, 8443, 9000
pegasus_http_port_t            tcp      5988
[root@selinux ~]# systemctl restart nginx
Job for nginx.service failed because the control process exited with error code.
See "systemctl status nginx.service" and "journalctl -xeu nginx.service" for details.
```

Страница снова не открывается.

#### 5. Способ 3: собираю и устанавливаю модуль SELinux

`audit2allow` превращает отказы из лога в правила модуля. Перед установкой смотрю исходник модуля `nginx.te`: в `audit.log` вся история стенда, и в модуль попадает всё, что нашёл `grep nginx`.

```bash
[root@selinux ~]# systemctl start nginx
Job for nginx.service failed because the control process exited with error code.
See "systemctl status nginx.service" and "journalctl -xeu nginx.service" for details.
[root@selinux ~]# grep nginx /var/log/audit/audit.log | audit2allow -M nginx
******************** IMPORTANT ***********************
To make this policy package active, execute:

semodule -i nginx.pp

[root@selinux ~]# cat nginx.te

module nginx 1.0;

require {
        type unreserved_port_t;
        type httpd_t;
        class tcp_socket name_bind;
}

#============= httpd_t ==============

#!!!! This avc can be allowed using the boolean 'nis_enabled'
allow httpd_t unreserved_port_t:tcp_socket name_bind;
[root@selinux ~]# semodule -i nginx.pp
[root@selinux ~]# systemctl start nginx
[root@selinux ~]# systemctl status nginx
● nginx.service - The nginx HTTP and reverse proxy server
     Loaded: loaded (/usr/lib/systemd/system/nginx.service; disabled; preset: disabled)
     Active: active (running) since Tue 2026-09-29 17:37:31 UTC; 2s ago
...
Sep 29 17:37:31 selinux systemd[1]: Started The nginx HTTP and reverse proxy server.
[root@selinux ~]# semodule -l | grep nginx
nginx
```

В модуле одно правило. Номера порта в нём нет: `httpd_t` получает право занимать любой порт типа `unreserved_port_t`. Страница снова открывается. Откатываю:

```bash
[root@selinux ~]# semodule -r nginx
libsemanage.semanage_direct_remove_key: Removing last nginx module (no other nginx module exists at another priority).
[root@selinux ~]# systemctl restart nginx
Job for nginx.service failed because the control process exited with error code.
See "systemctl status nginx.service" and "journalctl -xeu nginx.service" for details.
```

И снова не открывается.

### Задание 2. Обновление зоны DNS при включённом SELinux

#### 1. Воспроизвожу проблему

С клиента пытаюсь добавить запись в динамическую зону `ddns.lab`:

```bash
[vagrant@client ~]$ nsupdate -k /etc/named.zonetransfer.key
> server 192.168.50.10
> zone ddns.lab
> update add www.ddns.lab. 60 A 192.168.50.15
> send
update failed: SERVFAIL
> quit
```

#### 2. Смотрю лог SELinux на обеих машинах

По методичке на клиенте ошибок быть не должно, а у меня есть. Такие же записи есть и на сервере:

```bash
[root@client ~]# cat /var/log/audit/audit.log | audit2why
type=AVC msg=audit(1790704033.316:36): avc:  denied  { open } for  pid=776 comm="20-chrony-dhcp" path="/etc/sysconfig/network-scripts/ifcfg-eth1" dev="sda4" ino=17270566 scontext=system_u:system_r:NetworkManager_dispatcher_chronyc_t:s0 tcontext=unconfined_u:object_r:user_tmp_t:s0 tclass=file permissive=0

        Was caused by:
                Missing type enforcement (TE) allow rule.

                You can use audit2allow to generate a loadable module to allow this access.
...
# ... вырезаны ещё три такие же записи ...
```

К DNS они отношения не имеют. При каждом `vagrant up` Vagrant пересоздаёт `ifcfg-eth1` через временный файл, и файл получает метку `user_tmp_t`. Dispatcher-скрипт chrony не может его открыть. Это видно и по меняющемуся `ino`. Трогать не стал, но это хороший пример, почему `audit2allow` нельзя натравливать на весь лог без фильтра: это правило тоже попало бы в модуль.

На сервере `ns01`, кроме того же шума, есть запись, которая относится к задаче:

```bash
[root@ns01 ~]# cat /var/log/audit/audit.log | audit2why
...
# ... вырезаны четыре записи 20-chrony-dhcp, как на клиенте ...
type=AVC msg=audit(1790704145.182:505): avc:  denied  { write } for  pid=768 comm="isc-net-0000" name="dynamic" dev="sda4" ino=51109499 scontext=system_u:system_r:named_t:s0 tcontext=unconfined_u:object_r:named_conf_t:s0 tclass=dir permissive=0

        Was caused by:
                Missing type enforcement (TE) allow rule.

                You can use audit2allow to generate a loadable module to allow this access.
```

Процессу `named` (домен `named_t`) запрещена запись в каталог `dynamic` с типом `named_conf_t`.

#### 3. Сравниваю метки с политикой

```bash
[root@ns01 ~]# ls -alZ /var/named/named.localhost
-rw-r-----. 1 root named system_u:object_r:named_zone_t:s0 152 Sep 16 16:10 /var/named/named.localhost
[root@ns01 ~]# ls -laZ /etc/named
total 28
drw-rwx---.  3 root named system_u:object_r:named_conf_t:s0      121 Sep 28 19:18 .
drwxr-xr-x. 86 root root  system_u:object_r:etc_t:s0            8192 Sep 29 17:46 ..
drw-rwx---.  2 root named unconfined_u:object_r:named_conf_t:s0   56 Sep 28 19:18 dynamic
-rw-rw----.  1 root named system_u:object_r:named_conf_t:s0      784 Sep 28 19:18 named.50.168.192.rev
-rw-rw----.  1 root named system_u:object_r:named_conf_t:s0      610 Sep 28 19:18 named.dns.lab
-rw-rw----.  1 root named system_u:object_r:named_conf_t:s0      609 Sep 28 19:18 named.dns.lab.view1
-rw-rw----.  1 root named system_u:object_r:named_conf_t:s0      657 Sep 28 19:18 named.newdns.lab
[root@ns01 ~]# ls -laZ /etc/named/dynamic
total 8
drw-rwx---. 2 root  named unconfined_u:object_r:named_conf_t:s0  56 Sep 28 19:18 .
drw-rwx---. 3 root  named system_u:object_r:named_conf_t:s0     121 Sep 28 19:18 ..
-rw-rw----. 1 named named system_u:object_r:named_conf_t:s0     509 Sep 28 19:18 named.ddns.lab
-rw-rw----. 1 named named system_u:object_r:named_conf_t:s0     509 Sep 28 19:18 named.ddns.lab.view1
[root@ns01 ~]# semanage fcontext -l | grep named
...
/etc/named(/.*)?                                   all files          system_u:object_r:named_conf_t:s0 
...
/var/named(/.*)?                                   all files          system_u:object_r:named_zone_t:s0 
...
/var/named/dynamic(/.*)?                           all files          system_u:object_r:named_cache_t:s0 
...
# ... вырезано, оставлены строки для /etc/named и /var/named ...
```

#### 4. Причина

Метки на `/etc/named` не «неправильные», как сказано в методичке: по правилу `/etc/named(/.*)?` всё содержимое каталога и должно быть `named_conf_t`. Проблема в размещении. Файлы динамической зоны, в которые named пишет журнал обновлений (`*.jnl`), лежат в каталоге, который политика считает конфигурацией, а конфигурацию `named_t` может только читать. Для динамических зон политика предусматривает `/var/named/dynamic` с типом `named_cache_t`.

#### 5. Решение из методички: `chcon`

Методичка меняет тип всего `/etc/named` на `named_zone_t`. Сначала проверяю, что `named_t` вообще может писать в `named_zone_t`: это разрешено, только если включён переключатель `named_write_master_zones`.

```bash
[root@ns01 ~]# getsebool named_write_master_zones
named_write_master_zones --> on
[root@ns01 ~]# chcon -R -t named_zone_t /etc/named
[root@ns01 ~]# ls -laZ /etc/named /etc/named/dynamic
/etc/named:
total 28
drw-rwx---.  3 root named system_u:object_r:named_zone_t:s0      121 Sep 28 19:18 .
drwxr-xr-x. 86 root root  system_u:object_r:etc_t:s0            8192 Sep 29 17:46 ..
drw-rwx---.  2 root named unconfined_u:object_r:named_zone_t:s0   56 Sep 28 19:18 dynamic
-rw-rw----.  1 root named system_u:object_r:named_zone_t:s0      784 Sep 28 19:18 named.50.168.192.rev
-rw-rw----.  1 root named system_u:object_r:named_zone_t:s0      610 Sep 28 19:18 named.dns.lab
-rw-rw----.  1 root named system_u:object_r:named_zone_t:s0      609 Sep 28 19:18 named.dns.lab.view1
-rw-rw----.  1 root named system_u:object_r:named_zone_t:s0      657 Sep 28 19:18 named.newdns.lab

/etc/named/dynamic:
total 8
drw-rwx---. 2 root  named unconfined_u:object_r:named_zone_t:s0  56 Sep 28 19:18 .
drw-rwx---. 3 root  named system_u:object_r:named_zone_t:s0     121 Sep 28 19:18 ..
-rw-rw----. 1 named named system_u:object_r:named_zone_t:s0     509 Sep 28 19:18 named.ddns.lab
-rw-rw----. 1 named named system_u:object_r:named_zone_t:s0     509 Sep 28 19:18 named.ddns.lab.view1
```

Обновление с клиента проходит:

```bash
[root@client ~]# nsupdate -k /etc/named.zonetransfer.key
> server 192.168.50.10
> zone ddns.lab
> update add www.ddns.lab. 60 A 192.168.50.15
> send
> quit
[root@client ~]# dig @192.168.50.10 www.ddns.lab
...
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 23886
...
;; ANSWER SECTION:
www.ddns.lab.           60      IN      A       192.168.50.15
...
```

Перезагружаю стенд (`vagrant reload`), запись на месте: метка из `chcon` хранится в xattr на диске и переживает перезагрузку.

```bash
[vagrant@client ~]$ dig @192.168.50.10 www.ddns.lab
...
;; ANSWER SECTION:
www.ddns.lab.           60      IN      A       192.168.50.15
...
```

Но `restorecon` возвращает всё, что прописано в политике:

```bash
[root@ns01 ~]# restorecon -Rv /etc/named
Relabeled /etc/named from system_u:object_r:named_zone_t:s0 to system_u:object_r:named_conf_t:s0
Relabeled /etc/named/named.dns.lab from system_u:object_r:named_zone_t:s0 to system_u:object_r:named_conf_t:s0
Relabeled /etc/named/named.dns.lab.view1 from system_u:object_r:named_zone_t:s0 to system_u:object_r:named_conf_t:s0
Relabeled /etc/named/dynamic from unconfined_u:object_r:named_zone_t:s0 to unconfined_u:object_r:named_conf_t:s0
Relabeled /etc/named/dynamic/named.ddns.lab from system_u:object_r:named_zone_t:s0 to system_u:object_r:named_conf_t:s0
Relabeled /etc/named/dynamic/named.ddns.lab.view1 from system_u:object_r:named_zone_t:s0 to system_u:object_r:named_conf_t:s0
Relabeled /etc/named/dynamic/named.ddns.lab.view1.jnl from system_u:object_r:named_zone_t:s0 to system_u:object_r:named_conf_t:s0
Relabeled /etc/named/named.newdns.lab from system_u:object_r:named_zone_t:s0 to system_u:object_r:named_conf_t:s0
Relabeled /etc/named/named.50.168.192.rev from system_u:object_r:named_zone_t:s0 to system_u:object_r:named_conf_t:s0
```

То есть `chcon` — временная мера: её отменит любой `restorecon` или полная перемаркировка ФС. К тому же тип меняется у всего `/etc/named`, хотя запись нужна только в `dynamic`.

#### 6. Варианты решения и выбор

| Вариант | Переживает перемаркировку | Что задевает |
|---|---|---|
| `chcon -R -t named_zone_t /etc/named` (методичка) | нет | тип меняется у всего `/etc/named`, включая конфигурацию |
| `semanage fcontext` на `/etc/named/dynamic` с типом `named_cache_t` + `restorecon` | да | только каталог динамических зон |
| Перенести динамические зоны в `/var/named/dynamic` и поправить пути в `named.conf` | да | конфиг приложения и плейбук |
| Модуль `audit2allow`: `named_t` пишет в `named_conf_t` | да | named получает запись во всю свою конфигурацию, включая `named.conf` |

Выбрал `semanage fcontext` с типом `named_cache_t`:

- правило записывается в политику, поэтому метка переживает и `restorecon`, и полную перемаркировку;
- `named_cache_t` — тип, который политика сама назначает каталогу динамических зон (`/var/named/dynamic`), запись в него разрешена `named_t` без переключателей. Решение из методички через `named_zone_t` сломается, если выключить `named_write_master_zones`;
- правило касается только `dynamic`, конфигурация и статические зоны остаются только для чтения;
- конфигурацию BIND менять не нужно.

#### 7. Реализую выбранное решение

После `restorecon` из предыдущего шага стенд снова сломан. Проверяю на новой записи, чтобы не путать её со старой:

```bash
[vagrant@client ~]$ nsupdate -k /etc/named.zonetransfer.key
> server 192.168.50.10
> zone ddns.lab
> update add test.ddns.lab. 60 A 192.168.50.20
> send
update failed: SERVFAIL
> quit
```

Добавляю локальное правило и применяю его. `matchpathcon` показывает, что правило действует только на `dynamic`:

```bash
[root@ns01 ~]# semanage fcontext -a -t named_cache_t "/etc/named/dynamic(/.*)?"
[root@ns01 ~]# semanage fcontext -l -C
SELinux fcontext                                   type               Context

/etc/named/dynamic(/.*)?                           all files          system_u:object_r:named_cache_t:s0 
[root@ns01 ~]# matchpathcon /etc/named/dynamic /etc/named/named.dns.lab
/etc/named/dynamic      system_u:object_r:named_cache_t:s0
/etc/named/named.dns.lab        system_u:object_r:named_conf_t:s0
[root@ns01 ~]# restorecon -Rv /etc/named
Relabeled /etc/named/dynamic from unconfined_u:object_r:named_conf_t:s0 to unconfined_u:object_r:named_cache_t:s0
Relabeled /etc/named/dynamic/named.ddns.lab from system_u:object_r:named_conf_t:s0 to system_u:object_r:named_cache_t:s0
Relabeled /etc/named/dynamic/named.ddns.lab.view1 from system_u:object_r:named_conf_t:s0 to system_u:object_r:named_cache_t:s0
Relabeled /etc/named/dynamic/named.ddns.lab.view1.jnl from system_u:object_r:named_conf_t:s0 to system_u:object_r:named_cache_t:s0
[root@ns01 ~]# ls -laZ /etc/named /etc/named/dynamic
/etc/named:
total 28
drw-rwx---.  3 root named system_u:object_r:named_conf_t:s0       121 Sep 28 19:18 .
drwxr-xr-x. 86 root root  system_u:object_r:etc_t:s0             8192 Sep 29 17:57 ..
drw-rwx---.  2 root named unconfined_u:object_r:named_cache_t:s0   88 Sep 29 17:54 dynamic
-rw-rw----.  1 root named system_u:object_r:named_conf_t:s0       784 Sep 28 19:18 named.50.168.192.rev
-rw-rw----.  1 root named system_u:object_r:named_conf_t:s0       610 Sep 28 19:18 named.dns.lab
-rw-rw----.  1 root named system_u:object_r:named_conf_t:s0       609 Sep 28 19:18 named.dns.lab.view1
-rw-rw----.  1 root named system_u:object_r:named_conf_t:s0       657 Sep 28 19:18 named.newdns.lab

/etc/named/dynamic:
total 12
drw-rwx---. 2 root  named unconfined_u:object_r:named_cache_t:s0  88 Sep 29 17:54 .
drw-rwx---. 3 root  named system_u:object_r:named_conf_t:s0      121 Sep 28 19:18 ..
-rw-rw----. 1 named named system_u:object_r:named_cache_t:s0     509 Sep 28 19:18 named.ddns.lab
-rw-rw----. 1 named named system_u:object_r:named_cache_t:s0     509 Sep 28 19:18 named.ddns.lab.view1
-rw-r--r--. 1 named named system_u:object_r:named_cache_t:s0     704 Sep 29 17:54 named.ddns.lab.view1.jnl
```

Откатить решение можно так: `semanage fcontext -d "/etc/named/dynamic(/.*)?"`, затем `restorecon -Rv /etc/named`.

## Успех

Задание 1. Все три способа применены, работа nginx подтверждена с хоста, каждый откат подтверждён тем, что `restart` снова падает:

| Способ | Применение | Откат |
|---|---|---|
| `setsebool -P nis_enabled on` | `active (running)`, страница открывается | `off` → `restart` падает |
| `semanage port -a -t http_port_t -p tcp 4881` | `active (running)`, страница открывается | `-d` → `restart` падает |
| `audit2allow -M nginx` + `semodule -i nginx.pp` | `active (running)`, страница открывается | `semodule -r nginx` → `restart` падает |

Задание 2. Обновление зоны с клиента работает:

```bash
[vagrant@client ~]$ nsupdate -k /etc/named.zonetransfer.key
> server 192.168.50.10
> zone ddns.lab
> update add test.ddns.lab. 60 A 192.168.50.20
> send
> quit
[vagrant@client ~]$ dig @192.168.50.10 test.ddns.lab

; <<>> DiG 9.16.23-RH <<>> @192.168.50.10 test.ddns.lab
; (1 server found)
;; global options: +cmd
;; Got answer:
;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 16012
;; flags: qr aa rd ra; QUERY: 1, ANSWER: 1, AUTHORITY: 0, ADDITIONAL: 1

;; OPT PSEUDOSECTION:
; EDNS: version: 0, flags:; udp: 1232
; COOKIE: c31400ade750f6f9010000006abbfdcf7c0e3984567e5367 (good)
;; QUESTION SECTION:
;test.ddns.lab.                 IN      A

;; ANSWER SECTION:
test.ddns.lab.          60      IN      A       192.168.50.20

;; Query time: 4 msec
;; SERVER: 192.168.50.10#53(192.168.50.10)
;; WHEN: Tue Sep 29 18:05:03 UTC 2026
;; MSG SIZE  rcvd: 86
```

Повторный `restorecon` ничего не меняет, значит, метка соответствует политике:

```bash
[root@ns01 ~]# restorecon -Rv /etc/named
[root@ns01 ~]#
```

Я запустил nginx на порту 4881 тремя способами и сравнил, насколько широкие права даёт каждый. Нашёл причину, по которой не обновляется динамическая зона DNS, и исправил её правилом в политике, а не временной сменой метки.

Задание выполнено.