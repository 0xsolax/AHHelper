# 插件耗时 AddonCPU 0.1.0-test

负责人、开发及测试：Solazhu

独立的手动刷新插件耗时排行榜。输入 `/addoncpu` 打开或关闭窗口，点击“刷新”读取一次统计。窗口可拖动，按 Esc 或右上角关闭按钮收起。

## 显示与统计口径

- 列出当前已加载的用户插件，包含本插件；不列入未加载插件与游戏内置插件。
- 按“会话平均”从高到低排序，相同时按插件目录名排序；超过 12 项可翻页。
- 平均使用游戏的 `SessionAverageTime`，峰值使用 `PeakTime`，单位均为毫秒。二者采用游戏当前统计会话，读取 `C_AddOnProfiler` 已有结果；不是两次点击之间的平均，也不是整机 CPU 占用率。
- “刷新”只读取快照，不重置游戏统计。界面显示快照取得时间；随后游戏中的变化要再次点击刷新才能显示。
- 无法取得的单项数值显示“无数据”，不冒充零。真实零显示 `0.000`，小于 `0.001 ms` 的正数显示 `<0.001`。
- 悬停插件名称可查看完整标题和目录名。插件拆分的多个目录各占一行，不合并统计。

## 运行开销与异常

加载时只注册命令，首次打开才创建界面。打开、翻页、关闭及重新打开均不查询耗时；没有定时器、逐帧采样或后台事件监听。仅保留最新一次快照和固定 12 个界面行，不保存历史或声明 SavedVariables。

只使用客户端已有的插件统计接口，不修改统计开关，不开启旧式 `scriptProfile`，不强制垃圾回收。游戏自身采集统计的工作仍由客户端控制。手动刷新本身也有执行成本，不能据此承诺零帧率影响。

接口不支持、统计未启用或读取失败时显示原因。若已有快照，保留原数据并明确标注“仍为上次快照”；后续手动刷新可重试。

## 安装

包内 `AddonCPU` 文件夹放入游戏的 `Interface/AddOns/`，保证层级为 `Interface/AddOns/AddonCPU/AddonCPU.toc`，在插件列表启用“插件耗时”。无需依赖其他用户插件。

当前目标为本机 `_forever_` 客户端，TOC 使用项目现有的 `Interface 16001`。2026-11-16 读取到本机可执行文件版本为 `1.60.1.70938`。尚未进入该客户端执行接口验证或测试真实帧率。

## 开发验证

从分支工作目录执行，测试依赖使用项目现有的 Lua 5.1 / Lupa 环境：

```powershell
$env:PYTHONPATH = 'J:\SOFTWARE\addons\.tools\python'
& 'C:\Users\Admin\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' tests/run_addon_cpu_tests.py
.\tools\package-addon-cpu.ps1
```

测试可通过 `--addon-dir` 指向解压后的实际插件目录。测试与 Python 不参与游戏运行。

接口依据为客户端生成文档的源码镜像：[统计函数](https://github.com/Gethe/wow-ui-source/blob/classic_era/Interface/AddOns/Blizzard_APIDocumentationGenerated/AddOnProfilerDocumentation.lua)、[统计指标](https://github.com/Gethe/wow-ui-source/blob/classic_era/Interface/AddOns/Blizzard_APIDocumentationGenerated/AddOnProfilerConstantsDocumentation.lua)、[插件枚举](https://github.com/Gethe/wow-ui-source/blob/classic_era/Interface/AddOns/Blizzard_APIDocumentationGenerated/AddOnsDocumentation.lua)。文档支持实现选择，不能替代目标客户端验收。
