# 受保护操作拦截与原生接口审查

负责人、审查人：Solazhu  
日期：2026-11-16  
状态：全量静态审查完成；实机拦截根因未定位，未修改运行代码、未发布或安装修复包。

## 结论

当前不能宣布插件完全符合客户端安全执行约束，也不能把截图弹窗归因于某一行代码。已确认两处对原生共享函数或状态的改写，应作为下一轮实机验证重点；但未找到它们传播到“关闭拍卖行后，无修饰键右键使用物品”的完整调用链。

本次没有发现插件直接调用使用物品、施法、执行制造或提交拍卖交易的接口。原生上架集成只交接物品和填写表单，成交仍由原生页面处理。上述结论限定于本次冻结的运行源码，不等同于客户端无污染认证。

## 审查基线与覆盖

- 插件：AuctionPilot 0.12.0-test，TOC Interface 16001。
- 工作区分支：`codex/single-item-resale`，HEAD：`1e532f07ce2e7cc3dff44bb0333ea4d017fbaf9c`；审查包含既有未提交改动，不以 HEAD 代替实际源码。
- 冻结清单：`.tools/diagnose-protected-action-0.12.0/baseline.json`。全部 25 个源码、测试和交付相关文件复核时与冻结哈希一致。
- 游戏安装目录：`F:\GAME\World of Warcraft\_forever_\Interface\AddOns\AuctionPilot`。13 个安装文件与本次审查源码逐一 SHA256 比对一致。
- 游戏版本：1.60.1.70938。对照客户端 UI 源码镜像的同版本提交 `bebcb6bf309cf41b41bd74f8ca651e6a105b2676`，避免套用其他分支或版本的行号。
- 范围：全部 10 个运行 Lua 文件；初始化、事件、查询、原生窗口与表单、制造业扫描、提示、编辑输入和两项随包库。未修改其他插件。

| 范围 | 已查内容 | 结果 |
|---|---|---|
| Core.lua、Market.lua | 开关 AH、异步查询、取消与节流、扫描会话 | 关闭时先清理会话，未找到关闭后继续查询或交接出售物品的有效路径 |
| Native.lua | 原生页面切换、上架准备、延迟资料返回、战斗与身份校验 | 延迟回调重查 pending、可见性、物品身份和战斗状态；没有提交成交调用 |
| UI.lua、Editor.lua | 窗口挂接、关闭回退、原生配方行与表单布局、点击输入 | 回退有会话和可见性判断；原生配方行初始化会重置 OnEnter，未将重复追加误判为无限累积 |
| Widgets.lua | 物品拖入、粘贴、Shift 链接导入 | 确认替换了共享原生链接函数，详见候选 A |
| History.lua | 原生查询后置钩子、背包提示信息追加 | 回调只读传入资料并追加文字；原生提示处理有安全调用隔离，未发现修改物品按钮或点击方法 |
| Logic.lua、LibStub.lua | 数据计算、校验、库注册 | 未发现受保护操作入口 |
| LibAHTab.lua | 标签安装、显示状态切换、重复安装防护 | 确认改写原生显示状态，详见候选 B |

审查协作已全部完成：接口安全、原生状态与架构两项专项；假设破坏、组合路径、级联路径、重复操作四项对抗复核。后三项独立复核均未建立目标故障的完整链路；没有以零发现代替实机验证。

## 两处已确认的原生改写

### 候选 A：长期替换原生链接入口

位置：`AuctionPilot/Widgets.lua:170–187`，初始化入口 `AuctionPilot/Core.lua:360`。

代码把 `ChatFrameUtil.InsertLink`（兼容分支为 `ChatEdit_InsertLink`）替换为自己的包装函数。输入框和 Shift 条件只决定是否接收物品，不会使该替换仅在编辑窗口打开时存在。原生聊天、搜索和其他插件后续使用这个入口时，都会经过包装。

这是明确的共享函数替换，值得降低耦合；但同版本原生 `ContainerFrame.lua:1683–1697` 将普通点击和修饰点击分开，用户所述无修饰右键并不直接调用这个入口。重载后插件也会重新安装包装，因此“包装存在”本身不能解释使用 AH 后才发生的状态差异。

不能直接把包装改成后置 `hooksecurefunc` 就宣称修复：原实现依赖返回 true 吞掉已处理的 Shift 点击；后置钩子不能改变原生返回值，会改变拆分堆叠等交互。若移除这项接管，需要明确 Shift 导入的替代方案或行为变化。

### 候选 B：改写原生拍卖窗口显示状态

位置：`AuctionPilot/Libs/LibAHTab.lua:89–90`；相关关闭回退位于 `AuctionPilot/UI.lua:804–809`。

监控标签先调用 `AuctionHouseFrame:SetDisplayMode({})`，再直接写 `AuctionHouseFrame.displayMode = nil`。同版本原生 SetDisplayMode 自身也写该字段，故只删除后一行不能证明已消除这条状态传播路径。

普通右键路径会检查拍卖行，但 `ContainerFrame.lua:1559` 先检查 `AuctionHouseFrame:IsShown()`。窗口隐藏时短路，不读取 `IsListingAuctions()/displayMode`。当前没有证据把此字段改写与关闭 AH 后的右键报错接通。AH 仍显示等其他状态需要按实际拦截栈判断，不能移用到用户已描述的场景。

## 日志判断

本次正常退出后读取的 `taint.log` 为 5006 字节，最后写入时间为 2026-11-16 02:45:26。快照保存在 `.tools/diagnose-protected-action-0.12.0/taint-first-exit.log`。

其中 5 组记录均涉及 `CloseSpecialWindows` 读取全局 `AuctionPilotFrame`。同版本原生 `UIParentPanelManager.lua:1104–1105` 明确说明这里处理可能污染的值，1168 行通过 `securecall("CloseSpecialWindows")` 调用。日志没有包含实际被拒绝的函数或 `UseContainerItem` 调用栈，不能据此删除正常的 ESC 关闭注册并声称修复。

尚缺的决定性证据是弹窗当次的 blocked/forbidden 函数及传播栈，并核对当刻拍卖行实际显示状态。已请求使用 `taintLog 4` 重载后重新复现，弹窗出现后正常退出、不要再次重载；该轮结果仍待用户反馈。

## 本轮验证

使用项目 README 指定的 Python 与项目内 lupa，在冻结副本运行 `tests/run_tests.py`，共 214 项通过：

| 测试组 | 通过数 |
|---|---:|
| 逻辑与查询队列 | 47 |
| UI 与生命周期 | 68 |
| 历史与提示 | 33 |
| 原生上架交接 | 13 |
| 商店价与转售 | 33 |
| 原生制造业扫描 | 20 |

完整输出：`.tools/diagnose-protected-action-0.12.0/baseline-tests.log`。

现有 mock 只模拟普通 Lua 行为：`tests/wow_mock.lua:206–208` 的 hooksecurefunc 是普通包装，没有客户端污染追踪；按钮 Click 默认使用 LeftButton，未模拟原生背包 UseContainerItem 链。故 214 项通过只能证明现有逻辑回归通过，不能证明本次安全拦截消失。未编造污染模型或实机通过结果。

## 后续与交付状态

1. 代码与原生接口全量审查：完成。
2. 运行代码修改：未进行；当前没有足够证据确定最小修复点。
3. 修复包、备份与安装：尚未进行；已安装版本仍为 0.12.0-test。
4. 实机复现与根因修复：待本轮日志。取得实际被拦截函数后，先验证传播链，再对已确认位置修复、回归、打包和安装。

本轮没有修改 SavedVariables，没有提交、推送或更换分支。

## 对照来源

- [同版本原生背包点击处理](https://github.com/Gethe/wow-ui-source/blob/bebcb6bf309cf41b41bd74f8ca651e6a105b2676/Interface/AddOns/Blizzard_UIPanels_Game/Mainline/ContainerFrame.lua)
- [同版本原生拍卖窗口](https://github.com/Gethe/wow-ui-source/blob/bebcb6bf309cf41b41bd74f8ca651e6a105b2676/Interface/AddOns/Blizzard_AuctionHouseUI/Shared/Blizzard_AuctionHouseFrame.lua)
- [同版本原生窗口管理](https://github.com/Gethe/wow-ui-source/blob/bebcb6bf309cf41b41bd74f8ca651e6a105b2676/Interface/AddOns/Blizzard_UIParentPanelManager/Shared/UIParentPanelManager.lua)
- [同版本原生提示回调隔离](https://github.com/Gethe/wow-ui-source/blob/bebcb6bf309cf41b41bd74f8ca651e6a105b2676/Interface/AddOns/Blizzard_SharedXMLGame/Tooltip/TooltipDataHandler.lua)
- [同版本原生配方行初始化](https://github.com/Gethe/wow-ui-source/blob/bebcb6bf309cf41b41bd74f8ca651e6a105b2676/Interface/AddOns/Blizzard_ProfessionsTemplates/Blizzard_ProfessionsRecipeList.lua)
