# 法术效率 GCD 数据就绪兜底

日期：2026-11-16

负责人、开发、验证：Solazhu

## 范围与状态

从已发布提交 `2cf4298241e718bc140474c16447caab28c26b08` 建立独立修复分支 `codex/spell-efficiency-gcd-fallback`，交付版本为 `0.1.2-test`。本轮修复无限服法术效率提示框因急速或基础 GCD 暂不可用而显示“时间未知”的问题。修改运行代码、回归测试及对应说明；没有修改拍卖插件，也没有新增运行文件或依赖。用户已授权提交、推送、合并到 `main`，并备份后安装到游戏目录；游戏保持运行，由用户 `/reload` 验证。

## 行为

- 急速缺失、不可访问或读取失败时，先使用法术基础 GCD。基础 GCD 也暂不可用时使用牧师默认的 1.5 秒；明确返回的零 GCD 和较短基础值仍保留。
- 急速可读取后继续按原公式修正，并沿用无限服常规 1.0～1.5 秒限值。客户端提供的读条时间不重复应用急速。
- 监听玩家的 `UNIT_SPELL_HASTE`，更新当前可见技能提示框的原有效率行；每次取当前主提示框的数据，不保存上一个技能或上一次急速。隐藏、清空、物品或光环提示框不触发旧技能查询。
- 治疗蓝色、伤害红色及伤害转治疗计算保持原样。缺失读条或引导时长、确认为零的有效占用时间仍不能生成每秒分数。
- 没有逐帧轮询、定时扫描或持久化数据。

## 验证

先修改回归用例，在旧运行代码上得到 7 项预期失败，涵盖缺失数据、读取失败及当前提示框不更新。修复后使用项目本地 Lupa / Lua 5.1 执行 `tests/run_tests.py`，退出码 0，245 项通过：法术效率 81 项、基线拍卖插件 164 项。

新增 6 项测试并调整原有缺失数据用例；模拟瞬发技能效果 600、耗蓝 100，缺急速时显示 4.00，急速恢复到 25% 后同一提示框显示 5.00。覆盖再次失去急速、零急速、隐藏和清空、切换技能、附加提示框上下文、物品 ID 与法术 ID 相同、真实零 GCD、较短基础值及无重复行。

测试使用合成数据和事件模拟。本轮没有游戏内验收；安装后应以瞬发技能悬停及急速变化验证实际事件到达和显示更新。

## 交付范围

运行包 `dist/SpellEfficiency-0.1.2-test.zip` 仅包含 `SpellEfficiency` 下的 TOC、两个 Lua 文件和 README；核对归档成员、TOC 引用和源码字节，并从解压目录加载 TOC 运行离线测试。安装到无限服的 `Interface/AddOns/SpellEfficiency` 前备份旧文件，安装后核对四个文件的哈希并再次运行插件离线测试。

本次安装仅更新发生变化的 `Tooltip.lua`、`SpellEfficiency.toc` 和 README。拍卖插件及其保存数据在安装前后比对，备份位于项目本地 `backups` 目录，提交及安装回执记录在 `.tools/ship-spell-efficiency-0.1.2/`。

## 接口依据

- [无限服单位接口及急速事件](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua)：`UnitSpellHaste` 返回值可能受限；`UNIT_SPELL_HASTE` 携带单位参数。
- [无限服提示框处理](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_SharedXMLGame/Tooltip/TooltipDataHandler.lua)：事件更新使用 `GetPrimaryTooltipInfo()`，避免将后续附加提示框的处理上下文当成当前主技能。
