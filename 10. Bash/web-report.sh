#!/bin/bash
# Ежечасный отчёт по access-логу nginx. Запускается из cron.
# Отчёт сохраняется в файл в $REPORT_DIR.
# Обрабатывает только строки, появившиеся после предыдущего запуска.

LOG=${LOG:-/var/log/nginx/access.log}   # какой лог разбирать
TOP=${TOP:-10}                          # сколько строк в топах

STATE=/var/lib/web-report/position      # сколько строк лога уже обработано
REPORT_DIR=/var/lib/web-report/reports  # готовые отчёты
LOCK=/var/lock/web-report.lock

# Защита от одновременного запуска: flock держит блокировку на открытом
# дескрипторе 9, пока жив процесс. Вторая копия сразу выходит.
exec 9> "$LOCK"
if ! flock -n 9; then
    echo "web-report: уже запущен, выходим" >&2
    exit 1
fi

mkdir -p "$REPORT_DIR"
NEW=$(mktemp)
REPORT=$(mktemp)
trap 'rm -f "$NEW" "$REPORT"' EXIT

# Время из строки лога: всё, что между [ и ]
get_time() {
    sed -n "$1"'s/^[^[]*\[\([^]]*\)\].*/\1/p' "$NEW"
}

top_ips() {
    awk '{print $1}' "$NEW" | sort | uniq -c | sort -rn | head -n "$TOP"
}

# Делим строку по кавычкам: $2 — запрос "GET /url HTTP/1.1", $3 — " код размер "
top_urls() {
    awk -F'"' '{split($2, r, " "); if (r[2] != "") print r[2]}' "$NEW" \
        | sort | uniq -c | sort -rn | head -n "$TOP"
}

http_codes() {
    awk -F'"' '{split($3, s, " "); print s[1]}' "$NEW" | sort | uniq -c | sort -rn
}

# Ошибки: ответы 4xx и 5xx — код, запрос, сколько раз.
# Запрос обрезаем до 60 символов: вместо него бывает длинный бинарный мусор
errors() {
    awk -F'"' '{split($3, s, " "); if (s[1] ~ /^[45]/) print s[1], substr($2, 1, 60)}' "$NEW" \
        | sort | uniq -c | sort -rn
}

# Сколько строк обработано в прошлый раз
last=0
[ -f "$STATE" ] && last=$(cat "$STATE")
total=$(wc -l < "$LOG")

# Лог стал короче — значит, его ротировали, читаем с начала
if [ "$total" -lt "$last" ]; then
    last=0
fi

tail -n +"$((last + 1))" "$LOG" | head -n "$((total - last))" > "$NEW"
count=$(wc -l < "$NEW")

{
    echo "Отчёт веб-сервера $(hostname)"
    echo "Лог: $LOG"
    if [ "$count" -eq 0 ]; then
        echo "Новых запросов с прошлого запуска нет."
    else
        echo "Строки лога: $((last + 1))-$total"
        echo "Период: $(get_time 1) - $(get_time '$')"
        echo "Всего запросов: $count"
        echo
        echo "== IP-адреса с наибольшим числом запросов =="
        top_ips
        echo
        echo "== URL с наибольшим числом запросов =="
        top_urls
        echo
        echo "== Ошибки (ответы 4xx и 5xx) =="
        errors
        echo
        echo "== HTTP-коды ответов =="
        http_codes
    fi
} > "$REPORT"

# Позицию сохраняем только после того, как отчёт лёг на место,
# иначе при сбое эти строки пропадут из отчётов
mv "$REPORT" "$REPORT_DIR/report-$(date +%F-%H%M%S).txt" && echo "$total" > "$STATE"

# Старые отчёты удаляем через неделю
find "$REPORT_DIR" -name 'report-*.txt' -mtime +7 -delete
