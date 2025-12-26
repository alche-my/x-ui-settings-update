#!/bin/bash

################################################################################
# ByeDPI + 3x-ui: All-in-One Installer
#
# Description: Installs ByeDPI and generates complete 3x-ui JSON config
#
# Usage: sudo ./install-byedpi-3xui.sh
#
# Key Features:
# - Parses vless:// URLs automatically (no manual parameter entry)
# - Uses proxySettings instead of dialerProxy (gRPC compatible)
# - ByeDPI parameters optimized for Reality (no --tlsrec)
# - Supports multiple servers with load balancing
#
# Version: 2.0 (2025-12-26)
# - Fixed: gRPC + dialerProxy incompatibility (GitHub Issue #2232)
# - Fixed: ByeDPI --tlsrec breaks Reality handshake
# - Fixed: Added explicit x-ui restart instruction
#
################################################################################

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

# Configuration
BYEDPI_REPO="https://github.com/hufrea/byedpi.git"
BYEDPI_DIR="/opt/byedpi"
BYEDPI_PORT="1080"
CONFIG_OUTPUT_DIR="/root/byedpi-config"

log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $*"
}

log_step() {
    echo -e "${CYAN}${BOLD}==>${NC} $*"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Этот скрипт должен быть запущен с правами root"
        log_info "Используйте: sudo $0"
        exit 1
    fi
}

install_dependencies() {
    log_step "Установка зависимостей..."

    if command -v apt-get &> /dev/null; then
        apt-get update -qq
        apt-get install -y -qq gcc make git curl jq
    elif command -v yum &> /dev/null; then
        yum install -y gcc make git curl jq
    else
        log_error "Неподдерживаемый менеджер пакетов"
        exit 1
    fi

    log_success "Зависимости установлены"
}

install_byedpi() {
    log_step "Установка ByeDPI..."

    # Clone repository
    if [[ -d "$BYEDPI_DIR" ]]; then
        log_warn "ByeDPI уже установлен в $BYEDPI_DIR"
        read -p "Переустановить? [y/N]: " reinstall </dev/tty
        if [[ "$reinstall" =~ ^[Yy]$ ]]; then
            rm -rf "$BYEDPI_DIR"
        else
            log_info "Пропускаем установку ByeDPI"
            return 0
        fi
    fi

    git clone "$BYEDPI_REPO" "$BYEDPI_DIR" --quiet

    # Compile
    log_info "Компиляция ByeDPI..."
    cd "$BYEDPI_DIR"
    make

    # Install binary
    cp ciadpi /usr/local/bin/
    chmod +x /usr/local/bin/ciadpi

    log_success "ByeDPI установлен в /usr/local/bin/ciadpi"
}

create_byedpi_service() {
    log_step "Создание systemd сервиса..."

    cat > /etc/systemd/system/byedpi.service << EOF
[Unit]
Description=ByeDPI SOCKS5 Proxy for DPI Bypass
Documentation=https://github.com/hufrea/byedpi
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/ciadpi --ip 127.0.0.1 --port $BYEDPI_PORT --oob 1 --disorder 1 --auto=torst
Restart=on-failure
RestartSec=5s
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable byedpi
    systemctl restart byedpi

    sleep 2

    if systemctl is-active --quiet byedpi; then
        log_success "ByeDPI сервис запущен"
    else
        log_error "Не удалось запустить ByeDPI"
        exit 1
    fi
}

url_decode() {
    local url_encoded="${1//+/ }"
    printf '%b' "${url_encoded//%/\\x}"
}

parse_vless_url() {
    local vless_url="$1"

    # Remove vless:// prefix
    vless_url="${vless_url#vless://}"

    # Extract UUID (before @)
    local uuid="${vless_url%%@*}"

    # Extract rest (after @)
    local rest="${vless_url#*@}"

    # Extract IP:PORT (before ?)
    local address_port="${rest%%\?*}"
    local address="${address_port%:*}"
    local port="${address_port##*:}"

    # Extract parameters (after ? and before #)
    local params="${rest#*\?}"
    params="${params%%\#*}"

    # Extract tag (after #)
    local tag=""
    if [[ "$rest" == *"#"* ]]; then
        tag="${rest##*\#}"
        tag=$(url_decode "$tag")
    fi

    # Parse parameters
    local network="tcp"
    local security="none"
    local pbk=""
    local fp="chrome"
    local sni=""
    local sid=""
    local service_name=""
    local flow=""

    IFS='&' read -ra PARAMS <<< "$params"
    for param in "${PARAMS[@]}"; do
        key="${param%%=*}"
        value="${param#*=}"
        value=$(url_decode "$value")

        case "$key" in
            type) network="$value" ;;
            security) security="$value" ;;
            pbk) pbk="$value" ;;
            fp) fp="$value" ;;
            sni) sni="$value" ;;
            sid) sid="$value" ;;
            serviceName) service_name="$value" ;;
            flow) flow="$value" ;;
        esac
    done

    # Export parsed values
    echo "$uuid|$address|$port|$network|$security|$pbk|$fp|$sni|$sid|$service_name|$flow|$tag"
}

collect_server_info() {
    log_step "Сбор информации о Non-RU серверах..."

    echo ""
    echo -e "${YELLOW}Сколько Non-RU серверов вы хотите добавить?${NC}"
    read -p "Количество серверов [1]: " server_count </dev/tty
    server_count=${server_count:-1}

    if ! [[ "$server_count" =~ ^[0-9]+$ ]] || [[ "$server_count" -lt 1 ]]; then
        log_error "Некорректное количество серверов"
        exit 1
    fi

    declare -g -a server_ips
    declare -g -a server_ports
    declare -g -a server_uuids
    declare -g -a server_networks
    declare -g -a server_securities
    declare -g -a server_public_keys
    declare -g -a server_short_ids
    declare -g -a server_sni
    declare -g -a server_fingerprints
    declare -g -a server_service_names
    declare -g -a server_flows
    declare -g -a server_tags

    for i in $(seq 1 $server_count); do
        echo ""
        echo -e "${CYAN}${BOLD}=== Сервер #$i ===${NC}"

        while true; do
            echo ""
            echo -e "${YELLOW}Вставьте vless:// ссылку для сервера #$i:${NC}"
            read -p "> " vless_url </dev/tty

            if [[ -z "$vless_url" ]]; then
                log_error "Ссылка не может быть пустой"
                continue
            fi

            if [[ ! "$vless_url" =~ ^vless:// ]]; then
                log_error "Ссылка должна начинаться с vless://"
                continue
            fi

            # Parse vless URL
            parsed=$(parse_vless_url "$vless_url")

            IFS='|' read -r uuid ip port network security pbk fp sni sid service_name flow tag <<< "$parsed"

            if [[ -z "$uuid" ]] || [[ -z "$ip" ]] || [[ -z "$port" ]]; then
                log_error "Не удалось распарсить ссылку"
                continue
            fi

            # Display parsed info
            echo ""
            log_success "Ссылка успешно распознана:"
            echo "  IP: $ip"
            echo "  Порт: $port"
            echo "  UUID: $uuid"
            echo "  Тип: $network"
            echo "  Безопасность: $security"
            [[ -n "$pbk" ]] && echo "  Public Key: ${pbk:0:20}..."
            [[ -n "$sni" ]] && echo "  SNI: $sni"
            [[ -n "$fp" ]] && echo "  Fingerprint: $fp"
            [[ -n "$sid" ]] && echo "  Short ID: $sid"
            [[ -n "$service_name" ]] && echo "  Service Name: $service_name"
            [[ -n "$flow" ]] && echo "  Flow: $flow"
            echo ""

            read -p "Использовать эти настройки? [Y/n]: " confirm </dev/tty
            if [[ ! "$confirm" =~ ^[Nn]$ ]]; then
                server_uuids+=("$uuid")
                server_ips+=("$ip")
                server_ports+=("$port")
                server_networks+=("$network")
                server_securities+=("$security")
                server_public_keys+=("$pbk")
                server_fingerprints+=("$fp")
                server_sni+=("$sni")
                server_short_ids+=("$sid")
                server_service_names+=("$service_name")
                server_flows+=("$flow")
                server_tags+=("${tag:-non-ru-${i}-via-byedpi}")
                break
            fi
        done
    done

    # Balancing strategy (only if multiple servers)
    if [[ $server_count -gt 1 ]]; then
        echo ""
        echo -e "${YELLOW}Стратегия балансировки:${NC}"
        echo "  1) random   - случайный выбор сервера"
        echo "  2) leastPing - выбор сервера с наименьшим пингом"
        echo "  3) leastLoad - выбор наименее загруженного сервера"
        read -p "Выберите стратегию [1-3]: " strategy_choice </dev/tty

        case "$strategy_choice" in
            2) strategy_type="leastPing" ;;
            3) strategy_type="leastLoad" ;;
            *) strategy_type="random" ;;
        esac
    else
        strategy_type=""
    fi

    declare -g server_count
    declare -g strategy_type
}

generate_full_config() {
    log_step "Генерация полной конфигурации 3x-ui..."

    mkdir -p "$CONFIG_OUTPUT_DIR"

    # Build outbounds array
    outbounds='['

    # Direct outbound
    outbounds+='
    {
      "tag": "direct",
      "protocol": "freedom",
      "settings": {
        "domainStrategy": "AsIs",
        "redirect": "",
        "noises": []
      }
    },'

    # Blocked outbound
    outbounds+='
    {
      "tag": "blocked",
      "protocol": "blackhole",
      "settings": {}
    },'

    # ByeDPI SOCKS outbound
    outbounds+='
    {
      "protocol": "socks",
      "settings": {
        "servers": [
          {
            "address": "127.0.0.1",
            "port": '$BYEDPI_PORT',
            "users": []
          }
        ]
      },
      "tag": "byedpi-socks"
    }'

    # Non-RU server outbounds
    for i in $(seq 0 $((server_count - 1))); do
        network="${server_networks[$i]}"
        security="${server_securities[$i]}"
        flow="${server_flows[$i]}"

        # Build streamSettings based on network type
        stream_settings='
        "network": "'$network'",
        "security": "'$security'"'

        # Add security settings
        if [[ "$security" == "reality" ]]; then
            stream_settings+=',
        "realitySettings": {
          "publicKey": "'${server_public_keys[$i]}'",
          "fingerprint": "'${server_fingerprints[$i]}'",
          "serverName": "'${server_sni[$i]}'",
          "shortId": "'${server_short_ids[$i]}'",
          "spiderX": "/",
          "mldsa65Verify": ""
        }'
        elif [[ "$security" == "tls" ]]; then
            stream_settings+=',
        "tlsSettings": {
          "serverName": "'${server_sni[$i]}'",
          "fingerprint": "'${server_fingerprints[$i]}'",
          "allowInsecure": false
        }'
        fi

        # Add network-specific settings
        if [[ "$network" == "grpc" ]]; then
            stream_settings+=',
        "grpcSettings": {
          "serviceName": "'${server_service_names[$i]}'",
          "authority": "",
          "multiMode": false
        }'
        elif [[ "$network" == "ws" ]]; then
            stream_settings+=',
        "wsSettings": {
          "path": "/",
          "headers": {}
        }'
        elif [[ "$network" == "tcp" ]]; then
            stream_settings+=',
        "tcpSettings": {
          "header": {
            "type": "none"
          }
        }'
        fi

        outbounds+=',
    {
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "'${server_ips[$i]}'",
            "port": '${server_ports[$i]}',
            "users": [
              {
                "id": "'${server_uuids[$i]}'",
                "flow": "'$flow'",
                "encryption": "none"
              }
            ]
          }
        ]
      },
      "tag": "'${server_tags[$i]}'",
      "proxySettings": {
        "tag": "byedpi-socks",
        "transportLayer": true
      },
      "streamSettings": {'$stream_settings'
      }
    }'
    done

    outbounds+='
  ]'

    # Build routing rules
    routing_rules='['

    # API rule
    routing_rules+='
      {
        "type": "field",
        "inboundTag": ["api"],
        "outboundTag": "api"
      },'

    # Block private IPs
    routing_rules+='
      {
        "type": "field",
        "outboundTag": "blocked",
        "ip": ["geoip:private"]
      },'

    # Block BitTorrent
    routing_rules+='
      {
        "type": "field",
        "outboundTag": "blocked",
        "protocol": ["bittorrent"]
      },'

    # Main routing rule
    if [[ $server_count -gt 1 ]]; then
        # Multiple servers: use balancer
        routing_rules+='
      {
        "type": "field",
        "network": "TCP,UDP",
        "balancerTag": "balancer"
      }'
    else
        # Single server: direct routing
        routing_rules+='
      {
        "type": "field",
        "network": "TCP,UDP",
        "outboundTag": "'${server_tags[0]}'"
      }'
    fi

    routing_rules+='
    ]'

    # Build balancers (only if multiple servers)
    balancers=''
    if [[ $server_count -gt 1 ]]; then
        selector='['
        for i in $(seq 0 $((server_count - 1))); do
            [[ $i -gt 0 ]] && selector+=', '
            selector+='"'${server_tags[$i]}'"'
        done
        selector+=']'

        balancers=',
    "balancers": [
      {
        "tag": "balancer",
        "selector": '$selector',
        "strategy": {
          "type": "'$strategy_type'"
        }
      }
    ]'
    fi

    # Generate full config
    local full_config='{
  "log": {
    "access": "none",
    "dnsLog": false,
    "error": "",
    "loglevel": "warning",
    "maskAddress": ""
  },
  "api": {
    "tag": "api",
    "services": [
      "HandlerService",
      "LoggerService",
      "StatsService"
    ]
  },
  "inbounds": [
    {
      "tag": "api",
      "listen": "127.0.0.1",
      "port": 62789,
      "protocol": "tunnel",
      "settings": {
        "address": "127.0.0.1"
      }
    }
  ],
  "outbounds": '$outbounds',
  "policy": {
    "levels": {
      "0": {
        "statsUserDownlink": true,
        "statsUserUplink": true
      }
    },
    "system": {
      "statsInboundDownlink": true,
      "statsInboundUplink": true,
      "statsOutboundDownlink": false,
      "statsOutboundUplink": false
    }
  },
  "routing": {
    "domainStrategy": "AsIs",
    "rules": '$routing_rules$balancers'
  },
  "stats": {},
  "metrics": {
    "tag": "metrics_out",
    "listen": "127.0.0.1:11111"
  }
}'

    # Save and format JSON
    echo "$full_config" | jq '.' > "$CONFIG_OUTPUT_DIR/3xui-full-config.json" 2>/dev/null || {
        echo "$full_config" > "$CONFIG_OUTPUT_DIR/3xui-full-config.json"
    }

    log_success "Конфигурация сохранена в $CONFIG_OUTPUT_DIR/3xui-full-config.json"
}

show_final_instructions() {
    echo ""
    echo -e "${GREEN}${BOLD}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║  ✓ Установка завершена!                                   ║${NC}"
    echo -e "${GREEN}${BOLD}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    log_info "📊 Сводка:"
    echo "  ✓ ByeDPI установлен и запущен (порт $BYEDPI_PORT)"
    echo "  ✓ Конфигурация для $server_count серверов готова"
    [[ $server_count -gt 1 ]] && echo "  ✓ Балансировка: $strategy_type"
    echo ""

    log_info "📋 Следующие шаги:"
    echo ""
    echo "1. Скопируйте JSON конфигурацию:"
    echo -e "${YELLOW}cat $CONFIG_OUTPUT_DIR/3xui-full-config.json${NC}"
    echo ""
    echo "2. Откройте 3x-ui панель в браузере"
    echo ""
    echo "3. Перейдите: Panel Settings → Xray Configs"
    echo ""
    echo "4. Замените весь JSON на скопированный"
    echo ""
    echo "5. Нажмите Save и Restart Xray"
    echo ""
    echo -e "${RED}${BOLD}⚠️  ВАЖНО: После применения конфигурации обязательно перезапустите x-ui:${NC}"
    echo -e "${YELLOW}sudo systemctl restart x-ui${NC}"
    echo ""

    log_info "📝 Информация о серверах:"
    echo ""
    for i in $(seq 0 $((server_count - 1))); do
        echo "  Сервер #$((i+1)): ${server_ips[$i]}:${server_ports[$i]}"
        echo "  UUID: ${server_uuids[$i]}"
        echo "  Тип: ${server_networks[$i]}, Безопасность: ${server_securities[$i]}"
        echo ""
    done
    echo ""
    log_warn "⚠️  ВАЖНО: Убедитесь, что эти UUID уже добавлены на Non-RU серверах!"

    log_info "🔧 Проверка:"
    echo -e "${YELLOW}sudo systemctl status byedpi${NC}"
    echo -e "${YELLOW}sudo systemctl status x-ui${NC}"
    echo ""

    echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}Показать JSON конфигурацию сейчас? [y/N]:${NC}"
    read -p "" show_config </dev/tty

    if [[ "$show_config" =~ ^[Yy]$ ]]; then
        echo ""
        echo -e "${YELLOW}╔══════════════════════════════════════════════════════════╗${NC}"
        echo -e "${YELLOW}║  Скопируйте этот JSON в 3x-ui → Xray Configs            ║${NC}"
        echo -e "${YELLOW}╚══════════════════════════════════════════════════════════╝${NC}"
        echo ""
        cat "$CONFIG_OUTPUT_DIR/3xui-full-config.json"
        echo ""
        echo -e "${YELLOW}╚══════════════════════════════════════════════════════════╝${NC}"
        echo ""
    fi
}

main() {
    echo ""
    echo -e "${CYAN}${BOLD}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}${BOLD}║  ByeDPI + 3x-ui: Универсальный установщик                 ║${NC}"
    echo -e "${CYAN}${BOLD}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    check_root
    install_dependencies
    install_byedpi
    create_byedpi_service
    collect_server_info
    generate_full_config
    show_final_instructions
}

main "$@"
