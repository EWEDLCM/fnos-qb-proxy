#!/bin/bash

# 删除已存在的目录和文件
if [ -d "fnos-qb-proxy" ]; then
    echo "Deleting existing directory 'fnos-qb-proxy'..."
    rm -rf fnos-qb-proxy
fi

# 提示用户输入端口号
read -p "Please enter the port number: " PORT

# 检查是否提供了端口号
if [ -z "$PORT" ]; then
    echo "Port number cannot be empty!"
    exit 1
fi

# 获取仓库URL，默认为你的GitHub仓库
read -p "Enter the repository URL (default: https://github.com/EWEDLCM/fnos-qb-proxy.git): " REPO_URL
REPO_URL=${REPO_URL:-https://github.com/EWEDLCM/fnos-qb-proxy.git}

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

# 设置环境变量
export FNOS_QB_PROXY_PORT=$PORT

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

# 显示完成信息
echo "fnos-qb-proxy has been compiled and is ready to use as fnos-qb-proxy_linux-amd64"
