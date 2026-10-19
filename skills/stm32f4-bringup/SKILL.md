---
name: stm32f4-bringup
description: Get an STM32F4 board from "it flashed fine but the LED is dark" to a verified blink, using the Keil command line (UV4 -b / -f) and CubeMX-generated projects. Covers the clock-config traps that silently park the MCU in Error_Handler, LED polarity and pin-mapping checks, and the exact log markers that prove a build or a flash really succeeded. Use when a firmware builds and flashes with 0 errors but does nothing, when a CubeMX project has no visible output, when you need to compile/flash without opening uVision, or when PLL values from a .ioc have to be sanity-checked before trusting them. Also load it for the setup side — 用 CubeMX 新建工程 / 新建 CubeMX 工程 / 生成 Keil 工程 / 用 CubeMX + Keil 做个 xxx / .ioc 需要能生成代码 / CubeMX 批处理卡住或挂住 / 让 CubeMX 在命令行生成 — the headless recipe, the sandbox trap that makes javaw die silently, and the rule that only a CubeMX-saved .ioc generates.
---

# STM32F4 bring-up: build, flash, and prove it runs

A board that flashes with `Verify OK` and shows nothing is the normal case, not
the exception. Work the checklist in order; each step rules out one layer.

## 1. Build and flash without the IDE

```powershell
$uv = "C:\Keil_v5\UV4\UV4.exe"
& $uv -b "C:\path\proj.uvprojx" -j0 -o "C:\path\build.log"   # compile + link
& $uv -f "C:\path\proj.uvprojx" -j0 -o "C:\path\flash.log"   # build if needed, then download
```

`UV4.exe` exit codes are unreliable (it returns 1 for warnings). **Always read the
log**:

| Marker | Means |
|---|---|
| `0 Error(s), 0 Warning(s)` | build really succeeded |
| `Program Size: Code=... RO-data=... RW-data=... ZI-data=...` | link produced an image |
| `Erase Done.Programming Done.Verify OK.` | the flash was written and read back |
| `Error: Flash Download failed - Target DLL has been cancelled` | wrong debugger selected (see §2) |
| `No ST-LINK detected` | driver is right, probe is not plugged in |

## 2. Debugger settings live in the .uvoptx, not the .uvprojx

A CubeMX-generated project ships without a debugger choice, so uVision silently
defaults to ULINK2 and the first flash fails with `Target DLL has been
cancelled`. In `*.uvoptx`:

```xml
<nTsel>6</nTsel>
<pMon>STLink\ST-LINKIII-KEIL_SWO.dll</pMon>
```

`<nTsel>6</nTsel>` is ST-Link. Do not copy a `-U<serial>` option string out of
another project: it pins the config to one physical probe.

## 3. The LED-is-dark checklist

### 3a. Is the MCU even running? (most common cause)

A failing `HAL_RCC_OscConfig` / `HAL_RCC_ClockConfig` calls `Error_Handler()`,
which by default is `__disable_irq(); while (1);` — the board is dead and no
LED ever moves. **Make the error path visible first.** This blinks PA11 at
~5 Hz with raw registers, so it works even when the clock is wrong:

```c
void Error_Handler(void)
{
  __disable_irq();
  RCC->AHB1ENR |= RCC_AHB1ENR_GPIOAEN;
  GPIOA->MODER = (GPIOA->MODER & ~(3UL << 22)) | (1UL << 22);  /* PA11 output */
  volatile uint32_t n;
  while (1) {
    GPIOA->ODR ^= (1UL << 11);
    for (n = 0; n < 400000UL; n++) { __NOP(); }
  }
}
```

Now the LED tells you which layer failed: requested blink = running,
fast blink = clock error, dark = pin or wiring.

### 3b. Check the PLL arithmetic, especially PLLM

STM32F4 limits: **PLL input 1–2 MHz, VCO output 192–432 MHz** (F401: 192–432).
Two caveats, both verified against the HAL source on this machine
(`Drivers/STM32F4xx_HAL_Driver/Src/stm32f4xx_hal_rcc.c`):

- **HAL does not validate frequencies.** `assert_param(IS_RCC_PLLM_VALUE(...))`
  and `IS_RCC_PLLN_VALUE(...)` only check bit widths (PLLM 2..63, PLLN 50..432).
  `PLLM=8 / PLLN=336` passes every assertion while producing a 672 MHz VCO.
- **The failure comes back as `HAL_TIMEOUT`, not `HAL_ERROR`** — line 487 returns
  `HAL_TIMEOUT` after spinning on `RCC_FLAG_PLLRDY`. So HAL neither clamps nor
  rejects: it programs the registers and then waits for a lock that may never
  come. Always compare with `!= HAL_OK`, never `== HAL_ERROR`.

Real failure (2026-10-18, STM32F401RCT6, CubeMX output):

```
OscillatorType = HSI (16 MHz)      PLLM = 8    PLLN = 336    PLLP = /4
PLL input  = 16/8  = 2 MHz         inside 1-2 MHz, HAL is happy
VCO output = 2*336 = 672 MHz       > 432 MHz, HAL knows nothing about it
```

Outcome observed: the board flashed with `Verify OK` and the LED never moved, because
the clock init never returns success and `Error_Handler()` spins forever. Those PLL
values were correct for an **8 MHz HSE** and wrong for **16 MHz HSI**. Two working
configurations:

| Source | PLLM | PLLN | PLLP | SYSCLK | PLLQ |
|---|---|---|---|---|---|
| HSE 8 MHz | 8 | 336 | /4 | 84 MHz | 7 (48 MHz USB) |
| HSI 16 MHz | 16 | 336 | /4 | 84 MHz | 7 |

Rule: before trusting a `.ioc`, check `OscillatorType` and confirm the PLLM
matches that source. CubeMX writes derived values (`VCOOutputFreq_Value`, …)
that can be stale after a hand edit; the generated `.c` is the truth. A `.ioc`
shipped with `HCLK=168000000` is F407/F411 arithmetic and is out of range on an
F401 — verify the generated C, not the .ioc field.

Also check `FLASH_LATENCY`: 84 MHz at 3.3 V needs `FLASH_LATENCY_2`, and
`PWR_REGULATOR_VOLTAGE_SCALE2` above 84 MHz. (These two numbers match RM0368 and
the datasheet wait-state table; the exact page numbers are still to be cited — a
review flagged them as "consistent but uncited", so treat them as strong
convention rather than quoted spec.)

### 3c. Is the LED on that pin at all?

- Confirm the pin in the schematic, not from memory or a tutorial.
- Confirm polarity: an active-low LED (anode to 3.3 V) blinks exactly the same as
  active-high — brightness is inverted but the rhythm is not, so polarity almost
  never explains "fully dark".
- PA11/PA12 are USB_DM/DP on F4. They work as GPIO when USB is disabled, but a
  board may route them to the USB connector instead of the LED.
- Cheap decisive test: toggle three candidate pins at three different rates
  (PA11 at 2 s, PA5 at 0.5 s, PC13 at 0.25 s). Whichever LED lights names the pin.

### 3d. Busy-wait before blaming HAL_Delay

`HAL_Delay` needs SysTick interrupts. If `HAL_Init` was skipped, or interrupts
are disabled, the first `HAL_Delay` hangs forever and the LED never changes.
For a pure bring-up test use a `for (volatile ...)` loop first.

## 4. Verify the image, not your intentions

Disassemble and look for the constant you think you wrote:

```powershell
& "C:\Keil_v5\ARM\ARMCLANG\bin\fromelf.exe" --text -c --output=dis.txt proj.axf
Select-String -Path dis.txt -Pattern "0x7d0|HAL_Delay" -Context 2,2
```

`MOV r0,#0x7d0` before `BL HAL_Delay` is 2000 ms actually compiled in.

## 5. CubeMX specifics

- Headless: `STM32CubeMX.exe -q gen.txt`, where `gen.txt` is
  `config load <abs .ioc>` / `project generate` / `exit`. The launcher `.exe`
  forks `javaw` and returns immediately — watch the log for `Bye bye`, not the
  exit code.
- The `.ioc` must be one CubeMX itself wrote. A hand-written minimal `.ioc`
  fails with `IP not ready for code generation: Clock`, and a mismatched
  `MxDb.Version` triggers a database migration that can NPE on `Mcu.getDie()`.
- Editing `.ioc` text works for RCC keys, but CubeMX rewrites derived values on
  the next save, and `RCC.PLLQ=RCC_PLLQ_DIV7` may still emit
  `RCC_PLLQ_DIV7` in C, which is not a macro in this HAL — it wants a number
  (`PLL.PLLQ = 7;`).
- GUI automation is only for dialogs. Its UIA tree exposes the window frame and
  nothing else (Java/SWT), so it needs pixels and verified clicks.
- **Sandbox kills CubeMX silently.** Under a write-restricted sandbox
  (`workspace-write`), CubeMX cannot write `%USERPROFILE%\.stm32cubemx\`, so
  `javaw` exits within seconds and the log file's mtime simply stops — no error,
  no new line, and the launcher's exit code is already 0. Before blaming the
  `.ioc`, check: does the log have a new mtime? does `javaw` still exist? If
  both are no, it never ran. Re-run with write access to the home directory (or
  ask the user), do not retry blindly three times.
- A migration/dialog prompt inside the CubeMX window is a **self-drawn Swing
  panel, not a separate HWND** — enumerating windows will not find it. Capture
  the main window and look at the pixels.

## 6. Definition of done

1. Build log says `0 Error(s)` and prints a `Program Size` line.
2. Flash log says `Erase Done.Programming Done.Verify OK.`
3. The disassembly contains the delay/constant you intended.
4. **The human confirms the LED rhythm.** Without step 4 the job is unverified —
   say so instead of claiming success.

## 经验库（自动维护）

`knowledge\lessons.md` 是本技能的经验条目（<=40 行，加载技能时一并读）。
判据：**换一个任务，这句话还用得上吗？** 工程参数、账号、一次性坐标不要写。

- 命中（按它做并且成功）：`lesson.ps1 hit  -Skill <本技能> -Key <key>`
- 矛盾（按它做失败）：`lesson.ps1 miss -Skill <本技能> -Key <key>`（连续 2 次降一级，降到 1 标 [REFUTED]，保留但不再采用）
- 新增：只在“同一坑踩两次 / 结果推翻假设 / 用户明确指教”时
  `lesson.ps1 add -Skill <本技能> -Key <域>.<主题> -Text "<一句话规则>" -Confidence 3-5`
