#!/bin/bash

set -u

# ============================================================================
# АНАЛИЗАТОР КОНФИГУРАЦИЙ ПО ВЕДОМОСТИ (РАЗДЕЛЫ А, Б, В, Г, Д)
# Добавлена живая проверка интерфейсов через "show ip interface brief"
# ИСПРАВЛЕН ПАРСИНГ ТАБЛИЦЫ ECOROUTER (Status & IP)
# ДОБАВЛЕНО УДАЛЕНИЕ СТАРЫХ ФАЙЛОВ ПЕРЕД СБОРОМ
# ЖЕЛЕЗОБЕТОННЫЙ ПАРСЕР OSPF ROUTER-ID (через grep контекста)
# ============================================================================

# ============================================================================
# [ НАСТРОЙКИ ТОПОЛОГИИ И IP-АДРЕСОВ ] - МЕНЯЙТЕ ЗНАЧЕНИЯ ЗДЕСЬ!
# ============================================================================

ROUTER_CREDS=(
    "net_admin P@ssw0rd"
    "admin admin"
    "net_admin admin"
    "admin P@ssw0rd"
    "root root"
    "admin ecorouter"
)

# Имя пользователя для проверки в localdb
CHECK_USERNAME="net_admin"

# VM IDs
VM_ISP=13901
VM_HQ_RTR=13902
VM_HQ_SRV=13903
VM_HQ_CLI=13904
VM_BR_RTR=13905
VM_BR_SRV=13906

# Имена хостов (Hostnames)
HOST_ISP="isp"
HOST_HQ_RTR="hq-rtr"
HOST_HQ_SRV="hq-srv.au-team.irpo"
HOST_HQ_CLI="hq-cli.au-team.irpo"
HOST_BR_RTR="br-rtr"
HOST_BR_SRV="br-srv.au-team.irpo"

# IP-адреса и маски (Ожидаемые значения)
IP_ISP_ENP7S2="172.16.1.1/28"
IP_ISP_ENP7S3="172.16.2.1/28"

IP_HQ_RTR_ISP="172.16.1.2/28"
IP_HQ_RTR_VL100="192.168.100.1/27"
IP_HQ_RTR_VL200="192.168.200.1/24"
IP_HQ_RTR_VL999="192.168.99.1/29"

IP_BR_RTR_ISP="172.16.2.2/28"
IP_BR_RTR_INT1="192.168.0.1/28"

IP_HQ_SRV="192.168.100.2/27"
IP_BR_SRV="192.168.0.2/28"

# Туннели и Маршрутизация
IP_TUNNEL_HQ="10.10.10.1/30"
IP_TUNNEL_BR="10.10.10.2/30"
OSPF_ID_HQ="10.10.10.1"
OSPF_ID_BR="10.10.10.2"

# Порты и UID
SSH_PORT="2026"
SSH_UID="2026"

# ============================================================================
# [ МАССИВ ПРОВЕРОК ]
# ============================================================================

CHECKS=(
    "HEADER|РАЗДЕЛ А. Планирование, адресация и маршрутизация|---|---|---|---|---"
    
    # Проверки маски (А1Д1) через конфиг
    "${VM_HQ_RTR}|HQ-RTR|А1Д1|IP+Маска (vl100) [running-config]|${IP_HQ_RTR_VL100}|iface_ip|vl100"
    "${VM_HQ_RTR}|HQ-RTR|А1Д1|IP+Маска (vl200) [running-config]|${IP_HQ_RTR_VL200}|iface_ip|vl200"
    "${VM_HQ_RTR}|HQ-RTR|А1Д1|IP+Маска (vl999) [running-config]|${IP_HQ_RTR_VL999}|iface_ip|vl999"
    "${VM_BR_RTR}|BR-RTR|А1Д1|IP+Маска (int1) [running-config]|${IP_BR_RTR_INT1}|iface_ip|int1"
    "${VM_BR_SRV}|BR-SRV|А1Д1|IP+Маска (enp7s1)|${IP_BR_SRV}|linux|cat /etc/net/ifaces/enp7s1/ipv4address"

    # Живая проверка IP адресов (без маски) через show ip int brief
    "${VM_HQ_RTR}|HQ-RTR|А1Д1|IP (vl100) [show ip int brief]|${IP_HQ_RTR_VL100%/*}|iface_brief_ip|vl100"
    "${VM_HQ_RTR}|HQ-RTR|А1Д1|IP (vl200) [show ip int brief]|${IP_HQ_RTR_VL200%/*}|iface_brief_ip|vl200"
    "${VM_HQ_RTR}|HQ-RTR|А1Д1|IP (vl999) [show ip int brief]|${IP_HQ_RTR_VL999%/*}|iface_brief_ip|vl999"
    "${VM_HQ_RTR}|HQ-RTR|А2Д1|IP (isp) [show ip int brief]|${IP_HQ_RTR_ISP%/*}|iface_brief_ip|isp"
    
    "${VM_BR_RTR}|BR-RTR|А1Д1|IP (int1) [show ip int brief]|${IP_BR_RTR_INT1%/*}|iface_brief_ip|int1"
    "${VM_BR_RTR}|BR-RTR|А2Д1|IP (isp) [show ip int brief]|${IP_BR_RTR_ISP%/*}|iface_brief_ip|isp"

    # Проверки хостнеймов
    "${VM_ISP}|ISP|А2Д1|Имя устройства (Hostname)|${HOST_ISP}|linux|hostname"
    "${VM_ISP}|ISP|А2Д1|IP (enp7s2)|${IP_ISP_ENP7S2}|linux|cat /etc/net/ifaces/enp7s2/ipv4address"
    "${VM_ISP}|ISP|А2Д1|IP (enp7s3)|${IP_ISP_ENP7S3}|linux|cat /etc/net/ifaces/enp7s3/ipv4address"
    "${VM_HQ_RTR}|HQ-RTR|А2Д1|Имя устройства (Hostname)|${HOST_HQ_RTR}|global_val|hostname"
    "${VM_HQ_SRV}|HQ-SRV|А2Д1|Имя устройства (Hostname)|${HOST_HQ_SRV}|linux|hostname"
    "${VM_HQ_CLI}|HQ-CLI|А2Д1|Имя устройства (Hostname)|${HOST_HQ_CLI}|linux|hostname"
    "${VM_BR_RTR}|BR-RTR|А2Д1|Имя устройства (Hostname)|${HOST_BR_RTR}|global_val|hostname"
    "${VM_BR_SRV}|BR-SRV|А2Д1|Имя устройства (Hostname)|${HOST_BR_SRV}|linux|hostname"

    # Проверка OSPF ID (парсит running-config)
    "${VM_HQ_RTR}|HQ-RTR|АЗД1|Настройка динамической маршрутизации (OSPF ID) [running-config]|${OSPF_ID_HQ}|ospf_id|1"
    "${VM_BR_RTR}|BR-RTR|АЗД1|Настройка динамической маршрутизации (OSPF ID) [running-config]|${OSPF_ID_BR}|ospf_id|1"

    "HEADER|РАЗДЕЛ Б. Сетевые сервисы, учетные записи и доступ|---|---|---|---|---"
    "${VM_HQ_CLI}|HQ-CLI|Б1Д1|Автоматическое распределение IP (BOOTPROTO)|dhcp|linux|grep -i '^BOOTPROTO' /etc/net/ifaces/enp7s1/options | cut -d= -f2"
    "${VM_HQ_RTR}|HQ-RTR|Б1Д1|Наличие DHCP Сервера|dhcp-server 1|global_exist|dhcp-server 1"

    "${VM_HQ_SRV}|HQ-SRV|Б2Д1|Локальная учетная запись sshuser (UID ${SSH_UID})|${SSH_UID}|linux|id -u sshuser 2>/dev/null || echo missing"
    "${VM_HQ_RTR}|HQ-RTR|Б2Д1|Учетная запись (${CHECK_USERNAME}) в localdb|${CHECK_USERNAME}|localdb_user|${CHECK_USERNAME}"
    "${VM_BR_RTR}|BR-RTR|Б2Д1|Учетная запись (${CHECK_USERNAME}) в localdb|${CHECK_USERNAME}|localdb_user|${CHECK_USERNAME}"

    "${VM_ISP}|ISP|БЗД1|Сетевая связность и выход в интернет (IP Forwarding)|1|linux|cat /proc/sys/net/ipv4/ip_forward"

    "HEADER|РАЗДЕЛ В. Безопасность, DNS, Туннелирование и Уд. Доступ|---|---|---|---|---"
    "${VM_HQ_SRV}|HQ-SRV|В1Д1|Сервер доменных имен (bind)|active|linux|systemctl is-active bind.service 2>/dev/null || echo inactive"
    
    "${VM_HQ_RTR}|HQ-RTR|В2Д1|IP Туннеля HQ [show ip int brief]|${IP_TUNNEL_HQ%/*}|iface_brief_ip|tunnel.0"
    "${VM_HQ_RTR}|HQ-RTR|В2Д1|Статус Туннеля HQ [show ip int brief]|up|iface_brief_status|tunnel.0"
    "${VM_BR_RTR}|BR-RTR|В2Д1|IP Туннеля BR [show ip int brief]|${IP_TUNNEL_BR%/*}|iface_brief_ip|tunnel.0"
    "${VM_BR_RTR}|BR-RTR|В2Д1|Статус Туннеля BR [show ip int brief]|up|iface_brief_status|tunnel.0"

    "${VM_HQ_SRV}|HQ-SRV|ВЗД1|Нестандартный порт удаленного доступа|${SSH_PORT}|linux|grep -i '^Port' /etc/openssh/sshd_config | awk '{print \$2}'"
    "${VM_BR_SRV}|BR-SRV|ВЗД1|Нестандартный порт удаленного доступа|${SSH_PORT}|linux|grep -i '^Port' /etc/openssh/sshd_config | awk '{print \$2}'"

    "HEADER|РАЗДЕЛ Г. Создание подсетей (Подинтерфейсы HQ-RTR)|---|---|---|---|---"
    "${VM_HQ_RTR}|HQ-RTR|Г1Д1|Статус подинтерфейса vl100 [show ip int brief]|up|iface_brief_status|vl100"
    "${VM_HQ_RTR}|HQ-RTR|Г1Д1|Статус подинтерфейса vl200 [show ip int brief]|up|iface_brief_status|vl200"
    "${VM_HQ_RTR}|HQ-RTR|Г1Д1|Статус подинтерфейса vl999 [show ip int brief]|up|iface_brief_status|vl999"

    "HEADER|РАЗДЕЛ Д. Оформление результата поиска|---|---|---|---|---"
    "00000|MANUAL|Д1Д1|Отчёт составлен по ГОСТ Р 7.0.97-2016|Ручная проверка файла отчета экспертом|manual|Ручная проверка файла отчета экспертом"
)

CONFIG_DIR="/root/routereco"
mkdir -p "$CONFIG_DIR"

PASS=0
FAIL=0
WARN=0

# Функция выполнения команд внутри Linux VM
get_linux_value() {
    local vmid="$1"
    local cmd="$2"
    local result
    
    qm guest exec "$vmid" -- echo OK >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "[ВМ НЕ ДОСТУПНА ИЛИ НЕ ЗАПУЩЕН АГЕНТ]"
        return
    fi

    result=$(qm guest exec "$vmid" -- bash -c "$cmd" 2>/dev/null)
    echo "$result" | grep -o '"out-data"[[:space:]]*:[[:space:]]*"[^"]*"' | \
        sed 's/"out-data"[[:space:]]*:[[:space:]]*"//' | sed 's/"$//' | \
        sed 's/\\n/\n/g' | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

# Функция извлечения параметров из конфигов EcoRouter
get_router_value() {
    local name="$1"
    local type="$2"
    local param="$3"
    
    local file_name=$(echo "$name" | tr 'A-Z' 'a-z')
    local file="${CONFIG_DIR}/${file_name}_running_config.txt"
    local db_file="${CONFIG_DIR}/${file_name}_localdb.txt"
    local iface_file="${CONFIG_DIR}/${file_name}_iface_brief.txt"

    # === ПАРСИНГ SHOW IP INT BRIEF ===
    if [[ "$type" == "iface_brief_ip" ]]; then
        if [ ! -f "$iface_file" ]; then echo "[ФАЙЛ IFACE BRIEF НЕ ВЫГРУЖЕН]"; return; fi
        awk -v iface="$param" 'tolower($1) == tolower(iface) {sub(/\/.*/, "", $2); print $2}' "$iface_file" | head -n 1
        return
    elif [[ "$type" == "iface_brief_status" ]]; then
        if [ ! -f "$iface_file" ]; then echo "[ФАЙЛ IFACE BRIEF НЕ ВЫГРУЖЕН]"; return; fi
        awk -v iface="$param" 'tolower($1) == tolower(iface) {print $3}' "$iface_file" | head -n 1
        return
    fi

    # === ПРОВЕРКА LOCALDB ===
    if [[ "$type" == "localdb_user" ]]; then
        if [ ! -f "$db_file" ]; then echo "[БАЗА LOCALDB НЕ ВЫГРУЖЕНА]"; return; fi
        if grep -Eiq "\b$param\b" "$db_file"; then echo "$param"; else echo "не найдено"; fi
        return
    fi

    if [ ! -f "$file" ]; then
        echo "[КОНФИГ НЕ НАЙДЕН]"
        return
    fi

    if [[ "$type" == "iface_ip" ]]; then
        awk -v iface="$param" '
            tolower($0) ~ "^[ \t]*interface[ \t]+"tolower(iface) {in_iface=1; next}
            in_iface && /^!/ {in_iface=0; exit}
            in_iface && /^[ \t]*ip address/ {
                sub(/^[ \t]*ip address[ \t]+/, "")
                print $0
                exit
            }
        ' "$file"
    elif [[ "$type" == "global_val" ]]; then
        grep -Ei "^[ \t]*$param" "$file" | awk '{print $2}' | head -n 1
    elif [[ "$type" == "global_exist" ]]; then
        if grep -Eiq "^[ \t]*$param" "$file"; then echo "$param"; else echo "не найдено"; fi
    elif [[ "$type" == "ospf_id" ]]; then
        # Ищет блок OSPF, захватывает 50 строк после него, находит строку с router-id и выдергивает IP
        grep -EiA 50 "^[ \t]*router ospf[ \t]+$param" "$file" | grep -Ei "router-id" | head -n 1 | awk '{print $NF}'
    fi
}

build_tcl_creds() {
    local tcl_str=""
    for cred in "${ROUTER_CREDS[@]}"; do
        local u="${cred%% *}"; local p="${cred#* }"
        tcl_str+="{\"$u\" \"$p\"} "
    done
    echo "$tcl_str"
}

make_export_expect() {
    local vmid="$1"
    local expscript="$2"
    local db_file="$3"
    local iface_file="$4"
    local tcl_creds=$(build_tcl_creds)

    cat > "$expscript" <<'EOF_EXP'
#!/usr/bin/expect -f
set timeout 15
match_max 1000000
log_user 1
set send_slow {1 .1}

proc wait_prompt {} {
    set loops 0
    while {$loops < 60} {
        expect {
            -re {--More--.*} { send " " ; exp_continue }
            -re {(?i)login:\s*} { return "login" }
            -re {(?i)password:\s*} { return "password" }
            -re {Login incorrect} { return "incorrect" }
            -re {Maximum number of tries exceeded} { return "max_tries" }
            -re {Login timed out} { return "timeout_msg" }
            -re {\(config[^\r\n]*\)#\s*} { return "config" }
            -re {[a-zA-Z0-9_.-]+>\s*} { return "user" }
            -re {[a-zA-Z0-9_.-]+#\s*} { return "priv" }
            timeout { send "\r"; incr loops; exp_continue }
            eof { return "eof" }
        }
    }
    return "timeout"
}

proc try_login {user pass} {
    set tries 0
    while {$tries < 15} {
        set state [wait_prompt]
        if {$state eq "login"} { sleep 0.2; send -s -- "$user\r"; incr tries; continue }
        if {$state eq "password"} { sleep 0.2; send -s -- "$pass\r"; incr tries; continue }
        if {$state eq "incorrect"} { return 1 }
        if {$state eq "max_tries" || $state eq "timeout_msg"} { sleep 2; send "\r"; incr tries; continue }
        if {$state eq "user"} { sleep 0.2; send -s -- "enable\r"; incr tries; continue }
        if {$state eq "config"} { sleep 0.2; send -s -- "\032"; after 500; incr tries; continue }
        if {$state eq "priv"} { return 0 }
        if {$state eq "eof" || $state eq "timeout"} { return 2 }
        send "\r"; incr tries
    }
    return 2
}

proc ensure_privileged_prompt {} {
    set creds { __TCL_CREDS__ }
    send "\r"; sleep 1
    foreach cred $creds {
        set u [lindex $cred 0]; set p [lindex $cred 1]
        puts "\nINFO: Trying $u / $p ..."
        set res [try_login $u $p]
        if {$res == 0} { return 0 }
        sleep 0.5; send "\r"
    }
    return 1
}

spawn qm terminal __VMID__
sleep 2; send "\r"
if {[ensure_privileged_prompt] != 0} { exit 11 }
sleep 0.5; send -s -- "no cli pager session\r"; set state [wait_prompt]

# === Выгрузка LocalDB ===
sleep 0.5
log_file -noappend "__DB_FILE__"
send -s -- "show users localdb\r"
set pages 0
while {1} {
    expect {
        -re {--More--.*} { send " "; incr pages; if {$pages > 2000} { break }; exp_continue }
        -re {[a-zA-Z0-9_.-]+#\s*} { break }
        timeout { break }
    }
}
log_file

# === Выгрузка show ip int brief ===
sleep 0.5
log_file -noappend "__IFACE_FILE__"
send -s -- "show ip interface brief\r"
set pages 0
while {1} {
    expect {
        -re {--More--.*} { send " "; incr pages; if {$pages > 2000} { break }; exp_continue }
        -re {[a-zA-Z0-9_.-]+#\s*} { break }
        timeout { break }
    }
}
log_file

# === Выгрузка Running Config ===
sleep 0.5; send -s -- "show running-config\r"
set pages 0
while {1} {
    expect {
        -re {--More--.*} { send " "; incr pages; if {$pages > 2000} { break }; exp_continue }
        -re {[a-zA-Z0-9_.-]+#\s*} { break }
        timeout { send "\r" }
        eof { break }
    }
}
sleep 0.5; send -s -- "exit\r"; expect eof
EOF_EXP

    sed -i -e "s|__VMID__|$vmid|g" \
           -e "s|__DB_FILE__|$db_file|g" \
           -e "s|__IFACE_FILE__|$iface_file|g" \
           -e "s|__TCL_CREDS__|$tcl_creds|g" "$expscript"
    chmod +x "$expscript"
}

export_running_config() {
    local vmid="$1"
    local name="$2"
    local rawfile="$CONFIG_DIR/${name}_running_raw.txt"
    local cleanfile="$CONFIG_DIR/${name}_running_config.txt"
    local db_file="$CONFIG_DIR/${name}_localdb.txt"
    local iface_file="$CONFIG_DIR/${name}_iface_brief.txt"
    local expscript="/tmp/exp_export_${vmid}.exp"

    # Удаляем старые файлы, чтобы не парсить неактуальные данные
    rm -f "$rawfile" "$cleanfile" "$db_file" "$iface_file"

    echo -e "\033[1;36m[ ИДЕТ СБОР ДАННЫХ ИЗ $name (VM $vmid) ]\033[0m"

    local status=$(qm status "$vmid" 2>/dev/null | awk '{print $2}')
    if [ "${status:-}" != "running" ]; then return 1; fi

    make_export_expect "$vmid" "$expscript" "$db_file" "$iface_file"
    timeout 180 /usr/bin/expect "$expscript" > "$rawfile" 2>&1
    local rc=$?
    rm -f "$expscript"

    # Очистка основного конфига
    if [ -f "$rawfile" ]; then
        cp "$rawfile" "$cleanfile"
        sed -i 's/\r//g' "$cleanfile"
        perl -CSDA -0pi -e 's/\e\[[0-9;?]*[ -\/]*[@-~]//g; s/[\x00-\x08\x0B\x0C\x0E-\x1F]//g' "$cleanfile"
        sed -i '/^spawn qm terminal/d; /^starting serial terminal/d; /press Ctrl+O/d; /^User Access Verification/d; /^EcoRouterOS version /d; /^<<< EcoRouter /d' "$cleanfile"
        sed -i '/login:/d; /Password:/d; /Login incorrect/d; /Login timed out/d; /Maximum number of tries/d; /INFO: Trying/d' "$cleanfile"
        sed -i '/^.*>enable$/d; /^.*#show running-config$/d; /^.*#terminal/d; /^.*#no cli pager session$/d; /^.*#exit$/d; /^--More--.*$/d; /^\s*\^\s*$/d' "$cleanfile"
        awk 'NF{blank=0; print; next} !blank{print; blank=1}' "$cleanfile" > "${cleanfile}.tmp" && mv "${cleanfile}.tmp" "$cleanfile"
    fi

    # Очистка вывода LocalDB
    if [ -f "$db_file" ]; then
        sed -i 's/\r//g' "$db_file"
        perl -CSDA -0pi -e 's/\e\[[0-9;?]*[ -\/]*[@-~]//g; s/[\x00-\x08\x0B\x0C\x0E-\x1F]//g' "$db_file"
        sed -i '/show users localdb/d' "$db_file"
    fi

    # Очистка вывода Interface Brief
    if [ -f "$iface_file" ]; then
        sed -i 's/\r//g' "$iface_file"
        perl -CSDA -0pi -e 's/\e\[[0-9;?]*[ -\/]*[@-~]//g; s/[\x00-\x08\x0B\x0C\x0E-\x1F]//g' "$iface_file"
        sed -i '/show ip interface brief/d' "$iface_file"
    fi

    if [ "$rc" -ne 0 ]; then return 1; fi
    return 0
}

# Главная функция вывода результатов
print_result() {
    local vmid="$1"
    local name="$2"
    local crit="$3"
    local desc="$4"
    local expected="$5"
    local actual="$6"
    local type="$7"

    local act_clean=$(echo "$actual" | tr -d '\r' | sed 's/^[ \t]*//;s/[ \t]*$//')
    local exp_clean=$(echo "$expected" | tr -d '\r' | sed 's/^[ \t]*//;s/[ \t]*$//')

    echo -e "\033[1;36mname $name\033[0m"
    echo "$desc ="
    echo -e "VM = \033[1;34m$vmid\033[0m"
    echo "Критерий $crit"

    if [[ "$type" == "manual" ]]; then
        echo -e "\033[1;33mВНИМАНИЕ\033[0m"
        echo "Требование: $expected"
        echo "Статус    : Проверяется визуально (не автоматизировано)"
        WARN=$((WARN + 1))
    elif [[ -n "$act_clean" ]] && [[ "$act_clean" == *"$exp_clean"* ]]; then
        echo -e "\033[0;32mсовпадает\033[0m"
        echo "должно быть = $expected"
        echo "а стоит     = $act_clean"
        PASS=$((PASS + 1))
    else
        echo -e "\033[0;31mне совпадает\033[0m"
        echo "должно быть = $expected"
        if [[ -z "$act_clean" ]]; then
            echo "а стоит     = [НЕ НАСТРОЕНО / ПУСТО]"
        else
            echo "а стоит     = $act_clean"
        fi
        FAIL=$((FAIL + 1))
    fi
    echo "----------------------------------------"
}

main() {
    clear
    echo -e "\033[1;33mСБОР ДАННЫХ С МАРШРУТИЗАТОРОВ ECOROUTER...\033[0m\n"
    export_running_config "$VM_HQ_RTR" "hq-rtr"
    export_running_config "$VM_BR_RTR" "br-rtr"

    clear
    echo -e "\033[1;33mЗАПУСК АНАЛИЗАТОРА ПО КРИТЕРИЯМ ОЦЕНКИ\033[0m\n"

    for check in "${CHECKS[@]}"; do
        IFS='|' read -r vmid name crit desc expected type param <<< "$check"
        
        if [[ "$vmid" == "HEADER" ]]; then
            echo -e "\n\033[1;35m════════════════════════════════════════════════════════\033[0m"
            echo -e "\033[1;35m  $name\033[0m"
            echo -e "\033[1;35m════════════════════════════════════════════════════════\033[0m\n"
            continue
        fi

        local actual=""
        if [[ "$type" == "linux" ]]; then
            actual=$(get_linux_value "$vmid" "$param")
        elif [[ "$type" == "manual" ]]; then
            actual="$expected"
        else
            actual=$(get_router_value "$name" "$type" "$param")
        fi

        print_result "$vmid" "$name" "$crit" "$desc" "$expected" "$actual" "$type"
    done
    
    echo -e "\033[1;32mАнализ завершен! Успешно: $PASS | Ошибки: $FAIL | Предупреждения: $WARN\033[0m"
}

main
