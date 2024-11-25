#!/bin/bash

# 选择语言
echo "请选择语言(Please select a language)："
echo "1. 中文"
echo "2. English"
read -p "请输入选项 (1 或 2): " LANG_CHOICE

# 根据选择设置语言变量
if [ "$LANG_CHOICE" == "1" ]; then
    LANG="zh"
elif [ "$LANG_CHOICE" == "2" ]; then
    LANG="en"
else
    echo "无效的选项，使用默认语言：中文"
    LANG="zh"
fi

# 根据语言选择显示提示语
if [ "$LANG" == "zh" ]; then
    # 显示提示语
    echo "┌──────────────────────────────────────────────────────────┐"
    echo "│      本项目基于xxxuuu大佬的fnos-qb-proxy项目进行修改     │"
    echo "│                      感谢大佬的贡献                      │"
    echo "│             本脚本旨在方便用户进行自定义配置             │"
    echo "│                 具体根据脚本提示进行即可                 │"
    echo "└──────────────────────────────────────────────────────────┘"

    # 检测系统内是否含有fnos-qb-proxy服务
    if systemctl list-unit-files | grep -q "fnos-qb-proxy.service"; then
        echo "系统中已存在该服务，是否删除"
        echo "yes：删除服务并退出脚本；no：直接退出脚本"
        read -p "您想删除现有的服务和文件吗？(yes/no): " DELETE_SERVICE
        DELETE_SERVICE=$(echo "$DELETE_SERVICE" | tr '[:upper:]' '[:lower:]')
        if [ "$DELETE_SERVICE" == "yes" ]; then
            echo "正在删除现有服务和文件..."
            sudo systemctl stop fnos-qb-proxy
            sudo systemctl disable fnos-qb-proxy
            sudo rm -f /etc/systemd/system/fnos-qb-proxy.service
            sudo rm -f /usr/local/bin/fnos-qb-proxy
            sudo systemctl daemon-reload
            echo "现有服务和文件已删除。"
            exit 0
        else
            echo "退出脚本且不进行更改"
            exit 0
        fi
    fi

    # 获取当前用户名
    USER=$(whoami)

    # 提示用户输入配置文件路径
    echo "------------------------------------------------------------"
    echo "请输入端口配置文件存放位置"
    echo "请注意vol后面的序号是否与你的存储空间对应，回车采用默认存放地址"
    read -p "请输入配置文件路径 (默认: /vol1/1000/config/fnqb.conf): " CONFIG_FILE
    CONFIG_FILE=${CONFIG_FILE:-/vol1/1000/config/fnqb.conf}

    # 检查配置文件是否存在，如果不存在则提示用户输入端口号
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "请输入端口号，请注意避免端口冲突，默认28080"
        read -p "请输入端口号 (默认: 28080): " PORT
        # 检查是否提供了端口号，如果没有提供则使用默认值
        PORT=${PORT:-28080}
        # 创建配置文件目录
        mkdir -p "$(dirname $CONFIG_FILE)"
        # 写入配置文件
        echo "port=$PORT" > "$CONFIG_FILE"
        echo "配置文件已创建于 $CONFIG_FILE"
    else
        # 询问是否直接采用现有配置文件
        read -p "是否直接采用现有配置文件？(yes/no): " USE_EXISTING_CONFIG
        USE_EXISTING_CONFIG=$(echo "$USE_EXISTING_CONFIG" | tr '[:upper:]' '[:lower:]')
        if [ "$USE_EXISTING_CONFIG" == "yes" ]; then
            # 读取配置文件中的端口号
            PORT=$(grep -Po '(?<=port=)\d+' "$CONFIG_FILE")
            if [ -z "$PORT" ]; then
                echo "配置文件中的端口号无效: $CONFIG_FILE"
                exit 1
            fi
        else
            echo "请输入端口号，请注意避免端口冲突，默认28080"
            read -p "请输入端口号 (默认: 28080): " PORT
            # 检查是否提供了端口号，如果没有提供则使用默认值
            PORT=${PORT:-28080}
            # 更新配置文件中的端口号
            sed -i "s/^port=.*/port=$PORT/" "$CONFIG_FILE"
            echo "配置文件已更新：$CONFIG_FILE"
        fi
    fi

    echo "正在拉取项目中，预计总占用10mb"
    echo "请输入仓库 URL，默认为 https://github.com/EWEDLCM/fnos-qb-proxy.git"
    read -p "请输入仓库 URL (直接回车保持默认): " REPO_URL
    REPO_URL=${REPO_URL:-https://github.com/EWEDLCM/fnos-qb-proxy.git}
    while true; do
        echo "克隆仓库 $REPO_URL 到 fnos-qb-proxy 目录中..."
        git clone --depth 1 "$REPO_URL" fnos-qb-proxy

        # 检查克隆是否成功
        if [ $? -eq 0 ]; then
            break
        else
            echo "克隆仓库失败，请检查输入的仓库 URL 是否正确。"
            read -p "是否重新输入仓库 URL？(yes/no): " TRY_AGAIN
            TRY_AGAIN=$(echo "$TRY_AGAIN" | tr '[:upper:]' '[:lower:]')
            if [ "$TRY_AGAIN" == "yes" ]; then
                read -p "请输入新的仓库 URL: " REPO_URL
            else
                echo "退出脚本。"
                exit 1
            fi
        fi
    done
    cd fnos-qb-proxy

    # 检查是否安装了Go
    if ! command -v go &> /dev/null; then
        echo "未安装Go。正在安装Go..."
        # 根据操作系统安装Go
        if [[ "$OSTYPE" == "linux"* ]]; then
            sudo apt-get update
            sudo apt-get install -y golang
        elif [[ "$OSTYPE" == "darwin"* ]]; then
            brew install go
        else
            echo "不支持的操作系统: $OSTYPE"
            exit 1
        fi
    fi

    # 移除 go.mod 文件中的 Go 版本声明
    if grep -q '^go ' go.mod; then
        sed -i '/^go /d' go.mod
        echo "已从 go.mod 中移除 Go 版本声明"
    else
        echo "go.mod 中未找到 Go 版本声明"
    fi

    # 下载所有依赖项并更新 go.sum 文件
    go mod download

    # 编译Go程序
    GOOS=linux GOARCH=amd64 go build -o fnos-qb-proxy_linux-amd64

    # 检查编译结果
    if [ $? -ne 0 ]; then
        echo "编译失败！"
        exit 1
    fi
    echo "编译成功！"

    # 询问是否将服务添加到 systemd
    echo "------------------------------------------------------------"
    read -p "您想将服务添加到 systemd 吗？(yes/no): " ADD_TO_SYSTEMD
    ADD_TO_SYSTEMD=$(echo "$ADD_TO_SYSTEMD" | tr '[:upper:]' '[:lower:]')

    if [ "$ADD_TO_SYSTEMD" == "yes" ]; then
        # 创建 systemd 服务文件
        SERVICE_FILE="/etc/systemd/system/fnos-qb-proxy.service"
        echo "[Unit]
Description=fnOS qBittorrent Proxy Service
After=network.target

[Service]
User=$USER
ExecStart=/usr/local/bin/fnos-qb-proxy --uds \"/home/$USER/qbt.sock\" --config \"$CONFIG_FILE\"
Restart=always

[Install]
WantedBy=multi-user.target" | sudo tee $SERVICE_FILE > /dev/null

        # 将编译后的程序文件移动到 /usr/local/bin
        sudo mv fnos-qb-proxy_linux-amd64 /usr/local/bin/fnos-qb-proxy
        # 启用并启动服务
        sudo systemctl daemon-reload
        sudo systemctl enable fnos-qb-proxy
        sudo systemctl start fnos-qb-proxy

        echo "fnos-qb-proxy 服务已成功添加到 systemd 并启动。"
        
        # 直接跳到最后的提示语
        read -p "脚本结束，按回车键可退出脚本"
        exit 0
    fi
    # 最后的提示语
    echo "------------------------------------------------------------"
    read -p "脚本结束，按回车键可退出脚本"
    exit 0
elif [ "$LANG" == "en" ]; then
    # Display prompts
    echo "This project is based on the fnos-qb-proxy project modified by xxxuuu"
    echo "Thank you for your contribution"
    echo "This script aims to facilitate user customization, adding functions to install and uninstall services"
    echo "Please follow the script prompts"
    echo "------------------------------------------------------------"

    # Check if the system contains the fnos-qb-proxy service
    if systemctl list-unit-files | grep -q "fnos-qb-proxy.service"; then
        echo "The service already exists in the system"
        echo "yes: Delete the service and exit the script; no: Exit the script directly"
        read -p "Do you want to delete the existing service and files? (yes/no): " DELETE_SERVICE
        DELETE_SERVICE=$(echo "$DELETE_SERVICE" | tr '[:upper:]' '[:lower:]')
        if [ "$DELETE_SERVICE" == "yes" ]; then
            echo "Deleting existing service and files..."
            sudo systemctl stop fnos-qb-proxy
            sudo systemctl disable fnos-qb-proxy
            sudo rm -f /etc/systemd/system/fnos-qb-proxy.service
            sudo rm -f /usr/local/bin/fnos-qb-proxy
            sudo systemctl daemon-reload
            echo "Existing service and files have been deleted."
            exit 0
        else
            echo "Exiting script without making changes"
            exit 0
        fi
    fi

    # Get current username
    USER=$(whoami)

    # Prompt user to input configuration file path
    echo "Please enter the location to store the port configuration file, note the number after vol should match your storage space, press Enter to use the default location"
    read -p "Please enter the configuration file path (default: /vol1/1000/config/fnqb.conf): " CONFIG_FILE
    CONFIG_FILE=${CONFIG_FILE:-/vol1/1000/config/fnqb.conf}

    # Check if the configuration file exists, if not prompt the user to enter the port number
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "Please enter the port number, be aware of port conflicts, default 28080"
        read -p "Please enter the port number (default: 28080): " PORT
        # Check if a port number was provided, if not use the default value
        PORT=${PORT:-28080}
        # Create the configuration file directory
        mkdir -p "$(dirname $CONFIG_FILE)"
        # Write to the configuration file
        echo "port=$PORT" > "$CONFIG_FILE"
        echo "Configuration file created at $CONFIG_FILE"
    else
        # Ask if the user wants to use the existing configuration file
        read -p "Do you want to use the existing configuration file? (yes/no): " USE_EXISTING_CONFIG
        USE_EXISTING_CONFIG=$(echo "$USE_EXISTING_CONFIG" | tr '[:upper:]' '[:lower:]')
        if [ "$USE_EXISTING_CONFIG" == "yes" ]; then
            # Read the port number from the configuration file
            PORT=$(grep -Po '(?<=port=)\d+' "$CONFIG_FILE")
            if [ -z "$PORT" ]; then
                echo "Invalid port number in configuration file: $CONFIG_FILE"
                exit 1
            fi
        else
            echo "Please enter the port number, be aware of port conflicts, default 28080"
            read -p "Please enter the port number (default: 28080): " PORT
            # Check if a port number was provided, if not use the default value
            PORT=${PORT:-28080}
            # Update the port number in the configuration file
            sed -i "s/^port=.*/port=$PORT/" "$CONFIG_FILE"
            echo "Configuration file updated: $CONFIG_FILE"
        fi
    fi

    echo "Fetching the project, estimated total size 10mb"
    # Get repository URL, default to your GitHub repository
    read -p "Please enter the repository URL (default: https://github.com/EWEDLCM/fnos-qb-proxy.git): " REPO_URL
    REPO_URL=${REPO_URL:-https://github.com/EWEDLCM/fnos-qb-proxy.git}

    # Clone repository
    echo "Cloning repository $REPO_URL to fnos-qb-proxy directory..."
    git clone --depth 1 "$REPO_URL" fnos-qb-proxy
    if [ $? -ne 0 ]; then
        echo "Failed to clone repository, please check the URL and try again."
        exit 1
    fi
    cd fnos-qb-proxy

    # Check if Go is installed
    if ! command -v go &> /dev/null; then
        echo "Go is not installed. Installing Go..."
        # Install Go based on the operating system
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

    # Remove Go version declaration from go.mod file
    if grep -q '^go ' go.mod; then
        sed -i '/^go /d' go.mod
        echo "Removed go version declaration from go.mod"
    else
        echo "No go version declaration found in go.mod"
    fi

    # Download all dependencies and update go.sum file
    go mod download

    # Build the Go program
    GOOS=linux GOARCH=amd64 go build -o fnos-qb-proxy_linux-amd64
    if [ $? -ne 0 ]; then
        echo "Build failed!"
        exit 1
    fi
    echo "Build successful!"

    # Ask if the user wants to add the service to systemd
    echo "------------------------------------------------------------"
    read -p "Do you want to add the service to systemd? (yes/no): " ADD_TO_SYSTEMD
    ADD_TO_SYSTEMD=$(echo "$ADD_TO_SYSTEMD" | tr '[:upper:]' '[:lower:]')

    if [ "$ADD_TO_SYSTEMD" == "yes" ]; then
        # Create systemd service file
        SERVICE_FILE="/etc/systemd/system/fnos-qb-proxy.service"
        echo "[Unit]
Description=fnOS qBittorrent Proxy Service
After=network.target

[Service]
User=$USER
ExecStart=/usr/local/bin/fnos-qb-proxy --uds \"/home/$USER/qbt.sock\" --config \"$CONFIG_FILE\"
Restart=always

[Install]
WantedBy=multi-user.target" | sudo tee $SERVICE_FILE > /dev/null

        # Move the compiled binary to /usr/local/bin
        sudo mv fnos-qb-proxy_linux-amd64 /usr/local/bin/fnos-qb-proxy
        # Enable and start the service
        sudo systemctl daemon-reload
        sudo systemctl enable fnos-qb-proxy
        sudo systemctl start fnos-qb-proxy

        echo "fnos-qb-proxy service has been successfully added to systemd and started."
        
        # Final message
        read -p "Script finished, press Enter to exit"
        exit 0
    fi
    # Final message
    echo "------------------------------------------------------------"
    read -p "Script finished, press Enter to exit"
    exit 0
fi
