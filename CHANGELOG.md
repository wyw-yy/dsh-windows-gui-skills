## 0.1.5 - 2026-10-18

Self-review of 0.1.4, found and fixed six issues:

- Get-ChangeMask used per-pixel GetPixel (2560x1600 took ~10 s). Rewritten as
  PixelMask.Write with LockBits + Marshal.Copy: **136 ms** (73x).
  (unsafe cannot be used: Add-Type compiles without /unsafe.)
- Invoke-ClickTemplate returned two different shapes; on "not found" it had no
  .Changed, so callers silently read $null. Now one shape, always with
  Clicked/Found/Reason/Changed/Ratio/RawRatio.
- Test-HoverPopup parked the pointer at (X-600, Y-600), which can land on
  another widget and raise ITS tooltip -> wrong bbox. Now parks at (4,4) and
  restores the original cursor position afterwards.
- Save-ImageCrop had no bounds check (GDI threw a cryptic error); now throws
  with the rect and the image size.
- A checkbox tick changes too few pixels for the 24-px-cell cluster pass, so a
  real click could report Changed=false. Added a raw-ratio fallback
  (RawRatio >= 0.00005).
- Win32UI had no GetCursorPos, which Test-HoverPopup needs. Added.

Verified: mask 136 ms; template click on a live WinForms button ->
ound/clicked/changed true and the app's own label went idle -> pong-211549;
self-match on an identical screenshot scores 0 at the exact position.
## 0.1.4 - 2026-10-18

- NEW scripts/pixelscan.ps1 (auto-loaded by ui.ps1): pixel localization that
  survives window moves and mouse interference.
  - Get-ScreenBurst / Get-ChangedRegion / Get-ChangeMask: burst capture plus
    cluster-aware diff (largest 8-connected cluster of changed 24px cells).
  - Find-ImageOnScreen / Invoke-ClickTemplate / Save-ImageCrop: template match
    (coarse step 4, then +-8 px refine) with a flat-template guard, plus verified click.
  - Test-HoverPopup: diff "pointer on target" vs "pointer away" to find flyouts.
- ui.ps1 now calls Set-DpiAware when dot-sourced, so Click(x,y) is physical
  pixels on every display scale (previously only Get-ScreenInfo was aware).
# Changelog

## 0.1.3 鈥?2026-10-18

绗簩杞鏍革紙`REVIEW-NOTES-2.md`锛夐€愭潯澶勭悊锛?
- **`click --input` 瀛楁鏀瑰悕**锛氳緭鍑虹敱鍚硦鐨?`foreground` 鏀逛负 `foreground_before`
  + `foreground_after`锛屾棦鑳借〃绀?鐐逛箣鍓嶅氨鍦ㄥ墠鍙?锛屼篃鑳借〃绀?椤烘墜鎶捣鏉ヤ簡"銆?  鎷掔粷鍒嗘敮鍚屾牱甯?`foreground_before: false`銆?- **`tree` 涓嶅啀鎶㈢劍鐐?*锛氳瀵熺被鎿嶄綔榛樿涓嶈皟 `set_focus`锛岄渶瑕佹椂鏄惧紡鍔?`--focus`銆?  瀹炴祴涓ょ獥鍙ｆ硶楠岃瘉锛氬闈炲墠鍙扮獥鍙ｈ窇 `tree`锛宍GetForegroundWindow()` 鍓嶅悗涓嶅彉銆?- **鏈€灏忓寲 / 鍧愭爣閫€鍖栨姢鏍?*锛氭柊澧?`is_minimized()`銆乣rect_bogus()`銆乣bogus_reason()`銆?  `find` 閬囧埌鏈€灏忓寲绐楀彛涓嶅啀杩斿洖 `(-47940,-47940)` 杩欑被鍧愭爣锛岃€屾槸甯?  `"unusable"` 璇存槑骞堕€€鍑?**4**锛沗click` 鍚屾牱鍏堣繃杩欓亾妫€鏌ワ紙`--force` 鍙秺杩囷級銆?- **DPI 涓€鑷存€?*锛歚main()` 鍚姩鍗?`SetProcessDpiAwareness(2)`锛岄伩鍏?pywinauto 鐨?  鐗╃悊鍍忕礌鐭╁舰涓?`GetSystemMetrics` 鐨勯€昏緫鍍忕礌鍦?150% 缂╂斁涓嬩簰鐩哥煕鐩俱€?- 鏂囨。琛ワ細閫€鍑虹爜 0/2/3/4 璇箟銆乣--focus` 鐢ㄦ硶銆佹嫆缁濊矾寰勭殑鍙鐜版祴娉?  锛堝悓涓€涓祴璇曠獥鍙ｅ紑涓ゆ锛岀敤 `--handle` 鎸囧悜闈炲墠鍙扮殑閭ｄ釜锛夈€?- **`jabswitch` 瀹炴祴缁撹**锛氬 STM32CubeMX 6.16.1 鏃犳晥鈥斺€擿-enable` 鎴愬姛銆?  JRE 閲?`javaaccessbridge.dll` / `windowsaccessbridge-64.dll` 閮藉湪銆佸簲鐢ㄩ噸鍚悗
  UIA 鏍戜粛鍙湁 6 涓獥鍙ｈ楗拌妭鐐癸紙鏃?`GENERATE CODE`锛夈€備袱涓妧鑳介噷鐨勫缓璁兘鏀规垚
  "璇曚竴娆″氨澶燂紝鍒啀璇曠浜屾"銆?
## 0.1.2 鈥?2026-10-18

澶栭儴瀹℃牳锛坄REVIEW-NOTES-2026-10-18.md`锛夐€愭潯淇锛?
- **P0 `uia.py` 宕╂簝**锛歚control_of()` 涓嶅啀瀵?`UIAWrapper` 璋?`child_window()`
  锛堟鍓?`find`/`click` 蹇呮姏 `'UIAWrapper' object has no attribute 'child_window'`锛夛紝
  鏀逛负鎸夌鍏堥亶鍘嗗尮閰嶏紝`tree` 鐨勭缉杩涙寜鐪熷疄娣卞害杈撳嚭銆?- **P1 鐗╃悊鐐瑰嚮浼氱偣鍒板埆鐨勭獥鍙?*锛歚uia.py click --input` 鍦ㄧ洰鏍囩獥鍙ｄ笉鏄墠鍙版椂鎷掔粷锛?  閫€鍑虹爜 3 骞剁粰鍑烘彁绀猴紱纭灞傚彔鍏崇郴鍚庢墠鍙?`--force`銆?- **P1 鏂囨。鍐欓敊 HAL 琛屼负**锛歚stm32f4-bringup` 鐨?3b 鑺傜籂姝ｄ负鈥淗AL 涓嶆牎楠?PLL 棰戠巼鈥濓紝
  `HAL_RCC_OscConfig` 鍦ㄧ瓑 `PLLRDY` 瓒呮椂鍚庤繑鍥?`HAL_TIMEOUT`
  锛坄stm32f4xx_hal_rcc.c:487`锛屼笉鏄?`HAL_ERROR`锛夛紝骞惰ˉ涓?`.ioc` 閲?  `HCLK=168000000` 鐨勮法鍨嬪彿闄烽槺銆?- **P2 瀹氫綅 API**锛歚Get-Window -Like` 鐪熸寜閫氶厤绗﹁浆涔夛紙`-Regex` 鎵嶅綋姝ｅ垯锛夈€佹柊澧?  `Get-Window -Hwnd` 涓?`-Pattern` / `-Title` 鍒悕锛沗Assert-Window` 鎺ュ彈 HWND銆?  IntPtr 鍜?`Get-WindowList` 鐨勮锛岄敊璇俊鎭篃璇存槑璇ヤ紶浠€涔堛€?- **P2 鎴浘濂戠害**锛歚Get-WindowCapture` 瀵规渶灏忓寲绐楀彛鐩存帴鎶涢敊锛坄-NoThrow` 鎵嶈繑鍥炵姸鎬侊級锛?  榛樿鏂囦欢鍚嶅甫 HWND锛沗Test-Occluded` 鐢ㄩ殢鏈烘枃浠跺悕骞惰繑鍥炵湡瀹?`WindowPng/ScreenPng`銆?- **P2 纭鍒?*锛氳ˉ UAC 鎻愭潈绐楀彛涓嶅彲鎺э紙UIPI锛夈€佹埅鍥炬秹鍙婇殣绉併€佽剼鏈唴淇濇寔 ASCII銆?- **鎻忚堪鍘婚噸**锛歚windows-gui-control` 鏀逛负鈥滃嚱鏁板弬鑰冣€濓紝鍏ュ彛鍒ゆ柇褰?  `windows-screen-automation`锛岄伩鍏嶅洓涓妧鑳界殑瑙﹀彂鎻忚堪浜掔浉閲嶅彔銆?
## 0.1.0 鈥?2026-10-18

棣栦釜鐗堟湰銆傛妸鍥涗釜鍦ㄧ湡瀹炰换鍔￠噷楠岃瘉杩囩殑鎶€鑳芥墦鍖呮垚 DSH 鎻掍欢銆?
- `windows-gui-control`锛歚ui.ps1`锛?9 KB锛?5 涓嚱鏁帮級+ `uia.py`锛坧ywinauto 妗ワ級
- `windows-screen-automation`锛氱湅鈫掔偣鈫掗獙闂幆銆乣Get-WindowCapture` 閬尅鎴浘銆佸儚绱犲樊闃堝€?- `windows-uia-inspector`锛歎IA 鏍?dump銆佸畾浣嶄紭鍏堢骇銆丣ava/SWT 绌烘爲鐨勫缃?- `windows-input-bridge`锛氬壀璐存澘鎵撳瓧銆佺粍鍚堥敭銆佺劍鐐?鏃跺簭銆佹帶鍒跺彴绐楀彛鐨勭壒娈婃儏鍐?
宸查獙璇佺殑鍦烘櫙锛?
- STM32CubeMX锛圝ava/SWT锛屾棤鎺т欢鏍戯級锛氱偣 `GENERATE CODE`銆佺偣鏃堕挓姹傝В鍣ㄥ璇濇
- Keil uVision锛歚UV4.exe -b/-f` 涔嬪鐨勫浘褰㈡搷浣?- 璁颁簨鏈?/ 璧勬簮绠＄悊鍣?/ cmd锛氱湡瀹為紶鏍囩偣鍑?+ 鍓创鏉挎墦瀛?+ 绐楀彛鎴浘鍥炴墽

宸茬煡闂锛?
- 鏈€灏忓寲绐楀彛鏃犳硶鎴浘锛堢煩褰㈤€€鍖栦负 158脳26锛夛紱
- 鍚姩鍣ㄨ繘绋?PID 鈮?绐楀彛 PID锛圵in11 鎵撳寘搴旂敤浼氬鐢ㄥ疄渚嬶級锛宍Get-WindowByPid` 鍙兘杩斿洖 `$null`锛岃剼鏈凡鍔?`Assert-Window` 鏄庣‘鎶ラ敊銆?

