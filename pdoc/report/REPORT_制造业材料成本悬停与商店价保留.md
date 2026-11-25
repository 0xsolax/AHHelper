# 制造业材料成本悬停与商店价保留交付

负责人、修改人、操作人：Solazhu  
日期：2026-11-16  
版本：0.12.1-test  
状态：独立分支验证、打包、旧插件备份及游戏目录安装完成；游戏内显示待用户重载验收。

## 完成内容

原生制造业材料提示现在追加采购来源、每件成本和本配方用量小计。AH 使用满足配方用量的逐档采购均价；商店使用记录的买入组价分摊；固定价保持原选择。显示取自与利润卡片相同的配方扫描快照，不被其他配方、后续 AH 查询或商店更新改写。重扫成功才替换快照，失败保留旧结果和原时间。

缺价、库存不足及首次扫描超时会明确显示未取得成本及原因，不生成零成本。未扫描且没有可用商店记录的材料不虚构价格。提示保留原生物品说明，仅通过现有 TooltipDataProcessor 后置回调追加文字；没有新增原生函数替换或物品操作入口。

商店买入价不按时间过期，也不因扫描、关窗、移除监控、重载或退出游戏而删除。再次访问商店并读取有效买入价时更新，保存的是最近一次有效价，不是历史最低价。AH 扫描、未载入、代币／附加物品成本、无效报价均不会覆盖它；售罄继续保留原价格与价格时间。

商店记录仍按当前角色保存在既有 vendorPrices 中，没有新增数据库字段。首次采价仍限于监控成品及其材料；移除监控后的已记录物品可继续更新。重载清理会话扫描后，原生材料提示仍能显示适用的商店记录及时间；明确选择 AH 价的材料不会回退商店价。从未记录过的商店价，需要先保存相关监控并访问商店一次；原生提示中的回收卖价不作为采购成本。

## 最小改动范围

- History.lua：识别原生 GetRecipeReagentItem，按配方编号和材料编号匹配扫描成本，或读取适用的持久商店记录。
- Core.lua：去掉按监控引用清理商店记录的逻辑，保留原有会话报价裁剪。
- Native.lua：商店观察继续覆盖已记录过、但已移除监控的物品。
- 相关测试、版本字段、使用说明及两张离线提示预览同步更新；制造业布局、扫描队列、单品转售和原生交易入口没有改动。

同版本原生入口已核对：[客户端 1.60.1.70938 的材料 OnEnter](https://github.com/Gethe/wow-ui-source/blob/bebcb6bf309cf41b41bd74f8ca651e6a105b2676/Interface/AddOns/Blizzard_ProfessionsTemplates/Blizzard_ProfessionsRecipeSchematicForm.lua#L943)使用配方编号和材料槽位生成提示；[提示处理器](https://github.com/Gethe/wow-ui-source/blob/bebcb6bf309cf41b41bd74f8ca651e6a105b2676/Interface/AddOns/Blizzard_SharedXMLGame/Tooltip/TooltipDataHandler.lua)保留 getter 参数，并在重建时清理原提示行。

## 验证证据

工作分支：`codex/profession-material-cost`。独立目录：`J:\SOFTWARE\addons\.tools\worktrees\profession-material-cost`。本次在既有 0.12.0 工作源码上冻结 25 个输入文件，只同步本轮修改，未提交、推送或切换主工作区分支。

| 验证 | 结果 |
|---|---|
| 旧代码回归 | 材料提示行缺失、删除配方清理商店价均按预期失败 |
| 首次超时回归 | 通过 FinishRecipeScan 的错误结果复现；修复前提示缺失，修复后显示原因 |
| 完整测试 | 221 项通过：逻辑 47、UI 68、历史 33、上架交接 13、商店及转售 34、制造业 26 |
| 实际包测试 | 解压最终压缩包后按包内运行代码再次执行，221 项通过 |
| 布局 | 41 项视口检查无越界，3 张提示预览生成；两张新材料提示已人工查看 |
| 专项与对抗复核 | 安全、架构及四个对抗角度完成；发现的首次失败提示缺口已修复，并完成四角度增量复核 |
| 包与安装文件 | 13 个文件逐项哈希一致；包内和安装目录按 TOC 加载后的功能检查通过 |
| 备份及保存数据 | 13 个旧插件文件完整备份并核验；2 个 SavedVariables 文件安装前后哈希不变 |

测试包含多档 AH 采购、商店分数组价、固定零价、明确 AH 来源、不同配方用量、后续报价隔离、失败保留、关闭重开、重载后商店成本提示、旧价更新、无效价保护及原背包提示隔离。模拟测试不等同于客户端安全环境或游戏内显示验收。

证据目录：`J:\SOFTWARE\addons\.tools\ship-material-tooltip-0.12.1`。其中 `regression-before.log`、`regression-first-failure.log`、`tests-after.log`、`package-tests.log`、`layouts.log`、`package-manifest.json`、`source-sync.json`、`install-receipt.json`、`installed-verify.log` 对应上述检查。

## 交付位置

- 安装包：`J:\SOFTWARE\addons\dist\AuctionPilot-0.12.1-test.zip`
- SHA256：`5aa6bb627629a95e1b04eea67ce26c39ea1784637d91bea7e00730f099b67452`
- 游戏目录：`F:\GAME\World of Warcraft\_forever_\Interface\AddOns\AuctionPilot`
- 旧版备份：`J:\SOFTWARE\addons\backups\AuctionPilot-before-0.12.1-test-20261116-075848`
- AH 提示预览：`J:\SOFTWARE\addons\design\offline-material-ah-tooltip.png`
- 商店提示预览：`J:\SOFTWARE\addons\design\offline-material-vendor-tooltip.png`

## 实机验收

重载后打开 AH 和制造业，扫描当前配方，依次悬停 AH 材料与已记录商店价的材料。核对来源、单价和用量小计；关闭再打开页面后应保留结果。重载后 AH 扫描结果按原规则清理，适用的商店成本继续显示。移除监控后商店记录仍保留，重新访问商店可更新有效买入价。

此前的受保护操作拦截调查仍等待实机记录，本次没有把材料提示修复声称为该问题的修复。原诊断目标保持受阻；系统拒绝在同一线程另建第二个未完成目标，本次按本报告的验收清单完成交付。
