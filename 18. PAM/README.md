# PAM — ограничение входа в выходные

## Задание

Создать пользователей и запретить вход в субботу и воскресенье всем, кроме участников группы `admin`.

Праздники не учитываю, как и в практической части [методички OTUS](https://docs.google.com/document/d/1lOFe3rv0QcnvOTNfQm0OMHbNQ0Cet6AR/edit).

## Окружение

- VirtualBox 7.2.8, Vagrant 2.4.9.
- Box: `bento/ubuntu-24.04`, локальный файл `_boxes/bento-ubuntu-24.04.box`.
- Гостевая ОС: Ubuntu 24.04.3 LTS.
- VM: `otus-hw18`, 2 CPU, 2048 МБ RAM по Vagrantfile.
- Адрес для подключения: `192.168.56.10`.

## 1. Запуск VM

На хосте Windows, в PowerShell из папки задания:

```powershell
Set-Location .\vm
vagrant up
vagrant ssh
```

## 2. Пользователи и пароли

Создал пользователей с домашними каталогами и оболочкой Bash:

```bash
sudo useradd -m -s /bin/bash otus
sudo useradd -m -s /bin/bash otusadm
```

Попытался установить учебные пароли командой из методички:

```bash
echo "Otus2022!" | sudo passwd --stdin otusadm && echo "Otus2022!" | sudo passwd --stdin otus
```

Получил ошибку:

```text
passwd: unrecognized option '--stdin'
Usage: passwd [options] [LOGIN]
```

В этой версии Ubuntu у `passwd` нет параметра `--stdin`. Использовал `chpasswd`:

```bash
printf '%s\n' 'otusadm:Otus2022!' 'otus:Otus2022!' | sudo chpasswd
sudo passwd -S otusadm
sudo passwd -S otus
```

Результат:

```text
otusadm P 2026-10-04 0 99999 7 -1
otus P 2026-10-04 0 99999 7 -1
```

`P` означает, что пароль установлен.

## 3. Группа admin

Создал группу и добавил в неё пользователей, которым разрешён вход в выходные:

```bash
sudo groupadd -f admin
sudo usermod -aG admin otusadm
sudo usermod -aG admin root
sudo usermod -aG admin vagrant
getent group admin
id otusadm
id otus
```

Вывод:

```text
admin:x:1003:otusadm,root,vagrant
uid=1002(otusadm) gid=1002(otusadm) groups=1002(otusadm),1003(admin)
uid=1001(otus) gid=1001(otus) groups=1001(otus)
```

`otusadm` входит в `admin`, а `otus` — нет. Для этого задания группа используется как исключение из запрета входа.

До настройки PAM проверил с хоста:

```powershell
ssh otus@192.168.56.10
ssh otusadm@192.168.56.10
```

Оба пользователя успешно вошли по паролю.

## 4. Скрипт проверки

Создал `/usr/local/bin/login.sh` через `sudo nano /usr/local/bin/login.sh`. Использовал скрипт из методички:

```bash
#!/bin/bash
if [ $(date +%a) = "Sat" ] || [ $(date +%a) = "Sun" ]; then
    if getent group admin | grep -qw "$PAM_USER"; then
        exit 0
    else
        exit 1
    fi
else
    exit 0
fi
```

Скрипт проверяет день недели. В выходные разрешает вход участникам `admin`, в будни возвращает разрешение для всех. Имя пользователя получает из переменной `PAM_USER`.

Первая попытка изменить права без `sudo` завершилась ошибкой:

```text
chmod: changing permissions of '/usr/local/bin/login.sh': Operation not permitted
```

Исправил права и проверил скрипт:

```bash
sudo chmod 755 /usr/local/bin/login.sh
sudo bash -n /usr/local/bin/login.sh
sudo env PAM_USER=otus /usr/local/bin/login.sh
echo "otus: $?"
sudo env PAM_USER=otusadm /usr/local/bin/login.sh
echo "otusadm: $?"
```

В воскресенье, 4 октября 2026 года, получил:

```text
otus: 1
otusadm: 0
```

Код `0` означает разрешение, `1` — отказ. Скрипт использует английские названия дней `Sat` и `Sun`; в проверенном стенде это сработало.

## 5. Подключение к PAM

Добавил строку к `/etc/pam.d/sshd`:
```text
auth required pam_exec.so debug /usr/local/bin/login.sh
```

После этого `otusadm` вошёл, а `otus` получил отказ. Журнал подтвердил результат:

```text
Oct 04 09:24:53 otus-hw18 sshd[2221]: Accepted password for otusadm from 192.168.56.1 port 54080 ssh2
Oct 04 09:24:53 otus-hw18 sshd[2221]: pam_unix(sshd:session): session opened for user otusadm(uid=1002) by otusadm(uid=0)
Oct 04 09:25:03 otus-hw18 sshd[2286]: pam_exec(sshd:auth): /usr/local/bin/login.sh failed: exit code 1
Oct 04 09:25:05 otus-hw18 sshd[2286]: Failed password for otus from 192.168.56.1 port 54081 ssh2
```

Затем заменил строку вызова на проверку разрешения входа в секции `account`:

```text
account required pam_exec.so /usr/local/bin/login.sh
```

После замены повторил вход с хоста в воскресенье, 4 октября 2026 года. Пользователь `otus` получил отказ:

```text
PS C:\DEV\learning\otus\18. PAM\vm> ssh otus@192.168.56.10
otus@192.168.56.10's password:
/usr/local/bin/login.sh failed: exit code 1
Connection closed by 192.168.56.10 port 22
```

Пользователь `otusadm` успешно вошёл:

```text
PS C:\DEV\learning\otus\18. PAM\vm> ssh otusadm@192.168.56.10
otusadm@192.168.56.10's password:
Welcome to Ubuntu 24.04.3 LTS (GNU/Linux 6.8.0-86-generic x86_64)
System information as of Sun Oct  4 09:48:49 AM UTC 2026
```


## Результат

Созданы пользователи и группа, проверен скрипт и вход по SSH с паролем в воскресенье: участник `admin` вошёл, обычный пользователь получил отказ.

После замены `auth` на `account` результат подтверждён повторным входом.

Задание выполнено.