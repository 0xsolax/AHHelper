# 通缉令海报界面

负责人 Solazhu · 2026-11-18 · WantedPoster 0.1.1-test

## 版式

430 × 565 的面板采用大号 WANTED 刊头、墨线画像框、旧纸边缘和印刷横线。中文名位于画像下方，录入和五人名单排进海报正文。「搜本页」使用深红色。参考 [ONE PIECE 官方手配书](https://baseshop.onepiece-base.com/en/item/etnqp4vj9wc0) 的版式。

画像由内置 imagegen 生成。原图保存在 [WantedPoster-portrait.png](J:/SOFTWARE/addons/design/WantedPoster-portrait.png)，用于生成运行时的 [Parchment.tga](J:/SOFTWARE/addons/WantedPoster/Parchment.tga)。海报预览使用实际 Lua 布局与随包纹理。

## 验证

- 渲染并检查满页、空列表、战斗中待同步三种界面。
- 源码与解包版本分别通过 11 项 Lua 5.1 离线回归。录入逻辑、列表模型与原生宏模块和 0.1.0 测试包逐字节一致。
- 安装包 [WantedPoster-0.1.1-test.zip](J:/SOFTWARE/addons/dist/WantedPoster-0.1.1-test.zip) 含六个运行文件。检查了 CRC、解包内容与纹理透明通道。
- 安装包 SHA-256 为 b119a29a413aa9f2c63278d70c637fc6b63198c150e974b5fd52445c3448f0a4。
- 游戏内打开命令为 /wanted。实际客户端渲染、字体和选中行为仍待实测。

## 画像生成提示词

```text
Use case: illustration-story. Create an original 2.5:1 landscape portrait insert for a nautical fantasy wanted handbill. The picture itself fills the canvas. Original character: a rakish adult privateer with windblown dark hair, a tied cloth headscarf with tails, a weathered high-collared sailing coat, and a crooked, confident smile, seen chest-up in three-quarter view, with distant brig rigging and rough waves in the background. Expressive hand-inked adventure manga, large readable black ink shapes, pen hatching and vintage letterpress grain, only deep umber, soft amber, and warm tan. One clear face just off the center, both eyes and the smile around the middle height of the image so a wide center crop retains the expression. Detailed rigging and horizon fading softly at the sides, no bright highlights. Fill the edges with the illustration. No lettering, logos, printed frame, border, weapons, or known character likeness. This is the interior illustration only; the actual in-game handbill layout will supply its own border and typography.
```

## 0.1.2-test

负责人 Solazhu · 2026-11-18

移除画像后将面板收紧为 430 × 419，保留 WANTED 刊头的字形、尺寸和位置。录入、翻页、移除、清空和搜索使用游戏的 UIPanelButtonTemplate，整页搜索同时继承安全动作模板。预览模拟原生按钮的外观，实际颜色与字体由客户端提供。 [暴雪宏窗口使用的按钮模板](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_MacroUI/Blizzard_MacroUI.xml#L156-L171)

满页、空列表、战斗中待同步三个画面已检查。源码和解包版本各通过 11 项离线回归。安装包校验了 CRC 和纹理透明通道，实际客户端表现仍待实测。 [0.1.2 测试包](J:/SOFTWARE/addons/dist/WantedPoster-0.1.2-test.zip)

SHA-256 为 cc5a06b83503679f48074da30922aad4f91fe98f0b839a04cb1a5333906be2f1。

### Forever 安装验证

Solazhu 于 2026-11-18 将 0.1.2-test 安装到 Forever 1.60.1.70938。六个文件均与安装包逐字节一致，直接从已安装目录运行的 11 项离线回归全部通过。进游戏输入 /wanted 打开面板。 [已安装目录](<F:/GAME/World of Warcraft/_forever_/Interface/AddOns/WantedPoster>)

## 0.1.3-test 小地图开关

负责人 Solazhu · 2026-11-18

小地图左侧增加卷轴图标，左键开关面板。点击复用 /wanted 的面板逻辑，战斗中提示脱战后操作。离线回归覆盖初次进入世界、打开和关闭、战斗限制以及界面重载后恢复。

新版已安装到 Forever，全套六个文件与测试包逐字节一致。源码和已安装副本分别通过 12 项离线测试。 [测试包](J:/SOFTWARE/addons/dist/WantedPoster-0.1.3-test.zip) · [0.1.2-test 备份](J:/SOFTWARE/addons/backups/WantedPoster-before-0.1.3-test-20261118)

## 0.1.4-test 卷轴拖动与面板打开修复

负责人 Solazhu · 2026-11-18

客户端日志记录了卷轴进入 Toggle 后在 Panel.lua 第 138 行失败。姓名输入框调用 SetFont 时缺少第三个 flags 参数。卷轴和 /wanted 共用这段初始化，因此两种入口都无法打开。根据日志将必填参数加进测试模拟，旧版两种入口均复现错误。新版明确传入 flags 后通过打开回归。 [客户端日志](<F:/GAME/World of Warcraft/_forever_/Logs/General.log:358>)

按住左键可沿小地图边缘拖动卷轴，位置按角色保存。拖动结束后，下次正常点击继续切换面板。测试覆盖拖动结束、位置重载、鼠标点击、命令打开以及战斗限制。

新版六个文件均与安装包逐字节一致，直接从已安装目录运行的 13 项离线回归全部通过。新版本的客户端实测待确认。 [测试包](J:/SOFTWARE/addons/dist/WantedPoster-0.1.4-test.zip) · [0.1.3-test 备份](J:/SOFTWARE/addons/backups/WantedPoster-before-0.1.4-test-20261118)

## 0.1.5-test 窄版和等比缩放

负责人 Solazhu · 2026-11-18

实机截图中，翻组和翻页的弯角字符显示成方框。四个按钮改用 ASCII 的小于号和大于号。默认面板从 430 × 419 收紧为 348 × 399，并重新排布录入、名单和页脚。

右下角使用游戏的拖动把手。脱战时按住左键等比缩放，范围为 70% 到 150%，比例按角色保存。进入战斗时停止当前缩放。已检查默认满页、最小尺寸空页和最大尺寸待同步三种离线预览。

新版已安装到 Forever，六个文件与安装包逐字节一致，已安装副本通过 14 项离线回归。客户端缩放与字体显示仍待实机确认。 [测试包](J:/SOFTWARE/addons/dist/WantedPoster-0.1.5-test.zip) · [0.1.4-test 备份](J:/SOFTWARE/addons/backups/WantedPoster-before-0.1.5-test-20261118)

## 0.1.6-test 复用已有角色宏

负责人 Solazhu · 2026-11-18

用户实机截图确认角色专用栏已有 WP_Target 宏，正文为预期的 /tar。离线复现旧版角色宏已存在且插件缺少绑定记录时，查找按钮仍禁用的情况。旧版只读同步依赖先前保存的记录和按名称查询结果。

新版直接读取角色宏栏。正文匹配的 WP_Target 宏可用于查找，即使宏窗口仍开着。正文核对兼容行尾空白和换行格式，按钮在宏写入或删除后使用最终读回的编号。写入结果下一帧可见时，会做一次只读补查。覆盖或删除继续要求有可核验的插件归属记录。 [原生宏窗口读取角色宏的代码](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_MacroUI/Blizzard_MacroUI.lua#L152-L176)

源码和已安装版本分别通过 16 项离线场景。安装目录六个文件与包一致，客户端实际点击和选中仍待实测。 [测试包](J:/SOFTWARE/addons/dist/WantedPoster-0.1.6-test.zip) · [0.1.5-test 备份](J:/SOFTWARE/addons/backups/WantedPoster-before-0.1.6-test-20261118)

## 0.1.7-test 清空本页时清理查找宏

负责人 Solazhu · 2026-11-18

确认「清空本页」后，通缉令清理角色专用栏中与本页名单对应的查找宏和可核验的旧副本。游戏宏窗口打开时，清理延至窗口关闭，删除前再次核对宏的名称、正文和图标。海报移除了 WANTED 下方的中文副标题。

旧版复现了清空名单后留下旧宏的问题。源码和 Forever 安装副本各通过 18 项 Lua 5.1 离线测试，覆盖旧宏和重复项清理、取消确认、宏窗口延迟清理及清理前重新核对。六个安装文件与源码及测试包逐字节一致。客户端实测待确认。 [测试包](J:/SOFTWARE/addons/dist/WantedPoster-0.1.7-test.zip) · [0.1.6-test 备份](J:/SOFTWARE/addons/backups/WantedPoster-before-0.1.7-test-20261118)
