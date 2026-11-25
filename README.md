# 拍卖助手开发目录

负责人：Solazhu

- `AuctionPilot/`：可直接安装的插件源码和使用说明。
- `dist/AuctionPilot-0.12.0-test.zip`：制造业材料框内嵌利润卡片与单品转售的测试包。关闭页面保留扫描结果，重载或退出游戏后清理；普通与限量商品均可监控转售利润。仅包含运行文件、说明和第三方许可证。
- `tests/`：Lua 5.1 逻辑、界面事件模拟和离线布局检查。
- `.tools/python/`：仅用于本项目测试的 `lupa==2.6`，不参与游戏运行或打包。
- `design/`：设计参考和明确标注的离线布局预览。
- `pdoc/design/`、`pdoc/report/`：实现边界与交付证据。

测试命令（当前机器）：

```powershell
$env:PYTHONPATH = 'J:\SOFTWARE\addons\.tools\python'
& 'C:\Users\Admin\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' .\tests\run_tests.py
& 'C:\Users\Admin\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' .\tests\render_layout.py
.\tools\package.ps1
```

更换开发机器时，将 Python 包 `lupa==2.6` 安装到本项目 `.tools/python`；布局预览还使用 Pillow 和 Windows 微软雅黑字体。它们都不是插件运行依赖。

本轮按用户确认的交互图，把扫描按钮和利润结果放进原生制造业页面，支持扫描本专业偏好与当前配方。关闭页面保留结果，重载或退出后清理，单品转售继续保留。改动在 `codex/profession-inline-profit` 隔离目录验证，交付步骤与证据见 [页内扫描安装报告](pdoc/report/REPORT_原生制造业页内扫描交付.md)。当前源码尚未提交或推送；离线验证不代表实机验收。

0.11.1-test 将两个扫描按钮移入利润区，修复被原生窗口标题栏覆盖的问题；见 [遮挡修复报告](pdoc/report/REPORT_制造业扫描按钮遮挡修复.md)。

0.12.0-test 将利润卡片放入原生材料框的空余区域，普通配方不再增加窗口高度；主卡片和悬停提示精简为每件净利、售价、含手续费的总成本及报价时间。见 [内嵌与精简报告](pdoc/report/REPORT_制造业利润区内嵌与精简.md)、[离线布局预览](design/offline-profession-scan.png)及[离线悬停预览](design/offline-profession-tooltip.png)。
