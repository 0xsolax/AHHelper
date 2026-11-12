# 分级刷新与价格、数量修复交付

负责人、修改人、操作人：Solazhu  
日期：2026-11-12  
版本：AuctionPilot 0.5.0

## 完成内容

产品行末、当前配方标题和每个材料行增加常显旋转刷新图标，保留顶部全部刷新和原操作菜单。产品图标刷新该产品售价及全部配方的拍卖行材料；配方图标只刷新当前成品与当前配方；材料图标只查该物品。复用现有队列、去重及节流，查询期间禁用刷新入口。固定价材料单独刷新只供市场比较，不改变固定成本；其他批量范围继续跳过固定价材料。

初级巫师之油售价错误已复现。用户原生截图为 290 铜、1 件；300 铜、234 件；500 铜、18 件。旧代码将已经是单件一口价的 buyoutAmount 再除以档位数量，300/234 约为 1.28 铜，成为错误最低价并显示为 1 铜。已改为直接读取该金额，材料成本按需要数量逐档累计。例如采购 2 件应为 290+300=590 铜，不要求购入整档 234 件。

背包历史价格同步修正。旧记录缺少报价来源，不能安全恢复原价；保留记录并提示在拍卖行刷新，收到新的完整结果后替换并标记 priceVersion=2。失败、不完整报价仍不更新历史时间或价格，配方和数据库版本不变。

上架数量修复先复现了输入 20 件后被原生资料回填改为背包 120 件的过程。现在等待原生物品初始化完成，在回调结束后带入数量，更新原生提交状态并读取数量框核对。等待期间先置数量为 0；主动编辑、切换商品、离开出售页、关闭拍卖行、库存不足或超过 5 秒均停止回填。散装商品带入单价；普通物品价格仍在原生界面设置。插件没有执行上架、购买或出价。

## 验证

- Lua 5.1 共 87 项通过：32 项计算/行情、41 项界面/生命周期、14 项历史/背包提示。
- 回归测试覆盖截图三档报价、跨档采购成本、分组库存数量变化不影响单价、旧历史刷新、完整与失败查询边界。
- 刷新测试覆盖全部配方与当前配方范围、单物品查询、重复物品去重、忙碌拒绝、固定价保留、选择保持和刷新点击不跳购买页。
- 数量测试覆盖原生延迟重置、用户手动编辑与最大数量按钮、页面切换和换物品、库存变化、超时、普通物品数量交接，以及不触发交易。
- 离线布局生成主列表、菜单、编辑器、独立窗口、历史报价、缺价、长名称刷新中和空列表 8 种画面，检测范围内无越界。检查包含原生尺寸 800×538、850×600、1000×650 与独立模式 1024×768。
- Git 差异空白检查通过；未覆盖既有未提交改动，未提交或推送远端。

布局预览使用实际 Lua 控件位置和模拟数据；图标及边框为示意绘制。以上证明离线行为和文件一致性，游戏内实际网络回调、纹理显示及最终数量仍需加载后核对。

## 代码与来源

变更集中在 Market.lua 查询范围及单价读取、Logic.lua 材料成本、History.lua 历史报价、Native.lua 与 Core.lua 的数量交接、UI.lua 刷新入口，另更新版本、说明、测试和预览。没有新增运行依赖或后台查询机制。

核对的客户端界面源码镜像为 forever 分支：

- [一口价列直接使用 buyoutAmount，数量另行显示](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_AuctionHouseUI/Shared/Blizzard_AuctionHouseTableBuilder.lua)
- [物品资料回调与原生数量控件](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_AuctionHouseUI/Shared/Blizzard_AuctionHouseSharedTemplates.lua)
- [出售表单的数量重置及状态更新](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_AuctionHouseUI/Shared/Blizzard_AuctionHouseSellFrame.lua)
- [商品出售默认采用背包堆叠数量](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_AuctionHouseUI/Shared/Blizzard_AuctionHouseCommoditiesSellFrame.lua)

## 包与安装

- 安装包：`dist/AuctionPilot-0.5.0.zip`，39,203 字节，13 个文件，逐文件内容与源码一致，TOC 引用齐全。
- SHA256：`63d865ca355038244c7a60dc3cfa1c181b946f0f5c597cdfb4a42429d8933f77`。
- 原 0.4.0 备份：`J:\SOFTWARE\addons\backups\AuctionPilot-before-0.5.0-20261112`，13 个文件复制前后校验一致。
- 已更新：`F:\GAME\World of Warcraft\_forever_\Interface\AddOns\AuctionPilot`，13 个文件与当前源码一致，安装前再次确认原文件未偏离备份。
- 未写入游戏 SavedVariables 或其他插件；旧监控配置保留。

## 游戏内验证入口

输入 `/reload` 后打开「监控利润」，点击「全部刷新」，比较初级巫师之油与同一时刻原生最低一口价，旧错误报价应被新结果替换。再检查三个层级的旋转图标；输入少于背包库存的数量，点击准备上架，确认原生数量框采用填写值。实际提交仍由用户点击。
