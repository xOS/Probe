#!/bin/bash

#========================================================
#   System Required: CentOS 7+ / Debian 8+ / Ubuntu 16+ /
#   Arch 未测试
#   Description: 楠格探针安装脚本
#   Github: https://github.com/xOS/Probe
#========================================================

BASE_PATH="/opt/probe"
DASHBOARD_PATH="${BASE_PATH}/dashboard"
AGENT_PATH="${BASE_PATH}/agent"
AGENT_SERVICE="/etc/systemd/system/probe-agent.service"
VERSION="v2.2.9"

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'
export PATH=$PATH:/usr/local/bin

os_arch=""

pre_check() {
    command -v systemctl >/dev/null 2>&1
    if [[ $? != 0 ]]; then
        echo "不支持此系统：未找到 systemctl 命令"
        exit 1
    fi

    # check root
    [[ $EUID -ne 0 ]] && echo -e "${red}错误: ${plain} 必须使用root用户运行此脚本！\n" && exit 1

    ## os_arch
    if [[ $(uname -m | grep 'x86_64') != "" ]]; then
        os_arch="amd64"
    elif [[ $(uname -m | grep 'i386\|i686') != "" ]]; then
        os_arch="386"
    elif [[ $(uname -m | grep 'aarch64\|armv8b\|armv8l') != "" ]]; then
        os_arch="arm64"
    elif [[ $(uname -m | grep 'arm') != "" ]]; then
        os_arch="arm"
    fi

    ## China_IP
    if [[ $(curl -m 10 -s https://api.ip.sb/geoip | grep 'China') != "" ]]; then
        echo "根据ip.sb提供的信息，当前IP可能在中国"
        read -e -r -p "是否选用中国镜像完成安装? [Y/n] " input
        case $input in
        [yY][eE][sS] | [yY])
            echo "使用中国镜像"
            CN=true
            ;;

        [nN][oO] | [nN])
            echo "不使用中国镜像"
            ;;
        *)
            echo "使用中国镜像"
            CN=true
            ;;
        esac
    fi

    if [[ -z "${CN}" ]]; then
        GITHUB_RAW_URL="raw.githubusercontent.com/xos/probe/master"
        GITHUB_URL="github.com"
        Get_Docker_URL="get.docker.com"
        Get_Docker_Argu=" "
        Docker_IMG="ghcr.io\/xos\/probe-dashboard"
    else
        GITHUB_RAW_URL="cdn.jsdelivr.net/gh/xos/probe@master"
        GITHUB_URL="dn-dao-github-mirror.daocloud.io"
        Get_Docker_URL="get.daocloud.io/docker"
        Get_Docker_Argu=" -s docker --mirror Aliyun"
        Docker_IMG="registry.cn-shanghai.aliyuncs.com\/dns\/probe-dashboard"
    fi
}

confirm() {
    if [[ $# > 1 ]]; then
        echo && read -e -p "$1 [默认$2]: " temp
        if [[ x"${temp}" == x"" ]]; then
            temp=$2
        fi
    else
        read -e -p "$1 [y/n]: " temp
    fi
    if [[ x"${temp}" == x"y" || x"${temp}" == x"Y" ]]; then
        return 0
    else
        return 1
    fi
}

update_script() {
    echo -e "> 更新脚本"

    curl -sL https://${GITHUB_RAW_URL}/script/probe.sh -o /tmp/probe.sh
    new_version=$(cat /tmp/probe.sh | grep "VERSION" | head -n 1 | awk -F "=" '{print $2}' | sed 's/\"//g;s/,//g;s/ //g')
    if [ ! -n "$new_version" ]; then
        echo -e "脚本获取失败，请检查本机能否链接 https://${GITHUB_RAW_URL}/script/probe.sh"
        return 1
    fi
    echo -e "当前最新版本为: ${new_version}"
    mv -f /tmp/probe.sh ./probe.sh && chmod a+x ./probe.sh

    echo -e "3s后执行新脚本"
    sleep 3s
    clear
    exec ./probe.sh
    exit 0
}

before_show_menu() {
    echo && echo -n -e "${yellow}* 按回车返回主菜单 *${plain}" && read temp
    show_menu
}

install_base() {
    (command -v git >/dev/null 2>&1 && command -v curl >/dev/null 2>&1 && command -v wget >/dev/null 2>&1 && command -v tar >/dev/null 2>&1) ||
        (install_soft curl wget git tar)
}

install_soft() {
    (command -v yum >/dev/null 2>&1 && yum install $* -y) ||
        (command -v apt >/dev/null 2>&1 && apt install $* -y) ||
        (command -v pacman >/dev/null 2>&1 && pacman -Syu $*) ||
        (command -v apt-get >/dev/null 2>&1 && apt-get install $* -y)
}

install_dashboard() {
    install_base

    echo -e "> 安装面板"

    # 楠格探针文件夹
    mkdir -p $DASHBOARD_PATH
    chmod 777 -R $DASHBOARD_PATH

    command -v docker >/dev/null 2>&1
    if [[ $? != 0 ]]; then
        echo -e "正在安装 Docker"
        bash <(curl -sL https://${Get_Docker_URL}) ${Get_Docker_Argu} >/dev/null 2>&1
        if [[ $? != 0 ]]; then
            echo -e "${red}下载脚本失败，请检查本机能否连接 ${Get_Docker_URL}${plain}"
            return 0
        fi
        systemctl enable docker.service
        systemctl start docker.service
        echo -e "${green}Docker${plain} 安装成功"
    fi

    command -v docker-compose >/dev/null 2>&1
    if [[ $? != 0 ]]; then
        echo -e "正在安装 Docker Compose"
        wget -O /usr/local/bin/docker-compose "https://${GITHUB_URL}/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" >/dev/null 2>&1
        if [[ $? != 0 ]]; then
            echo -e "${red}下载脚本失败，请检查本机能否连接 ${GITHUB_URL}${plain}"
            return 0
        fi
        chmod +x /usr/local/bin/docker-compose
        echo -e "${green}Docker Compose${plain} 安装成功"
    fi

    modify_dashboard_config 0

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

install_agent() {
    install_base

    echo -e "> 安装探针Agent"

    echo -e "正在获取探针Agent版本号"

    local version=$(curl -m 10 -sL "https://api.github.com/repos/xOS/Probe/releases/latest" | grep "tag_name" | head -n 1 | awk -F ":" '{print $2}' | sed 's/\"//g;s/,//g;s/ //g')
    if [ ! -n "$version" ]; then
        version=$(curl -m 10 -sL "https://cdn.jsdelivr.net/gh/xOS/Probe/" | grep "option\.value" | awk -F "'" '{print $2}' | sed 's/xOS\/Probe@/v/g')
    fi

    if [ ! -n "$version" ]; then
        echo -e "获取版本号失败，请检查本机能否链接 https://api.github.com/repos/xOS/Probe/releases/latest"
        return 0
    else
        echo -e "当前最新版本为: ${version}"
    fi

    # 楠格探针文件夹
    mkdir -p $AGENT_PATH
    chmod 777 -R $AGENT_PATH

    echo -e "正在下载探针端"
    wget -O probe-agent_linux_${os_arch}.tar.gz https://${GITHUB_URL}/xos/probe/releases/download/${version}/probe-agent_linux_${os_arch}.tar.gz >/dev/null 2>&1
    if [[ $? != 0 ]]; then
        echo -e "${red}Release 下载失败，请检查本机能否连接 ${GITHUB_URL}${plain}"
        return 0
    fi
    tar xf probe-agent_linux_${os_arch}.tar.gz &&
        chmod +x probe-agent &&
        mv probe-agent $AGENT_PATH &&
        rm -rf probe-agent_linux_${os_arch}.tar.gz README.md

    if [[ $# == 3 ]]; then
        modify_agent_config $1 $2 $3
    else
        modify_agent_config 0
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

update_agent() {
    echo -e "> 更新Agent"

    echo -e "正在获取探针Agent版本号"

    local version=$(curl -m 10 -sL "https://api.github.com/repos/xOS/Probe/releases/latest" | grep "tag_name" | head -n 1 | awk -F ":" '{print $2}' | sed 's/\"//g;s/,//g;s/ //g')
    if [ ! -n "$version" ]; then
        version=$(curl -m 10 -sL "https://cdn.jsdelivr.net/gh/xOS/Probe/" | grep "option\.value" | awk -F "'" '{print $2}' | sed 's/xOS\/Probe@/v/g')
    fi

    if [ ! -n "$version" ]; then
        echo -e "获取版本号失败，请检查本机能否链接 https://api.github.com/repos/xOS/Probe/releases/latest"
        return 0
    else
        echo -e "当前最新版本为: ${version}"
    fi

    # 楠格探针文件夹
    chmod 777 -R $AGENT_PATH

    echo -e "正在下载最新版探针端"
    wget -O probe-agent_linux_${os_arch}.tar.gz https://${GITHUB_URL}/xos/probe/releases/download/${version}/probe-agent_linux_${os_arch}.tar.gz >/dev/null 2>&1
    if [[ $? != 0 ]]; then
        echo -e "${red}Release 下载失败，请检查本机能否连接 ${GITHUB_URL}${plain}"
        return 0
    fi
    tar xf probe-agent_linux_${os_arch}.tar.gz &&
        chmod +x probe-agent &&
        mv probe-agent $AGENT_PATH &&
        systemctl restart probe-agent
        rm -rf probe-agent_linux_${os_arch}.tar.gz README.md

    if [[ $# == 0 ]]; then
        echo -e "更新完毕！"
        before_show_menu
    fi
}

modify_agent_config() {
    echo -e "> 修改Agent配置"

    wget -O $AGENT_SERVICE https://${GITHUB_RAW_URL}/script/probe-agent.service >/dev/null 2>&1
    if [[ $? != 0 ]]; then
        echo -e "${red}文件下载失败，请检查本机能否连接 ${GITHUB_RAW_URL}${plain}"
        return 0
    fi
    if [[ $# != 3 ]]; then
        echo "请先在管理面板上添加Agent，记录下密钥" &&
            read -ep "请输入一个解析到面板所在IP的域名（不可套CDN）: " grpc_host &&
            read -ep "请输入面板RPC端口: (2222)" grpc_port &&
            read -ep "请输入Agent 密钥: " client_secret
        if [[ -z "${grpc_host}" || -z "${client_secret}" ]]; then
            echo -e "${red}所有选项都不能为空${plain}"
            before_show_menu
            return 1
        fi

        if [[ -z "${grpc_port}" ]]; then
            grpc_port=2222
        fi
    else
        grpc_host=$1
        grpc_port=$2
        client_secret=$3
    fi

    sed -i "s/grpc_host/${grpc_host}/" ${AGENT_SERVICE}
    sed -i "s/grpc_port/${grpc_port}/" ${AGENT_SERVICE}
    sed -i "s/client_secret/${client_secret}/" ${AGENT_SERVICE}

    echo -e "Agent配置 ${green}修改成功，请稍等重启生效${plain}"

    systemctl daemon-reload
    systemctl enable probe-agent
    systemctl restart probe-agent

    if [[ $# == 0 ]]; then
        echo -e "Agent 已重启完毕！"
        before_show_menu
    fi
}

modify_dashboard_config() {
    echo -e "> 修改面板配置"

    echo -e "正在下载 Docker 脚本"
    wget -O ${DASHBOARD_PATH}/docker-compose.yaml https://${GITHUB_RAW_URL}/script/docker-compose.yaml >/dev/null 2>&1
    if [[ $? != 0 ]]; then
        echo -e "${red}下载脚本失败，请检查本机能否连接 ${GITHUB_RAW_URL}${plain}"
        return 0
    fi

    mkdir -p $DASHBOARD_PATH/data

    wget -O ${DASHBOARD_PATH}/data/config.yaml https://${GITHUB_RAW_URL}/script/config.yaml >/dev/null 2>&1
    if [[ $? != 0 ]]; then
        echo -e "${red}下载脚本失败，请检查本机能否连接 ${GITHUB_RAW_URL}${plain}"
        return 0
    fi

    echo "关于 GitHub Oauth2 应用：在 https://github.com/settings/developers 创建，无需审核，Callback 填 http(s)://域名或IP/oauth2/callback" &&
        echo "关于 Gitee Oauth2 应用：在 https://gitee.com/oauth/applications 创建，无需审核，Callback 填 http(s)://域名或IP/oauth2/callback" &&
        read -ep "请输入 OAuth2 提供商(gitee/github，默认 github): " oauth2_type &&
        read -ep "请输入 Oauth2 应用的 Client ID: " github_oauth_client_id &&
        read -ep "请输入 Oauth2 应用的 Client Secret: " github_oauth_client_secret &&
        read -ep "请输入 GitHub/Gitee 登录名作为管理员，多个以逗号隔开: " admin_logins &&
        read -ep "请输入站点标题: " site_title &&
        read -ep "请输入站点访问端口: (8008)" site_port &&
        read -ep "请输入用于 Agent 接入的 RPC 域名: (默认为空)" grpc_host &&
        read -ep "请输入用于 Agent 接入的 RPC 端口: (2222)" grpc_port

    if [[ -z "${admin_logins}" || -z "${github_oauth_client_id}" || -z "${github_oauth_client_secret}" || -z "${site_title}" ]]; then
        echo -e "${red}所有选项都不能为空${plain}"
        before_show_menu
        return 1
    fi

    if [[ -z "${site_port}" ]]; then
        site_port=8008
    fi
    if [[ -z "${grpc_host}" ]]; then
        grpc_host=''
    fi
    if [[ -z "${grpc_port}" ]]; then
        grpc_port=2222
    fi
    if [[ -z "${oauth2_type}" ]]; then
        oauth2_type=github
    fi

    sed -i "s/oauth2_type/${oauth2_type}/" ${DASHBOARD_PATH}/data/config.yaml
    sed -i "s/admin_logins/${admin_logins}/" ${DASHBOARD_PATH}/data/config.yaml
    sed -i "s/grpc_host/$grpc_host}/" ${DASHBOARD_PATH}/data/config.yaml
    sed -i "s/grpc_port/$grpc_port}/" ${DASHBOARD_PATH}/data/config.yaml
    sed -i "s/github_oauth_client_id/${github_oauth_client_id}/" ${DASHBOARD_PATH}/data/config.yaml
    sed -i "s/github_oauth_client_secret/${github_oauth_client_secret}/" ${DASHBOARD_PATH}/data/config.yaml
    sed -i "s/site_title/${site_title}/" ${DASHBOARD_PATH}/data/config.yaml
    sed -i "s/site_port/${site_port}/" ${DASHBOARD_PATH}/docker-compose.yaml
    sed -i "s/grpc_port/${grpc_port}/g" ${DASHBOARD_PATH}/docker-compose.yaml
    sed -i "s/image_url/${Docker_IMG}/" ${DASHBOARD_PATH}/docker-compose.yaml

    echo -e "面板配置 ${green}修改成功，请稍等重启生效${plain}"

    restart_and_update

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

restart_and_update() {
    echo -e "> 重启并更新面板"

    cd $DASHBOARD_PATH
    docker-compose pull
    docker-compose down
    docker-compose up -d
    if [[ $? == 0 ]]; then
        echo -e "${green}楠格探针 重启成功${plain}"
        echo -e "默认管理面板地址：${yellow}域名:站点访问端口${plain}"
    else
        echo -e "${red}重启失败，可能是因为启动时间超过了两秒，请稍后查看日志信息${plain}"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

start_dashboard() {
    echo -e "> 启动面板"

    cd $DASHBOARD_PATH && docker-compose up -d
    if [[ $? == 0 ]]; then
        echo -e "${green}楠格探针 启动成功${plain}"
    else
        echo -e "${red}启动失败，请稍后查看日志信息${plain}"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

stop_dashboard() {
    echo -e "> 停止面板"

    cd $DASHBOARD_PATH && docker-compose down
    if [[ $? == 0 ]]; then
        echo -e "${green}楠格探针 停止成功${plain}"
    else
        echo -e "${red}停止失败，请稍后查看日志信息${plain}"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

show_dashboard_log() {
    echo -e "> 获取面板日志"

    cd $DASHBOARD_PATH && docker-compose logs -f

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

uninstall_dashboard() {
    echo -e "> 卸载管理面板"

    cd $DASHBOARD_PATH &&
        docker-compose down
    rm -rf $DASHBOARD_PATH
    docker rmi -f ghcr.io/xos/probe-dashboard > /dev/null 2>&1
    docker rmi -f registry.cn-shanghai.aliyuncs.com/dns/probe-dashboard > /dev/null 2>&1
    clean_all

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

show_agent_log() {
    echo -e "> 获取Agent日志"

    systemctl status probe-agent.service

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

uninstall_agent() {
    echo -e "> 卸载Agent"

    systemctl disable probe-agent.service
    systemctl stop probe-agent.service
    rm -rf $AGENT_SERVICE
    systemctl daemon-reload

    rm -rf $AGENT_PATH
    clean_all

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

restart_agent() {
    echo -e "> 重启Agent"

    systemctl restart probe-agent.service

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

clean_all() {
    if [ -z "$(ls -A ${BASE_PATH})" ]; then
        rm -rf ${BASE_PATH}
    fi
}

show_usage() {
    echo "楠格探针 管理脚本使用方法: "
    echo "--------------------------------------------------------"
    echo "./probe.sh                            - 显示管理菜单"
    echo "./probe.sh install_dashboard          - 安装面板端"
    echo "./probe.sh modify_dashboard_config    - 修改面板配置"
    echo "./probe.sh start_dashboard            - 启动面板"
    echo "./probe.sh stop_dashboard             - 停止面板"
    echo "./probe.sh restart_and_update         - 重启并更新面板"
    echo "./probe.sh show_dashboard_log         - 查看面板日志"
    echo "./probe.sh uninstall_dashboard        - 卸载管理面板"
    echo "--------------------------------------------------------"
    echo "./probe.sh install_agent              - 安装探针Agent"
    echo "./probe.sh update_agent              	- 更新探针Agent"
    echo "./probe.sh modify_agent_config        - 修改Agent配置"
    echo "./probe.sh show_agent_log             - 查看Agent日志"
    echo "./probe.sh uninstall_agent            - 卸载Agen"
    echo "./probe.sh restart_agent              - 重启Agen"
    echo "./probe.sh update_script              - 更新脚本"
    echo "--------------------------------------------------------"
}

show_menu() {
    clear
    echo -e "
    =========================
    ${green}楠格探针管理脚本${plain} ${red}[${VERSION}]${plain}
    =========================
    ${green}1.${plain}  安装面板端
    ${green}2.${plain}  修改面板配置
    ${green}3.${plain}  启动面板
    ${green}4.${plain}  停止面板
    ${green}5.${plain}  重启并更新面板
    ${green}6.${plain}  查看面板日志
    ${green}7.${plain}  卸载管理面板
    —————————————————————————
    ${green}8.${plain}  安装探针Agent
    ${green}9.${plain}  更新探针Agent
    ${green}10.${plain} 修改Agent配置
    ${green}11.${plain} 查看Agent日志
    ${green}12.${plain} 卸载Agent
    ${green}13.${plain} 重启Agent
    —————————————————————————
    ${green}14.${plain} 更新脚本
    —————————————————————————
    ${green}0.${plain}  退出脚本
    =========================
    "
    echo && read -ep "请输入选择 [0-14]: " num

    case "${num}" in
    0)
        exit 0
        ;;
    1)
        install_dashboard
        ;;
    2)
        modify_dashboard_config
        ;;
    3)
        start_dashboard
        ;;
    4)
        stop_dashboard
        ;;
    5)
        restart_and_update
        ;;
    6)
        show_dashboard_log
        ;;
    7)
        uninstall_dashboard
        ;;
    8)
        install_agent
        ;;
    9)
        update_agent
        ;;
    10)
        modify_agent_config
        ;;
    11)
        show_agent_log
        ;;
    12)
        uninstall_agent
        ;;
    13)
        restart_agent
        ;;
    14)
        update_script
        ;;
    *)
        echo -e "${red}请输入正确的数字 [0-14]${plain}"
        ;;
    esac
}

pre_check

if [[ $# > 0 ]]; then
    case $1 in
    "install_dashboard")
        install_dashboard 0
        ;;
    "modify_dashboard_config")
        modify_dashboard_config 0
        ;;
    "start_dashboard")
        start_dashboard 0
        ;;
    "stop_dashboard")
        stop_dashboard 0
        ;;
    "restart_and_update")
        restart_and_update 0
        ;;
    "show_dashboard_log")
        show_dashboard_log 0
        ;;
    "uninstall_dashboard")
        uninstall_dashboard 0
        ;;
    "install_agent")
        if [[ $# == 4 ]]; then
            install_agent $2 $3 $4
        else
            install_agent 0
        fi
        ;;
    "modify_agent_config")
        modify_agent_config 0
        ;;
    "show_agent_log")
        show_agent_log 0
        ;;
    "uninstall_agent")
        uninstall_agent 0
        ;;
    "restart_agent")
        restart_agent 0
        ;;
    "update_script")
        update_script 0
        ;;
    *) show_usage ;;
    esac
else
    show_menu
fi
