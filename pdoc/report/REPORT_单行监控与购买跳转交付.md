# 单行利润监控与购买跳转交付

负责人、修改人、操作人：Solazhu  
日期：2026-11-12  
版本：AuctionPilot 0.4.0

## 完成内容

- 产品标题和配方明细行合并，每个产品只占一行。集中显示当前配方、单件售价、成本、净利润、成本利润率及最旧报价时间；价格右对齐，选中整行高亮。
- 行末箭头展开原生菜单，显示各配方单件净利润并支持选用、编辑、添加和移除。材料区右上角也可打开菜单。移除仍使用原确认框。
- 全界面只保留一个「全部刷新」，查询全部产品及全部配方，沿用物品去重、固定价跳过和手动队列规则。刷新中禁用按钮。
- 材料行和明细标题中的成品图标/名称可点击，按物品编号进入原生购买页。跳转前暂停插件刷新，原生购买列表显示时查询，不执行购买或出价。
- 物品资料未载入、拍卖行关闭、节流繁忙、战斗或属性变体等情况提示原因；固定价材料可查看市场但配置不变。
- 单行长名称按字体宽度裁切，保留完整行提示。竞争变化显示「!」及提示详情，原聊天、声音行为保留。
- 每秒更新报价年龄不再隐藏全部产品行，避免菜单因所属控件隐藏而关闭。切换配方仍保留手填上架单价。

改动集中在 UI.lua、Native.lua，另更新版本、说明、测试与预览。配方数据库、利润计算和行情调度算法未修改。

## 验证

Lua 5.1 共 78 项通过：30 项计算/行情，35 项界面/生命周期，13 项历史价格/背包提示。新增覆盖单行多配方切换、菜单持续展开、唯一刷新入口、材料与成品精确跳转、商品与整组物品分流、无自动交易、拒绝跳转时保留状态、排序与详情目标一致，以及长中文名称。

界面尺寸模拟覆盖原生 800×538、850×600、1000×650，独立窗口在 1024×768 适配。检查了主列表、菜单、编辑器、独立窗口、空列表、历史报价、缺价、刷新中及长名称；离线渲染未发现检测范围内的越界。

预览：`design/offline-docked-list.png`、`design/offline-docked-menu.png`，以及更新的编辑器和独立窗口预览。边界、图标和原生菜单为示意绘制，使用示例数据，不能替代真实游戏纹理、网络事件和操作验收。

原生入口依据已核对：

- [SelectBrowseResult 与购买页分流](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_AuctionHouseUI/Shared/Blizzard_AuctionHouseFrame.lua)
- [购买列表显示时刷新](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_AuctionHouseUI/Shared/Blizzard_AuctionHouseItemList.lua)
- [原生菜单](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_Menu/MenuUtil.lua)

## 包与安装

- 包：`dist/AuctionPilot-0.4.0.zip`，37,152 字节，13 个文件；逐文件与源码字节一致，TOC 引用齐全。
- SHA256：`e0ea211414a85417c19f92d929d37066b0f98db661ac2589ea21eaf0a96307d7`。
- 原安装备份：`J:\SOFTWARE\addons\backups\AuctionPilot-before-0.4.0-20261112`，原 0.3.0 的 13 个文件逐一核对通过。
- 已更新：`F:\GAME\World of Warcraft\_forever_\Interface\AddOns\AuctionPilot`，安装后 13 个文件与当前源码校验一致。未修改游戏保存变量或其他插件。

本轮没有执行游戏内交易，也没有推送远端仓库。

## 游戏内验收入口

输入 `/reload` 后打开拍卖行的「监控利润」。检查每个产品一行，展开行末箭头切换配方、查看成本利润和下方材料同步；点击材料及成品进入对应原生购买页，返回监控后选择保留。测试全部刷新中的跳转、菜单保持展开、实际字体及滚动。真实客户端显示和购买交接尚待该步骤确认。
