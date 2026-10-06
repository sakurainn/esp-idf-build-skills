# 本机环境速查模板（复制为 local-env.md 后填写）

> 通用方法见 `SKILL.md`。本文件只记录**你自己这台机器**的具体路径、已装版本与工程对照。
> **建议**：填写后的 `local-env.md` 只留在本地，不要提交到公开仓库（它包含本地路径与工程名）。本仓库只提供这份脱敏模板。

## 怎么用

1. 复制本文件为同目录下的 `local-env.md`：
   - PowerShell：`Copy-Item local-env.example.md local-env.md`
   - Linux / macOS：`cp local-env.example.md local-env.md`
2. 把下面的 `<...>` 占位符换成你机器上的真实路径与版本。
3. 只有需要具体路径时再让 agent 读它；换一台机器就不必参考。

## 安装布局

先勾出你机器上是哪种布局，再填路径：

- [ ] 官方 ESP-IDF Tools Installer：根目录 `<例如 %USERPROFILE%\.espressif>`，工具链在 `<...\.espressif\tools>`
- [ ] Espressif 安装管理器（EIM）：根目录 `<例如 C:\Espressif\tools>`；安装清单 `<例如 C:\Espressif\tools\eim_idf.json>`
      （`idfInstalled[]` = 已装版本，`idfSelectedId` = 当前默认版本——**会变，别硬编码**）
- [ ] 旧版 Espressif IDE：`IDF_TOOLS_PATH` 指向 `<IDE 目录>`，用其中的 `idf_cmd_init.bat`
- [ ] 手动克隆 / 便携版：克隆根目录 `<例如 C:\esp>`，含版本 `<v6.0.2>`
- [ ] 容器：镜像 `<例如 espressif/idf:v5.3>`，缓存卷 `<例如 esp-idf-cache:/root/.espressif>`

已知坑（本机特有，务必写清楚，否则下次一定踩）：

- `<例如：系统环境变量 IDF_TOOLS_PATH 指向了已删除的 <旧目录>，直接跑 IDF 目录里的 export.bat 会报 Python virtual environment not found；要用 EIM 的 *.PowerShell_profile.ps1，它会把 IDF_TOOLS_PATH 指回 <正确目录>>`

## 已装版本与激活脚本

激活一律用**点号 source**（PowerShell `. xxx.ps1`）或 `source`（bash），且必须与 `idf.py` 在同一会话里。

| 版本 | 激活脚本 | 备注 |
|---|---|---|
| `<v6.0.2>` | `. <C:\Espressif\tools\Microsoft.v6.0.2.PowerShell_profile.ps1>` | `<例如：自带 Mbed TLS 4.1.0>` |
| `<v5.5.4>` | `. "<C:\Toolchain\esp\v5.5.4\esp-idf\export.ps1">` | `<需自行保证 IDF_TOOLS_PATH 正确>` |
| `<v5.3.5>` | `. "<...\export.ps1">` | `<...>` |

> 注意个别安装的 profile 文件名不带 `v`（例如 `Microsoft.5.3.4.PowerShell_profile.ps1`），别按规律猜。

一条命令完成「激活 + 进工程 + 构建」：

```powershell
. <你的激活脚本>
Set-Location <你的工程目录>
idf.py build
```

```bash
source <你的激活脚本>
cd <你的工程目录>
idf.py build
```

## 工程 ↔ IDF 版本对照

来源：各工程 `build/project_description.json` 里的 `idf_path`（**不要在公开仓库里填真实客户 / 内网工程名**）。

| 工程 | IDF 版本 |
|---|---|
| `<C:\path\to\your\app>` | `<v5.5.4（C:/path/to/esp-idf）>` |
| `<D:\work\another-app>` | `<v5.3.5（C:/path/to/esp-idf）>` |

> 换版本前一律先 `idf.py fullclean`，否则 `build/` 缓存会锁住旧版本。

## 本机习惯

- `<例如：只在 PowerShell 里跑 idf.py（Git Bash / WSL 里没有，报 command not found）；不要用 cmd /c 包裹构建命令>`
- `<例如：烧录端口形如 COMx，用 idf.py -p COM5 flash>`
- `<例如：板级工程都在 <目录> 下，managed_components/ 是生成物，不要手改>`
