# REVIEW-NOTES.md · dsh-windows-gui-skills

审核对象：`_skill-review-2026-10-18/skills/` 下 5 个技能（源仓库 `github.com/wyw-yy/dsh-windows-gui-skills`）
审核环境：Windows 11（build 26100）、Windows PowerShell **5.1.26100.9711**、Python 3.12.8 + pywinauto 0.6.9、
屏幕 2560×1600 物理 / **150% 缩放**（`GetSystemMetrics(SM_CXSCREEN)` 在未做 DPI aware 的进程里返回 1707×1067，
`Set-DpiAware` 之后返回 2560×1600 —— 两者都对，差值就是 1.5 倍）。
本次为**实跑 + 源码核对**，不是通读式复核。

---

## 汇总：3 个必须修的（P0/P1）

| # | 严重度 | 一句话 |
|---|---|---|
| 1 | **P0** | `uia.py` 的 `find` / `click` / `value` 三个子命令**全部崩溃**，语义点击通道实际上不存在 |
| 2 | **P1** | `uia.py click` 用 `click_input()` 走真实屏幕坐标，**窗口被遮挡时会点到遮挡它的窗口**，且不做效果校验 |
| 3 | **P1** | `stm32f4-bringup` 关于 `HAL_RCC_OscConfig` 的结论**与 HAL 源码不符**（返回 `HAL_TIMEOUT` 不是 `HAL_ERROR`，且 HAL 根本不校验 PLL 频率） |

---

## P0 · `uia.py find/click/value` 全部不可用

- 位置：`skills/windows-gui-control/scripts/uia.py:90`（`control_of()`）与 `:58`（`find_window()`）
- 证据（实跑，三个子命令同一条错误）：

```
$ python uia.py find  --title "npmjs" --name "new tab"
ERROR: 'UIAWrapper' object has no attribute 'child_window'
$ python uia.py click --title "npmjs" --name "new tab"
ERROR: 'UIAWrapper' object has no attribute 'child_window'
$ echo $LASTEXITCODE
1
```

- 根因：`find_window()` 返回的是 **`UIAWrapper`（已经解析好的控件）**，而 `control_of()` 对它调用
  `w.child_window(**crit)` —— `child_window` 只存在于 **`WindowSpecification`** 上。pywinauto 里
  `Desktop(...).window(title=...)` 返回 spec，`.exists()` / `.set_focus()` 之后拿到的才是 wrapper。
  函数里 `w.exists(timeout=0.3)` 这一步就把 spec 变成了 wrapper，于是后面必然炸。
- 影响：`windows-uia-inspector` 的标题写着 "Includes the pywinauto CLI bridge"，
  `AGENTS.md` 第 35 行也把 `python scripts\uia.py find` 列为第 2 优先通道。实际是**只有 `windows` / `tree` /
  `text` / `focus` 能用**（这四个不走 `control_of`），凡是"按名字定位并操作控件"的路径 100% 失败。
  因为直接抛异常且退出码 1，不比静默失败更危险，但会让使用者误判为"这个控件不存在"。
- 建议：`control_of()` 分两种情况，别赌类型：

```python
def control_of(w, name=None, auto_id=None, control_type=None):
    crit = {}
    if name: crit["title"] = name
    if auto_id: crit["auto_id"] = auto_id
    if control_type: crit["control_type"] = control_type
    if not crit:
        raise SystemExit("need --name / --auto-id / --type")
    if hasattr(w, "child_window"):          # WindowSpecification
        return w.child_window(**crit)
    # UIAWrapper: 自己走一遍后代树
    for c in w.descendants():
        ei = c.element_info
        if name and (c.window_text() or "") != name: continue
        if auto_id and (ei.automation_id or "") != auto_id: continue
        if control_type and ei.control_type != control_type: continue
        return c
    raise SystemExit("CONTROL NOT FOUND")
```

  修完之后请把 `find`/`click`/`value` 各跑一次并贴进 README —— 目前这三个命令没有任何一次成功的技术记录。

---

## P1 · `uia.py click` 在被遮挡窗口上会点到别的窗口

- 位置：`skills/windows-gui-control/scripts/uia.py:154`（`c.click_input()`）
- 证据：`click_input()` 的实现是 `SetCursorPos` + 真鼠标事件，**按屏幕绝对坐标投递**。本次实测同机
  有 `Occluded=True, Diff=192.5` 的窗口（DSH 被终端盖住），此时对它的控件调用 `click_input()`
  会把点击送到最上层窗口。而 `ui.ps1` 的 `Invoke-ClickElement`/`Invoke-VerifiedClick` 是会先做遮挡判断的
  —— 两个通道的安全等级不一致，偏偏 `AGENTS.md` 把 `uia.py` 排在截图之前。
- 影响：静默点到用户其它窗口（可能是编辑器、可能是删除按钮）。这正是 `AGENTS.md` 第 66–74 行自己列为
  硬规则要避免的那类事故。
- 建议：①优先用 `c.invoke()`（UIA InvokePattern）/ `c.select()`，不碰鼠标；②确实需要物理点击时先
  `w.set_focus()` 再用 `ui.ps1` 的 `Invoke-VerifiedClick` 并读 `Changed/Diff`；③`click` 成功时不要无条件
  打印 `CLICKED`，改成打印 `{"clicked": true, "changed": true/false, "diff": n}`，否则它违反了
  `windows-screen-automation` 自己立的"证明点击生效"原则。

---

## P1 · STM32：`HAL_RCC_OscConfig` 的失败原因写错了（有源码证据）

- 位置：`skills/stm32f4-bringup/SKILL.md`（PLL 越界那段，REVIEW.md 第 53 行引用的同一条）
- 技能原文结论：*"`HAL_RCC_OscConfig` 越界返回 `HAL_ERROR` 而不是钳制"*
- 证据（本机 HAL 源码 `C:\Users\yang'yu\Desktop\deep32\MX_PA11_LED\Drivers\STM32F4xx_HAL_Driver\Src\stm32f4xx_hal_rcc.c`）：

```
471:  assert_param(IS_RCC_PLLM_VALUE(RCC_OscInitStruct->PLL.PLLM));
472:  assert_param(IS_RCC_PLLN_VALUE(RCC_OscInitStruct->PLL.PLLN));
483:  while (__HAL_RCC_GET_FLAG(RCC_FLAG_PLLRDY) != RESET)
487:  return HAL_TIMEOUT;
```

  两点都不对：
  1. **HAL 不校验频率**。`IS_RCC_PLLM_VALUE` / `IS_RCC_PLLN_VALUE` 只查位宽（PLLM 2..63、PLLN 50..432），
     `PLLM=8 / PLLN=336` 完全合法地通过断言。VCO=672MHz 越界这件事，**HAL 一无所知**。
  2. **返回值是 `HAL_TIMEOUT` 不是 `HAL_ERROR`**（第 487 行）。物理过程是 PLL 锁不上 → 等 `PLLRDY` 超时。
  也就是说 HAL 既没有"钳制"也没有"拒绝"，它只是**配置完然后等锁，等到超时**。
- 影响：读者会以为"HAL 会帮我拦下来"。真实行为是 `HAL_TIMEOUT`，如果代码只判 `!= HAL_OK` 就没事，
  但若写成 `if (HAL_RCC_OscConfig(...) == HAL_ERROR)` 就会漏掉，直接跑到 4xx MHz 的 SYSCLK 上。
  排查时按 `HAL_ERROR` 去找也会找不到。
- 建议：改成
  > `HAL_RCC_OscConfig` 不校验 PLL 频率，只写寄存器然后轮询 `PLLRDY`；参数越界时 PLL 锁不上，
  > 等满超时后返回 **`HAL_TIMEOUT`**（`stm32f4xx_hal_rcc.c:487`）。判据一律用 `!= HAL_OK`。

- 附带发现（同目录 `.ioc`）：`MX_PA11_LED.ioc` 里是 `PLLM=8 / PLLN=336 / PLLP=DIV4 / HCLK=168000000`,
  这是 F411/F407 的 168MHz 参数，对 F401 直接越界 —— REVIEW.md 记录的失败案例就是它。
  `PLLM=16` → VCO 输入 1MHz → VCO 336MHz → /4 = 84MHz，与实测"同工程 PLLM=16 正常工作"完全对得上。

- **未能核实（不是错误，是没找到原文）**：
  - "F401 VCO 输出 192–432MHz、VCO 输入 1–2MHz" —— 只找到二手页面，没打开 RM0368 的 PLL 章节原文。
  - "84MHz 需 `FLASH_LATENCY_2` + `VCO_SCALE_2`" —— 没打开数据手册的 wait-state 表。
  这两条与 84MHz/3.3V 的常识一致，但我没有手册页码，请在技能里补上出处或标为"待核"。

---

## 已验证（这些是复核过的，下游可以直接信）

- **Windows PowerShell 5.1 下可用**：`Set-ExecutionPolicy -Scope Process Bypass -Force` + dot-source
  `ui.ps1` 正常，无解析错误。`Set-DpiAware` 返回 2560×1600，坐标空间正确。
- **纯 ASCII 规则确有必要（实测）**：我照抄写了个含中文标题字面量的 `.ps1`，5.1 直接
  `Unexpected token ... ParserError` 炸掉；同一脚本改成纯 ASCII 立刻正常。这条规则请保留，
  并且在 SKILL.md 里加一句"`.ps1` 里连注释都别写中文"。
- **不加 ExecutionPolicy 时的失败形态很难懂**：在 pwsh 下直接 dot-source 会得到
  `SecurityError: AuthorizationManager 检查失败`，看不出是执行策略问题（脚本里的中文提示也没帮上忙）。
  建议在 SKILL.md 顶部把 `Set-ExecutionPolicy` 标成"第一条，不是可选项"。
- **`PrintWindow(PW_RENDERFULLCONTENT)` 在 Chromium/Electron 上工作正常**——这一点比预期好：
  | 窗口 | 类名 | 结果 |
  |---|---|---|
  | DSH 主窗（被终端遮挡） | `Chrome_WidgetWin_1` | `Status=OK mean=37.3 sd=43.6`，`Test-Occluded` → `Occluded=True Diff=192.5` |
  | Edge | `Chrome_WidgetWin_1` | `Status=OK mean=223.2 sd=74.7` |
  | 资源管理器 | `CabinetWClass` | `Status=OK mean=30.3 sd=21.9` |
  | CC Switch | `Tauri Window` | `Status=OK mean=34.6 sd=24.9` |

  即"WebView/Electron 抓不到"在本机（Win11 26100）**没有复现**。建议技能里补一句适用范围
  "在 Win10 19045 / Win11 26100 上验证；老版本 Win10 与部分 GPU 合成路径仍可能返黑"，
  而不是笼统写"可能黑"。
- **最小化窗口确实抓不到**：`Status=TOOSMALL 237x39 iconic=True` —— 但注意它**不写文件**
  （`Test-Path` 为 false）。调用方紧接着 `read_image` 会得到一个"文件不存在"，离真正的
  "窗口最小化了"十万八千里。建议 `Get-WindowCapture` 在 TOOSMALL 时直接 `throw`
  或写一张占位图 + 把原因放进 `Status`。
- **Chromium 窗口的 UIA 树几乎是空的**：Edge 在 `--depth 4` 下只枚举出 8 个元素
  （一堆无名的 `Pane` + `StatusBar`），`uia.py text` 只拿到 2 行文本。确认"网页类窗口必须回落到看图"。
- **`uia.py windows` / `focus` / `text` 正常**，中文标题不乱码（`reconfigure(encoding="utf-8")` 起作用了，
  这条写法值得保留）。
- **截图成本很低**：单窗 29–105 ms。所以"点完就重截一张"完全负担得起，不要为了省一次截图去猜。

---

## P2 · 其余问题

### P2 `cmd_tree` 的缩进永远是 0
- 位置：`uia.py:111`，`"  " * 0`
- 证据：`tree --depth 4` 输出 8 行全是顶格，看不出父子关系，等于放弃了树形信息。
- 建议：按深度累加（`descendants` 里用 `c.element_info.depth` 或自己维护层级）。

### P2 `Get-Window -Regex` 的参数绑定容易误用
- 位置：`ui.ps1:112`（`param([string]$Like, [switch]$Regex)`）
- 证据：`Get-Window -Regex '^foo$'` 会把 `'^foo$'` 按位置绑给 `$Like`，`-Regex` 拿到 `$true`——
  恰好能工作，但读代码的人会以为 `-Regex` 收模式串。我第一遍就写错了。
- 建议：改成 `-Pattern <string> -Literal`（默认字面量，`-Pattern` 才走正则），或至少把注释写在 param 旁边。

### P2 `Test-Occluded` 用固定文件名
- 位置：`ui.ps1`，输出到 `$env:TEMP\occ_win.png` / `occ_screen.png`
- 证据：本次返回 `WindowPng : C:\Users\yang'yu\AppData\Local\Temp\occ_win.png`，固定名。
- 建议：加时间戳或 `-Path` 参数。两个 agent 并行时会互相覆盖，得到"遮挡了但 Diff=0"的假结论。

### P2 `-Window` 不接受 HWND / PID，错误信息误导
- 位置：`ui.ps1:177 Assert-Window` 的默认 hint
- 证据：我把 `EnumWindows` 拿到的 `IntPtr` 直接传进去，八个窗口全部得到
  `window not found: got $null (app not started yet, or matched by PID of a launcher process)`——
  但窗口明明在，问题是**参数类型不对**（需要 `AutomationElement`，不是 HWND）。
- 建议：`Assert-Window` 里先判 `$Window -is [IntPtr]` / `-is [int]`，是的话用
  `AutomationElement::FromHandle()` 转换后再继续；错误信息里把"传什么类型"写清楚。

---

## 触发词与分工（P2，但会实际影响加载）

四个 `windows-*` 技能的 `description` **互相重复**：

| 技能 | 宣称的能力 | 重复点 |
|---|---|---|
| `windows-gui-control` | 截图 + PrintWindow + 控件树 + 真实鼠标 + 剪贴板打字 + 验证点击 | **几乎是另外三个的并集** |
| `windows-screen-automation` | 截图/遮挡/像素差/重试 | 与上一行的"截图 + 验证点击"重 |
| `windows-uia-inspector` | UIA 树/按名字点/Java 无控件对策 | 与上一行的"控件树"重 |
| `windows-input-bridge` | 剪贴板/组合键/鼠标三键/焦点 | 与上一行的"剪贴板打字"重 |

- 现状：`windows-gui-control` 的触发词写着"帮我点一下 / 截图看看 / 自动化这个界面"，
  这三个短语**正好是另外三个技能最该被命中的场景**。结果就是任何 GUI 任务都先命中
  gui-control，另外三个很少被单独加载，分工表（AGENTS.md 第三节）实际上失效。
- 建议：`windows-gui-control` 的 description 收缩成"函数参考手册：ui.ps1 有哪些函数、签名是什么、
  选哪个"，触发词改成"需要 ui.ps1 的函数清单/不知道该调哪个函数"；把
  "帮我点一下 / 截图看看" 移到 `windows-screen-automation`。
  `stm32f4-bringup` 的触发词（`flashed fine but the LED is dark`）很清晰，不用动。

## 安全规则缺口（建议补进 SKILL.md）

1. **UAC 提权窗口**：非提权进程对它既看不到控件也发不进消息，表现是 `NOT FOUND`，不是权限错误。
   现在 4 个技能都没提，使用者会误判成"没有这个控件"。
2. **截图前的隐私检查**：密码框、私信、浏览器标签标题都会被 `PrintWindow` 原样抓进上下文，
   且不可撤回。建议加一条"截 GUI 前先看窗口标题是否含密码/银行/私信"。
3. **`uia.py click` 与遮挡判断不一致**（见上面 P1 第 2 条）。

---

## 没做的部分（诚实交代）

- 双屏 / 负坐标 / 远程桌面：本机单屏，**没测**。
- 125% / 150% 两档下的 `Invoke-VerifiedClick` 落点误差：只验证了 150% 的 DPI 上报正确，
  没有用真实点击去标定误差。
- `SendInput` 与 `mouse_event` 的对比：没做，技能里 `mouse_event` 的写法按现有证据不算错。
- `install.ps1` / `lib\index.js` / `cordis.patch.yml` 未审。
- CubeMX（Java/SWT）的 `jabswitch` 建议未验证。
