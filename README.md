# Tracker ARM64 Launcher for Windows on ARM

讓 [Tracker](https://physlets.org/tracker/)（物理影片分析軟體）在 Windows on ARM（Snapdragon X 等）上以**原生 ARM64 速度**執行，不再走 x64 模擬層。

Run the Tracker video-analysis tool at **native ARM64 speed** on Windows on ARM — no x64 emulation.

## 問題 / The problem

Tracker 官方安裝包內建 x64 版 OpenJDK 與 Xuggle 影片引擎。在 ARM 筆電上，整套軟體（Java JIT、影片解碼、自動追蹤運算）都經過 Windows Prism x86→ARM 模擬層執行，慢 3–10 倍。

更麻煩的是：即使你自己用 ARM64 Java 去跑它的 jar，Tracker 的啟動器（`tracker.jar`）和主程式都會**自我重啟回內建的 x64 JRE**。

## 解法 / The solution

1. **原生 ARM64 JVM** — Microsoft OpenJDK ARM64 直接跑主程式 `tracker-x.y.z.jar`。
2. **`TRACKER_RELAUNCH=true`** — 環境變數，阻止 Tracker 自我重啟回 x64 JRE（從 `Tracker.class` 反組譯找到的機制）。
3. **影片 → JPG 序列** — Xuggle 是 x64 原生 DLL，ARM64 JVM 載不了，所以用原生 ARM64 版 ffmpeg 先把影片轉成圖片序列（限寬 1280 加速）。
4. **自動產生 .trk 專案** — 轉檔時直接寫出含 `delta_t`（=1000/fps 毫秒）的最小 Tracker 專案檔，開啟後幀率已設定好，不必手動填 Clip Settings。

## 安裝 / Install

```powershell
winget install Microsoft.OpenJDK.21     # ARM64 native JDK (auto-selected on ARM)
winget install BtbN.FFmpeg.GPL.8.1      # ARM64 native ffmpeg (winarm64 build)
```

1. 下載本 repo 的 `tracker_launch.bat` 和 `video_to_trk.ps1` 放到同一個資料夾。
2. 對 `tracker_launch.bat` 建捷徑放桌面，圖示可指到 `C:\Program Files\Tracker\tracker.ico`。
3. （可選）以系統管理員執行 `fix_prefs.ps1`，永久關掉「缺少影片處理程式」警告並把記憶體設為 2GB。

腳本會自動偵測 `C:\Program Files\Microsoft\jdk-*`、`C:\Program Files\Tracker\tracker-*.jar` 和 ffmpeg 位置。

## 使用 / Usage

| 動作 | 結果 |
|---|---|
| 雙擊捷徑 | 開啟 Tracker（ARM64 原生） |
| 把影片拖到捷徑上 | 自動轉 JPG 序列 → 產生 .trk → Tracker 開啟，幀率已設好 |
| 把 .trk 拖到捷徑上 | 直接開啟舊專案 |

## 注意 / Caveats

- 此模式下 Tracker 沒有影片引擎：mp4 不能直接從 Tracker 內開啟，一律把影片拖到捷徑轉檔。
- 別直接雙擊 .trk 檔——檔案關聯仍指向舊的 x64 版 `Tracker.exe`。
- 長影片載入需要時間（圖片序列全部載入 RAM），建議先剪出需要的片段。
- 在 Tracker 6.3.4 + Microsoft OpenJDK 21 + Snapdragon X (Windows 11) 驗證過。

## License

MIT
