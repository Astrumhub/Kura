# Kazumi 自编译版（自用）

> 目的：在官方 Kazumi 基础上做自己的改动，**保留官方版不动**，两份并存。
> 官方版：`F:\Tools\KAZUMI`　自编版：`F:\Tools\Kazumi-SelfBuild`
> 源码：`F:\Projects\Kazumi`（浅克隆自 Predidit/Kazumi，2.4.2，GPL-3.0）

## 一、工具链（全部在 F 盘）

| 组件 | 路径 | 版本 |
|---|---|---|
| Flutter SDK | `F:\environments\Flutter` | 3.47.7 stable（官方 zip，已加进用户 PATH） |
| VS Build Tools | `F:\environments\VisualStudioBuildTools2022` | MSVC 14.44 + Windows SDK 10.0.26100 |
| nuget | `F:\Tools\nuget\nuget.exe` | 7.9（已在用户 PATH） |
| 7-Zip | `F:\Tools\7zip\7-Zip\7z.exe` | 26.02 |

C 盘只进：`%ProgramData%\Microsoft\VisualStudio\Packages`（约 0.7 GB 安装缓存，可删）。

## 二、编译命令

```powershell
$env:Path = 'F:\environments\Flutter\bin;F:\Tools\nuget;' + $env:Path
cd F:\Projects\Kazumi
flutter build windows --release
# 产物：build\windows\x64\runner\Release\
# 复制到 F:\Tools\Kazumi-SelfBuild（复制前必须先关掉正在运行的 kazumi.exe）
```

增量编译约 40 秒，全量约 2 分钟。

## 三、四个必踩的坑（都已解决，换机重装时照抄）

| 现象 | 原因 | 解法 |
|---|---|---|
| `webview_windows` 构建失败 | 缺 nuget.exe 拉 NuGet 包（WebView2 / WIL） | 装 nuget 到 `F:\Tools\nuget` 并加 PATH；同时在 `build\windows\x64\` 放一份 |
| `build_hooks failed / native assets` | `ech_http` 编译期要从 GitHub 下 4.8 MB 预编译包，直连超时 | 预先下好放 `build\.dart_tool\hooks_runner\shared\ech_http\build\prebuilt\windows-x64-<sha256>.zip` |
| `C2026 字符串太长` | `ech_http` 把 200 KB CA 证书包塞进**单个**字符串字面量，超 MSVC 16384 字节上限 | 见下方「ech_http 补丁」 |
| `--no-enable-native-assets` 无效 | `media_kit` 自身依赖 native assets | 放弃该开关，必须走补丁 |

## 四、改动清单（三处）

### 1. 播放器：AMD 硬件插帧（amf_frc）

文件：`lib/pages/player/controller/player_playback_controller.dart`

在 `_installPlayer` 里、`Platform.isAndroid` 分支之前加：

```dart
if (Platform.isWindows && frameGenEnabled) {
  await pp.command(["vf", "add", "amf_frc"]);   // 必须用 command，setProperty 会被静默忽略
}
```

前提参数（同处设置）：`hwdec=d3d11va`、`d3d11va-zero-copy=yes`。

> **关键教训**：mpv 的 `vf-append` 是命令行选项，运行时用 `setProperty` 改它**不会报错也不会生效**；运行时加滤镜必须用 `vf add` 命令。

### 2. 帧生成开关 + 统计浮层 + 快捷键

| 文件 | 改动 |
|---|---|
| `lib/pages/player/controller/player_playback_controller.dart` | `frameGenEnabled` 字段、`frameGenNotifier`（ValueNotifier）、`setFrameGen()` 方法（`vf add` / `vf remove`） |
| `lib/pages/player/player_item_panel.dart` | 底栏「帧生成」菜单按钮（超分辨率左侧）+ 切换后 toast |
| `lib/pages/player/player_stats_overlay.dart` | 新增：统计浮层（600ms 轮询 mpv 属性） |
| `lib/pages/player/player_item.dart` | 浮层接入 Stack、`_showStats` 字段、`showstats` 动作 |
| `lib/utils/constants.dart` | `defaultShortcuts` 加 `'showstats': ['I']`；`shortcutsChineseName` 加「播放统计」 |

### 3. ech_http 补丁（修 C2026）

`ech_http` 0.2.3 是本仓库最新的版本，上游未修。做法：把包复制进项目，用 `dependency_overrides` 指过去。

```
F:\Projects\Kazumi\third_party\ech_http\        ← 从 pub cache 复制来的 0.2.3
  src\CMakeLists.txt   ← 把 cacert.pem 切成 8KB 块，生成 EH_CA_CHUNKS
  src\ca_bundle.h.in   ← 改成「多个独立 raw string + 运行时拼接」
pubspec.yaml           ← dependency_overrides: ech_http: path: third_party/ech_http
```

这样改动跟着项目走，`pub cache repair` 冲不掉。

## 五、回滚

- 想回官方版：直接跑 `F:\Tools\KAZUMI\kazumi.exe`，自编版是独立目录，互不影响。
- 想撤某个改动：`git diff` 看改动，`git checkout -- <file>` 还原单个文件。
- 注意：`dependency_overrides` 一旦去掉，`ech_http` 会回到上游版本 → 编译必失败。

## 六、当前状态与待办

**已完成**
- 插帧 `amf_frc` 实测生效：23.976 → 47.952 fps，Kazumi 内置播放器
- 帧生成开关（底栏菜单，带 toast）
- 统计浮层（`I` 键开关）
- 快捷键可自定义（设置 → 键盘 → 播放统计）

**浮层待改（用户 2026-10-25 反馈）**
1. 位置：右上角 → **左上角**
2. 颜色：跟随应用主题（现在写死白色）
3. 删掉「引擎」行
4. 补全显示为 `—` 的字段：显示器、编码、迟帧、像素格式

**已知问题**
- **弹幕全部 403（2026-10-25 查明，原因在编译方式）**：`lib/utils/dandan_credentials.dart` 用
  `String.fromEnvironment('DANDANAPI_APPID'/'DANDANAPI_KEY')` 读凭证，正式版由 CI 注入，
  **我们本地编译没传 → 空凭证 → 弹弹play 返回 403**。不是上游挂、不是代码 bug、也与三个弹幕源无关
  （BiliBili / Gamer / 弹弹play 只是同一条 dandanplay 搜索结果的标签）。
  修法：自备 AppId/AppSecret，写进 `local\credentials.json`，编译时加
  `--dart-define-from-file=local/credentials.json`（凭证不进源码、不进对话）。