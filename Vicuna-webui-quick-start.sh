#!/bin/bash

# 激活conda环境
echo "激活conda环境: fastchat..."
source ~/anaconda3/bin/activate fastchat

# 查找并终止占用8809端口的进程
echo "查找并终止占用8809端口的进程..."
lsof -t -i :8809 | xargs kill -9 2>/dev/null || true

# 定义一个函数来关闭进程
cleanup() {
    echo "正在关闭进程..."
    for pid in $controller_pid $worker_pid $test_pid $server_pid
    do
        pkill -P $pid
        kill $pid 2>/dev/null || true
    done
    echo "清理占用GPU的Python进程...使用nvidia-smi杀死全部Python进程"
    nvidia-smi | awk '/python3.9/ {print $5}' | xargs -I{} kill -9 {}
}

# 在接收到 EXIT 信号时调用 cleanup 函数
trap cleanup EXIT

cd ~/Vicuna
echo "切换到工作目录"

echo "启动控制器..."
python -m fastchat.serve.controller --host 0.0.0.0 &
controller_pid=$!
sleep 10

# 询问用户选择模型
echo "请选择模型："
echo "1) vicuna-7b"
echo "2) vicuna-13b"
read -p "输入选择的数字： " model_choice

case $model_choice in
  1) model_name="vicuna-7b"
     model_path="./vicuna-7b"
     ;;
  2) model_name="vicuna-13b"
     model_path="./vicuna-13b"
     ;;
  *) echo "无效的选择。默认使用vicuna-7b。"
     model_name="vicuna-7b"
     model_path="./vicuna-7b"
     ;;
esac

echo "启动模型工作进程...等待20秒保证程序完全启动"
python -m fastchat.serve.model_worker --model-path $model_path --model-name $model_name --host 0.0.0.0  --num-gpus 2 &
worker_pid=$!
sleep 20

echo "测试模型..."
python -m fastchat.serve.test_message --model-name $model_name &
test_pid=$!
sleep 10

echo "如果测试成功，启动web服务器..."
python -m fastchat.serve.gradio_web_server --port 8809 &
server_pid=$!

# 获取主机IP地址
ip_address=$(hostname -I | cut -d' ' -f1)
echo "服务器已启动，你可以在浏览器中访问 http://${ip_address}:8809 进行交互。"

disown $controller_pid $worker_pid $test_pid $server_pid

# 在脚本退出前等待
while true; do sleep 1; done

