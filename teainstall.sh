#!/bin/bash

# =============================================================================
# Script de Instalação Automatizada do TeaSpeaK
# =============================================================================

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Banner
clear
echo -e "${CYAN}${BOLD}================================================"
echo -e "           INSTALADOR TEASPEAK"
echo -e "================================================${NC}\n"

# Função de log simples
log() { echo -e "${GREEN}[✓]${NC} $1"; }
err() { echo -e "${RED}[✗]${NC} $1"; exit 1; }
step() { echo -e "\n${CYAN}▶${NC} $1"; }

# Verificar root
[[ $EUID -ne 0 ]] && err "Execute como root"

# 1. Instalação de pacotes
step "Instalando dependências..."
apt update > /dev/null 2>&1 || err "Falha no apt update"
apt install -y sudo wget curl screen xz-utils libnice10 iptables-persistent > /dev/null 2>&1 || err "Falha na instalação de pacotes"
log "Dependências instaladas"

# 2. Criar usuário teaspeak
step "Configurando usuário teaspeak..."
if id "teaspeak" &>/dev/null; then
    log "Usuário já existe"
else
    echo -e "\n${YELLOW}Digite a senha para o usuário teaspeak:${NC}"
    adduser teaspeak --gecos ""
    [[ $? -eq 0 ]] || err "Falha ao criar usuário"
    log "Usuário criado com sucesso"
fi

# 3. Download e extração do TeaSpeak
step "Baixando TeaSpeak 1.4.21-beta-3..."
su - teaspeak -c '
cd ~
wget -q https://repo.teaspeak.de/server/linux/amd64_optimized/TeaSpeak-1.4.21-beta-3.tar.gz || exit 1
tar -xzf TeaSpeak-1.4.21-beta-3.tar.gz || exit 1
rm -f TeaSpeak-1.4.21-beta-3.tar.gz
' || err "Falha no download/extração"
log "TeaSpeak extraído"

# 4. Criar scripts de automação
step "Criando scripts de automação..."
mkdir -p /home/teaspeak/resources

# Script anticrash
cat > /home/teaspeak/resources/anticrash.sh << 'EOF'
#!/bin/bash
case $1 in
teaspeakserver)
    teaspeakserverpid=`ps ax | grep TeaSpeakServer | grep -v grep | wc -l`
    if [ $teaspeakserverpid -eq 1 ]
    then exit
    else
        /home/teaspeak/teastart.sh start
    fi
;;
esac
EOF

# Script backup
cat > /home/teaspeak/resources/teaspeakbackup.sh << 'EOF'
#!/bin/bash

TS3_DIR="/home/teaspeak"
BACKUP_DIR="/home/teaspeak/backups"
LOG_FILE="/home/teaspeak/backups/backup.log"
DATE=$(date +"%Y%m%d_%H%M%S")
BACKUP_NAME="teaspeak_backup_$DATE.tar.gz"
RETENTION_DAYS=30

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

error_exit() {
    log_message "ERRO - $1"
    exit 1
}

log_message "=== Iniciando Backup ==="
mkdir -p "$BACKUP_DIR" || error_exit "Erro ao criar diretório de backup"

[ ! -d "$TS3_DIR" ] && error_exit "Diretório TeaSpeak não encontrado"

FILES_TO_BACKUP=""
for item in "files" "geoloc" "config.yml" "query_ip_whitelist.txt" "TeaData.sqlite"; do
    [ -e "$TS3_DIR/$item" ] && FILES_TO_BACKUP="$FILES_TO_BACKUP $item"
done

[ -z "$FILES_TO_BACKUP" ] && error_exit "Nenhum arquivo encontrado"

cd "$TS3_DIR" || error_exit "Erro ao acessar diretório"

eval "tar -czf \"$BACKUP_DIR/$BACKUP_NAME\" $FILES_TO_BACKUP" 2>> "$LOG_FILE"

if [ $? -eq 0 ] && [ -f "$BACKUP_DIR/$BACKUP_NAME" ]; then
    BACKUP_SIZE=$(ls -lh "$BACKUP_DIR/$BACKUP_NAME" | awk '{print $5}')
    log_message "Backup criado: $BACKUP_NAME ($BACKUP_SIZE)"
    
    find "$BACKUP_DIR" -name "teaspeak_backup_*.tar.gz" -type f -mtime +$RETENTION_DAYS -delete
    log_message "Limpeza de backups antigos concluída"
else
    error_exit "Falha ao criar backup"
fi

tail -n 1000 "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
exit 0
EOF

chmod +x /home/teaspeak/resources/*.sh
chown -R teaspeak:teaspeak /home/teaspeak/resources
log "Scripts criados"

# 5. Configurar crontab
step "Configurando crontab..."
su - teaspeak -c 'cat > /tmp/teaspeak_crontab << "CRON"
@reboot cd /home/teaspeak && ./teastart.sh start
*/5 * * * * /home/teaspeak/resources/anticrash.sh teaspeakserver > /dev/null 2>&1
0 6 * * * /home/teaspeak/resources/teaspeakbackup.sh >/dev/null 2>&1
CRON
crontab /tmp/teaspeak_crontab
rm -f /tmp/teaspeak_crontab'
log "Crontab configurado"

# 6. Configurar iptables
step "Configurando firewall (iptables)..."

# Limpar regras antigas
iptables -F
iptables -X

# Políticas padrão
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# Permitir tráfego local
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# TCP: SSH, 10101 e 30303
iptables -A INPUT -p tcp --dport 22 -j ACCEPT
iptables -A INPUT -p tcp --dport 10101 -j ACCEPT
iptables -A INPUT -p tcp --dport 30303 -j ACCEPT

# UDP: 10500-10530 com rate limiting
iptables -N TS3_UDP
iptables -A INPUT -p udp --dport 10500:10530 -j TS3_UDP
iptables -A TS3_UDP -m conntrack --ctstate NEW -m limit --limit 50/sec --limit-burst 100 -j ACCEPT
iptables -A TS3_UDP -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A TS3_UDP -m limit --limit 5/min -j LOG --log-prefix "TS3 DDoS: "
iptables -A TS3_UDP -j DROP

# Mitigação de flood com recent
iptables -A INPUT -p udp --dport 10500:10530 -m recent --name TS3_ATTACK --set
iptables -A INPUT -p udp --dport 10500:10530 -m recent --name TS3_ATTACK --update --seconds 60 --hitcount 100 -j DROP

# ICMP limitado
iptables -A INPUT -p icmp -m limit --limit 1/s -j ACCEPT
iptables -A INPUT -p icmp -j DROP

# Salvar regras permanentemente
if command -v netfilter-persistent &> /dev/null; then
    netfilter-persistent save > /dev/null 2>&1
    log "Firewall configurado e salvo (netfilter-persistent)"
else
    # Fallback: salvar manualmente
    iptables-save > /etc/iptables/rules.v4
    log "Firewall configurado e salvo (iptables-save)"
fi

# Garantir que as regras sejam restauradas no boot
cat > /etc/network/if-pre-up.d/iptables << 'EOF'
#!/bin/sh
/sbin/iptables-restore < /etc/iptables/rules.v4
EOF
chmod +x /etc/network/if-pre-up.d/iptables
log "Restauração automática no boot configurada"

# Resumo final
echo -e "\n${GREEN}${BOLD}================================================"
echo -e "          INSTALAÇÃO CONCLUÍDA"
echo -e "================================================${NC}\n"

echo -e "${CYAN}Resumo:${NC}"
echo -e "  • Usuário: ${BOLD}teaspeak${NC}"
echo -e "  • Diretório: ${BOLD}/home/teaspeak/${NC}"
echo -e "  • AutoStart: ${GREEN}✓${NC} (no boot)"
echo -e "  • Anti-Crash: ${GREEN}✓${NC} (a cada 5min)"
echo -e "  • Backup: ${GREEN}✓${NC} (diário às 6h)"
echo -e "  • Firewall: ${GREEN}✓${NC} (iptables configurado)"

echo -e "\n${CYAN}Portas abertas:${NC}"
echo -e "  • TCP: 22 (SSH), 10101, 30303"
echo -e "  • UDP: 10500-10530 (rate limited)"

echo -e "\n${CYAN}Verificar firewall:${NC}"
echo -e "  ${YELLOW}iptables -L -v -n${NC} (ver regras detalhadas)"
echo -e "  ${YELLOW}iptables -L TS3_UDP -v -n${NC} (ver chain TeaSpeak)"

echo -e "\n${CYAN}Primeira inicialização:${NC}"
echo -e "  ${YELLOW}su teaspeak${NC}"
echo -e "  ${YELLOW}cd ~/TeaSpeak${NC}"
echo -e "  ${YELLOW}./teastart_minimal.sh${NC} ${RED}← IMPORTANTE: Execute primeiro!${NC}"
echo -e "\n${CYAN}Iniciar servidor (após primeira vez):${NC}"
echo -e "  ${YELLOW}./teastart.sh start${NC}\n"
