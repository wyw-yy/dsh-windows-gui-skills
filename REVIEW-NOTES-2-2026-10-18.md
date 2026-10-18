# REVIEW-NOTES-2.md · dsh-windows-gui-skills 0.1.2

审核对象：`_skill-review-2026-10-18/skills/` 下 0.1.2 版（对照 `REVIEW-RESPONSE.md` 逐条复核）
审核环境：Windows 11，PowerShell **5.1.26100**，2560×1600 物理 / 150% DPI
测试载体：**我自己写的 WinForms 窗口**（标题 `UIATEST`，按钮 `PINGBTN` + 输出标签，90s 自毁），不复用包内自测脚本

---

## 汇总

对方声称 P0/P1/P2 全部修复。**逐条实测结论：3 个 P0/P1 全部真修好，4 个 P2 全部真修好，0 个回归。**

| # | 上轮问题 | 级别 | 结论 | 证据 |
|---|---|---|---|---|
| 1 | `uia.py find/click/value` 全崩 `child_window` | P0 | ✅ 已修 | 三命令 exit 0，返回值合理 |
| 2 | `click` 走真实坐标、不判遮挡 | P1 | ✅ 已修 | 返回 `"method": "invoke"`，语义点击优先 |
| 3 | `click` 无条件报 CLICKED | P1 | ✅ 已修 | 现在返回 method 字段 + foreground 字段 |
| 4 | `stm32` 误报 `HAL_ERROR` | P1 | ✅ 已修 | SKILL.md:79-82 改为 `HAL_TIMEOUT` |
| 5 | `cmd_tree` 缩进恒 0 | P2 | ✅ 已修 | 输出层级正确 |
| 6 | `-Window` 不收 HWND | P2 | ✅ 已修 | 传 int 成功 |
| 7 | `Test-Occluded` 固定文件名互覆盖 | P2 | ✅ 已修 | 两次随机名，互不相同 |
| 8 | 触发词并集、互相抢加载 | P2 | ✅ 已修 | 四条 description 已分工并互相指路 |

另有 **1 项未能端到端验证**（见下节）和 **3 条新发现**（P2，不阻塞发布）。

---

## 逐条复核（有证据的）

### P0 · uia.py 三个子命令

用我自己的窗口，不碰对方的 `UIATEST` 自测残留：

```
$ python uia.py find --title UIATEST --name PINGBTN
{"class": "Button", "control_type": "Button", "text": "PINGBTN", "auto_id": "PINGBTN",
 "rect": [162, 227, 342, 262], "center": [252, 244], "enabled": true,
 "patterns": ["invoke", "select", "toggle"]}
```

`rect` 落在窗口内、`center` 是几何中心、`patterns` 正确列出了 3 个可用模式 —— 说明 `find_window` → `control_of` → `describe` 这条链彻底通了，不是靠异常吞掉蒙对的。

`value` 读到 `pong-861615`：这个字符串**只有按钮真的被触发才会出现**，所以它是"点击确实生效"的端到端证据，而不是"函数没报错"。

### P1 · 语义点击优先

```
$ python uia.py click --title UIATEST --name PINGBTN
{"clicked": true, "method": "invoke"}
```

`method` 是 `invoke` 而不是 `click_input` —— 验证了"有语义模式就不动真实鼠标"的决策顺序。这条最关键：它把最危险的操作（真实坐标点击）从默认路径上移走了。

### P1 · stm32 的 HAL 结论

三处都改对了，措辞也准确：

- `SKILL.md:79-82` —— "The failure comes back as `HAL_TIMEOUT`, not `HAL_ERROR` … line 487 returns `HAL_TIMEOUT` after spinning on `RCC_FLAG_PLLRDY` … Always compare with `!= HAL_OK`, never `== HAL_ERROR`."
- `SKILL.md:105` —— 明确标注 `.ioc` 里的 `HCLK=168000000` 是 F407/F411 的算法、对 F401 越界。
- `SKILL.md:108-109` —— 补了 `FLASH_LATENCY_2` 与 `PWR_REGULATOR_VOLTAGE_SCALE2`（84MHz@3.3V）。

第 105 行那条是我上轮没直接要求、但由同一处源码推出来的坑，对方主动补进去了。

### P2 · 四条全部实测通过

```
Get-Window -Pattern '*UIATEST*'   -> OK   （别名可用）
Get-Window -Title  '*UIATEST*'    -> OK   （原参数仍可用）
Get-WindowCapture -Window 2885802 -> OK 630x330   （int HWND 被接受）
Get-WindowCapture -Window 2885802（不传 -Path）-> %TEMP%\win_2885802_capture.png
Test-Occluded 连跑两次 -> occ_62cda38e_win.png / occ_03c8888e_win.png（不同且都存在）
```

`630×330` = 420×220 逻辑尺寸 × 1.5 DPI，说明 HWND 路径同样过了 DPI 换算，不是碰巧。

默认文件名带 HWND、遮挡检查文件名带随机后缀 —— 并发调用不再互相覆盖。

### P2 · 触发词分工

四条 description 现在是分工而不是并集：`gui-control` 只认"我已经确定要用 GUI、要查函数签名/决策阶梯"，并在末尾显式写了 "For the general look-then-act strategy see windows-screen-automation; for typing see windows-input-bridge; for the control tree see windows-uia-inspector"。`screen-automation` 保留了中文触发词（帮我点一下 / 截图看看 / 自动化这个界面）。这个结构能避免"点一下"被函数手册抢走。

---

## 未能端到端验证的（诚实交代）

### `click --input` 的拒绝分支

代码是对的：

```python
if a.input:
    if not is_foreground(w.handle) and not a.force:
        print(json.dumps({... "refused": "target window is not foreground ..."}))
        return 3
```

谓词也是对的（单独单测过）：

```
is_foreground(当前前台窗口)      -> True
is_foreground(桌面窗口 0x10010)  -> False
is_foreground(0)                 -> False
```

**但我在这台机器上造不出"非前台"这个前提**：从后台进程调 `SetForegroundWindow` 被系统拒绝，`ShowWindow(hwnd, 6)` 对 WinForms 窗体也不生效，测试窗口始终是前台，于是每次 `--input` 都走了成功分支（`foreground: true`）。

所以结论只能到"**代码与谓词都正确，拒绝路径本身未被触发**"。建议补一个可复现的自测法（比如 `uia.py click --input` 对着一个被最大化窗口盖住的目标跑，或在 SKILL.md 里写明"把目标拖到第二个显示器再点"），否则这个安全网永远处于"写了但没人证明它拦得住"的状态 —— 和上轮 `print("CLICKED")` 是同一类问题，只是方向相反。

---

## 新发现（都是 P2，不阻塞发布）

### 1. `"foreground"` 字段是点击之后才求值的，读起来像"点击前"

```python
w.set_focus()
c.click_input()
print(json.dumps({"clicked": True, "method": "click_input",
                  "foreground": is_foreground(w.handle)}))
```

`set_focus()` 在前，所以这个字段**恒为 true**，它证明的是"点完之后它是前台"，不是"点之前它是前台"。字段名叫 `foreground` 很容易被下游读成后者，而后者才是决定"会不会点到别人"的那个条件。

建议改名 `foreground_after`，或再加一个点击前采样的 `foreground_before`。一行改动，消掉一个误读。

### 2. `cmd_tree` 无条件抢焦点

```python
try:
    w.set_focus()
except Exception:
    pass
```

`tree` 是只读探查，不应该改变桌面状态。它会在用户正在打字的窗口上把焦点抢走；对提权窗口还会静默失败（于是树可能是"未激活状态"的那份）。建议去掉，或加 `--focus` 开关，默认不抢。

### 3. 最小化窗口的 `find` 会返回荒谬坐标且不报警

上轮实测（`-WindowStyle Minimized` 启动的窗口）：

```
find -> {"rect": [-47976, -48019, ...], "center": [-47880, -47923], "enabled": true}
```

`enabled: true`、`exit 0`、无任何提示。调用方若信任 `center`，会把鼠标移到屏幕外，然后 Windows 把坐标钳到 (0,0) 或右下角 —— 正好是"静默点错东西"的教科书形态。

建议：`describe()` 里若 `rect` 完全落在虚拟屏幕之外（或 `right<=left`），直接 `exit 4` 并提示 `window may be minimized`。`ui.ps1` 那边已经对最小化做了 `TOOSMALL` 拦截，`uia.py` 这条路径没有对应防护，两边不对称。

（复现前提是窗口确实处于最小化；我这轮 `ShowWindow(6)` 没能把测试窗体最小化，所以这条沿用上轮的观测数据，标为"复现过一次"。）

---

## 结论

**0.1.2 可以发。** 上轮 3 个 P0/P1 是真修，不是把报错吞了：`find` 的 `rect`/`patterns` 内容自洽，`click` 返回 `method=invoke`，`value` 读到了只有点击成功才会出现的字符串。4 个 P2 也全部可复现地修好。

剩下的是一条未验证的安全网（拒绝分支）和三条 P2。三条 P2 里我建议只把第 1 条（`foreground` 字段名）和第 3 条（最小化坐标护栏）排进去 —— 它们都直接关系到"点错地方"这个核心失效模式；第 2 条（tree 抢焦点）属于体验，不是正确性。
