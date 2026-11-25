# 拍卖助手开发目录

负责人：Solazhu

- `AuctionPilot/`：可直接安装的插件源码和使用说明。
- `dist/AuctionPilot-0.10.0-test.zip`：合并专业配方扫描与单品转售的测试包。关闭页面保留扫描结果，重载或退出游戏后清理；普通与限量商品均可监控转售利润。仅包含运行文件、说明和第三方许可证。
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

本次按用户授权合并单品转售与专业配方扫描，在 `codex/combined-auction-features` 隔离工作目录验证两份基于 `1e532f0` 的功能改动。已通过 194 项回归及 36 个布局检查，同步合并源码，完整备份旧插件，并将统一测试版安装到现有游戏目录，SavedVariables 前后哈希不变。当前源码尚未提交或推送。使用方法见插件内 README，备份位置、安装核对和实机测试步骤见 [合并安装报告](pdoc/report/REPORT_配方扫描与单品转售合并安装.md)；离线验证不代表实机验收。
