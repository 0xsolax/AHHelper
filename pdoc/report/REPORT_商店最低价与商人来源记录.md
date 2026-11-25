# 商店最低价与商人来源交付记录

负责人、修改人、操作人：Solazhu  
日期：2026-11-16  
版本：0.12.2-test  
状态：检查、打包、完整旧版备份及游戏目录安装完成；实机重载验收待用户执行。

## 用户确认的规则与实现

首次有效商店买入价建立记录；以后仅在单件价严格更低时，整体更新价格、每组数量、商人名称、所在地区、时间及当时库存。同价、高价及无效报价不写入、不更新时间、不触发刷新或价格聊天提示。比较使用原始组价与组数，保留小于一铜的差异。

原生制造业材料提示和监控材料悬停显示「最低价商人：地区 · 商人名」。扫描快照同时保留成本及对应商人；后续商店新低价不改写已完成扫描。商店记录继续按角色长期保留，关闭页面、扫描、移除监控、重载和退出都不主动清理。

旧版现存价格作为最低价起点，不恢复此前已被覆盖的价格。旧记录缺少商人信息显示「未记录」，只有遇到更低价才随新记录补齐。库存统一标注为「历史商店库存」；旧版独立更新过库存，即使两个时间同秒也不证明同次采集。新记录仅随首次采价或新低价替换当时库存，不修改旧保存数据。

新增字段仅 merchantName、merchantLocation，沿用现有 vendorPrices 和既有商店事件、提示后置回调；无新运行文件或依赖，未扩大首次商店采价范围。修改在 codex/vendor-minimum-source 隔离分支验证。受保护操作拦截的旧调查继续等待实机日志，本版不宣称修复该问题。

## 验证证据

证据目录：`.tools/ship-vendor-minimum-0.12.2/`。对照本轮开始时冻结的 0.12.1-test 实际源码，保留根目录原有改动。HEAD 为 `1e532f07ce2e7cc3dff44bb0333ea4d017fbaf9c`；17 个已有文件变化，其中 3 张相关离线预览。

- `regression-before.log`：旧代码高价覆盖失败，预期 9，实际 10。
- `legacy-stock-before.log` / `same-second-before.log`：修正前对旧版独立库存误标的回归失败，覆盖不同秒和同秒观察。
- `tests-final.log`：227 项 Lua 5.1 用例通过，分组 47 + 68 + 33 + 13 + 40 + 26；本轮新增 6 项，更新材料悬停与旧库存相关断言。
- `layouts-final.log`：41 项视口检查无越界、3 张提示预览；人工打开商人来源、转售编辑器、转售列表和旧库存提示预览核对。
- `review-final.patch` / `review-final.json`：完整差异与冻结哈希；只在确认根目录 43 项基线及 HEAD 未变化后同步。
- `package-tests-final.log`：从实际压缩包提取的运行文件再次通过全部 227 项。
- `package-verify-final.log` / `package-manifest.json`：包内恰好 13 个文件，与源码逐字节一致；按 TOC 加载 10 个 Lua 文件完成初始化，验证偏好扫描、结果保留、监控与转售、材料提示和商店同价/高价保持、新低价及商人更新。

复核深度为 Deep：持久数据写入规则及跨模块快照变化。安全、架构及假设、组合、连续状态、高频滥用四项独立对抗复核全部完成。修正后四项对抗复核均回读最终 17 文件哈希，没有剩余新增问题。已发现旧库存时间归属问题，使用真实旧版采价路径复现后，仅修正显示标签并补回归，不迁移或改写保存数据。

商人名称读取接口与原生商店标题一致：[MerchantFrame.lua](https://github.com/Gethe/wow-ui-source/blob/bebcb6bf309cf41b41bd74f8ca651e6a105b2676/Interface/AddOns/Blizzard_UIPanels_Game/Mainline/MerchantFrame.lua)。地区采用 [ZoneScript 的 GetRealZoneText](https://github.com/Gethe/wow-ui-source/blob/bebcb6bf309cf41b41bd74f8ca651e6a105b2676/Interface/AddOns/Blizzard_APIDocumentationGenerated/ZoneScriptDocumentation.lua)。本次只读这两个接口，不增加受保护操作调用。

## 交付与验收

测试包：`dist/AuctionPilot-0.12.2-test.zip`  
SHA256：`0119a31ee6a8a37cb08b1fd154e57b6d77aae21d5bdc7c71241dc9e8685b7e7f`

安装目标：`F:\GAME\World of Warcraft\_forever_\Interface\AddOns\AuctionPilot`。已先完整备份旧插件，再安装并回读全部 13 个文件哈希；旧版备份 13 文件与安装前一致，两份 SavedVariables 前后哈希未变。按实际安装目录 TOC 再次加载的模拟烟雾检查通过。备份位于 `J:\SOFTWARE\addons\backups\AuctionPilot-before-0.12.2-test-20261116-083007`；证据为 `install-receipt.json`、`installed-verify.log` 和 `final-readback.json`。未提交、推送或进行远程发布。

待用户进入游戏或输入 `/reload`，确认材料悬停的商人及地区显示正确；同价、高价商人不改变记录，遇到更低单价才更新；关窗、重载后商店记录保留。旧记录没有商人时应显示未记录。离线及包内模拟不替代真实客户端验收。

交付清单：实现、复核、测试、打包、旧插件备份、安装及保存数据回读均完成；远程提交和发布不适用；游戏内 `/reload` 与实际商人报价显示仍待用户验收。

任务工具说明：原受保护操作调查仍为未完成目标，本次创建新目标被工具以已有未完成目标拒绝；未将旧调查伪标为完成，本轮使用上述验收清单独立跟踪。
