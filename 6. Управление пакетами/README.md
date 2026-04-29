# Управление пакетами. Дистрибьюция софта

## Цель

Научиться собирать RPM-пакеты.
Создавать собственный RPM-репозиторий.

## Текст задания

🎯 Что нужно сделать?

- создать свой RPM (можно взять свое приложение, либо собрать к примеру Apache с определенными опциями);
- cоздать свой репозиторий и разместить там ранее собранный RPM;
- реализовать это все либо в Vagrant, либо развернуть у себя через Nginx и дать ссылку на репозиторий.

## Окружение

- Хостовая машина на Windows 11.
- VirtualBox версии 7.2.6 r172322 (Qt6.8.0 on windows)
- Vagrant 2.4.9
- Образ AlmaLinux 9.3.20231118 для Vagrant (https://portal.cloud.hashicorp.com/vagrant/discover/almalinux/9/versions/9.3.20231118)

### Каталоги и файлы

В репозитории представлены следующие каталоги и файлы

|Файл/Каталог|Назначение|
|---|---|
|`README.md`| Этот файл. Пошагово описывает выполнение задания|
|vm|Каталог для Vagrant|
|vm/Vagrantfile|Файл для Vagrant, описывающий виртуальные машины тестового стенда под это задание|

## Выполнение

### 1. Подготовка, Vagrant

Подготавливаю Vagrant файл для развёртывания.

Запускаю стенд командой `vagrant up`

### 2. Создание RPM пакета

#### Установка требуемых для сборки пакетов

```bash
[root@alma-otus ~]#yum install -y wget rpmdevtools rpm-build createrepo yum-utils cmake gcc git nano

```

#### Сборка

Нужно загрузить пакет SRPM для httpd

```bash
[vagrant@alma-otus ~]$ mkdir rpm && cd rpm
[vagrant@alma-otus rpm]$ 
```

Создаю папку для дальнейшей работы с файлами пакета, проваливаюсь в неё и загружаю SRPM пакет для nginx.
```bash
[root@alma-otus ~]# mkdir rpm && cd rpm
[root@alma-otus rpm]# yumdownloader --source nginx
enabling appstream-source repository
enabling baseos-source repository
enabling extras-source repository
AlmaLinux 9 - AppStream - Source                           701 kB/s | 920 kB     00:01    
AlmaLinux 9 - BaseOS - Source                              307 kB/s | 378 kB     00:01    
AlmaLinux 9 - Extras - Source                              7.2 kB/s | 8.5 kB     00:01    
nginx-1.20.1-24.el9_7.2.alma.1.src.rpm                     1.1 MB/s | 1.1 MB     00:00
```

Ставлю все необходимые для сборки пакета зависимости
```bash
[root@alma-otus rpm]# rpm -Uvh nginx*.src.rpm
Updating / installing...
################################# [100%]
[root@alma-otus rpm]#  yum-builddep nginx
Transaction Summary
===============================
Install  70 Packages
Upgrade  34 Packages

Total download size: 47 M
Is this ok [y/N]: y
-------------------------------
Total                                                      5.2 MB/s |  47 MB     00:08     
```

Далее скачиваю исходный код модуля `ngx_brotli`
```bash
[root@alma-otus rpm]# cd /root
[root@alma-otus ~]# git clone --recurse-submodules -j8 \
https://github.com/google/ngx_brotli
Cloning into 'ngx_brotli'...
[root@alma-otus ~]# cd ngx_brotli/deps/brotli
[root@alma-otus brotli]# mkdir out && cd out
```

Далее соберу модуль `ngx_brotli`
```bash
[root@alma-otus out]# cmake -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DCMAKE_C_FLAGS="-Ofast -m64 -march=native -mtune=native -flto -funroll-loops -ffunction-sections -fdata-sections -Wl,--gc-sections" -DCMAKE_CXX_FLAGS="-Ofast -m64 -march=native -mtune=native -flto -funroll-loops -ffunction-sections -fdata-sections -Wl,--gc-sections" -DCMAKE_INSTALL_PREFIX=./installed ..

-- Build files have been written to: /root/ngx_brotli/deps/brotli/out

[root@alma-otus out]# cmake --build . --config Release -j 2 --target brotlienc
[100%] Built target brotlienc
```

Далее правлю правлю файл `nginx.spec` по пути `~/rpmbuild/SPECS/nginx.spec` в котором, в секции `%build%` в разделе `configure` добавляю указание на модуль.

```bash
[root@alma-otus ~]# nano ~/rpmbuild/SPECS/nginx.spec
```

И приступаю к сборке RPM пакета
```bash
[root@alma-otus ~]# cd ~/rpmbuild/SPECS/
[root@alma-otus ~]# rpmbuild -ba nginx.spec -D 'debug_package %{nil}'
+ umask 022
+ cd /root/rpmbuild/BUILD
+ cd nginx-1.20.1
+ /usr/bin/rm -rf /root/rpmbuild/BUILDROOT/nginx-1.20.1-24.el9.2.alma.1.x86_64
+ RPM_EC=0
++ jobs -p
+ exit 0
```

После завершения проверяю, что пакеты созданы
```bash
[root@alma-otus SPECS]# cd ~
[root@alma-otus ~]# ll rpmbuild/RPMS/x86_64/
total 2012
...
-rw-r--r--. 1 root root   37458 Apr 28 11:51 nginx-1.20.1-24.el9.2.alma.1.x86_64.rpm
...
```

Пакет появился. Версия несколько новее, чем в методичке.

Копирую все пакеты в одно место и устанавливаю их.
```bash
[root@alma-otus ~]# cp ~/rpmbuild/RPMS/noarch/* ~/rpmbuild/RPMS/x86_64/
[root@alma-otus ~]# cd ~/rpmbuild/RPMS/x86_64
[root@alma-otus x86_64]# yum localinstall *.rpm
Last metadata expiration check: 2:01:23 ago on Tue Apr 28 09:57:06 2026.
Dependencies resolved.
Transaction Summary
==============
Install  11 Packages
Total size: 2.0 M
Total download size: 18 k
Installed size: 9.5 M

Is this ok [y/N]: y
Complete!
```

Проверяю, что `nginx` установился и работает.

```bash
[root@alma-otus x86_64]# systemctl start nginx
[root@alma-otus x86_64]# systemctl status nginx
● nginx.service - The nginx HTTP and reverse proxy server
     Loaded: loaded (/usr/lib/systemd/system/nginx.service; disabled; preset: disabled)      
     Active: active (running) since Tue 2026-04-28 11:59:53 UTC; 4s ago
```

### 3. Создание своего репозитория и размещение там моего RPM

По-умолчанию для статических файлов у nginx директория `/usr/share/nginx/html`.

Создам там каталог `repo` и закину в него собранные RPM, после чего инициализирую репозиторий командой `createrepo /usr/share/nginx/html/repo/`

```bash
root@alma-otus x86_64]# mkdir /usr/share/nginx/html/repo
[root@alma-otus x86_64]# cp ~/rpmbuild/RPMS/x86_64/*.rpm /usr/share/nginx/html/repo/
[root@alma-otus x86_64]# createrepo /usr/share/nginx/html/repo/
Directory walk started
Directory walk done - 10 packages
Temporary output repo path: /usr/share/nginx/html/repo/.repodata/
Preparing sqlite DBs
Pool started (with 5 workers)
Pool finished
```

Внесу изменения в `nginx.conf` для того, чтобы у nginx был доступ к листингу каталогов.

Для этого в блоке `server` добавлю директивы:

```bash
index index.html index.htm;
autoindex on;
```

После чего запущу автопроверку корректености конфига и перезапущу nginx
```bash
[root@alma-otus x86_64]# nginx -t
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful
[root@alma-otus x86_64]# nginx -s reload
```

#### Проверка

Проверю свой репозиторий с помощью curl

```bash
root@alma-otus x86_64]# curl -a http://localhost/repo/
```

В ответе вижу файлы, всё нормально.

#### Тестирование

Добавляю в папку `/etc/yum.repos.d` файл с описанием репизитория и ссылкой на него.

```bash
[root@alma-otus ~]# cat >> /etc/yum.repos.d/otus.repo << EOF
[otus]
name=otus-linux
baseurl=http://localhost/repo
gpgcheck=0
enabled=1
EOF
```

Проверю, что репозиторий подключен и его наполнение
```bash
[root@alma-otus x86_64]# yum repolist enabled | grep otus
otus                             otus-linux
```

Добавлю в репозиторий новый пакет, обновлю список пакетов в репозитории и кеш репозитория.
```bash
[root@alma-otus x86_64]# cd /usr/share/nginx/html/repo/
[root@alma-otus repo]# wget https://repo.percona.com/yum/percona-release-latest.noarch.rpm
2026-04-29 05:42:20 (662 KB/s) - ‘percona-release-latest.noarch.rpm’ saved [28532/28532]

[root@alma-otus repo]# createrepo /usr/share/nginx/html/repo/

[root@alma-otus repo]# yum makecache 
Metadata cache created.
```

Проверю наличие пакета в репозитории и установлю его.

```bash
[root@alma-otus repo]# yum list | grep otus
percona-release.noarch                               1.0-32                             otus      
[root@alma-otus repo]# yum install -y percona-release.noarch
==================================================================================================
 Package                       Architecture         Version              Repository          Size
==================================================================================================
Installing:
 percona-release               noarch               1.0-32               otus                28 k 

Installed:
  percona-release-1.0-32.noarch

Complete!
```

Новый пакет появился в репозитории otus и успешно был из него установлен.

## Успех

В процессе выполнения мною был собран свой RPM-пакет `nginx` с дополнительным модулем, после чего я развернул собственный репозиторий, где разместил этот пакет.

Репозиторий был иницииализирован и проверен, далее в него был добавлен дополнительный пакет.

Потом я проверил наполнение репозитория и установил из него новый пакет в свою систему.

Задание выполнено.