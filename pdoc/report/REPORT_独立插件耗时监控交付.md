# 独立插件耗时监控交付记录

最新交付：0.1.1-test，小地图入口更新见文末。

- 负责人、修改人、操作人：Solazhu
- 日期：2026-11-16
- 版本：AddonCPU 0.1.0-test
- 状态：实现、离线验证与独立测试包完成；游戏内验收待用户执行。

## 已确认范围与结果

用户确认制作独立插件，偶尔手动刷新查看各插件耗时。实现单独的 `AddonCPU` 目录和 `/addoncpu` 命令；打开窗口后点击“刷新”，读取已加载用户插件的会话平均耗时与峰值，按平均耗时降序排列。每页 12 行，翻页只显示快照中的其他条目。完整标题和目录名通过名称悬停查看。

读取 `C_AddOnProfiler.GetAddOnMetric` 的 `SessionAverageTime` 与 `PeakTime`，单位为毫秒。二者采用客户端当前统计会话，不表示两次点击之间的平均或整机 CPU 百分比。刷新不会清零统计。快照包含自身插件，不合并插件的多个目录。

加载时只注册命令，首次打开才创建窗口。无定时器、逐帧回调或后台事件订阅。打开、翻页、关闭和重开都不读取统计；只保留最近一次快照，不声明 SavedVariables。不会开启旧式详细分析或修改客户端设置。

无数据与真实零值分别显示；不支持接口、统计未启用、读取失败都有明确提示。一次刷新完整成功才替换快照，失败保留原数据并标明“仍为上次快照”；后续可手动重试。

## 分支与改动范围

- 分支：`codex/addon-cpu`。
- 工作目录：`J:\SOFTWARE\addons\.tools\worktrees\addon-cpu`。
- 基线：本地 `main`，`53f4f48c224b595e5e896f044b3f220c5cafc8d5`。
- 新增 7 个文件：插件目录下的 TOC、Core.lua、README.md；独立测试入口及 Lua 用例；独立打包脚本；本报告。
- 没有修改既有插件、测试入口或打包脚本。根工作目录的已有未提交改动单独保留。

仓库中未发现本轮指令列出的本地 RULE、GUIDE 或项目附加规范文件；本次按用户提供的 AGENTS.md 及已确认范围执行。未新增运行依赖、历史记录、自动刷新、统计开关或后台扫描。

## 验证证据

证据目录：`J:\SOFTWARE\addons\.tools\ship-addon-cpu-0.1.0`。

- `tests-layout-final.log`：源码在 Lua 5.1 模拟环境通过 25 项测试。覆盖手动触发、只查询已加载用户插件、排序、零值与缺失值、分页、快照保持、刷新失败的原子性与恢复、工具提示所有权、重复刷新复用界面行、无后台回调及不修改统计设置。
- `layout-result.json`、`preview-normal.png`、`preview-unavailable.png`：检查真实代码创建的控件坐标，正常与异常界面各 38 个可见控件均在窗口内，非名称字段没有文字越界。图片使用合成数据和模拟字体，已人工打开复核，不是游戏截图。
- `package-manifest.json`：安装包恰好包含 `AddonCPU/AddonCPU.toc`、`AddonCPU/Core.lua`、`AddonCPU/README.md`，逐字节匹配源码。
- `package-tests-final.log`：从实际压缩包解压后，按 TOC 加载运行文件，再次通过相同 25 项测试。
- `root-before.json`：开发前记录根工作目录 HEAD、状态及 65 个文件的哈希；交付前回读核对结果写入 `final-readback.json`。

没有修改既有模块，因此未重复执行与本插件无依赖关系的其他插件回归。离线测试只证明模拟 API 合同与交互路径；不能证明目标客户端提供接口，也不能证明真实 CPU 开销或帧率影响。

接口参考为游戏生成文档的源码镜像：[统计函数](https://github.com/Gethe/wow-ui-source/blob/classic_era/Interface/AddOns/Blizzard_APIDocumentationGenerated/AddOnProfilerDocumentation.lua)、[统计指标](https://github.com/Gethe/wow-ui-source/blob/classic_era/Interface/AddOns/Blizzard_APIDocumentationGenerated/AddOnProfilerConstantsDocumentation.lua)、[插件枚举](https://github.com/Gethe/wow-ui-source/blob/classic_era/Interface/AddOns/Blizzard_APIDocumentationGenerated/AddOnsDocumentation.lua)。本机目标可执行文件版本为 `1.60.1.70938`，TOC 沿用该项目的 `Interface 16001`。

## 交付与实机验收

测试包：`J:\SOFTWARE\addons\dist\AddonCPU-0.1.0-test.zip`。

SHA256：`8185ee56c92e23abc1c21e925c3ba79ff9b438b08f995c2cc7e9973e0d7eff73`。

源代码与使用说明在分支工作目录的 `AddonCPU` 文件夹中。当前未合并、推送或安装到游戏目录。

安装后输入 `/addoncpu` 打开窗口，再点击“刷新”。检查插件名称、平均值与峰值能否正常显示；打开后等待、翻页或关闭重开，数值应保持不变，直到再次点击“刷新”。接口不支持时应显示明确提示。

实机开销应在相同场景对比禁用插件、启用但窗口关闭、打开窗口三种状态，并单独观察点击刷新的瞬时变化。游戏内置统计本身的开销不能归零，也不能从本插件的离线执行时间推断实际帧率。

## 0.1.1-test：小地图窗口开关

日期：2026-11-16。负责人、修改人、操作人：Solazhu。

按用户本轮要求，在小地图左下边缘增加固定的怀表按钮。左键切换排行榜窗口，悬停说明操作；命令入口继续可用。两种入口复用同一个窗口开关，只有窗口内“刷新”按钮读取耗时。按钮随小地图显隐，不新增拖动、位置保存、后台采样或依赖库。

在原分支 `codex/addon-cpu` 上以 `4b3f3fdae3d209ffd76f65d26a0fa4f87150f092` 为基线修改。仅变更 Core.lua、TOC 版本、README、相关测试及本报告，共 5 个文件。小地图按钮使用原生控件及贴图，布局参考[客户端小地图源码](https://github.com/Gethe/wow-ui-source/blob/classic_era/Interface/AddOns/Blizzard_Minimap/Classic/Minimap.xml)。

证据目录：`J:\SOFTWARE\addons\.tools\ship-addon-cpu-0.1.1`。

- `tests-before.log`：新增入口测试在旧代码上因缺少小地图按钮失败。
- `tests-final.log`、`package-tests-final.log`：源码与实际压缩包中的插件均通过 29 项 Lua 5.1 测试。覆盖首次点击、命令与按钮交替开关、反复点击保持快照、不重复创建窗口、悬停不采样、提示所有权及小地图隐藏时不影响排行榜。
- `package-manifest.json`：包内仍恰好 3 个文件，逐字节匹配源码；缺少小地图控件时命令入口仍可开关窗口的独立烟雾检查通过。
- `root-before.json`、`final-readback.json`：保留并回读根工作目录状态及 65 个文件哈希。

新版测试包：`J:\SOFTWARE\addons\dist\AddonCPU-0.1.1-test.zip`。

SHA256：`0005d045ce73579daa19a08a1b4ace55c86eea8578b70f3b971561ab2f5bcc87`。

本版未合并、推送或安装到游戏目录。待实机确认小地图怀表图标可见、位置可用，左键可开关窗口，数值只在手动刷新后变化。离线测试未验证游戏贴图的实际显示或与其他插件图标的重叠情况。
