# esp-idf-build-skills

面向 **ESP-IDF** 工程开发的 agent skill（可复用指令集）集合。当前包含 **1 个技能**：[`esp-idf-build`](./esp-idf-build/SKILL.md)。

> Agent skill for ESP-IDF projects: detect and activate the matching ESP-IDF environment, then run `idf.py` build / flash / monitor — cross-platform (Windows / Linux / macOS / Docker), version-aware, with a common-error playbook.

纯文档 + 两个独立脚本，不依赖网络、不依赖第三方包，不修改技能目录以外的任何位置。

---

## 这个技能做什么

| 能力 | 说明 |
|---|---|
| 环境探测与激活 | 识别官方安装器 / Espressif 安装管理器（EIM）/ 旧版 Espressif IDE / 手动克隆 / 容器五种布局，按可靠性顺序挑激活脚本，并**在同一 shell 会话内**激活 |
| 版本匹配 | 从工程 `build/project_description.json` 的 `idf_path` 读出该工程锁定的 IDF 版本，避免"用默认版本"踩坑 |
| 标准命令 | `idf.py build / flash / monitor / fullclean / set-target / size-components ...` 的正确用法与组合（多目标并行、按地址烧录、compile_commands.json 等） |
| 报错速查 | `idf.py: command not found`、`Python virtual environment not found`、CMake 路径冲突、`app partition is too small`、`undefined reference` 等 11 类高频报错的原因与处理 |
| 平台坑位 | Linux udev / `dialout` 权限、`/dev/serial/by-id/` 稳定端口、macOS `/dev/cu.*` 与 Apple Silicon / Rosetta / Gatekeeper、Docker 缓存卷与设备透传、WSL + usbipd-win |
| 迁移经验 | ESP-IDF v6.0 + Mbed TLS 4.x（PSA Crypto）迁移中 PK 层 API 变更的实战注意点 |
| 附带脚本 | `scripts/build.ps1`（Windows）与 `scripts/build.sh`（Linux / macOS）：探测 → 激活 → 执行一条龙 |

## 目录结构

```
esp-idf-build-skills/
├─ README.md                              # 本文件：安装与使用
├─ .gitattributes                         # 统一 LF，保证 .sh 可直接执行
└─ esp-idf-build/                         # 技能本体（目录名 = 技能名）
   ├─ SKILL.md                            # 技能主文档（frontmatter: name / description）
   ├─ references/
   │  ├─ platform-notes.md                # Linux / macOS / Docker / WSL 平台坑位
   │  └─ local-env.example.md             # 本机环境速查模板（复制为 local-env.md 使用）
   └─ scripts/
      ├─ build.ps1                        # Windows PowerShell 5.1+，纯 ASCII
      └─ build.sh                         # Linux / macOS bash，纯 ASCII
```

## 安装

### 方式 A：用 skills CLI（推荐）

```bash
# 1) 先看仓库里有哪些技能（只列不装）
npx -y skills@latest add sakurainn/esp-idf-build-skills --list

# 2) 安装到用户级（全局，所有项目可用）
npx -y skills@latest add sakurainn/esp-idf-build-skills -g -a cline -y

# 3) 或只装到当前项目（落在 ./.agents/skills/）
npx -y skills@latest add sakurainn/esp-idf-build-skills -a cline -y

# 4) 也可以点名装（本仓库只有一个技能）
npx -y skills@latest add sakurainn/esp-idf-build-skills --skill esp-idf-build -g -a cline -y
```

`-a <agent>` 决定装到哪个 agent 的目录。**所有会把技能放进 `~/.agents/skills/` 的 agent key**（依据 skills CLI v1.7.0 的映射）：

| agent key | 全局目录 | 项目目录 |
|---|---|---|
| `cline`、`dexto`、`kimi-code-cli`、`loaf`、`sarvam-code`、`warp`、`zed` | `~/.agents/skills/` | `.agents/skills/` |

两个常见坑：

1. `amp` / `replit` / `universal` 的全局目录是 `~/.config/agents/skills/`，**不是** `~/.agents/skills/`，别用它们。
2. **省略 `-a` 时 CLI 会按"已安装的 agent"自动探测**（依据 `~/.cline`、`~/.zed` 等目录是否存在）。如果机器上没装这些 agent，自动探测不会写进 `~/.agents/skills/`，技能就"装了但没人读"。**显式写 `-a cline`（或上表任意一个）最稳。**

### 方式 B：手动安装（不用 npx / 不用 CLI）

```bash
git clone --depth 1 https://github.com/sakurainn/esp-idf-build-skills.git /tmp/esp-idf-build-skills
mkdir -p ~/.agents/skills
cp -r /tmp/esp-idf-build-skills/esp-idf-build ~/.agents/skills/
```

```powershell
git clone --depth 1 https://github.com/sakurainn/esp-idf-build-skills.git "$env:TEMP\esp-idf-build-skills"
New-Item -ItemType Directory -Force "$env:USERPROFILE\.agents\skills" | Out-Null
Copy-Item "$env:TEMP\esp-idf-build-skills\esp-idf-build" "$env:USERPROFILE\.agents\skills\" -Recurse -Force
```

技能加载只认一个条件：技能根目录下存在 `<技能名>/SKILL.md`（技能发现只走一层，不做深层递归猜测）。**手动安装不会写入 skills CLI 的 `.skill-lock.json`**，因此 `npx skills update` / `npx skills remove` 不认识它——卸载直接删目录即可。

### 装到哪儿才会被读到

| 顺序 | 目录 | 谁读它 |
|---|---|---|
| 1 | `<项目>/.dsh/skills/` | DeepSeek Harness（DSH）项目级，优先级最高 |
| 2 | `<项目>/.agents/skills/` | DSH 项目级；其他 agent 的项目级 |
| 3 | `$DSH_HOME/skills/`（本机为 `%APPDATA%\dsh-desktop\harness\skills\`） | DSH 用户级 |
| 4 | `~/.agents/skills/` | **通用用户级**：DSH 与 `cline` / `zed` / `warp` 等共用 |
| — | `~/.claude/skills/`、`~/.codex/skills/`、`~/.cursor/skills/` … | 各 agent 私有目录，DSH 不读 |

顺序越小越优先：同名技能放在优先级更高的目录里会覆盖低优先级的版本。

## 使用

### 1. 交给 agent 自动触发

技能的 `description` 已经写明了触发场景（需要编译/烧录/调试 ESP-IDF 工程、修 `idf.py` 报错、配置开发环境、切换 IDF 版本、管理组件依赖），命中时会自动加载。也可以直接点名，例如：

- "用 esp-idf-build 帮我把 `D:\work\myapp` 编出来，报错了就看日志"
- "这个工程该用哪个 IDF 版本？顺便切到 esp32s3"

### 2. 直接用附带的脚本

两个脚本做同一件事：**按可靠性顺序探测 ESP-IDF → 在同一会话内激活 → 在工程目录执行指定动作**。工程目录必须是含顶层 `CMakeLists.txt` 的那个目录，不是 `main/`。

**Windows PowerShell**（在 PowerShell 会话里直接调用即可，Windows PowerShell 5.1 与 PowerShell 7 都能跑）：

```powershell
# 先干跑：只打印会选中哪个环境，不执行任何命令（强烈建议第一步）
.\esp-idf-build\scripts\build.ps1 -Project D:\work\myapp -DryRun

# 构建（用工程 build/ 里记录的版本）
.\esp-idf-build\scripts\build.ps1 -Project D:\work\myapp

# 钉住 IDF 目录 + 换版本前先全清
.\esp-idf-build\scripts\build.ps1 -Project D:\work\myapp -IdfPath C:\Espressif\frameworks\esp-idf-v5.4.2 -Clean

# 烧录并看日志
.\esp-idf-build\scripts\build.ps1 -Project D:\work\myapp -Port COM5 -FlashMonitor

# 换目标芯片 / 只看体积
.\esp-idf-build\scripts\build.ps1 -Project D:\work\myapp -Action set-target -Target esp32s3
.\esp-idf-build\scripts\build.ps1 -Project D:\work\myapp -Action size-components
```

> 从 cmd / Git Bash 等非 PowerShell 环境调用时，用 `powershell -ExecutionPolicy Bypass -File .\esp-idf-build\scripts\build.ps1 ...`；装了 PowerShell 7 才用 `pwsh -File ...`。**Windows 自带的是 Windows PowerShell 5.1，`pwsh` 不一定存在**（先用 `Get-Command pwsh` 确认）。

**Linux / macOS：**

```bash
# 先干跑
bash esp-idf-build/scripts/build.sh --project ~/work/myapp --dry-run

# 构建 / 指定 IDF / 换版本先全清
bash esp-idf-build/scripts/build.sh --project ~/work/myapp
bash esp-idf-build/scripts/build.sh --project ~/work/myapp --idf-path /opt/esp/idf --clean

# 烧录并看日志（用 by-id 稳定端口，别用会变的 ttyUSB0）
bash esp-idf-build/scripts/build.sh --project ~/work/myapp \
  --port /dev/serial/by-id/usb-Silicon_Labs_CP2102N_0001-if00-port0 --flash-monitor

# 换目标芯片
bash esp-idf-build/scripts/build.sh --project ~/work/myapp --action set-target --target esp32s3

# 查看用法
bash esp-idf-build/scripts/build.sh -h
```

**`build.ps1` 参数：**

| 参数 | 必填 | 说明 |
|---|---|---|
| `-Project <路径>` | ✅ | 工程根目录（含顶层 `CMakeLists.txt`） |
| `-IdfPath <路径>` | | ESP-IDF 源码目录（含 `export.ps1`）；不填则自动探测 |
| `-ExportScript <路径>` | | 直接指定激活脚本，优先级最高 |
| `-Action <动作>` | | `build`（默认）/ `fullclean` / `reconfigure` / `menuconfig` / `size-components` / `size-files` / `set-target` / `erase-flash` |
| `-Target <芯片>` | | 配合 `-Action set-target`，如 `esp32s3` |
| `-Clean` | | 执行动作前先跑 `idf.py fullclean` |
| `-Port <串口>` | | 如 `COM5` |
| `-Flash` / `-Monitor` / `-FlashMonitor` | | 烧录 / 监视 / 烧录+监视 |
| `-DryRun` | | 只打印选中的环境，不执行 |

**`build.sh` 参数：** `--project`（必填）、`--idf-path`、`--export-script`、`--action`、`--target`、`--port`、`--clean`、`--flash`、`--monitor`、`--flash-monitor`、`--dry-run`、`-h|--help`。

**探测顺序（两者一致）：**
`-ExportScript` → `-IdfPath` → 当前 shell 的 `IDF_PATH` → 工程 `build/project_description.json` 的 `idf_path` → 扫描 `IDF_TOOLS_PATH`、`~/.espressif/frameworks`、`~/esp`、`%SystemDrive%\Espressif\tools` → PATH 上已有的 `idf.py`。

前四项是"有依据"的来源；一旦落到扫描盲选，脚本会打印 `picked from: probe:...` 并给出 `WARNING`，建议用 `-IdfPath` / `--idf-path` 钉死版本。

**退出码（已实测）：** `build.sh`——成功 `0`，用法/环境错误 `2`（`die`），`idf.py` 非零则原样传播；`build.ps1`——成功 `0`，任何失败（找不到可用环境、参数组合不合法、`idf.py` 非零）抛错退出 `1`。

### 3. 本机环境速查（可选）

`references/local-env.example.md` 是**模板**：复制成同目录的 `local-env.md`，填入你自己机器的安装布局、已装版本、激活脚本、工程↔版本对照。

这类内容包含本地路径与工程名，**建议只留本地、不要提交**；本仓库只提供这份脱敏模板，`SKILL.md` 的「参考」一节也相应指向模板。

## 前置要求

- 已安装 ESP-IDF（任意一种布局），或 `idf.py` 已在 PATH 上
- Windows：PowerShell 5.1+（`build.ps1` 声明了 `#requires -Version 5.1`；系统自带的 Windows PowerShell 5.1 就够用，**不需要另外安装 PowerShell 7**）
- Linux / macOS：bash；`python3` 可选（有则用它解析工程 JSON，没有则回退到 `sed`）
- 脚本不需要管理员权限、不联网、只读取工程与 IDF 目录

## 验证安装是否生效

```powershell
# 1) CLI 能否识别到技能
npx -y skills@latest add sakurainn/esp-idf-build-skills --list

# 2) 文件是否到位
Test-Path "$env:USERPROFILE\.agents\skills\esp-idf-build\SKILL.md"   # -> True

# 3) 脚本能否干跑（不会真的构建）
& "$env:USERPROFILE\.agents\skills\esp-idf-build\scripts\build.ps1" -Project <你的工程> -DryRun
```

干跑预期输出：

```
==> activation: <激活脚本路径>
==> picked from: project_description.json
==> project   : <工程绝对路径>
==> DryRun done.
```

出现 `picked from: probe:...` + `WARNING: ... picked a detected install` 时，说明工程还没有 `build/` 且你没指定版本；用 `-IdfPath` 明确指定即可。

## 故障排查

| 现象 | 原因 / 处理 |
|---|---|
| agent 没触发这个技能 | 确认 `<根>/esp-idf-build/SKILL.md` 存在且 frontmatter 完整；新开一个会话再试（技能目录在会话启动时载入） |
| `No usable ESP-IDF environment` | 先激活环境，或显式给 `-IdfPath` / `-ExportScript`（`--idf-path` / `--export-script`），或先把 ESP-IDF 装好 |
| `Python virtual environment not found` | `IDF_TOOLS_PATH` 指向了失效目录；EIM 布局要用它自己的 `*.PowerShell_profile.ps1`，别直接调 IDF 目录里的 `export.bat` |
| 换 IDF 版本后出现诡异编译/链接错误 | `build/` 缓存锁着旧版本：先 `idf.py fullclean` 再切版本 |
| Linux 下烧录 `Permission denied` | 串口权限：装 udev 规则或把用户加进 `dialout` 组，详见 `references/platform-notes.md` |
| `unknown argument: ...`（`build.sh`） | `bash esp-idf-build/scripts/build.sh -h` 查看支持的参数 |

更多报错（CMake 路径冲突、分区过小、`undefined reference`、clangd 满屏红等）见 [`esp-idf-build/SKILL.md`](./esp-idf-build/SKILL.md) 第 5 节。

## 许可

本仓库尚未声明开源许可证（No license declared）。如需被他人自由复用/分发，请补充 `LICENSE` 文件（例如 MIT）。
