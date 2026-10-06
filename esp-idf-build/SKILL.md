---
name: esp-idf-build
description: "通用 ESP-IDF 开发技能：跨平台环境探测与激活（Windows PowerShell/cmd、Linux、macOS；官方安装器 / Espressif 安装管理器 / 便携克隆 / 容器）、idf.py build/flash/monitor、IDF 版本与 build 缓存管理、组件依赖声明、常见编译与链接报错速查、v6.0 + Mbed TLS 4.x 迁移经验。当需要编译/烧录/调试 ESP-IDF 工程、修复 idf.py 报错、配置开发环境、切换 IDF 版本或管理组件依赖时使用。"
---

# ESP-IDF 工程开发（通用）

本技能给出与具体机器无关的 ESP-IDF 工作流：**怎么确认环境、在哪跑命令、版本怎么配、报错怎么查**。

**先探测环境再动手** —— 不同机器的安装方式（官方安装器 / Espressif 安装管理器 / 旧版 Espressif IDE / 手动克隆 / Docker）和 shell 都不同，硬编码任何路径都会失效。

## 0. 三条铁律

1. **激活与命令必须在同一个 shell 会话里。** 环境变量不跨进程继承：新开终端、脚本里分两次执行、通过 `ssh` / `bash -c` 调用，都会丢掉激活结果。
2. **在工程根目录执行**（含顶层 `CMakeLists.txt` 的目录），不是 `main/`。
3. **`idf.py build` 是唯一权威。** 编辑器 / clangd 的红波浪线通常只是缺 ESP-IDF include 上下文，不要照着改。

## 1. 探测环境（第一步，先做这个）

| 目标 | 命令 |
|---|---|
| 当前是否已激活 | `idf.py --version`（PowerShell 可用 `Get-Command idf.py -ErrorAction SilentlyContinue`） |
| 关键变量 | POSIX：`echo "$IDF_PATH $IDF_TOOLS_PATH $IDF_PYTHON_ENV_PATH"`；PowerShell：`$env:IDF_PATH` 等 |
| 工程锁定的版本 | `<project>/build/project_description.json` 的 `idf_path`，或 `build/CMakeCache.txt` |
| 芯片目标 | `sdkconfig` 里的 `CONFIG_IDF_TARGET`，或 `idf.py set-target` 记录 |

Windows PowerShell 一行式探测：

```powershell
"idf.py: "  + (Get-Command idf.py -ErrorAction SilentlyContinue).Source
"IDF_PATH: $env:IDF_PATH"
"TOOLS:    $env:IDF_TOOLS_PATH"
Get-ChildItem "$env:USERPROFILE\.espressif\frameworks" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name
```

Linux / macOS：

```bash
command -v idf.py; echo "$IDF_PATH"; ls ~/.espressif 2>/dev/null; ls /opt/esp 2>/dev/null
```

### 安装布局速查

| 布局 | 特征 | 激活脚本 |
|---|---|---|
| 官方 ESP-IDF Tools Installer | `~/.espressif/frameworks/esp-idf-vX.Y.Z`，工具链在 `~/.espressif/tools` | `$IDF_PATH/export.ps1` / `export.bat` / `export.sh` |
| Espressif 安装管理器（EIM） | `IDF_TOOLS_PATH` 下有安装清单 JSON 与 `<版本>.PowerShell_profile.ps1` | 对应版本的 `*.PowerShell_profile.ps1` |
| 旧版 Espressif IDE | `IDF_TOOLS_PATH` 指向 IDE 目录，内含 `tools` 与 `idf_cmd_init.bat` | `idf_cmd_init.bat` |
| 手动克隆 / 便携版 | 任意 `esp-idf` 克隆目录 | 该目录下的 `export.ps1` / `export.sh` |
| 容器 | 镜像里已有 `idf.py` | 无需激活；注意挂载 `~/.espressif` 缓存目录 |

**不知道装在哪**：先看 `$IDF_PATH` / `~/.espressif/frameworks` / `IDF_TOOLS_PATH`，再搜 `export.ps1`（Windows：`Get-ChildItem C:\ -Filter export.ps1 -Recurse -ErrorAction SilentlyContinue`，较慢，限定在常见根目录下）。

### 激活（务必与命令同会话）

```powershell
# Windows PowerShell —— 点号 source（不是 &，不是点空格）
. $env:IDF_PATH\export.ps1
idf.py build
```

```bat
:: Windows cmd —— 用 call
call %IDF_PATH%\export.bat
idf.py build
```

```bash
# Linux / macOS
. "$IDF_PATH/export.sh"
idf.py build
```

激活脚本会设置 `IDF_PATH`（IDF 源码）、`IDF_TOOLS_PATH`（工具链位置）、`IDF_PYTHON_ENV_PATH`（Python 虚拟环境）三个关键变量。

> 报 `Python virtual environment not found` 通常是 `IDF_TOOLS_PATH` 指向了已删除或错误的目录。先修正它再激活；安装管理器布局要用它自己的 profile 脚本，不要直接调 IDF 目录里的 `export.bat`。

### 平台差异速查

| | Windows | Linux | macOS |
|---|---|---|---|
| shell | PowerShell / cmd | bash / zsh | zsh（默认）/ bash |
| 激活 | `. $env:IDF_PATH\export.ps1` 或 `call export.bat` | `. "$IDF_PATH/export.sh"` | 同 Linux |
| 默认安装根 | `%USERPROFILE%\.espressif`、安装管理器目录 | `~/.espressif`、`/opt/esp/idf` | `~/.espressif`、`/opt/esp/idf` |
| 串口设备名 | `COM5` | `/dev/ttyUSB0`、`/dev/ttyACM0`、`/dev/serial/by-id/...` | `/dev/cu.usbserial-*`、`/dev/cu.SLAB_USBtoUART` |
| 串口权限 | 一般无需处理 | **需要** udev 规则或 `dialout` 组 | 一般无需处理 |
| 稳定性坑 | COM 号随插拔变化 | 优先用 `/dev/serial/by-id/` 而非 `ttyUSB0` | 端口随插拔变化；USB 转串口芯片要有驱动 |

三条高频要点：

- **Linux 串口权限**：未配置时 `idf.py -p /dev/ttyUSB0 flash` 直接 `Permission denied`，必须先装 udev 规则或加入 `dialout` 组。
- **macOS Apple Silicon**：官方安装器提供 arm64 工具链；个别老工具只有 x86_64 时会走 Rosetta 2（首次构建更慢）。下载物被 Gatekeeper 拦截需 `xattr -dr com.apple.quarantine ~/.espressif`。
- **容器 / WSL**：容器里直接用镜像自带的 `idf.py`，无需激活；**不要在 WSL 里跑 Windows 版 IDF**，要用就在 WSL 内单独安装，USB 串口靠 usbipd-win 透传。

完整命令与更多坑位见 `references/platform-notes.md`。

## 2. 标准命令

```bash
idf.py set-target esp32s3          # 换芯片（触发 reconfigure）
idf.py build
idf.py -p /dev/ttyUSB0 flash       # Linux / macOS
idf.py -p COM5 flash               # Windows
idf.py -p <port> monitor           # 退出 monitor：Ctrl+]
idf.py -p <port> flash monitor
idf.py fullclean                   # 换 IDF 版本 / 缓存异常
idf.py reconfigure                 # 改 sdkconfig / Kconfig 后刷新配置
idf.py menuconfig
idf.py size-components             # 各组件体积
idf.py size-files
idf.py erase-flash                 # 清除 flash 中的 app 数据（需确认）
```

同环境内可用的独立工具：`esptool.py`（烧录 / 读写 flash）、`idf_monitor`（串口监视）、`parttool.py`（分区表）、`idf_tools.py`（安装 / 升级工具链与 Python 环境）。

### 常用组合与进阶用法

- **在任意目录、指定构建目录运行**：`idf.py -C ~/work/app -B build_esp32s3 -D SDKCONFIG=sdkconfig.esp32s3 set-target esp32s3 build`。多目标 / 多配置并行时，每个组合用独立的 `-B` 与 `sdkconfig.xxx`，否则共用 `build/` 会互相踩。
- **给 IDE / clangd 提供编译数据库**：`idf.py build` 后把 `compile_commands.json` 指向 `<build>/compile_commands.json`（必要时加 `-DCMAKE_EXPORT_COMPILE_COMMANDS=ON`）。
- **按地址烧录**：只更新 app 用 `idf.py -p <port> flash --offset 0x10000`，偏移量以 `build/partition_table/partition-table.csv` 为准，不要猜。
- **monitor**：`--no-reset` 不自动复位；退出键是 `Ctrl+]`。
- **固化配置**：`idf.py save-sdkconfig` 把当前配置导出成 `sdkconfig.defaults`，便于换机器复现。
- **单独构建产物**：`idf.py app` / `idf.py bootloader` / `idf.py partition-table` / `idf.py add-partition`。
- **不知道端口时**：Linux `ls /dev/serial/by-id/`，macOS `ls /dev/cu.*`，Windows `Get-CimInstance Win32_SerialPort`。

## 3. 版本与工程匹配

- **权威来源是工程自己的记录**：`<project>/build/project_description.json` 的 `idf_path`；还没有 build 目录时，看 `CMakeLists.txt` / CI 配置里声明的 IDF 版本。
- **`build/` 会锁定版本**：换版本必须先 `idf.py fullclean`，否则会出现 toolchain 路径冲突、编译参数漂移、缓存不一致等难查的报错。
- **组件兼容性**：组件的 `idf_component.yml` 里有 `version` 与 `dependencies`，IDF 版本过低会被 idf-component-manager 拒绝；`managed_components/` 是生成物，不要手改。
- 机器上有多套 IDF 时，**用工程记录的 `idf_path` 选激活脚本**，不要用「默认版本」。

## 4. 工程结构与组件依赖

```
project/
├─ CMakeLists.txt        # project(...); include($ENV{IDF_PATH}/tools/cmake/project.cmake)
├─ sdkconfig / sdkconfig.defaults
├─ partitions.csv
├─ main/CMakeLists.txt   # idf_component_register(SRCS "..." INCLUDE_DIRS "." REQUIRES driver)
└─ components/<name>/    # 自研组件：各自的 CMakeLists.txt（+ 可选 idf_component.yml）
```

- 链接 `undefined reference to xxx` ⇒ **依赖没声明**：在 `idf_component_register(... REQUIRES ...)` 补公开依赖，或 `PRIV_REQUIRES ...` 补私有依赖。
- `fatal error: foo.h: No such file or directory` ⇒ 同上（跨组件的头文件必须通过依赖声明才能被包含）。
- `build/`、`managed_components/` 都是生成物；只改 `main/` 和自研 `components/`。

## 5. 常见报错速查

| 现象 | 常见原因 | 处理 |
|---|---|---|
| `idf.py: command not found` | 没激活环境；或跑在不匹配的 shell（如 WSL 里想用 Windows 的 IDF） | 在对应 shell 中先激活 export 脚本 |
| `Python virtual environment not found` | `IDF_TOOLS_PATH` 失效；或误用 `export.bat` | 修正 `IDF_TOOLS_PATH`；安装管理器布局用其 profile 脚本 |
| 激活后仍找不到 Python / 工具链 | 激活与命令不在同一会话 | 合并成一条命令：`. export.ps1; idf.py build` |
| CMake 报 IDF_PATH / 工具链路径冲突 | `build/` 缓存锁了旧版本 | `idf.py fullclean` 后重建 |
| 换了芯片行为仍像旧芯片 | target 变更未生效 | `idf.py fullclean` → `idf.py set-target <target>` → `idf.py build` |
| clangd / IDE 满屏红、`inttypes.h not found` | IDE 缺 ESP-IDF include 与宏定义 | 忽略，以 `idf.py build` 为准；把 clangd 的 compilation database 指向 `<build>/compile_commands.json` |
| `-Werror=<xxx>` | 告警被提升为错误 | 优先修代码；确有必要时在项目 `CMakeLists.txt` 加 `-Wno-error=<xxx>` |
| `app partition is too small` | 固件超出分区 | `idf.py size-components` 定位大头，再调 `partitions.csv` 或分区表 Kconfig |
| `implicit declaration of function 'mbedtls_...'` | 头文件缺失，或在组件升级中被移动 | 到 `<IDF_PATH>/components/` 下确认真实位置后再 include |
| `undefined reference` | 组件依赖未声明 | 见第 4 节 |
| 同一工程并发构建互相踩 | 多终端同时跑 `idf.py` | 串行执行，或各自用独立 `-B` 构建目录 |

## 6. v6.0 + Mbed TLS 4.x 迁移经验

v6.0 系列内置 **Mbed TLS 4.x**，并建立在 PSA Crypto 之上，部分旧 PK 层 API 被移除（如 `mbedtls_pk_write_pubkey()`）。迁移原则：

1. **先查源码再改**：在 `<IDF_PATH>/components/mbedtls/` 里确认符号与头文件是否还存在，不要凭记忆改。
2. **读实现确认语义**：例如 `mbedtls_pk_write_pubkey_der()` 从缓冲区**末尾往前写**并返回长度，数据起点是 `buf + size - ret`；忽略这个偏移就会对全零内存做哈希。
3. **涉及哈希 / 握手协议时只换 API、不改语义**：例如 OCPP 的 `issuerKeyHash` 按 RFC 6960 是对 **subjectPublicKey BIT STRING 的内容**求哈希，而不是对整段 SubjectPublicKeyInfo 求哈希，否则指纹与对端对不上。
4. **需要逐字节一致时，走原始字节上的 ASN.1**：用 `mbedtls_asn1_get_tag()` 解析，而不是重新序列化（EC 公钥压缩点 33 字节、非压缩 65 字节，长度与缓冲区大小都难估）。
5. **pk 层依赖 `psa_crypto_init()`**，未初始化会返回 `PSA_ERROR_NOT_INITIALIZED`。
6. 先用宏（`CONFIG_MBEDTLS_*`、项目自定义开关）确认哪些文件真正参与编译，避免改到不参与构建的副本。

## 7. 效率与习惯

- 先看 `build/` 是否存在，再决定增量还是全量；首次全量编译 / 链接很慢，放后台并给长超时。
- 成功标志：`Project build complete to flash`，以及 `Smallest app partition is ... free` 那行的余量。
- 单文件语法检查不要用裸 `gcc`（缺 `-I` 与宏定义必然报错），用 `idf.py build` 验证。
- 只让 `idf.py` 管理构建目录；需要并行时用独立 `-B` 构建目录。

## 8. 附带脚本

两个脚本逻辑相同：探测并激活匹配的 ESP-IDF，再执行 build / clean / flash / monitor。激活一律与 `idf.py` 在同一会话内完成。

`scripts/build.ps1`（Windows PowerShell）：

```powershell
# 在 PowerShell 会话里直接调用（Windows PowerShell 5.1 与 PowerShell 7 均可；
# Windows 自带的是 5.1，pwsh 不一定存在，跨 shell 调用用 powershell -File）
# 用工程 build/ 里记录的版本构建
.\scripts\build.ps1 -Project D:\work\myapp

# 显式指定 IDF 目录
.\scripts\build.ps1 -Project D:\work\myapp -IdfPath C:\Espressif\frameworks\esp-idf-v5.3.2

# 换版本前先全清
.\scripts\build.ps1 -Project D:\work\myapp -IdfPath D:\idf\esp-idf -Clean

# 烧录 + 看日志
.\scripts\build.ps1 -Project D:\work\myapp -Port COM5 -FlashMonitor

# 只看会选中哪个环境，不执行
.\scripts\build.ps1 -Project D:\work\myapp -DryRun
```

`scripts/build.sh`（Linux / macOS，bash）：

```bash
# 用工程 build/ 里记录的版本构建
bash scripts/build.sh --project ~/work/myapp

# 显式指定 IDF 目录
bash scripts/build.sh --project ~/work/myapp --idf-path ~/esp/esp-idf

# 换版本前先全清
bash scripts/build.sh --project ~/work/myapp --idf-path /opt/esp/idf --clean

# 烧录 + 看日志（用 by-id 稳定端口）
bash scripts/build.sh --project ~/work/myapp --port /dev/serial/by-id/usb-Silicon_Labs_CP2102N_0001-if00-port0 --flash-monitor

# 只看会选中哪个环境，不执行
bash scripts/build.sh --project ~/work/myapp --dry-run
```

探测顺序（两者一致）：`-ExportScript/--export-script` → `-IdfPath/--idf-path` → 当前已激活的 `$IDF_PATH` → 工程 `build/project_description.json` 的 `idf_path` → 扫描 `$IDF_TOOLS_PATH`、`~/.espressif/frameworks`、`~/esp`、`/opt/esp`、`%SystemDrive%\Espressif\tools` 下的安装 → PATH 上已有的 `idf.py`。
前四种是「有依据」的来源；若落到扫描盲选，脚本会打印 `picked from: probe:...` 并告警提示用 `-IdfPath` / `--idf-path` 钉住版本。
两个脚本都是纯 ASCII：中文注释写进 `.ps1` 会被 Windows PowerShell 5.1 按 ANSI 读取成乱码并破坏引号结构。

## 参考

- `references/platform-notes.md`：Linux / macOS / Docker / WSL 的独有坑与完整命令（udev 权限、by-id 端口、Apple Silicon 与 Rosetta、Gatekeeper `xattr`、容器缓存卷与 USB 透传、usbipd-win、WSL 文件系统性能）。
- `references/local-env.example.md`：**本机环境速查模板**（安装布局、已装版本与激活脚本、工程↔版本对照的写法示例）。复制成同目录的 `local-env.md` 并填入自己机器的真实路径后使用；`local-env.md` 含本地路径与工程名，只留在本地，不要提交到公开仓库。