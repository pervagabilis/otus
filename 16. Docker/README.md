# Docker

## Цель

Освоить базовые принципы работы с Docker: собрать собственный образ, запустить из него контейнер, опубликовать образ в Docker Hub.

## Критерии задания

- Кастомный образ nginx на базе Alpine, после запуска отдаёт изменённую страницу.
- Чёткое отличие контейнера от образа и ответ на вопрос, можно ли в контейнере собрать ядро.
- Образ опубликован в Docker Hub, ссылка на репозиторий.

## Окружение

- Хост: Microsoft Windows 10 IoT Enterprise LTSC (10.0.19044)
- VirtualBox 7.2.8r173730
- Vagrant 2.4.9
  - Vagrant box: `bento/ubuntu-24.04` из локального файла `_boxes/bento-ubuntu-24.04.box`.
- VM `otus-hw16` — Ubuntu 24.04.3 LTS, ядро 6.8.0-86-generic:
  - 2 ядра
  - 2 ГБ ОЗУ
  - диск 20 ГБ
- Docker Engine 29.8.2 (containerd v2.3.6, runc 1.5.1), Docker Compose v5.6.0
- Порт 8080 гостя проброшен на 8080 хоста (`forwarded_port` в [Vagrantfile](vm/Vagrantfile)).

## Выполнение

### 1. Установка Docker Engine и Compose

По официальной инструкции [docs.docker.com/engine/install/ubuntu](https://docs.docker.com/engine/install/ubuntu/), репозиторий `download.docker.com`, Compose — плагином `docker-compose-plugin`:

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker vagrant
```

Проверка (новая SSH-сессия, чтобы применилась группа):

```text
$ docker version
Client: Docker Engine - Community
 Version:           29.8.2
...
Server: Docker Engine - Community
 Engine:
  Version:          29.8.2
 containerd:
  Version:          v2.3.6
 runc:
  Version:          1.5.1

$ docker compose version
Docker Compose version v5.6.0

$ systemctl is-active docker containerd
active
active

$ docker run --rm hello-world | grep Hello
Hello from Docker!
```

### 2. Образ nginx на Alpine

Основа — официальный `nginx:1.30.5-alpine` (stable-ветка).

[nginx/Dockerfile](nginx/Dockerfile):

```dockerfile
FROM nginx:1.30.5-alpine
COPY index.html /usr/share/nginx/html/index.html
EXPOSE 80
```

[nginx/index.html](nginx/index.html) заменяет стандартную страницу. `COPY`, а не `ADD`: копируется локальный файл, распаковка архивов и загрузка по URL не нужны. `CMD` не задан — он наследуется из базового образа:

```text
$ docker build -t otus-nginx:1.0 .
...
#7 naming to docker.io/library/otus-nginx:1.0 0.0s done
#7 DONE 4.9s

$ docker images otus-nginx
IMAGE            ID             DISK USAGE   CONTENT SIZE   EXTRA
otus-nginx:1.0   49fcb9784838       92.8MB         26.1MB

$ docker image inspect otus-nginx:1.0 --format "Cmd={{.Config.Cmd}} Entrypoint={{.Config.Entrypoint}} StopSignal={{.Config.StopSignal}} Ports={{.Config.ExposedPorts}}"
Cmd=[nginx -g daemon off;] Entrypoint=[/docker-entrypoint.sh] StopSignal=SIGQUIT Ports=map[80/tcp:{}]
```

`daemon off;` держит nginx на переднем плане: он PID 1 контейнера, и контейнер живёт, пока живёт этот процесс. `SIGQUIT` — штатное плавное завершение nginx вместо `SIGTERM` по умолчанию.

Последние слои образа — две мои инструкции поверх слоёв базового:

```text
$ docker history otus-nginx:1.0 --format "{{.CreatedBy}}|{{.Size}}" | head -4
EXPOSE [80/tcp]|0B
COPY index.html /usr/share/nginx/html/index.…|24.6kB
RUN /bin/sh -c set -x     && apkArch="$(cat …|51.9MB
ENV ACME_VERSION=0.4.1|0B
```

### 3. Запуск контейнера

```text
$ docker run -d --name otus-nginx -p 8080:80 otus-nginx:1.0
a3e126cb8076e76cdb2263c3791beb946e94288702a8cad95decd1af55b71d06

$ docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
NAMES        IMAGE            STATUS         PORTS
otus-nginx   otus-nginx:1.0   Up 2 seconds   0.0.0.0:8080->80/tcp, [::]:8080->80/tcp

$ docker exec otus-nginx sh -c "grep PRETTY /etc/os-release; nginx -v 2>&1"
PRETTY_NAME="Alpine Linux v3.24"
nginx version: nginx/1.30.5
```

### 4. Публикация в Docker Hub

Вход по access token Docker Hub, а не по паролю:

```text
$ docker login -u pervagabilis
$ docker tag otus-nginx:1.0 pervagabilis/otus-nginx:1.0
$ docker push pervagabilis/otus-nginx:1.0
The push refers to repository [docker.io/pervagabilis/otus-nginx]
e3320d02d578: Pushed
44136fa355b3: Pushed
...
9f71ff9407d6: Pushed
1.0: digest: sha256:49fcb97848383d96c1d3d5c91fc8bcf252cf662115107409be7cbf46f5d2bacf size: 856

$ docker logout
Removing login credentials for https://index.docker.io/v1/
```

Проверка, что образ берётся из Hub. Локальный образ удалён, контейнер создан заново по имени из Hub:

```text
$ docker rm -f otus-nginx
$ docker rmi otus-nginx:1.0 pervagabilis/otus-nginx:1.0
Untagged: otus-nginx:1.0
Untagged: pervagabilis/otus-nginx:1.0
Deleted: sha256:49fcb97848383d96c1d3d5c91fc8bcf252cf662115107409be7cbf46f5d2bacf

$ docker run -d --name otus-nginx -p 8080:80 pervagabilis/otus-nginx:1.0
Unable to find image 'pervagabilis/otus-nginx:1.0' locally
1.0: Pulling from pervagabilis/otus-nginx
...
Digest: sha256:49fcb97848383d96c1d3d5c91fc8bcf252cf662115107409be7cbf46f5d2bacf
Status: Downloaded newer image for pervagabilis/otus-nginx:1.0

$ curl -s localhost:8080 | grep "<h1>"
<h1>OTUS Linux Professional — ДЗ 16 Docker</h1>
```

Репозиторий: https://hub.docker.com/r/pervagabilis/otus-nginx

## Успех

Контейнер отдаёт изменённую страницу в госте:

```text
$ curl -s localhost:8080
<!DOCTYPE html>
<html lang="ru">
<head><meta charset="utf-8"><title>OTUS HW16</title></head>
<body>
<h1>OTUS Linux Professional — ДЗ 16 Docker</h1>
<p>Кастомный образ nginx на Alpine.</p>
</body>
</html>
```

и на хосте Windows через проброс Vagrant 8080 → 8080 → контейнер 80:

```text
PS> curl.exe -s http://localhost:8080 | Select-String "<h1>"
<h1>OTUS Linux Professional — ДЗ 16 Docker</h1>
```

В логе контейнера оба запроса — из гостя (через мост `docker0`, 172.17.0.1) и с хоста (через NAT VirtualBox, 10.0.2.2):

```text
$ docker logs otus-nginx 2>&1 | tail -2
172.17.0.1 - - [03/Oct/2026:20:43:55 +0000] "GET / HTTP/1.1" 200 224 "-" "curl/8.5.0" "-"
10.0.2.2 - - [03/Oct/2026:20:43:56 +0000] "GET / HTTP/1.1" 200 224 "-" "curl/8.15.0" "-"
```

## Образ и контейнер

**Образ** — неизменяемый шаблон: упорядоченный набор read-only слоёв файловой системы плюс конфигурация запуска (`Cmd`, `Entrypoint`, `Env`, `ExposedPorts`, `StopSignal`). Он идентифицируется digest'ом, хранится и передаётся через registry и ничего не исполняет.

**Контейнер** — экземпляр, созданный из образа: слои образа, поверх них тонкий собственный слой для записи (overlayfs), параметры запуска (имя, публикация портов, тома, переменные) и процесс, изолированный namespaces и ограниченный cgroups. Контейнер существует и в остановленном состоянии (`docker ps -a`) вместе со своим слоем записи.

Проверка на стенде. Запись внутри контейнера попадает только в его слой, образ не меняется, и второй контейнер из того же образа её не видит:

```text
$ docker exec otus-nginx sh -c "echo test > /tmp/in-container.txt"
$ docker diff otus-nginx | head
C /tmp
A /tmp/in-container.txt
C /etc
C /etc/nginx
C /etc/nginx/conf.d
C /etc/nginx/conf.d/default.conf
C /run
A /run/nginx.pid
...
$ docker run --rm otus-nginx:1.0 ls /tmp
$
```

`C /etc/nginx/conf.d/default.conf` — это правка entrypoint-скрипта официального образа при старте (включение IPv6-listen). Она тоже живёт только в слое контейнера.

Контейнер — обычный процесс хоста, а не отдельная машина: master-процесс nginx виден в `ps` гостевой VM.

```text
$ ps -o pid,user,cmd -C nginx | head -3
    PID USER     CMD
   9654 root     nginx: master process nginx -g daemon off;
   9719 message+ nginx: worker process
```

## Можно ли в контейнере собрать ядро

**Собрать — да, загрузить или запустить — нет.** Сборка ядра — обычная пользовательская задача: `make` и `gcc` над исходниками дают `bzImage` и модули. Для этого не нужно ничего, кроме пакетов сборки и ресурсов (CPU, несколько гигабайт диска под дерево исходников). Так в CI и собирают ядра и `.deb`-пакеты с ними.

Использовать собранное ядро внутри контейнера нельзя, потому что своего ядра у контейнера нет — он работает на ядре хоста:

```text
$ uname -r                          # гостевая VM
6.8.0-86-generic
$ docker exec otus-nginx uname -r   # контейнер
6.8.0-86-generic
```