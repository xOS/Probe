# 楠格探针
> 本项目为原项目[哪吒探针](https://github.com/naiba/nezha)的修改自用版

![GitHub Workflow Status](https://img.shields.io/github/workflow/status/xOS/Probe/Dashboard%20image?label=管理面板%20v2.4.12&logo=github&style=for-the-badge) ![Agent release](https://img.shields.io/github/v/release/xOS/Probe?color=brightgreen&label=Agent&style=for-the-badge&logo=github) ![GitHub Workflow Status](https://img.shields.io/github/workflow/status/xOS/Probe/Agent%20release?label=Agent%20CI&logo=github&style=for-the-badge) ![shell](https://img.shields.io/badge/安装脚本-v2.3.1-brightgreen?style=for-the-badge&logo=linux)

一款探针。支持系统状态、HTTP(SSL 证书变更、即将到期、到期)、TCP、Ping 监控报警，命令批量执行和计划任务。

## 演示图
![首页截图1](https://github.com/xOS/Probe/raw/master/resource/%E6%88%AA%E5%B1%8F2021-08-20%2017.54.57.png)

## 安装脚本

**推荐配置：** 安装前解析 _两个域名_ 到面板服务器，一个作为 _公开访问_ ，可以 **接入CDN**；另外一个作为安装 Agent 时连接 Dashboard 使用，**不能接入CDN** 直接暴露面板主机IP。

```shell
curl -L https://git.io/probe.sh -o probe.sh && chmod +x probe.sh
sudo ./probe.sh
```

<details>
    <summary>国内镜像加速：</summary>

```shell
curl -L https://cdn.jsdelivr.net/gh/xos/probe@master/script/probe.sh -o probe.sh && chmod +x probe.sh
CN=true sudo ./probe.sh
```

</details>

_\* 使用 WatchTower 可以自动更新面板，Windows 终端可以使用 nssm 配置自启动。_

### 增强配置

通过执行 `./probe-agent --help` 查看支持的参数，如果你使用一键脚本，可以编辑 `/etc/systemd/system/probe-agent.service`，在 `ExecStart=` 这一行的末尾加上

- `--report-delay` 系统信息上报的间隔，默认为 1 秒，可以设置为 3 来进一步降低 agent 端系统资源占用（配置区间 1-4）
- `--skip-conn` 不监控连接数，机场/连接密集型机器推荐设置，不然比较占 CPU([shirou/gopsutil/issues#220](https://github.com/shirou/gopsutil/issues/220))
- `--skip-procs` 不监控进程数，也可以降低 agent 占用
- `--disable-auto-update` 禁止 **自动更新** Agent（安全特性）
- `--disable-force-update` 禁止 **强制更新** Agent（安全特性）
- `--disable-command-execute` 禁止在 Agent 机器上执行定时任务、打开在线终端（安全特性）
- `--tls` 启用SSL/TLS加密（使用 nginx 反向代理 Agent 的 grpc 连接，并且 nginx 开启 SSL/TLS 时，需要启用该项配置）

## 功能说明

<details>
    <summary>计划任务：备份脚本、服务重启，等定期运维任务。</summary>

使用此功能可以定期结合 restic、rclone 给服务器备份，或者定期某项重启服务来重置网络连接。

</details>

<details>
    <summary>报警通知：负载、CPU、内存、硬盘、带宽、流量、月流量、进程数、连接数实时监控。</summary>

#### 灵活通知方式

`#NG#` 是面板消息占位符，面板触发通知时会自动替换占位符到实际消息

Body 内容是`JSON` 格式的：**当请求类型为 FORM 时**，值为 `key:value` 的形式，`value` 里面可放置占位符，通知时会自动替换。**当请求类型为 JSON 时** 只会简进行字符串替换后直接提交到`URL`。

URL 里面也可放置占位符，请求时会进行简单的字符串替换。

参考下方的示例，非常灵活。

1. 添加通知方式

   - server 酱示例

     - 名称：server 酱
     - URL：<https://sc.ftqq.com/SCUrandomkeys.send?text=#NG>#
     - 请求方式: GET
     - 请求类型: 默认
     - Body: 空

   - wxpusher 示例，需要关注你的应用

     - 名称: wxpusher
     - URL：<http://wxpusher.zjiecode.com/api/send/message>
     - 请求方式: POST
     - 请求类型: JSON
     - Body: `{"appToken":"你的appToken","topicIds":[],"content":"#NG#","contentType":"1","uids":["你的uid"]}`

   - telegram 示例 [@haitau](https://github.com/haitau) 贡献

     - 名称：telegram 机器人消息通知
     - URL：<https://api.telegram.org/botXXXXXX/sendMessage?chat_id=YYYYYY&text=#NG>#
     - 请求方式: GET
     - 请求类型: 默认
     - Body: 空
     - URL 参数获取说明：botXXXXXX 中的 XXXXXX 是在 telegram 中关注官方 @Botfather ，输入/newbot ，创建新的机器人（bot）时，会提供的 token（在提示 Use this token to access the HTTP API:后面一行）这里 'bot' 三个字母不可少。创建 bot 后，需要先在 telegram 中与 BOT 进行对话（随便发个消息），然后才可用 API 发送消息。YYYYYY 是 telegram 用户的数字 ID。与机器人@userinfobot 对话可获得。

2. 添加一个离线报警

   - 名称：离线通知
   - 规则：`[{"Type":"offline","Duration":10}]`
   - 启用：√

3. 添加一个监控 CPU 持续 10s 超过 50% **且** 内存持续 20s 占用低于 20% 的报警

   - 名称：CPU+内存
   - 规则：`[{"Type":"cpu","Min":0,"Max":50,"Duration":10},{"Type":"memory","Min":20,"Max":0,"Duration":20}]`
   - 启用：√

#### 报警规则说明

##### 基本规则

- type
  - `cpu`、`memory`、`swap`、`disk`
  - `net_in_speed` 入站网速、`net_out_speed` 出站网速、`net_all_speed` 双向网速、`transfer_in` 入站流量、`transfer_out` 出站流量、`transfer_all` 双向流量
  - `offline` 离线监控
  - `load1`、`load5`、`load15` 负载
  - `process_count` 进程数 _目前取线程数占用资源太多，暂时不支持_
  - `tcp_conn_count`、`udp_conn_count` 连接数
- duration：持续秒数，秒数内采样记录 30% 以上触发阈值才会报警（防数据插针）
- min/max
  - 流量、网速类数值 为字节（1KB=1024B，1MB = 1024\*1024B）
  - 内存、硬盘、CPU 为占用百分比
  - 离线监控无需设置
- cover `[{"type":"offline","duration":10, "cover":0, "ignore":{"5": true}}]`
  - `0` 监控所有，通过 `ignore` 忽略特定服务器
  - `1` 忽略所有，通过 `ignore` 监控特定服务器
- ignore: `{"1": true, "2":false}` 特定服务器，搭配 `cover` 使用

##### 特殊：任意周期流量报警

可以用作月流量报警

- type
  - transfer_in_cycle 周期内的入站流量
  - transfer_out_cycle 周期内的出站流量
  - transfer_all_cycle 周期内双向流量和
- cycle_start 周期开始日期（可以是你机器计费周期的开始日期）
- cycle_interval 小时（可以设为 1 月，30\*24）
- min/max、cover、ignore 参考基本规则配置
- 示例: ID 为 3 的机器（ignore 里面定义）的每月 15 号计费的出站月流量 1T 报警 `[{"type":"transfer_out_cycle","max":1000000000000,"cycle_start":"2021-07-15T08:00:00Z","cycle_interval":730,"cover":1,"ignore":{"3":true}}]`
</details>

<details>
    <summary>服务监控：HTTP、SSL证书、ping、TCP 端口等。</summary>

进入 `/monitor` 页面点击新建监控即可，表单下面有相关说明。

</details>

<details>
  <summary>自定义代码：改LOGO、改色调、加统计代码等。</summary>

- 默认主题更改进度条颜色示例

  ```
  <style>
  .ui.fine.progress> .bar {
      background-color: pink !important;
  }
  </style>
  ```

- 默认主题修改 LOGO、移除版权示例（来自 [@iLay1678](https://github.com/iLay1678)）

  ```
  <style>
  .right.menu>a{
  visibility: hidden;
  }
  .footer .is-size-7{
  visibility: hidden;
  }
  .item img{
  visibility: hidden;
  }
  </style>
  <script>
  window.onload = function(){
  var avatar=document.querySelector(".item img")
  var footer=document.querySelector("div.is-size-7")
  footer.innerHTML="Powered by 你的名字"
  footer.style.visibility="visible"
  avatar.src="你的方形logo地址"
  avatar.style.visibility="visible"
  }
  </script>
  ```

</details>

## 常见问题


<details>
    <summary>如何进行数据迁移、备份恢复？</summary>

1. 先使用一键脚本 `停止面板`
2. 打包 `/opt/probe/dashboard` 文件夹，到新环境相同位置
3. 使用一键脚本 `启动面板`

</details>


<details>
    <summary>Agent 启动/上线 问题自检流程</summary>

1. 直接执行 `/opt/probe/agent/probe-agent -s 面板IP或非CDN域名:面板RPC端口 -p Agent密钥 -d` 查看日志是否是 DNS 问题。
2. `nc -v 域名/IP 面板RPC端口` 或者 `telnet 域名/IP 面板RPC端口` 检验是否是网络问题，检查本机与面板服务器出入站防火墙，如果单机无法判断可借助 https://port.ping.pe/ 提供的端口检查工具进行检测。
3. 如果上面步骤检测正常，Agent 正常上线，尝试关闭 SELinux，[如何关闭 SELinux？](https://www.google.com/search?q=%E5%85%B3%E9%97%ADSELINUX)
</details>

<details>
    <summary>如何使 OpenWrt/LEDE 自启动？来自 @艾斯德斯</summary>

首先在 release 下载对应的二进制解压 tar.gz 包后放置到 `/root`，然后 `chmod +x /root/probe-agent` 赋予执行权限，然后创建 `/etc/init.d/probe-service`：

```shell
#!/bin/sh /etc/rc.common

START=99
USE_PROCD=1

start_service() {
	procd_open_instance
	procd_set_param command /root/probe-agent -s 面板网址:接收端口 -p 唯一秘钥 -d
	procd_set_param respawn
	procd_close_instance
}

stop_service() {
    killall probe-agent
}

restart() {
	stop
	sleep 2
	start
}
```

赋予执行权限 `chmod +x /etc/init.d/probe-service` 然后启动服务 `/etc/init.d/probe-service enable && /etc/init.d/probe-service start`

</details>

<details>
    <summary>提示实时通道断开？</summary>

### 启用 HTTPS

使用宝塔反代或者上 CDN，建议 Agent 配置 跟 访问管理面板 使用不同的域名，这样管理面板使用的域名可以直接套 CDN，Agent 配置的域名是解析管理面板 IP 使用的，也方便后面管理面板迁移（如果你使用 IP，后面 IP 更换了，需要修改每个 agent，就麻烦了）

### 实时通道断开(WebSocket 反代)

使用反向代理时需要针对 `/ws` 和`/terminal`路径的 WebSocket 进行特别配置以支持实时更新服务器状态和后台 SSH 的连接。

- Nginx(宝塔)：在你的 nginx 配置文件中加入以下代码

  ```nginx
  server{

      #原有的一些配置
      #server_name blablabla...

      location ~ ^/(ws|terminal/.+)$  {
          proxy_pass http://ip:站点访问端口;
          proxy_set_header Upgrade $http_upgrade;
          proxy_set_header Connection "Upgrade";
          proxy_set_header Host $host;
      }

      #其他的 location blablabla...
  }
  ```

  如果非宝塔，还要在 `server{}` 中添加上这一段

  ```nginx
  location / {
    proxy_pass http://ip:站点访问端口;
    proxy_set_header Host $host;
  }
  ```

- CaddyServer v1（v2 无需特别配置）

  ```Caddyfile
  proxy /ws http://ip:8008 {
      websocket
  }
  proxy /terminal/* http://ip:8008 {
      websocket
  }
  ```

</details>

<details>
    <summary>反向代理 gRPC 端口（支持 Cloudflare CDN）</summary>
使用 Nginx 或者 Caddy 反向代理 gRPC

- Nginx 配置

```nginx
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ip-to-dashboard.nai.ba; # 你的 Agent 连接 Dashboard 的域名

    ssl_certificate          /data/letsencrypt/fullchain.pem; # 你的域名证书路径
    ssl_certificate_key      /data/letsencrypt/key.pem;       # 你的域名私钥路径

    underscores_in_headers on;

    location / {
        grpc_read_timeout 300s;
        grpc_send_timeout 300s;
        grpc_pass grpc://localhost:5555;
    }
}
```

- Caddy 配置

```Caddyfile
ip-to-dashboard.nai.ba:443 { # 你的 Agent 连接 Dashboard 的域名
    reverse_proxy {
        to localhost:5555
        transport http {
            versions h2c 2
        }
    }
}
```


Dashboard 面板端配置

- 首先登录面板进入管理后台 打开设置页面，在 `未接入CDN的面板服务器域名/IP` 中填入上一步在 Nginx 或 Caddy 中配置的域名 比如 `ip-to-dashboard.nai.ba` ，并保存。
- 然后在面板服务器中，打开 /opt/probe/dashboard/data/config.yaml 文件，将 `proxygrpcport` 修改为 Nginx 或 Caddy 监听的端口，比如上一步设置的 `443` ；因为我们在 Nginx 或 Caddy 中开启了 SSL/TLS，所以需要将 `tls` 设置为 `true` ；修改完成后重启面板。


Agent 端配置

- 登录面板管理后台，复制一键安装命令，在对应的服务器上面执行一键安装命令重新安装 agent 端即可。


开启 Cloudflare CDN（可选）

根据 Cloudflare gRPC 的要求：gRPC 服务必须侦听 443 端口 且必须支持 TLS 和 HTTP/2。
所以如果需要开启CDN，必须在配置 Nginx 或者 Caddy 反向代理 gRPC 时使用 443 端口，并配置证书（Caddy 会自动申请并配置证书）。

- 登录 Cloudflare，选择使用的域名。打开 `网络` 选项将 `gRPC` 开关打开，打开 `DNS` 选项，找到 Nginx 或 Caddy 反代 gRPC 配置的域名的解析记录，打开橙色云启用CDN。

</details>
