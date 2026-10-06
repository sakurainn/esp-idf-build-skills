# 平台坑位速查（Linux / macOS / 容器 / WSL）

> 通用流程见 `SKILL.md`；本文件只放各平台独有的坑。Windows 的本机信息见 `local-env.md`。

## 跨平台通用

- `export.sh` 在 bash 和 zsh 下都能 source；**不要用 `sudo` 跑 `idf.py`**（会产生 root 权限的 `build/` 与 Python venv 问题）。
- 确认版本：`$IDF_PATH/tools/idf.py --version`，或 `cat $IDF_PATH/version.txt`、`git -C $IDF_PATH describe --tags`。
- 缺工具时补装：`$IDF_PATH/tools/idf_tools.py install`（`idf_tools.py install-python-env` 只装 Python 环境）。工具落在 `IDF_TOOLS_PATH`，多个 IDF 版本可共用同一份工具目录。
- `pip install` 只对 `$IDF_PYTHON_ENV_PATH` 指向的 venv 生效（`export.sh` 会把它加进 PATH）；**不要**往系统 Python 里装 IDF 依赖。
- 切版本前开新 shell 或 `unset IDF_PATH IDF_TOOLS_PATH IDF_PYTHON_ENV_PATH`，避免残留环境变量指向旧版本。

## Linux

### 串口权限（最常见的坑）

`idf.py -p /dev/ttyUSB0 flash` 报 `Permission denied` / `serial open failed` 时：

```bash
ls -l /dev/ttyUSB0                       # 看属主是谁
ls $IDF_PATH/tools/*usb*.rules           # 通常是 99-esp-idf-usb.rules（文件名随版本略有差异）

sudo cp $IDF_PATH/tools/99-esp-idf-usb.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules && sudo udevadm trigger
```

不想动 udev 就把用户加进串口组（**需要重新登录**才生效）：

```bash
sudo usermod -aG dialout $USER   # 或 newgrp dialout（仅当前 shell）
```

### 用稳定的端口名

`/dev/ttyUSB0` 取决于插拔顺序，多板或换线就会变。优先用：

```bash
ls -l /dev/serial/by-id/     # 例：usb-Silicon_Labs_CP2102N_...-if00-port0
idf.py -p /dev/serial/by-id/usb-Silicon_Labs_CP2102N_0001-if00-port0 flash
```

### 常见缺包

Debian/Ubuntu 构建前通常需要：`git wget flex bison gperf cmake ninja-build ccache libffi-dev libssl-dev dfu-util libusb-1.0-0`。缺 `cmake`/`ninja` 时 `idf.py` 会明确报名字。

### 日志

USB 枚举问题看 `dmesg | tail`；`idf.py monitor` 的输出与内核日志是两路，别指望 monitor 里看到内核 panic。

## macOS

- 默认 shell 是 **zsh**：`. "$IDF_PATH/export.sh"` 即可；不要把激活写进 `~/.zshrc` 后再手动改 PATH，容易与 Python 冲突。
- 串口是 **`/dev/cu.*`**（不是 `/dev/tty.*`，后者是阻塞式）：`ls /dev/cu.*`。常见 `usbserial`、`SLAB_USBtoUART`（CH340）、`wchusbserial`。
- USB 转串口芯片要有对应驱动：CH340/CH341、CP210x、FTDI 缺驱动时设备根本不出现。
- **Apple Silicon**：官方安装器提供 arm64 工具链；个别老工具只有 x86_64，会走 Rosetta 2 变慢。确认架构：`file $(command -v idf.py)`、`arch -x86_64 ...` 可强制。
- **Gatekeeper 隔离标记**：下载的二进制被拦时执行 `xattr -dr com.apple.quarantine ~/.espressif`（或对 `$IDF_PATH` 同样处理）。
- **大小写不敏感的文件系统**：不要出现 `Main/` 与 `main/` 这类重名目录/文件；CMake 报找不到文件但文件明明存在时，先查重名。
- Homebrew 装的 python/openssl 不会覆盖 IDF 自带 venv，但不要用 brew python 去 `pip install` IDF 的 requirements。
- `build/` 常见几 GB，留足磁盘（`df -h .`）。

## 容器（Docker）

官方镜像：`espressif/idf:<版本>`（tag 对应 IDF 版本，如 `v5.3`；也可用 `latest` / `release-v5.3`）。

```bash
docker run -it --rm \
  -v "$PWD:/project" -w /project \
  -v esp-idf-cache:/root/.espressif \      # 工具链缓存，否则每次重新下载几百 MB~数 GB
  espressif/idf:v5.3 idf.py build
```

- 容器里**不用激活环境**，镜像自带 `idf.py`。
- 烧录要透传设备：`-v /dev/ttyUSB0:/dev/ttyUSB0`（或 `--device`）；Linux 上还要满足 udev 权限（见上一节）。
- 挂载卷写回的文件属主可能变成 root：加 `--user "$(id -u):$(id -g)"`。
- 工程放 Windows/macOS 挂载目录会明显变慢；量大时把 `~/.espressif` 和工程都放进具名卷或 Linux 文件系统。

## WSL

- **不要在 WSL 里跑 Windows 安装的 IDF**：`idf.py` 与工具链是平台绑定的，混用会出现路径转义、`.exe` 与 Linux 工具链混编等诡异错误。要用就在 WSL 内单独安装 ESP-IDF。
- USB 串口需要 **usbipd-win** 透传（Windows 侧）：`usbipd bind --busb-ids <VID:PID>` → `usbipd attach --wsl --busid <BUSID>`；设备变化后需 `wsl --shutdown` 重新 attach。
- **工程放在 `~/`（Linux 文件系统）里**，别放 `/mnt/c/...`：跨文件系统的 CMake/编译会慢一个数量级。
- 串口在 WSL 里通常是 `/dev/ttyUSB0`；若要长期稳定，仍建议 `/dev/serial/by-id/`。