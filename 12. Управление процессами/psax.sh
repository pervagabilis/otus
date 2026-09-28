#!/bin/bash
# Аналог ps ax: список процессов по данным из /proc

printf 'PID\tPPID\tSTATE\tCOMMAND\n'

# Для сортировки PID в числовом порядке возрастания, сначала формирую массив с сортировкой, потом пробегаюсь уже по нему
mapfile -t pids < <(printf '%s\n' /proc/[0-9]* | sed 's|.*/||' | sort -n)
for pid in "${pids[@]}"; do
    dir="/proc/$pid"

    # процесс мог завершиться, пока мы идём по списку
    { read -r stat < "$dir/stat"; } 2>/dev/null || continue

    # имя процесса стоит между первой "(" и последней ")" и может содержать пробелы и скобки
    comm=${stat#*(}
    comm=${comm%)*}

    # поля после последней ") " разбиваем по пробелам: f[0] — поле 3 (state), f[1] — поле 4 (ppid)
    read -ra f <<< "${stat##*) }"
    state=${f[0]}
    ppid=${f[1]}

    # аргументы в cmdline разделены символом \0
    mapfile -d '' -t args 2>/dev/null < "$dir/cmdline" || continue
    cmd="${args[*]}"

    # у потоков ядра cmdline пустой, показываем имя в квадратных скобках
    if [ -z "$cmd" ]; then
        cmd="[$comm]"
    fi

    printf '%s\t%s\t%s\t%s\n' "$pid" "$ppid" "$state" "$cmd"
done
