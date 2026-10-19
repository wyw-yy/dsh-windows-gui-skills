# dsh-windows-gui-skills

**在 DeepSeek Harness 里操作 Windows 图形界面**的六个 Agent Skill：截图（含被遮挡的窗口）、真实鼠标点击（带像素级回执）、走剪贴板打字（中文输入法不会吃字）、UI Automation 语义定位、动手前先问清，以及 STM32F4 的编译/烧录与「烧进去不亮」排查。

纯 PowerShell + 系统自带 .NET，**零依赖、零后台服务、零网络请求**。装完之后对 agent 说一句「截个图看看」或「点一下 GENERATE CODE」就能用。

> 社区插件，不是 DeepSeek 官方产品，也不代表 DeepSeek 背书。

## 为什么需要它

命令行能解决的事不该看屏幕；但真实开发里总有一类程序只能点：

- **STM32CubeMX**（Java/SWT，UI Automation 树里只有「最小化/最大化/关闭」）
- **Keil uVision** 的器件包管理器、STM32CubeProgrammer 的烧录确认框
- 各种安装向导、登录窗口、只能靠弹窗确认的对话框

这套技能是在真实任务里长出来的：给 STM32F401 点灯工程改时钟、点 CubeMX 的 `GENERATE CODE`、在 Calibration/OS 弹窗里选 Yes，都是它完成的。

## 安装

```bash
dsh plugin --profile <profile> add dsh-windows-gui-skills
```

把 `<profile>` 换成你在用的 profile（命令行看 `dsh --help`；桌面版通常是 `desktop`，纯净 Web 版是 `web`）。
安装命令顺便会把本包登记进该 profile 的 `dsh.profile.bundles`，不需要手动改配置。

装完**开一个新会话**（技能列表在会话启动时扫描），检查 skill 目录里是否出现 `windows-gui-control` 等六项。

升级 / 卸载：

```bash
dsh plugin --profile <profile> add dsh-windows-gui-skills@0.2.3     # 升级到指定版本
dsh plugin --profile <profile> remove dsh-windows-gui-skills        # 卸载
```

没有 npm 网络时，可以装本地 tarball：

```bash
npm pack                                  # 得到 dsh-windows-gui-skills-0.2.3.tgz
dsh plugin --profile <profile> add /abs/path/dsh-windows-gui-skills-0.2.3.tgz
```

不想装插件也可以只用技能：把 `skills/` 下六个目录拷进 `%USERPROFILE%\.agents\skills\`，效果一样（DSH 会从用户级技能目录加载）。

### 一条命令装技能（不需要 npm）

插件要等 npm 发包；只想立刻用上技能的话，仓库里带了一个安装脚本，直接从 GitHub 拉取并铺进用户级技能目录：

```powershell
powershell -ExecutionPolicy Bypass -File install.ps1
```

或者不下载脚本，一行搞定：

```powershell
$t="$env:TEMP\wgsk"; iwr https://github.com/wyw-yy/dsh-windows-gui-skills/archive/refs/heads/main.zip -OutFile "$t.zip"; Expand-Archive "$t.zip" $t -Force; Copy-Item "$t\dsh-windows-gui-skills-main\skills\*" "$env:USERPROFILE\.agents\skills\" -Recurse -Force
```

装完开新会话即可。注意 `dsh plugin add github:...` **不行**——DSH 的插件安装走 pnpm/npm 源，不认 git 源（实测装完不登记 bundle、也没有 skills 目录）。


## 六个技能

| 技能 | 管什么 | 典型触发 |
|---|---|---|
| `windows-gui-control` | 总入口：全量函数（`ui.ps1` + `pixelscan.ps1` + `flyouts.ps1`）、决策阶梯、硬规则、配方 | 「帮我点一下这个按钮」 |
| `windows-screen-automation` | 看→判断→点→验证闭环；全屏/单窗口截图；像素差校验；失败重试 | 「截图看看现在什么状态」 |
| `windows-uia-inspector` | UIA 控件树、按 Name/AutomationId 定位、语义点击、空树排查 | 「找到叫 OK 的按钮并点它」 |
| `windows-input-bridge` | 剪贴板打字（治中文输入法）、组合键、鼠标三键、焦点与时序 | 「在这个输入框里填 336」 |
| `stm32f4-bringup` | Keil 命令行编译/烧录、烧进去不亮的排查顺序、PLL 合法性算术、见证成功的四个条件 | 「烧录成功了但灯不亮」 |
| `clarify-before-act` | 动手前先问：什么该问、问几个、怎么问、什么时候别问；带 `clarify.ps1` 记录问了之后是好是坏 | 「先问我要做什么再动手」 |

每个技能都带 `SKILL.md`；`windows-gui-control` 还带两个可直接调用的脚本：

```powershell
# 加载（每次 pwsh 都是新进程，必须先放开执行策略）
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
. "$env:USERPROFILE\.dsh\profiles\<profile>\node_modules\dsh-windows-gui-skills\skills\windows-gui-control\scripts\ui.ps1"

Get-Screen -Path .\shot.png                  # 全屏截图
Get-WindowCapture -Title 'Notepad' -Path .\w.png   # 单窗口截图，被遮挡也行
Invoke-VerifiedClick -X 1235 -Y 900          # 点击 + 返回 {Changed, Diff}
Send-Text -Text '336'                        # 走剪贴板，规避输入法
```

## 它和「装个 pywinauto / MCP」有什么不同

- **不引入常驻进程或 MCP server**：每个动作都是一次 pwsh 调用，失败可重试、可复现。
- **遮挡截图是真的**：`PrintWindow` + `PW_RENDERFULLCONTENT`，窗口被别的窗口完全盖住时仍能取到自身内容（实测同一矩形：窗口图是原理图，屏幕图是另一个应用的界面，像素差 195/255）。
- **点击有回执**：`Invoke-VerifiedClick` 点击前后各截一次窗口，返回像素差；`Changed=False` 就说明没点中，不要盲点第二次。
- **语义优先**：能用 UI Automation 就不看图。看图是最后手段，因为一张图 ≈ 1k token。

## 环境要求

- Windows 10/11
- Windows PowerShell 5.1（系统自带）或 PowerShell 7
- .NET Framework 的 `UIAutomationClient` / `System.Windows.Forms`（系统自带）
- 可选：Python 3 + `pywinauto`（`pip install pywinauto`），用于 `scripts/uia.py` 的语义通道；不装也能用 UIA 的 PowerShell 回退路径

## 安全边界（请读）

这套技能能移动**真实鼠标**、往**真实窗口**打字。技能内部写死了几条规矩：

- 只按 PID 认自己启动的窗口，绝不按标题猜、绝不 `Stop-Process -Name`；
- 破坏性动作（删除/覆盖/提交/付款/格式化/擦除）必须先截图、说清后果、等用户确认；
- 中文输入法会吃掉 `SendKeys`，一律走剪贴板；
- 预览坐标 ≠ 屏幕坐标（2560×1600 的屏在预览里是 1610×1006，要 ×1.59）。

但**最终责任在使用者**：不要在有未保存工作的窗口上做无人监督的自动化。

## 已知限制

- Java/SWT（CubeMX）不暴露控件，只能靠坐标点；虚拟桌面、最小化窗口抓不到内容（最小化窗口矩形会退化成 158×26）。
- Chromium canvas、游戏、部分 DirectUI 外壳同样没有可读控件树。
- 虚拟列表只能看到可视行，滚出屏幕的行矩形是错的。
- 像素差只能证明「画面变了」，不能证明「点对了」——关键操作仍要读界面文字复核。

## 开发

```bash
npm pack --dry-run     # 检查打包内容（应只含 lib/ skills/ cordis.patch.yml README LICENSE）
node -e "import('./lib/index.js').then(m=>console.log(m.SKILL_NAMES))"
```

`cordis.patch.yml` 里的 `!!js` 表达式由 DSH 宿主在沙箱外求值，只做一件事：把本包的 `skills/` 目录算成绝对路径交给技能加载器。评审插件时请把它当宿主机代码看。

## 许可

MIT。见 [LICENSE](LICENSE)。
