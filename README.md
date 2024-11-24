# fnos-qb-proxy   由于无法持久化，项目暂不可用

## 项目出处?
本项目是出自于原作者xxxuuu的一个go程序，个人对项目中的部分代码逻辑做了修改，并制作了sh脚本方便部署

## 这是什么?
最近火热的fnOS 中自带了一个下载器（基于 qBittorrent 和 Aria2），但默认关闭了 WebUI，且采用动态密码。这使得我们无法在外部连接 fnOS 中的 qBittorrent（e.g. 接入 MoviePilot 或 NasTools 等）
该项目是一个简单的代理，利用用户目录下的sock进行联系，提供在外部访问 fnOS 的 qBittorrent 的能力同时不影响 fnOS 自身的下载器运行，并且可随时修改端口定义。

## 如何使用
使用以下代码进行部署即可，内有较为详细的注释提示，并做了双语支持
```
curl -s https://raw.githubusercontent.com/EWEDLCM/fnos-qb-proxy/main/fnos-qb.sh -o fnos-qb.sh && chmod +x fnos-qb.sh && ./fnos-qb.sh
```
## 注意事项
在部署前可能需要在飞牛的webui打开一次下载器界面，由此建立sock文化。如果忘了进行这一步，需要打开后在终端执行一次服务重启
```
sudo systemctl restart fnos-qb-proxy.service
```
最后，祝飞牛越来越好，也祝各位飞牛玩家玩的愉快

# fnos-qb-proxy

## Project Origin
This project is a Go program originally authored by xxxuuu. I have made some modifications to the code logic and created a shell script to facilitate deployment.

## What is This?
Recently, the popular fnOS comes with a built-in downloader (based on qBittorrent and Aria2), but the WebUI is disabled by default and uses a dynamic password. This makes it impossible to connect to the qBittorrent instance in fnOS from an external source (e.g., integrating with MoviePilot or NasTools).
This project is a simple proxy that uses a socket file in the user's directory to communicate, allowing external access to the qBittorrent instance in fnOS without affecting the operation of fnOS's built-in downloader. Additionally, it allows for easy modification of the port settings.

## How to Use
To deploy this project, simply run the following command. The script includes detailed comments and supports both Chinese and English.
```
curl -s https://raw.githubusercontent.com/EWEDLCM/fnos-qb-proxy/main/fnos-qb.sh -o fnos-qb.sh && chmod +x fnos-qb.sh && ./fnos-qb.sh
```

## Important Notes
Before deploying, you may need to open the downloader interface once in the fnOS web UI to establish the socket connection. If you forget to do this step, you will need to open the interface and then restart the service from the terminal:
```
sudo systemctl restart fnos-qb-proxy.service
```

Finally, I wish the best for the development of FnOS and hope that all users enjoy using it.
