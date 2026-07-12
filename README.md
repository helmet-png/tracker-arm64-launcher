# Tracker ARM64 Launcher for Windows on ARM

Run the [Tracker](https://physlets.org/tracker/) video-analysis tool at **native ARM64 speed** on Windows on ARM (Snapdragon X, etc.) — no x64 emulation.

**[繁體中文說明 ↓](#繁體中文說明)**

## The problem

The official Tracker installer bundles an x64 build of OpenJDK and the Xuggle video engine. On an ARM laptop, the entire stack — Java JIT, video decoding, auto-tracking computation — runs through Windows' Prism x86→ARM emulation layer, which is 3–10x slower.

Worse: even if you run Tracker's jar yourself with a native ARM64 Java, Tracker's launcher (`tracker.jar`) and main program **relaunch themselves on the bundled x64 JRE**.

## The solution

1. **Native ARM64 JVM** — Microsoft OpenJDK for ARM64 runs the main jar `tracker-x.y.z.jar` directly.
2. **`TRACKER_RELAUNCH=true`** — an environment variable that stops Tracker from relaunching itself on the x64 JRE (found by decompiling `Tracker.class`).
3. **Video → JPG sequence** — Xuggle is a native x64 DLL that the ARM64 JVM can't load, so a native ARM64 build of ffmpeg converts the video to an image sequence first (capped at 1280px wide for speed).
4. **Auto-generated .trk project** — the conversion step writes a minimal Tracker project file with `delta_t` (= 1000/fps ms) already set, so the frame rate is correct on open — no manual Clip Settings needed.

## Install

```powershell
winget install Microsoft.OpenJDK.21     # ARM64 native JDK (auto-selected on ARM)
winget install BtbN.FFmpeg.GPL.8.1      # ARM64 native ffmpeg (winarm64 build)
```

1. Download `tracker_launch.bat`, `video_to_trk.ps1` and `repair_trk.ps1` from this repo into the same folder.
2. Create a desktop shortcut to `tracker_launch.bat`; you can point its icon at `C:\Program Files\Tracker\tracker.ico`.
3. (Optional) Run `fix_prefs.ps1` as Administrator to permanently silence the "missing video engine" warnings and set the memory limit to 2GB.

The scripts auto-detect `C:\Program Files\Microsoft\jdk-*`, `C:\Program Files\Tracker\tracker-*.jar`, and the ffmpeg location.

## Usage

| Action | Result |
|---|---|
| Double-click the shortcut | Opens Tracker (native ARM64) |
| Drop a video on the shortcut | Auto-converts to a JPG sequence → builds a .trk → opens in Tracker with frame rate already set |
| Drop a .trk on the shortcut | Opens it; old movie-based projects are auto-repaired to image sequences at full resolution (original kept as `.trk.bak`), or fall back to the bundled x64 Tracker when the sequence cannot fit in RAM |

## Caveats

- There's no video engine in this mode: mp4s can't be opened from inside Tracker — always drop the video on the shortcut first.
- Don't double-click a .trk file directly — the file association still points to the old x64 `Tracker.exe`.
- If a project's original video file is gone, it still opens in data-only mode (tracked points, plots and tables all work; points show on a blank background) — just dismiss the one-time "unsupported format" dialog.
- The whole image sequence loads into RAM, so the Java heap size is computed per project. For long videos a dialog shows the suggested sampling (keep every Nth frame, `delta_t` adjusted so timing stays exact) and lets you change N or keep all frames; the effective frame rate appears in Tracker's Clip Settings as usual.
- Verified on Tracker 6.3.4 + Microsoft OpenJDK 21 + Snapdragon X (Windows 11).

## License

MIT

---

## 繁體中文說明

讓 [Tracker](https://physlets.org/tracker/)（物理影片分析軟體）在 Windows on ARM（Snapdragon X 等）上以**原生 ARM64 速度**執行，不再走 x64 模擬層。

### 問題

Tracker 官方安裝包內建 x64 版 OpenJDK 與 Xuggle 影片引擎。在 ARM 筆電上，整套軟體（Java JIT、影片解碼、自動追蹤運算）都經過 Windows Prism x86→ARM 模擬層執行，慢 3–10 倍。

更麻煩的是：即使你自己用 ARM64 Java 去跑它的 jar，Tracker 的啟動器（`tracker.jar`）和主程式都會**自我重啟回內建的 x64 JRE**。

### 解法

1. **原生 ARM64 JVM** — Microsoft OpenJDK ARM64 直接跑主程式 `tracker-x.y.z.jar`。
2. **`TRACKER_RELAUNCH=true`** — 環境變數，阻止 Tracker 自我重啟回 x64 JRE（從 `Tracker.class` 反組譯找到的機制）。
3. **影片 → JPG 序列** — Xuggle 是 x64 原生 DLL，ARM64 JVM 載不了，所以用原生 ARM64 版 ffmpeg 先把影片轉成圖片序列（限寬 1280 加速）。
4. **自動產生 .trk 專案** — 轉檔時直接寫出含 `delta_t`（=1000/fps 毫秒）的最小 Tracker 專案檔，開啟後幀率已設定好，不必手動填 Clip Settings。

### 安裝

```powershell
winget install Microsoft.OpenJDK.21     # ARM64 native JDK (auto-selected on ARM)
winget install BtbN.FFmpeg.GPL.8.1      # ARM64 native ffmpeg (winarm64 build)
```

1. 下載本 repo 的 `tracker_launch.bat`、`video_to_trk.ps1` 和 `repair_trk.ps1` 放到同一個資料夾。
2. 對 `tracker_launch.bat` 建捷徑放桌面，圖示可指到 `C:\Program Files\Tracker\tracker.ico`。
3. （可選）以系統管理員執行 `fix_prefs.ps1`，永久關掉「缺少影片處理程式」警告並把記憶體設為 2GB。

腳本會自動偵測 `C:\Program Files\Microsoft\jdk-*`、`C:\Program Files\Tracker\tracker-*.jar` 和 ffmpeg 位置。

### 使用

| 動作 | 結果 |
|---|---|
| 雙擊捷徑 | 開啟 Tracker（ARM64 原生） |
| 把影片拖到捷徑上 | 自動轉 JPG 序列 → 產生 .trk → Tracker 開啟，幀率已設好 |
| 把 .trk 拖到捷徑上 | 直接開啟；舊式（影片來源是 mp4 的）專案會自動修復成原解析度圖片序列（原檔備份為 `.trk.bak`），塞不進 RAM 的則自動改用內建 x64 版 Tracker 開啟 |

### 注意

- 此模式下 Tracker 沒有影片引擎：mp4 不能直接從 Tracker 內開啟，一律把影片拖到捷徑轉檔。
- 別直接雙擊 .trk 檔——檔案關聯仍指向舊的 x64 版 `Tracker.exe`。
- 原始影片檔遺失的專案仍可開啟（純數據模式：打點、圖表、表格都正常，點顯示在空白背景上）——把開啟時跳出的「不支援的格式」提示按掉即可。
- 圖片序列會全部載入 RAM，Java heap 依專案大小自動計算。過長的影片會**彈出視窗**顯示建議降幀值（每 N 幀取 1，`delta_t` 同步調整、時間軸仍精確），可自行改 N 或選擇全保留；降完的有效幀率會正常顯示在 Tracker 的 Clip Settings 裡。
- 在 Tracker 6.3.4 + Microsoft OpenJDK 21 + Snapdragon X (Windows 11) 驗證過。

### 授權

MIT
