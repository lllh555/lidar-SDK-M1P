# RoboSense LiDAR ROS2 Jazzy Deployment and Recording

## 克隆后部署（可复现版本）

部署脚本会根据脚本自身位置定位项目根目录，不要求克隆到固定路径。请在 WSL Ubuntu 24.04 中执行：

```bash
git clone https://github.com/lllh555/lidar-SDK-M1P.git
cd lidar-SDK-M1P
bash scripts/bootstrap_ros2_jazzy_rslidar.sh
```

脚本会初始化本仓库锁定提交的 `rslidar_sdk`、`rslidar_msg` 及其嵌套子模块，再构建 ROS 2 工作区。部署前请按实际设备检查并修改 `config/rslidar_sdk_config.yaml` 中的雷达型号与接收端口；电脑网卡 IP 仍需由部署者按现场网络配置。

启动时执行：

```bash
bash scripts/start_lidar.sh
```

如需使用其他设备配置，可通过 `LIDAR_SDK_CONFIG=/path/to/config.yaml bash scripts/start_lidar.sh` 指定配置文件。

本文档记录当前项目从部署 `rslidar_sdk` 到录制点云的完整流程。当前项目路径：

```text
Windows: E:\project\lidar-sdk
WSL:     /mnt/e/project/lidar-sdk
```

Windows 和 WSL 看到的是同一份文件。可以直接用 Windows VSCode 修改 `E:\project\lidar-sdk` 下的文件，WSL 中会同步看到。

## 1. 配置要求

先确认这些要求，再启动 SDK。

### 系统环境

当前采用：

```text
Windows 11
WSL Ubuntu 24.04
ROS2 Jazzy
RoboSense rslidar_sdk
```

ROS2 Jazzy 通过 apt 安装在：

```bash
/opt/ros/jazzy
```

SDK 工作区在：

```bash
/mnt/e/project/lidar-sdk/ros2_ws
```

源码在：

```bash
/mnt/e/project/lidar-sdk/ros2_ws/src/rslidar_sdk
/mnt/e/project/lidar-sdk/ros2_ws/src/rslidar_msg
```

### LiDAR 网络配置

当前已实测可连接的配置：

```text
LiDAR IP: 192.168.1.201
电脑网口 IP: 192.168.1.102
MSOP local receive port: 6688
DIFOP local receive port: 7799
LiDAR type: RSM1
```

不要随意修改这些 IP 配置。

如果 SDK 日志中出现：

```text
ERRCODE_MSOPTIMEOUT
```

并且：

```bash
ros2 topic hz /rslidar_points
```

显示：

```text
topic [/rslidar_points] does not appear to be published yet
```

说明 SDK 启动了，但没有收到 LiDAR 的 MSOP 数据包。

用下面命令检查 WSL 是否收到 6688/7799 UDP 包：

```bash
sudo tcpdump -ni any "udp port 6688 or udp port 7799"
```

判断：

```text
tcpdump 有包：继续检查 SDK 配置、型号、端口。
tcpdump 没包：检查 LiDAR 是否开机、网线、端口、防火墙和 WSL mirrored 网络配置。
```

### 时间戳配置

本项目目标是使用电脑本地时间作为点云消息时间戳。配置项是：

```yaml
use_lidar_clock: false
```

SDK 启动日志中显示：

```text
use_lidar_clock: 0
```

表示正在使用系统时间。

注意：这表示 ROS2 消息时间戳使用本机系统时间，不等于 LiDAR 硬件时钟已经通过 PTP/GPS/NTP 和电脑完成高精度同步。


### `config.yaml` 配置

配置文件位置：

```text
Windows:
E:\project\lidar-sdk\ros2_ws\src\rslidar_sdk\config\config.yaml

WSL:
/mnt/e/project/lidar-sdk/ros2_ws/src/rslidar_sdk/config/config.yaml
```

可以在 Windows VSCode 中直接修改。

当前在线 LiDAR 模式建议配置：

```yaml
common:
  msg_source: 1
  send_packet_ros: false
  send_point_cloud_ros: true

lidar:
  - driver:
      lidar_type: RSM1
      msop_port: 6688
      difop_port: 7799
      use_lidar_clock: false
```

关键项含义：

```text
msg_source: 1              从在线 LiDAR 接收数据
send_packet_ros: false     不发布 packet topic，只录制点云时建议关闭
send_point_cloud_ros: true 发布 /rslidar_points，可用于录制点云
use_lidar_clock: false     使用电脑本地系统时间作为消息时间戳
```

改完 `config.yaml` 后，重启 SDK 生效：

```bash
cd /mnt/e/project/lidar-sdk
bash scripts/start_lidar.sh
```

只改 yaml 通常不需要重新 `colcon build`。

## 2. 部署流程

在 WSL 终端中执行：

```bash
conda deactivate
cd /mnt/e/project/lidar-sdk
bash scripts/bootstrap_ros2_jazzy_rslidar.sh
```

部署成功后会看到：

```text
Deployment complete
```

验证 ROS2 和包：

```bash
source /opt/ros/jazzy/setup.bash
source /mnt/e/project/lidar-sdk/ros2_ws/install/setup.bash
ros2 pkg list | grep rslidar
```

正常应能看到 `rslidar_sdk` 和 `rslidar_msg`。

## 3. 录制全流程

录制时建议不要启动 RViz。RViz 渲染点云会增加 WSL/ROS2 负载，可能影响发布频率和录制稳定性。

### 1. 确认硬件和网络

确认：

```text
LiDAR 已开机
网线已连接
电脑网口 IP: 192.168.1.102
LiDAR IP: 192.168.1.201
MSOP local receive port: 6688
DIFOP local receive port: 7799
```

检查 WSL 是否能收到 UDP：

```bash
sudo tcpdump -ni any "udp port 6688 or udp port 7799"
```

正常应看到类似：

```text
192.168.1.201.6699 > 192.168.1.102.6688
192.168.1.201.7788 > 192.168.1.102.7799
```

### 2. 直接启动 SDK 节点，不启动 RViz

推荐用这个方式启动录制用的 SDK：

```bash
conda deactivate
source /opt/ros/jazzy/setup.bash
source /mnt/e/project/lidar-sdk/ros2_ws/install/setup.bash
ros2 run rslidar_sdk rslidar_sdk_node
```

不要用 `bash scripts/start_lidar.sh` 做正式录制启动，因为它调用的 `start.py` 默认会同时启动 RViz2。

如果只是临时看点云，可以使用：

```bash
cd /mnt/e/project/lidar-sdk
bash scripts/start_lidar.sh
```

### 3. 检查点云 topic

另开一个 WSL 终端：

```bash
conda deactivate
source /opt/ros/jazzy/setup.bash
source /mnt/e/project/lidar-sdk/ros2_ws/install/setup.bash
ros2 topic list
```

应能看到：

```text
/rslidar_points
```

检查点云发布频率：

```bash
ros2 topic hz /rslidar_points --window 30
```

如果没有频率，并且 SDK 报 `ERRCODE_MSOPTIMEOUT`，优先检查 WSL 是否收到 UDP：

```bash
sudo tcpdump -ni any "udp port 6688 or udp port 7799"
```

如果要确认原始输入是否是 10Hz，可以抓 6300 个 MSOP 包：

```bash
time sudo tcpdump -ni any "udp port 6688" -c 6300 > /dev/null
```

RSM1 单回波约 630 个 MSOP 包为一帧；如果 6300 个包约 1 秒抓满，说明原始输入接近 10Hz。

### 4. 录制点云

后续只使用一个录制入口：

```bash
cd /mnt/e/project/lidar-sdk
bash scripts/record_from_config.sh
```

录制参数在根目录 YAML 配置文件中修改：

```text
lidar_recording_config.yaml
```

立即录制 10 秒：

```yaml
recording:
  start_time: ""
  duration_seconds: 10
```

按指定本地时间录制 60 秒：

```yaml
recording:
  start_time: "2026-07-09 15:30:00"
  duration_seconds: 60
```

默认使用 MCAP 容器和 Zstd 压缩：

```yaml
recording:
  storage_id: mcap
  compression:
    mode: storage
    format: zstd
    profile: zstd_fast
```

`storage_id` 可设为 `mcap` 或 `sqlite3`。前者产生 `.mcap` 数据文件，后者产生 `.db3` 数据文件；ROS2 rosbag2 不直接录制 ROS1 的单文件 `.bag`。

`mode: storage` 使用 MCAP 原生分块压缩，文件仍可直接索引，推荐实时录制使用。切换到 `sqlite3` 时，应把 `mode` 改成 `file`、`message` 或 `none`。

然后运行：

```bash
cd /mnt/e/project/lidar-sdk
bash scripts/record_from_config.sh
```

录制结果在：

```bash
/mnt/e/project/lidar-sdk/bags/points
```

Windows 中对应：

```text
E:\project\lidar-sdk\bags\points
```

### 5. 检查录制结果

查看最新 bag：

```bash
ls -td /mnt/e/project/lidar-sdk/bags/points/points_* | head -1
```

查看 bag 信息：

```bash
ros2 bag info /mnt/e/project/lidar-sdk/bags/points/points_具体时间
```

重点看：

```text
Topic: /rslidar_points
Count: 点云帧数
Duration: 录制时长
```

10 秒录制如果有约 80-100 条 `/rslidar_points`，说明录制有效。

### 6. 导出点云

导出最新 bag 为 `npy`：

```bash
cd /mnt/e/project/lidar-sdk
bash scripts/export_points_from_bag.sh --input latest --format npy
```

导出最新 bag 的前 10 帧为 `pcd`：

```bash
bash scripts/export_points_from_bag.sh --input latest --format pcd --max-frames 10
```

导出指定 bag 为 `bin`，并指定输出目录：

```bash
bash scripts/export_points_from_bag.sh \
  --input /mnt/e/project/lidar-sdk/bags/points/points_具体时间 \
  --output /mnt/e/project/lidar-sdk/exports/my_bin \
  --format bin
```

## 4. 目录结构

```text
E:\project\lidar-sdk
  README.md
  scripts\
    bootstrap_ros2_jazzy_rslidar.sh
    start_lidar.sh
    record_from_config.sh
    export_points_from_bag.sh
    export_rosbag_points.py
    load_lidar_config.py
  lidar_recording_config.yaml
  ros2_ws\
    src\
      rslidar_sdk\
      rslidar_msg\
    build\
    install\
    log\
  bags\
    points\
  exports\
    pcd\
    npy\
    npz\
    bin\
```

## 5. 脚本说明

### `scripts/bootstrap_ros2_jazzy_rslidar.sh`

部署脚本。作用：

```text
安装 ROS2 Jazzy apt 源
安装 ROS2 Jazzy
安装 colcon、yaml-cpp、libpcap 等依赖
创建 ros2_ws 工作区
拉取 rslidar_sdk
拉取 rslidar_msg
初始化 rslidar_sdk 的 rs_driver 子模块
编译工作区
```

该脚本会强制使用系统 Python `/usr/bin/python3`，避免 conda `base` 环境影响 ROS2 编译。

运行：

```bash
cd /mnt/e/project/lidar-sdk
bash scripts/bootstrap_ros2_jazzy_rslidar.sh
```

### `scripts/start_lidar.sh`

启动 RoboSense SDK。

作用等价于：

```bash
source /opt/ros/jazzy/setup.bash
source /mnt/e/project/lidar-sdk/ros2_ws/install/setup.bash
ros2 launch rslidar_sdk start.py
```

运行：

```bash
cd /mnt/e/project/lidar-sdk
bash scripts/start_lidar.sh
```

这个脚本只是启动 SDK 节点并监听 LiDAR 数据，不代表一定已经收到点云。是否真正收到点云，需要用 `ros2 topic hz /rslidar_points` 验证。

### `scripts/record_from_config.sh`

唯一的点云录制入口。该脚本读取根目录 `lidar_recording_config.yaml`，录制 `/rslidar_points`。

如果 `recording.start_time` 为空，立即录制；如果不为空，等到指定时间再录制。

```bash
cd /mnt/e/project/lidar-sdk
bash scripts/record_from_config.sh
```

输出目录：

```bash
/mnt/e/project/lidar-sdk/bags/points/points_YYYYMMDD_HHMMSS
```

默认使用 MCAP 原生 Zstd 分块压缩：

```yaml
recording:
  storage_id: mcap
  compression:
    mode: storage
    format: zstd
    profile: zstd_fast
```

### `scripts/export_points_from_bag.sh`

从 ROS2 bag 中读取 `/rslidar_points`，导出为 `npy`、`npz`、`bin` 或 `pcd`。

导出最新 bag：

```bash
cd /mnt/e/project/lidar-sdk
bash scripts/export_points_from_bag.sh --input latest --format npy
```

导出指定 bag，并指定输出目录：

```bash
bash scripts/export_points_from_bag.sh \
  --input /mnt/e/project/lidar-sdk/bags/points/points_具体时间 \
  --output /mnt/e/project/lidar-sdk/exports/my_pcd \
  --format pcd
```

可以限制导出的帧数：

```bash
bash scripts/export_points_from_bag.sh --input latest --format pcd --max-frames 10
```

### `scripts/export_rosbag_points.py`

Python 导出实现脚本，由 `scripts/export_points_from_bag.sh` 调用。通常不需要直接运行它。

支持：

```text
npy: 每帧一个 N x F 的 numpy 数组
npz: 每帧一个压缩的 numpy 数据包，包含 points 和 fields
bin: 每帧一个 float32 x,y,z,intensity 文件
pcd: 每帧一个 PCD 文件，可用 CloudCompare/PCL 查看
```

### `scripts/load_lidar_config.py`

内部 YAML 加载与校验脚本，由录制和导出脚本调用。通常不需要直接运行。

### `lidar_recording_config.yaml`

根目录统一录制配置文件。常用配置项：

```yaml
recording:
  topic: /rslidar_points
  output_dir: /mnt/e/project/lidar-sdk/bags/points
  bag_prefix: points
  storage_id: mcap
  compression:
    mode: storage
    format: zstd
    profile: zstd_fast
  start_time: ""
  duration_seconds: 10
  wait_for_topic_seconds: 20
  wait_for_topic_qos: sensor_data
  stop_signal: TERM
  stop_grace_seconds: 20

export:
  input_bag: latest
  output_dir: ""
  output_root: /mnt/e/project/lidar-sdk/exports
  format: npy
  max_frames: 0
```

示例：立即录制 30 秒点云：

```yaml
recording:
  start_time: ""
  duration_seconds: 30
```

示例：在本地时间 `2026-07-09 10:30:00` 开始录制 60 秒：

```yaml
recording:
  start_time: "2026-07-09 10:30:00"
  duration_seconds: 60
```

如果确认 `/rslidar_points` 正在发布，但录制脚本在等待一帧时报错，可以临时关闭预检查：

```yaml
recording:
  wait_for_topic_seconds: 0
```

## 6. 查看和解析点云

### 查看实时点云

启动 SDK 后，可以直接打开 RViz2：

```bash
source /opt/ros/jazzy/setup.bash
source /mnt/e/project/lidar-sdk/ros2_ws/install/setup.bash
rviz2
```

在 RViz2 中设置：

```text
Fixed Frame: rslidar
Add -> By topic -> /rslidar_points -> PointCloud2
```

如果使用 `bash scripts/start_lidar.sh` 启动，SDK 的 `start.py` 默认也会启动 RViz2。

### 查看录制的 rosbag

先查看 bag 信息：

```bash
ros2 bag info /mnt/e/project/lidar-sdk/bags/points/points_具体时间
```

重点看：

```text
Topic: /rslidar_points
Count: 点云帧数
Duration: 录制时长
```

播放 bag：

```bash
source /opt/ros/jazzy/setup.bash
source /mnt/e/project/lidar-sdk/ros2_ws/install/setup.bash
ros2 bag play /mnt/e/project/lidar-sdk/bags/points/points_具体时间
```

另开一个终端运行 `rviz2`，添加 `/rslidar_points` 的 `PointCloud2` 显示。

### 导出为 NPY/BIN/PCD

导出最新 bag 为 `npy`：

```bash
cd /mnt/e/project/lidar-sdk
bash scripts/export_points_from_bag.sh --input latest --format npy
```

导出最新 bag 的前 10 帧为 `pcd`：

```bash
bash scripts/export_points_from_bag.sh --input latest --format pcd --max-frames 10
```

导出指定 bag 为 `bin`：

```bash
bash scripts/export_points_from_bag.sh \
  --input /mnt/e/project/lidar-sdk/bags/points/points_具体时间 \
  --format bin
```

输出目录：

```text
/mnt/e/project/lidar-sdk/exports/npy/points_具体时间
/mnt/e/project/lidar-sdk/exports/npz/points_具体时间
/mnt/e/project/lidar-sdk/exports/bin/points_具体时间
/mnt/e/project/lidar-sdk/exports/pcd/points_具体时间
```

Windows 中对应：

```text
E:\project\lidar-sdk\exports
```

每次导出会生成：

```text
frame_000000_时间戳.npy
frame_000001_时间戳.npy
manifest.jsonl
```

`manifest.jsonl` 记录每帧的 ROS bag 时间、点云消息头时间、点数、字段和输出路径。

当前工程编译时 `POINT_TYPE` 是：

```cmake
set(POINT_TYPE XYZI)
```

因此导出的主要字段是：

```text
x, y, z, intensity
```

如果后续需要每个点的 `timestamp` 和 `ring`，需要把 `ros2_ws/src/rslidar_sdk/CMakeLists.txt` 中的：

```cmake
set(POINT_TYPE XYZI)
```

改成：

```cmake
set(POINT_TYPE XYZIRT)
```

然后重新编译 SDK，并重新录制数据。

## 7. 推荐的数据保存策略

当前项目只录制点云 topic：

```text
/rslidar_points
```

录制入口只使用：

```bash
bash scripts/record_from_config.sh
```

默认采用 MCAP 并开启 Zstd 压缩：

```yaml
recording:
  storage_id: mcap
  compression:
    mode: storage
    format: zstd
    profile: zstd_fast
```

同时 `config.yaml` 中建议保持：

```yaml
send_packet_ros: false
send_point_cloud_ros: true
```

如果压缩后仍然很大，这是点云本身的数据量决定的。在不裁剪、不降采样、不改雷达输出、不改点云字段的前提下，不能无损压到很小。

## 8. 常见问题

### `AMENT_TRACE_SETUP_FILES: unbound variable`

这是 shell `set -u` 和 ROS2 `setup.bash` 的兼容问题。当前脚本已经在 `source /opt/ros/jazzy/setup.bash` 前后处理，不需要手动修。

### `ModuleNotFoundError: No module named 'em'`

通常是 conda `base` 环境影响了 ROS2 编译，导致使用了：

```text
/home/www/miniconda3/bin/python3
```

当前部署脚本已经强制使用系统 Python：

```text
/usr/bin/python3
```

仍然建议运行部署和编译前执行：

```bash
conda deactivate
```

### `ERRCODE_MSOPTIMEOUT`

SDK 没收到 LiDAR MSOP 数据。常见原因：

```text
LiDAR 没开机
网线没连接
本地接收端口不是 6688
LiDAR 型号配置错误
```

先用下面命令确认是否收到 MSOP：

```bash
sudo tcpdump -ni any "udp port 6688"
```

### 改了 yaml 没生效

重启 SDK：

```bash
cd /mnt/e/project/lidar-sdk
bash scripts/start_lidar.sh
```

只改 yaml 不需要重新编译。改源码、消息类型或 CMake 配置才需要：

```bash
cd /mnt/e/project/lidar-sdk/ros2_ws
colcon build --symlink-install --cmake-args -DPython3_EXECUTABLE=/usr/bin/python3
```
