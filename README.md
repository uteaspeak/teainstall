# Instalador Automático TeaSpeak

Script de instalação automatizada do TeaSpeak Server com configurações otimizadas para produção.

## Características

- Instalação completa do TeaSpeak 1.4.21-beta-3
- Configuração automática de firewall (iptables)
- Sistema anti-crash (verificação a cada 5 minutos)
- Backup automático diário às 6h
- AutoStart no boot do sistema
- Proteção contra DDoS com rate limiting
- Logs minimalistas e objetivos

## Instalação

### Requisitos
- Sistema operacional: **Debian11**
- Usuário: **root**

### Executar instalação

```bash
chmod +x install_teaspeak.sh
./install_teaspeak.sh
```

Durante a instalação, será solicitado que você crie uma **senha** para o usuário `teaspeak`.

## Configurações Aplicadas

### Firewall (iptables)

#### Portas TCP Abertas
- `22` - SSH
- `10101` - TeaSpeak Server
- `30303` - TeaSpeak FileTransfer

#### Portas UDP Abertas
- `10500-10530` - TeaSpeak Voice (com rate limiting)

#### Proteções Ativas
- **Rate Limiting**: 50 pacotes/segundo (burst 100)
- **Anti-DDoS**: Bloqueio automático após 100 pacotes/minuto do mesmo IP
- **ICMP Limitado**: 1 ping/segundo
- **Policy DROP**: Todo tráfego não autorizado é bloqueado

### Automações (Crontab)

| Tarefa | Frequência | Descrição |
|--------|-----------|-----------|
| AutoStart | No boot | Inicia o TeaSpeak automaticamente |
| Anti-Crash | A cada 5min | Verifica e reinicia o servidor se necessário |
| Backup | Diário às 6h | Backup completo dos dados |

## Usando o TeaSpeak

### Primeira Inicialização

```bash
su teaspeak
cd ~/TeaSpeak
./teastart_minimal.sh
```

**IMPORTANTE**: Execute `teastart_minimal.sh` na primeira vez para gerar as configurações iniciais.

### Inicializações Seguintes

```bash
su teaspeak
cd ~/TeaSpeak
./teastart.sh start
```

### Comandos Úteis

```bash
# Parar o servidor
./teastart.sh stop

# Reiniciar o servidor
./teastart.sh restart

# Ver status
./teastart.sh status
```

## Estrutura de Diretórios

```
/home/teaspeak/
├── TeaSpeak/                    # Arquivos do servidor
│   ├── config.yml               # Configuração principal
│   ├── TeaData.sqlite           # Banco de dados
│   ├── files/                   # Arquivos de áudio/ícones
│   └── geoloc/                  # Dados de geolocalização
├── resources/                   # Scripts de automação
│   ├── anticrash.sh             # Monitor de processo
│   └── teaspeakbackup.sh        # Sistema de backup
└── backups/                     # Backups automáticos
    ├── backup.log               # Log de backups
    └── teaspeak_backup_*.tar.gz
```

## Firewall

### Verificar Regras Ativas

```bash
# Ver todas as regras
iptables -L -v -n

# Ver chain específica do TeaSpeak
iptables -L TS3_UDP -v -n

# Ver regras salvas
iptables-save
```

### Regras Persistentes

As regras do firewall são salvas automaticamente e restauradas no boot através de:
- `netfilter-persistent`
- `/etc/iptables/rules.v4`
- `/etc/network/if-pre-up.d/iptables`

## Sistema de Backup

### Localização
- **Diretório**: `/home/teaspeak/backups/`
- **Formato**: `teaspeak_backup_YYYYMMDD_HHMMSS.tar.gz`
- **Retenção**: 30 dias (backups antigos são removidos automaticamente)

### Conteúdo do Backup
- `files/` - Arquivos de áudio e ícones
- `geoloc/` - Dados de geolocalização
- `config.yml` - Configurações
- `query_ip_whitelist.txt` - Lista de IPs permitidos
- `TeaData.sqlite` - Banco de dados completo

### Backup Manual

```bash
su teaspeak
/home/teaspeak/resources/teaspeakbackup.sh
```

### Verificar Logs de Backup

```bash
cat /home/teaspeak/backups/backup.log
```

## Monitoramento

### Verificar se o Servidor está Rodando

```bash
ps aux | grep TeaSpeak
```

### Ver Logs do Anti-Crash

```bash
# Verificar crontab
crontab -l -u teaspeak

# Ver logs do sistema
grep CRON /var/log/syslog | grep anticrash
```

### Monitorar Tentativas de DDoS

```bash
# Ver logs de bloqueios
dmesg | grep "TS3 DDoS"

# Ou em tempo real
tail -f /var/log/kern.log | grep "TS3 DDoS"
```

## Segurança

### Usuário TeaSpeak
- **Usuário**: `teaspeak`
- **Senha**: Definida durante a instalação
- **Diretório home**: `/home/teaspeak`

### Recomendações
1. Altere a porta SSH padrão (22) se possível
2. Configure autenticação por chave SSH
3. Mantenha o sistema atualizado: `apt update && apt upgrade`
4. Monitore os logs regularmente
5. Faça backup das configurações personalizadas

## Troubleshooting

### Servidor não inicia

```bash
# Verificar logs do TeaSpeak
su teaspeak
cd ~/TeaSpeak
cat logs/latest.log
```

### Firewall bloqueando conexões

```bash
# Ver pacotes dropados
iptables -L -v -n | grep DROP

# Desabilitar temporariamente
iptables -P INPUT ACCEPT
```

### Backup falhou

```bash
# Verificar log de erros
cat /home/teaspeak/backups/backup.log

# Testar backup manual
su teaspeak
/home/teaspeak/resources/teaspeakbackup.sh
```

### Anti-crash não funciona

```bash
# Verificar se o crontab está configurado
crontab -l -u teaspeak

# Verificar permissões do script
ls -la /home/teaspeak/resources/anticrash.sh
```

## Informações Técnicas

### Versão
- **TeaSpeak**: 1.4.21-beta-3
- **Arquitetura**: amd64_optimized
- **Sistema**: Linux

### Dependências Instaladas
- `sudo`
- `wget`
- `curl`
- `screen`
- `xz-utils`
- `libnice10`
- `iptables-persistent`

### Portas Utilizadas

| Porta | Protocolo | Descrição |
|-------|-----------|-----------|
| 22 | TCP | SSH |
| 10101 | TCP | TeaSpeak Server |
| 30303 | TCP | FileTransfer |
| 10500-10530 | UDP | Voice Channels |
