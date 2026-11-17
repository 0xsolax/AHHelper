# 独立插件耗时监控交付记录

最新交付：0.1.2-test 已安装到游戏目录，支持小地图按钮沿边缘拖动并保存位置；验收记录见文末。

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

## 2026-11-16：授权安装完成

负责人、修改人、操作人：Solazhu。按用户“安装到游戏”的明确授权，将已验证的 0.1.1-test 安装到 `F:\GAME\World of Warcraft\_forever_\Interface\AddOns\AddonCPU`。安装前该目录不存在，本次为首次独立安装，无旧版需要备份。

重新校验安装包哈希、3 个暂存文件及目标路径边界后，仅新建上述目录并复制 TOC、Core.lua 和 README.md。安装后回读全部 3 个文件，与已验证压缩包逐字节对应；18 个其他插件文件及 60 个 SavedVariables 文件的哈希前后保持一致。

从实际安装目录按 TOC 加载，在 Lua 5.1 模拟环境再次通过 29 项测试。证据为 `.tools/ship-addon-cpu-0.1.1/install-before.json`、`install-receipt.json`、`installed-tests.log` 和 `install-final-readback.json`。插件运行文件来自提交 `276610cd6eb4f39a98ba122df9162b32b08b678b`；本次未合并或推送分支。

进入游戏后，在插件列表确认“插件耗时”已启用，点击小地图左下边缘的怀表按钮，或输入 `/addoncpu` 打开窗口，再点击“刷新”。真实客户端的图标位置、接口取数和帧率影响仍待用户验收；文件校验与模拟测试不替代该验收。

## 2026-11-17：0.1.2-test 小地图按钮拖动

负责人、修改人、操作人：Solazhu。按用户要求，将固定小地图按钮改为按住左键沿地图边缘拖动；沿用原有普通点击开关和手动刷新行为。只在 `AddonCPUDB.minimapAngle` 保存位置角度，加载保存数据后恢复，并立即取消初始化事件监听。缺失或无效角度使用默认左下位置，保留保存表内其他已有字段。

鼠标坐标按小地图实际缩放换算，以小地图中心和宽高计算边缘位置。沿用项目已有的小地图拖动方式，坐标处理也核对了 [LibDBIcon 实现](https://github.com/Questie/Questie/blob/master/Libs/LibDBIcon-1.0/LibDBIcon-1.0.lua)。没有引入库或其他运行文件。

位置更新仅在拖动期间存在；松开、拖动结束、鼠标释放于按钮外或按钮隐藏后移除更新回调。拖动释放的点击不会开关窗口，下一次普通点击恢复正常。拖动与悬停不读取 CPU 统计；耗时快照仍只在点击“刷新”时更新。

修改基于 `codex/addon-cpu` 的 `a248981ddd32823e81371f4135157f58fac52e57`，仅涉及 Core.lua、TOC、README、对应测试和本报告，共 5 个文件。根目录的已有开发工作保留。

证据目录：`J:\SOFTWARE\addons\.tools\ship-addon-cpu-0.1.2`。

- `tests-before.log`：新增拖动测试在旧版本上因缺少拖动入口失败。
- `tests-first.log`、`package-tests-final.log`、`installed-tests.log`：源码、压缩包解压文件和实际游戏安装文件分别通过 42 项 Lua 5.1 离线测试。覆盖原有手动刷新，以及四向边缘约束、远近鼠标距离、界面缩放、不同地图尺寸、两种释放回调顺序、停止更新、提示所有权、保存恢复及异常角度。
- `package-manifest.json`：运行包仍只有 3 个文件，与源码逐字节匹配。
- `install-before.json`、`install-receipt.json`、`final-readback.json`：旧版完整备份、新版安装回读、其他插件及保存数据保护记录。

测试包：`J:\SOFTWARE\addons\dist\AddonCPU-0.1.2-test.zip`。

SHA256：`5969ed27debd27c8b69c2a5dfaa8dad94ee2c6fd7d88e4677830b95e2885ff86`。

沿用本会话已授权的游戏安装，先完整备份旧版 3 个文件到 `J:\SOFTWARE\addons\backups\AddonCPU-before-0.1.2-test-20261117`，再更新 `F:\GAME\World of Warcraft\_forever_\Interface\AddOns\AddonCPU`。安装文件回读通过，29 个其他插件文件及 66 个 SavedVariables 文件前后哈希一致。没有由安装程序写入新位置数据；角度由游戏加载插件后保存。未合并或推送分支。

实机验收：输入 `/reload`，按住怀表图标的左键沿小地图拖动，松开后确认窗口没有误开关；普通点击应正常开关窗口。再次 `/reload` 检查位置是否保留，并确认耗时数值仍只在点击“刷新”后变化。离线模拟验证不代表真实鼠标交互、客户端保存加载或帧率已经验收。
