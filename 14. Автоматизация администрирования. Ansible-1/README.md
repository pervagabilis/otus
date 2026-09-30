# Автоматизация администрирования. Ansible-1

## Цель

Сделать первые шаги с Ansible: подготовить инвентори и конфиг, выполнить ad-hoc команды и написать плейбук, который разворачивает nginx.

## Критерии задания

Поднять на Vagrant стенд хотя бы с одним сервером и развернуть на нём nginx через Ansible:

- пакет ставится модулем `apt`;
- конфиг nginx берётся из шаблона jinja2 с переменными;
- после установки nginx включён в systemd (`enabled`);
- для старта nginx после установки используется `notify`;
- сайт слушает на порту 8080, порт задаётся переменной Ansible.

После запуска стенда nginx должен быть доступен на порту 8080.

## Окружение

- Рабочая станция: Ubuntu 24.04.4 LTS
- KVM/libvirt 10.0.0, QEMU 8.2.2
- Vagrant 2.4.9 + `vagrant-libvirt` 0.12.2
  - Vagrant box: `cloud-image/ubuntu-24.04` (провайдер libvirt).
- Ansible core 2.21.4 (pipx), запускаю с рабочей станции.
- Управляемая VM `nginx` — Ubuntu 24.04.5 LTS:
  - ядро 6.8.0-142-generic
  - nginx 1.24.0-2ubuntu7.18
  - 1 ядро
  - 1 ГБ ОЗУ
  - private network `192.168.56.150`

### Каталоги и файлы

|Файл/Каталог|Назначение|
|---|---|
|`README.md`|Этот файл. Пошагово описывает выполнение задания|
|`vm/Vagrantfile`|Стенд: одна VM `nginx`|
|`vm/ansible.cfg`|Конфиг Ansible: инвентори по умолчанию, пользователь, проверка ключа хоста|
|`vm/staging/hosts`|Инвентори|
|`vm/nginx.yml`|Плейбук установки и настройки nginx|
|`vm/templates/nginx.conf.j2`|Шаблон `nginx.conf`|

### Отличия от методички

Методичка написана под VirtualBox, у меня стенд на KVM/libvirt, поэтому кое-что поменял:

| Что | Методичка | У меня |
|---|---|---|
| Провайдер, box | `virtualbox`, `generic/ubuntu2204` | `libvirt`, `cloud-image/ubuntu-24.04` |
| Сеть | `192.168.11.150`, `virtualbox__intnet` | `192.168.56.150`, сеть libvirt, видна с рабочей станции |
| Куда ходит Ansible | `127.0.0.1:2222` (проброс порта) | сразу на `192.168.56.150:22` |
| Ключ | `.vagrant/machines/nginx/virtualbox/private_key` | `.vagrant/machines/nginx/libvirt/private_key` |
| Shell-провижинер (ключи root, `PasswordAuthentication`) | есть | убрал, Ansible ходит как `vagrant` с ключом и `become` |
| `apt: update_cache=yes` | строкой | `update_cache: true`, YAML-словарём, как остальные параметры |


## Выполнение

Все команды выполняю на рабочей станции из папки `vm/`.

### 1. Поднимаю стенд

```bash
vadim@otus:~/otus/14. Автоматизация администрирования. Ansible-1/vm$ vagrant up
Bringing machine 'nginx' up with 'libvirt' provider...
==> nginx: Creating image (snapshot of base box volume).
==> nginx: Creating domain with the following settings...
==> nginx:  -- Name:              vm_nginx
==> nginx:  -- Domain type:       kvm
==> nginx:  -- Cpus:              1
==> nginx:  -- Memory:            1024M
==> nginx:  -- Base box:          cloud-image/ubuntu-24.04
# ... вырезаны параметры диска, графики и ожидание загрузки ...
==> nginx: Machine booted and ready!
==> nginx: Setting hostname...
==> nginx: Configuring and enabling network interfaces...
vadim@otus:~/otus/14. Автоматизация администрирования. Ansible-1/vm$ vagrant status
Current machine states:

nginx                     running (libvirt)
```

Проверяю, что VM получила адрес из `private_network`:

```bash
vadim@otus:~/otus/14. Автоматизация администрирования. Ansible-1/vm$ vagrant ssh -c 'hostname; ip -br addr'
nginx
lo               UNKNOWN        127.0.0.1/8 ::1/128
ens5             UP             192.168.121.41/24 metric 100 fe80::5054:ff:fe7c:8f5f/64
ens6             UP             192.168.56.150/24 fe80::5054:ff:fe0d:203f/64
```

`ens5` — служебная сеть vagrant-libvirt, адрес выдаёт DHCP. `ens6` — мой статический `192.168.56.150` из Vagrantfile.

### 2. Параметры подключения

```bash
vadim@otus:~/otus/14. Автоматизация администрирования. Ansible-1/vm$ vagrant ssh-config
Host nginx
  HostName 192.168.121.41
  User vagrant
  Port 22
  UserKnownHostsFile /dev/null
  StrictHostKeyChecking no
  PasswordAuthentication no
  IdentityFile "/home/vadim/otus/14. Автоматизация администрирования. Ansible-1/vm/.vagrant/machines/nginx/libvirt/private_key"
  IdentitiesOnly yes
  LogLevel FATAL
  PubkeyAcceptedKeyTypes +ssh-rsa
  HostKeyAlgorithms +ssh-rsa
```

Vagrant показывает адрес из служебной сети, но он динамический и после пересоздания VM может смениться. Поэтому в инвентори пишу `192.168.56.150`. Из `ssh-config` беру только пользователя и путь к ключу.

### 3. Инвентори и ansible.cfg

`staging/hosts`:

```ini
[web]
nginx ansible_host=192.168.56.150 ansible_port=22 ansible_private_key_file=.vagrant/machines/nginx/libvirt/private_key ansible_python_interpreter=/usr/bin/python3
```

В методичке `[web]` и переменные хоста разъехались по строкам из-за вёрстки. Я сначала так и перенёс. Если `[web]` стоит в одной строке с хостом, парсер INI падает с `host range must be begin:end`, а переменные на отдельных строках Ansible считает отдельными хостами. Всё должно быть так: заголовок группы — отдельной строкой, хост со всеми переменными — одной.

`ansible.cfg`:

```ini
[defaults]
inventory = staging/hosts
remote_user = vagrant
host_key_checking = False
retry_files_enabled = False
```

Проверяю, как Ansible разобрал инвентори, и пингую хост уже без `-i`:

```bash
vadim@otus:~/otus/14. Автоматизация администрирования. Ansible-1/vm$ ansible-inventory --graph --vars
@all:
  |--@ungrouped:
  |--@web:
  |  |--nginx
  |  |  |--{ansible_host = 192.168.56.150}
  |  |  |--{ansible_port = 22}
  |  |  |--{ansible_private_key_file = .vagrant/machines/nginx/libvirt/private_key}
vadim@otus:~/otus/14. Автоматизация администрирования. Ansible-1/vm$ ansible nginx -m ping
[WARNING]: Host 'nginx' is using the discovered Python interpreter at '/usr/bin/python3.12', but future installation of another Python interpreter could cause a different interpreter to be discovered. See https://docs.ansible.com/ansible-core/2.21/reference_appendices/interpreter_discovery.html for more information.
nginx | SUCCESS => {
    "ansible_facts": {
        "discovered_interpreter_python": "/usr/bin/python3.12"
    },
    "changed": false,
    "ping": "pong"
}
```


### 4. Ad-hoc команды

```bash
vadim@otus:~/otus/14. Автоматизация администрирования. Ansible-1/vm$ ansible nginx -m command -a "uname -r"
nginx | CHANGED | rc=0 >>
6.8.0-142-generic
vadim@otus:~/otus/14. Автоматизация администрирования. Ansible-1/vm$ ansible nginx -m systemd -a name=firewalld
nginx | SUCCESS => {
    "changed": false,
    "name": "firewalld",
    "status": {
        "ActiveEnterTimestampMonotonic": "0",
        "ActiveExitTimestampMonotonic": "0",
        "ActiveState": "inactive",
# ...
        "LoadError": "org.freedesktop.systemd1.NoSuchUnit \"Unit firewalld.service not found.\"",
        "LoadState": "not-found",
# ...
    }
}
```

### 5. Первая версия плейбука: установка nginx

```yaml
- name: NGINX | Install and configure NGINX
  hosts: nginx
  become: true

  tasks:
    - name: update
      apt:
        update_cache: true

    - name: NGINX | Install NGINX
      apt:
        name: nginx
        state: latest
```

```bash
vadim@otus:~/otus/14. Автоматизация администрирования. Ansible-1/vm$ ansible-playbook nginx.yml --syntax-check

playbook: nginx.yml
vadim@otus:~/otus/14. Автоматизация администрирования. Ansible-1/vm$ ansible-playbook nginx.yml

PLAY [NGINX | Install and configure NGINX] ***********************************************

TASK [Gathering Facts] *******************************************************************
ok: [nginx]

TASK [update] ****************************************************************************
changed: [nginx]

TASK [NGINX | Install NGINX] *************************************************************
changed: [nginx]

PLAY RECAP *******************************************************************************
nginx                      : ok=3    changed=2    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

### 6. Шаблон, переменная, handlers

Шаблон `templates/nginx.conf.j2` взял из gist методички, порт подставляется из переменной `nginx_listen_port`:

```nginx
# {{ ansible_managed }}
events {
    worker_connections 1024;
}

http {
    server {
        listen       {{ nginx_listen_port }} default_server;
        server_name  default_server;
        root         /usr/share/nginx/html;

        location / {
        }
    }
}
```

Итоговый [`nginx.yml`](vm/nginx.yml): переменная `nginx_listen_port: 8080`, задача `template`, теги и два handler'а. `restart nginx` (перезапуск + `enabled: yes`) вызывается после установки пакета, `reload nginx` — после смены конфига:

```yaml
---
- name: NGINX | Install and configure NGINX
  hosts: nginx
  become: true
  vars:
    nginx_listen_port: 8080

  tasks:
    - name: update
      apt:
        update_cache: true
      tags:
        - update apt

    - name: NGINX | Install NGINX
      apt:
        name: nginx
        state: latest
      notify:
        - restart nginx
      tags:
        - nginx-package

    - name: NGINX | Create NGINX config file from template
      template:
        src: templates/nginx.conf.j2
        dest: /etc/nginx/nginx.conf
      notify:
        - reload nginx
      tags:
        - nginx-configuration

  handlers:
    - name: restart nginx
      systemd:
        name: nginx
        state: restarted
        enabled: yes

    - name: reload nginx
      systemd:
        name: nginx
        state: reloaded
```

```bash
vadim@otus:~/otus/14. Автоматизация администрирования. Ansible-1/vm$ ansible-playbook nginx.yml

PLAY [NGINX | Install and configure NGINX] *************************************

TASK [Gathering Facts] *********************************************************
ok: [nginx]

TASK [update] ******************************************************************
changed: [nginx]

TASK [NGINX | Install NGINX] ***************************************************
ok: [nginx]

TASK [NGINX | Create NGINX config file from template] **************************
changed: [nginx]

RUNNING HANDLER [reload nginx] *************************************************
changed: [nginx]

PLAY RECAP *********************************************************************
nginx                      : ok=5    changed=3    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```

Совпало со скриншотом методички. nginx был уже установлен на прошлом шаге, поэтому задача установки дала `ok`, и сработал только `reload nginx`. `restart nginx` сработает на чистом стенде, когда пакет ставится впервые.

Шаблон заменяет `nginx.conf` целиком, поэтому пропадает и дефолтный сайт на 80 порту: `sites-enabled` больше не подключается.

## Успех

Страница открывается с рабочей станции по адресу VM на порту 8080:

```bash
vadim@otus:~$ curl http://192.168.56.150:8080
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
# ... вырезаны стили и остальная страница ...
<h1>Welcome to nginx!</h1>
<p>If you see this page, the nginx web server is successfully installed and
working. Further configuration is required.</p>
```

nginx запущен, включён в автозагрузку и слушает только 8080:

```bash
vadim@otus:~/otus/14. Автоматизация администрирования. Ansible-1/vm$ ansible nginx -b -m command -a "systemctl status nginx --no-pager"
nginx | CHANGED | rc=0 >>
● nginx.service - A high performance web server and a reverse proxy server
     Loaded: loaded (/usr/lib/systemd/system/nginx.service; enabled; preset: enabled)
     Active: active (running) since Wed 2026-09-30 17:47:02 UTC; 4min 56s ago
       Docs: man:nginx(8)
    Process: 3042 ExecStartPre=/usr/sbin/nginx -t -q -g daemon on; master_process on; (code=exited, status=0/SUCCESS)
    Process: 3044 ExecStart=/usr/sbin/nginx -g daemon on; master_process on; (code=exited, status=0/SUCCESS)
    Process: 3699 ExecReload=/usr/sbin/nginx -g daemon on; master_process on; -s reload (code=exited, status=0/SUCCESS)
vadim@otus:~/otus/14. Автоматизация администрирования. Ansible-1/vm$ ansible nginx -b -m command -a "ss -tlnp"
nginx | CHANGED | rc=0 >>
# ... вырезаны строки остальных сервисов, оставлен только nginx ...
LISTEN 0      511          0.0.0.0:8080      0.0.0.0:*    users:(("nginx",pid=3701,fd=10),("nginx",pid=3073,fd=10))
```

Я поднял стенд на KVM/libvirt, настроил инвентори и `ansible.cfg`, по шагам методички написал плейбук: `apt`, шаблон jinja2 с переменной порта, `notify` и handlers. nginx доступен на порту 8080.

Задание выполнено.
