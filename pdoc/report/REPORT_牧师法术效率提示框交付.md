# 牧师法术效率提示框交付

日期：2026-11-15

负责人、开发、验证：Solazhu

## 目标与边界

按已确认方案开发独立插件，牧师悬停法术书或动作条中的各等级技能时，仅在原生提示框增加“效率”一行。数值为效果除以耗蓝再除以有效占用时间；范围效果取单个目标，持续效果取完整总量。按用户补充要求，混合伤害和治疗同时保留，治疗文字和数值用蓝色，伤害文字和数值用红色，分别计算且不相加。单一效果只显示对应项；护盾仍单列为吸收。

当前主工作目录有未提交的单品转售工作，因此从本地 `main` 的 `1e532f07ce2e7cc3dff44bb0333ea4d017fbaf9c` 建立了独立工作目录：

- 分支：`codex/priest-spell-efficiency`
- 目录：`J:\SOFTWARE\addons\.tools\worktrees\priest-spell-efficiency`
- 独立插件：`SpellEfficiency`，版本 `0.1.0-test`
- 目标接口：`16001`；实查本机客户端文件版本为 `1.60.1.70938`

用户已授权将本插件提交、推送并合并到 `main`，然后安装到 `F:\GAME\World of Warcraft\_forever_\Interface\AddOns\SpellEfficiency`。本轮只交付此独立插件，不包含主工作目录中尚未提交的拍卖插件改动。游戏内验证由用户安装后执行。

## 实现

运行文件为 TOC、`Logic.lua` 和 `Tooltip.lua`，另附独立 README。

使用原生 `TooltipDataProcessor` 的法术提示框后处理回调，读取当前提示框的法术 ID。对该 ID 查找包含隐藏低等级的法术书槽位，并核对返回 ID，避免按名称查询而误用最高等级。过滤未学会、通用技能栏、宠物、其他职业、物品、光环及聊天链接提示。

效果优先解析已经显示的原生描述，缺失时读取相同 ID 的法术描述。费用和施法时间读取当前客户端，不存旧值，也不自行叠加法强或天赋系数。支持直接伤害、直接治疗、完整持续效果、明确跳频和时长的周期效果、护盾吸收以及完整引导效果。零耗蓝、缺失或无法可靠解释的数据使用同一行状态文字，不输出无穷大或部分效果计算值。

瞬发使用基础公共冷却；普通读条和引导时间与公共冷却取较大值。公共冷却首版采用基础值，不另行修正急速，接口不存在时为 1.5 秒参考值。法术自身冷却和剩余冷却不计入分母。

提示框重建清除上一行；同次提示框重复回调更新已有行。异常只影响当前悬停。没有逐帧任务、扫描队列、历史记录、SavedVariables 或第三方运行依赖，也没有修改原生受保护操作的点击处理函数。

## 验证

Lua 5.1 离线测试共 224 项通过：

| 测试组 | 通过数 |
| --- | ---: |
| 原有逻辑与查询队列 | 47 |
| 原有界面与生命周期 | 51 |
| 原有价格历史与提示框 | 33 |
| 原有原生上架交接 | 13 |
| 原有商店价格 | 20 |
| 新插件计算与提示框 | 60 |

新测试按实际 TOC 加载模块，模拟原生清空、添加原文、执行后处理的生命周期。覆盖等级切换、两种悬停入口、原文优先、直接和周期效果、引导标题时间、费用条件、重复悬停、缺失数据重试、失败隔离、不可访问数据、零耗蓝、非有限值和 1,000 次重复悬停。

双效果补充测试先复现旧实现只输出一个数值，再验证同一行的蓝色治疗与红色伤害、两个法术等级、重复回调、切换回纯治疗时不残留伤害，以及共同耗蓝缺失时只显示一次状态。完整测试退出码为 0。

复核时增加了英文治疗分词回归用例，先复现 `expected 200, got 400`，再收紧词边界消除重复计数。另补充了百分比效果、遗漏第二段效果、中文额外伤害、引导标题时间和过小数值的用例。最终完整测试退出码为 0。

发布复核再次修正三类合成输入误算：ASCII `~` 区间取平均；`per second`／`per N sec` 换算完整总量，无法归属的独立周期句拒绝计算；英文数量尾缀不明确时拒绝截取前面的数字。修复前分别复现了 200 代替 150、100 代替 1500，以及 1.2k 被取成 1.2；修复后 4 项新增回归通过。架构、安全和四个异常场景角度完成复核，未保留未处理的阻断项。

验证以基线提交建立独立工作目录，仅复制本次 7 个文件并核对字节，运行相同 Lua 5.1 测试入口。运行包内只有四个插件文件，首次安装采用先校验暂存目录再移动至最终目录的方式；已有目标则拒绝覆盖。安装前后比对拍卖插件源码和其 SavedVariables 的哈希，结果记录于本机 `.tools/ship-spell-efficiency/install-receipt.json`，不将这份本机回执作为游戏内效果已验证的证据。

按用户要求将悬停标签缩为“效率”，公式和颜色保持不变；对应断言及说明同步修改，完整 224 项测试再次通过。此次安装更新仅替换 Tooltip.lua 和 README.md，先备份原文件并校验安装前后哈希，回执保留于本机 `.tools/ship-spell-efficiency/label-update-receipt.json`。

测试使用合成文本与数值，不能证明游戏中所有法术文本均已适配。实际技能悬停、战斗期间受限数据，以及装备／天赋对面板数值的影响仍待游戏内验证。未将其他并行分支尚未提交的改动包含在本次回归基线中。

## 交付和验收方式

测试包位于本工作目录的 `dist/SpellEfficiency-0.1.0-test.zip`，包含插件目录内的四个文件。打包后逐一比对归档和源码字节，防止漏掉运行文件或混入开发依赖。

归档大小 8,661 字节，四个源码／说明文件共 20,968 字节。SHA-256：`9eaba88cad64b0edd23f0120cdd78ed10e2e3455471fdead20ba087f593f726e`。字节比对结果保存在 `dist/SpellEfficiency-0.1.0-test.verification.json`；已检查 Git 差异与新文件的行尾空白。

使用说明见 `SpellEfficiency/README.md`。游戏内优先检查同一治疗术的两个等级、瞬发恢复、精神鞭笞、真言术盾及神圣新星；确认每个提示框只新增一行、不同等级数据独立、持续效果和混合效果符合说明。此处列出的是待验证场景，不是已完成的实机验收。

## 接口依据

本轮读取了目标 `forever` 分支的原生界面源码与生成接口说明：

- [提示框显示的法术 ID](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_SharedXMLGame/Tooltip/TooltipUtil.lua)
- [原生提示框回调及重建顺序](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_SharedXMLGame/Tooltip/TooltipDataHandler.lua)
- [法术书槽位与隐藏技能查询](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/SpellBookDocumentation.lua)
- [法术描述、当前消耗与施法时间](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/SpellDocumentation.lua)
- [资源消耗结构和条件费用字段](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/SpellSharedDocumentation.lua)
