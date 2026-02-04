#!/bin/bash

# WARP 优化脚本 (支持 CentOS 7 / Ubuntu / Debian)
# 修复 CentOS 7 glibc 兼容性问题，自动解锁 Google

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

show_banner() {
    clear
    echo -e "${CYAN}"
    echo "╔════════════════════════════════════════════════════╗"
    echo "║     🌐 WARP 优化脚本 - 兼容 CentOS 7 🌐             ║"
    echo "║       自动解锁 Google，解决 GLIBC 报错              ║"
    echo "╚════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# 检查权限
[[ $EUID -ne 0 ]] && { echo -e "${RED}请使用 root 运行！${NC}"; exit 1; }

# 检测系统
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VERSION_ID=$VERSION_ID
else
    echo -e "${RED}无法检测系统${NC}"; exit 1
fi

# 安装依赖执行程序
install_dependencies() {
    echo -e "\n${CYAN}[1/3] 安装系统依赖 (redsocks, iptables)...${NC}"
    if [[ "$OS" == "centos" || "$OS" == "rhel" ]]; then
        yum install -y epel-release
        yum install -y redsocks iptables wget curl
    else
        apt-get update
        apt-get install -y redsocks iptables wget curl
    fi
}

# 安装 WARP 客户端 (CentOS 7 特殊处理)
install_warp() {
    echo -e "\n${CYAN}[2/3] 安装 WARP 客户端...${NC}"
    
    # 检测是否为 CentOS 7
    if [[ "$OS" == "centos" && "$VERSION_ID" == "7" ]]; then
        echo -e "${YELLOW}检测到 CentOS 7，官方客户端不兼容，正在安装 warp-go...${NC}"
        wget -N https://github.com/fscarmen/warp-go/releases/latest/download/warp-go_linux_amd64 -O /usr/local/bin/warp-cli
        chmod +x /usr/local/bin/warp-cli
        # warp-go 注册逻辑
        /usr/local/bin/warp-cli register
    else
        # 其他系统安装官方版 (略，保持你原有的逻辑或使用 warp-go 通用版)
        echo -e "安装通用版 warp-go..."
        wget -N https://github.com/fscarmen/warp-go/releases/latest/download/warp-go_linux_amd64 -O /usr/local/bin/warp-cli
        chmod +x /usr/local/bin/warp-cli
        /usr/local/bin/warp-cli register
    fi
}

# 配置透明代理规则
setup_proxy_rules() {
    echo -e "\n${CYAN}[3/3] 配置转发逻辑...${NC}"
    
    # 启动 warp-go 代理模式
    nohup /usr/local/bin/warp-cli proxy -p 40000 >/dev/null 2>&1 &
    sleep 3

    # 生成 redsocks 配置
    cat > /etc/redsocks.conf << 'EOF'
base {
    log_debug = off; log_info = on; log = "syslog:daemon";
    daemon = on; redirector = iptables;
}
redsocks {
    local_ip = 127.0.0.1; local_port = 12345;
    ip = 127.0.0.1; port = 40000; type = socks5;
}
EOF

    # 创建 iptables 脚本 (复用你原有的 IP 列表逻辑)
    cat > /usr/local/bin/warp-google << 'SCRIPT'
#!/bin/bash
GOOGLE_IPS="8.8.4.0/24 8.8.8.0/24 34.0.0.0/9 142.250.0.0/15 172.217.0.0/16 172.253.0.0/16"
start() {
    pkill redsocks 2>/dev/null
    redsocks -c /etc/redsocks.conf
    iptables -t nat -N WARP_GOOGLE 2>/dev/null || iptables -t nat -F WARP_GOOGLE
    for ip in $GOOGLE_IPS; do
        iptables -t nat -A WARP_GOOGLE -d $ip -p tcp -j REDIRECT --to-ports 12345
    done
    iptables -t nat -C OUTPUT -j WARP_GOOGLE 2>/dev/null || iptables -t nat -A OUTPUT -j WARP_GOOGLE
    echo "代理已启动"
}
stop() {
    pkill redsocks 2>/dev/null
    iptables -t nat -D OUTPUT -j WARP_GOOGLE 2>/dev/null
    echo "代理已停止"
}
case "$1" in
    start) start ;;
    stop) stop ;;
    *) $0 start ;;
esac
SCRIPT
    chmod +x /usr/local/bin/warp-google
    /usr/local/bin/warp-google start
}

# 测试
do_test() {
    echo -e "\n${CYAN}验证连接...${NC}"
    CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 https://www.google.com)
    if [ "$CODE" == "200" ]; then
        echo -e "${GREEN}✓ 完美解锁 Google (状态码: 200)${NC}"
    else
        echo -e "${RED}✗ 仍未成功 (状态码: $CODE)，请检查 40000 端口是否被占用${NC}"
    fi
}

# 主流程
show_banner
install_dependencies
install_warp
setup_proxy_rules
do_test
