#!/bin/bash

# 显示提示语
echo "本脚本基于xxxuuu大佬的fnos-qb-proxy项目进行修改，感谢大佬的贡献"
echo "本脚本旨在方便用户进行自定义配置，增加了安装和卸载服务的功能"
echo "具体根据脚本提示进行即可"
echo "---------------------------------------------------------"

# 检测系统内是否含有fnos-qb-proxy服务
echo "# 检测系统内是否含有fnos-qb-proxy服务"
if systemctl list-unit-files | grep -q "fnos-qb-proxy.service"; then
    echo "系统中已存在该服务，是否删除，请输入yes或no"
    echo "yes：删除服务并退出脚本；no：直接退出脚本"
    read -p "Do you want to delete the existing service and files? (yes/no): " DELETE_SERVICE
    DELETE_SERVICE=$(echo "$DELETE_SERVICE" | tr '[:upper:]' '[:lower:]')
    if [ "$DELETE_SERVICE" == "yes" ]; then
        echo "Deleting existing service and files..."
        sudo systemctl stop fnos-qb-proxy
        sudo systemctl disable fnos-qb-proxy
        sudo rm -f /etc/systemd/system/fnos-qb-proxy.service
        sudo rm -f /usr/local/bin/fnos-qb-proxy
        echo "Existing service and files have been deleted."
        exit 0
    else
        echo "Exiting script without making changes."
        exit 0
    fi
fi

# 获取当前用户名
USER=$(whoami)

# 提示用户输入配置文件路径
echo "请输入端口配置文件存放位置，请注意vol后面的序号是否与你的存储空间对应，回车采用默认存放地址"
echo "直接回车将采用默认存放地址：/vol1/1000/config/fnqb.conf"
read -p "Please enter the configuration file path (default: /vol1/1000/config/fnqb.conf): " CONFIG_FILE
CONFIG_FILE=${CONFIG_FILE:-/vol1/1000/config/fnqb.conf}

# 检查配置文件是否存在，如果不存在则提示用户输入端口号
echo "检查配置文件是否存在，如果不存在则提示用户输入端口号"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "请输入端口号，请注意避免端口冲突，默认28080"
    read -p "Please enter the port number (default: 28080): " PORT
    # 检查是否提供了端口号，如果没有提供则使用默认值
    PORT=${PORT:-28080}
    # 创建配置文件目录
    mkdir -p "$(dirname $CONFIG_FILE)"
    # 写入配置文件
    echo "port=$PORT" > "$CONFIG_FILE"
    echo "Configuration file created at $CONFIG_FILE"
else
    # 读取配置文件中的端口号
    PORT=$(grep -Po '(?<=port=)\d+' "$CONFIG_FILE")
    if [ -z "$PORT" ]; then
        echo "Invalid port number in configuration file: $CONFIG_FILE"
        exit 1
    fi
fi

echo "拉取项目中，预计总占用10mb"
# 获取仓库URL，默认为你的GitHub仓库
REPO_URL="https://github.com/EWEDLCM/fnos-qb-proxy.git"

# 克隆仓库
echo "Cloning repository from $REPO_URL..."
git clone "$REPO_URL" fnos-qb-proxy
cd fnos-qb-proxy

# 检查是否安装了Go
if ! command -v go &> /dev/null; then
    echo "Go is not installed. Installing Go..."
    # 根据操作系统安装Go
    if [[ "$OSTYPE" == "linux"* ]]; then
        sudo apt-get update
        sudo apt-get install -y golang
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        brew install go
    else
        echo "Unsupported operating system: $OSTYPE"
        exit 1
    fi
fi

# 移除 go.mod 文件中的 Go 版本声明
if grep -q '^go ' go.mod; then
    sed -i '/^go /d' go.mod
    echo "Removed go version declaration from go.mod"
else
    echo "No go version declaration found in go.mod"
fi

# 下载所有依赖项并更新 go.sum 文件
echo "Downloading dependencies and updating go.sum..."
go mod download

# 编译Go程序
echo "Compiling Go program..."
GOOS=linux GOARCH=amd64 go build -o fnos-qb-proxy_linux-amd64

# 检查编译结果
if [ $? -eq 0 ]; then
    echo "Compilation successful!"
else
    echo "Compilation failed!"
    exit 1
fi

echo "# 是否创建服务到 systemd以实现开机启动，输入yes或no"
read -p "Do you want to add the service to systemd? (yes/no): " ADD_TO_SYSTEMD
ADD_TO_SYSTEMD=$(echo "$ADD_TO_SYSTEMD" | tr '[:upper:]' '[:lower:]')

if [ "$ADD_TO_SYSTEMD" == "yes" ]; then
    # 创建 systemd 服务文件
    SERVICE_FILE="/etc/systemd/system/fnos-qb-proxy.service"
    echo "[Unit]
    Description=fnOS qBittorrent Proxy Service
    After=docker.service

    [Service]
    User=$USER
    ExecStart=/usr/local/bin/fnos-qb-proxy --uds \"/home/$USER/qbt.sock\" --port $PORT
    Restart=always

    [Install]
    WantedBy=multi-user.target" | sudo tee $SERVICE_FILE

    # 将二进制文件移动到 /usr/local/bin
    sudo mv fnos-qb-proxy_linux-amd64 /usr/local/bin/fnos-qb-proxy
    echo "# 重载并启用服务中"
    # 启用并启动服务
    sudo systemctl daemon-reload
    sudo systemctl enable fnos-qb-proxy
    sudo systemctl start fnos-qb-proxy

    # 检查服务状态
    sudo systemctl status fnos-qb-proxy

    echo "fnos-qb-proxy service has been successfully added to systemd and started."
    
    # 直接跳到最后的提示语
    read -p "脚本结束，回车可退出脚本"
    exit 0
fi

# 确保 qbt.sock 文件存在
QBT_SOCK="/home/$USER/qbt.sock"
if [ ! -S "$QBT_SOCK" ]; then
    echo "qbt.sock file does not exist at $QBT_SOCK. Please ensure qBittorrent is configured to use this socket."
    exit 1
fi

# 询问是否立即运行服务
read -p "Do you want to run the service now? (yes/no): " RUN_SERVICE
RUN_SERVICE=$(echo "$RUN_SERVICE" | tr '[:upper:]' '[:lower:]')

if [ "$RUN_SERVICE" == "yes" ]; then
    echo "Running fnos-qb-proxy on port $PORT..."
    ./fnos-qb-proxy_linux-amd64 --uds "$QBT_SOCK" --port $PORT
fi

# 最后的提示语
read -p "脚本结束，回车可退出脚本"
