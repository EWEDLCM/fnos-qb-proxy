## 项目出处?
本项目源于xxxuuu作者的fnos-qb-proxy项目，项目地址为：https://github.com/xxxuuu/fnos-qb-proxy（喜欢的可以给原作者点歌star，当然也可以给我点一个！）
经二次开发与优化，对其中的部分代码逻辑进行了调整，提升了易用性和灵活性，更好地满足使用需求。

## 这是什么?
最近火热的fnOS 中自带了一个下载器（基于 qBittorrent 和 Aria2），但默认关闭了 WebUI，且采用动态密码。这使得我们无法在外部连接 fnOS 中的 qBittorrent（e.g. 接入 MoviePilot 或 NasTools 等）
该项目是一个简单的代理，利用用户目录下的sock进行联系，提供在外部访问 fnOS 的 qBittorrent 的能力同时不影响 fnOS 自身的下载器运行，并且可随时修改端口定义。

## 如何使用
使用以下代码进行部署即可，内有较为详细的注释提示，并做了双语支持
```
curl -s https://raw.githubusercontent.com/EWEDLCM/fnos-qb-proxy/main/fnos-qb.sh -o fnos-qb.sh && chmod +x fnos-qb.sh && ./fnos-qb.sh
```
## 注意事项
本项目部署及使用时，需要确保下载器内有至少一个任务保持持续做种状态，由此来确保sock的持久化，否则将导致服务无法正常使用。
如果服务已经报错，请补充一个种子任务让其做种，而后执行以下命令重启本服务
```
sudo systemctl restart fnos-qb-proxy.service
```
最后，祝飞牛越来越好，也祝各位飞牛玩家玩的愉快

# fnos-qb-proxy

## Project Origin
This project originates from the fnos-qb-proxy project by author xxxuuu, available at: https://github.com/xxxuuu/fnos-qb-proxy (if you like it, feel free to give the original author a star, and of course, you can give me one too!)
After secondary development and optimization, adjustments have been made to some of the code logic to improve usability and flexibility, better meeting user needs.

## What is This?
Recently, the popular fnOS comes with a built-in downloader (based on qBittorrent and Aria2), but the WebUI is disabled by default and uses a dynamic password. This makes it impossible to connect to the qBittorrent instance in fnOS from an external source (e.g., integrating with MoviePilot or NasTools).
This project is a simple proxy that uses a socket file in the user's directory to communicate, allowing external access to the qBittorrent instance in fnOS without affecting the operation of fnOS's built-in downloader. Additionally, it allows for easy modification of the port settings.

## How to Use
To deploy this project, simply run the following command. The script includes detailed comments and supports both Chinese and English.
```
curl -s https://raw.githubusercontent.com/EWEDLCM/fnos-qb-proxy/main/fnos-qb.sh -o fnos-qb.sh && chmod +x fnos-qb.sh && ./fnos-qb.sh
```

## Important Notes
When deploying and using this project, ensure that there is at least one task in the downloader maintaining a continuous seeding state to ensure the persistence of the sock. Otherwise, it will result in the service failing to function properly.
If the service has already reported an error, add a seeding task and then execute the following command to restart the service：
```
sudo systemctl restart fnos-qb-proxy.service
```

Finally, I wish the best for the development of FnOS and hope that all users enjoy using it.
