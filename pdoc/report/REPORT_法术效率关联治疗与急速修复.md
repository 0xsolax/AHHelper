# 法术效率关联治疗与急速修复

日期：2026-11-15

负责人、开发、验证：Solazhu

## 范围与结果

从已安装版本 `9d20f0b6b7ae99f98029a3dace954aac09696d69` 建立独立修复分支 `codex/spell-efficiency-leech-haste`。本轮面向无限服 `_forever_` / `Interface 16001`，交付版本为 `0.1.1-test`。用户已授权提交、推送、合并到 `main`，并备份后安装到当前游戏的 `SpellEfficiency` 目录；游戏保持运行，由用户 `/reload` 验证。

支持噬灵瘟疫式“恢复等量生命”及明确的“按造成伤害百分比回血”，先合计完整伤害再派生治疗总量。伤害、治疗分别除以同一耗蓝和占用时间，保留原有红色伤害、蓝色治疗和“效率”标题。不重复乘周期跳数；没有伤害基数、比例不明、重复关联或固定治疗可能重复时不给部分估计。

公共冷却改为依据当前法术急速修正基础值；无限服常规 GCD 使用 1.0～1.5 秒限制，天然零 GCD 保留零。客户端返回的读条时间不再重复应用急速。接口或数据不可用时显示“时间未知”，移除旧的固定 1.5 秒备用值。

没有新增运行文件、配置、定时器、后台扫描、战斗记录或持久化状态。拍卖插件不在本轮修改范围。

## 验证

先增加回归用例，在未修改运行代码时复现 14 项失败，包括等量回血漏项、比例回血无法估算、1.3 秒施法仍用 1.5 秒分母。修复后另补明确双数值共处一段文本、英文等量表述和回血与急速共同作用的检查。

使用项目本地 Python / Lupa Lua 5.1 执行 `tests/run_tests.py`，239 项通过、退出码 0：法术效率 75 项，基线拍卖插件 164 项。相较基线新增 15 项测试，并将原先依赖固定 GCD 备用值的用例改为验证未知时间。

测试样本模拟不同等级的噬灵瘟疫式描述；数值为合成输入，不是本次游戏实测数据。覆盖等量及 15%、50%、125% 比例回血、完整周期伤害、重复描述、缺失基数、单行颜色与等级切换、无重复输出、1.3 秒读条、0/25/50/100% 急速、GCD 限值及数据不可访问后恢复。

实际客户端悬停效果及角色当前急速仍需游戏内验证。建议分别检查噬灵瘟疫、快速治疗及一个瞬发技能，并在急速变化后重新悬停。

## 交付与平台范围

运行包 `dist/SpellEfficiency-0.1.1-test.zip` 仅包含 `SpellEfficiency` 目录中的 TOC、两个 Lua 文件和 README。交付时核对归档成员、文件字节及 TOC 引用，实际安装后再次核对源码哈希，并从安装目录加载 TOC 执行离线测试。原插件文件备份保留在本机工作目录的 `backups` 下；安装前后核对拍卖插件源码和其保存数据，具体回执保存在本机 `.tools/ship-spell-efficiency-0.1.1/`。

两款插件的游戏运行文件均为 Lua / TOC，未发现操作系统专用运行依赖；文件名与 TOC 引用核对大小写。代码层面可供对应版本的 Windows 和 Mac 客户端共用。仓库中的 PowerShell 打包脚本和本地测试环境属于开发工具，不是游戏运行依赖。本轮没有 Mac 实机环境，未将源码检查作为 Mac 游戏内验收。

## 版本依据

- [无限服 GCD 问题记录及限值说明](https://github.com/ClassicWoWCommunity/forever-bugs/issues/389#issuecomment-6308929421)：法术急速影响 GCD，记录给定下限 1 秒、上限 1.5 秒。
- [forever 分支 UnitSpellHaste 接口](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua)：读取当前单位法术急速，返回值在受限状态下可能不可访问。
- [forever 分支法术接口](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/SpellDocumentation.lua)：继续读取当前法术 ID 的说明、消耗和施法时间。
