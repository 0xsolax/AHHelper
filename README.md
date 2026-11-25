# 拍卖助手开发目录

负责人：Solazhu

- `AuctionPilot/`：可直接安装的插件源码和使用说明。
- `dist/AuctionPilot-0.8.2-profession-test.zip`：当前专业配方扫描测试包。关闭页面保留会话扫描结果，重载或退出游戏后清理；主动加入监控才保存配方。保留 0.8.1 的已有功能；仅包含运行文件、说明和第三方许可证。
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

本次功能在 `codex/profession-profit-scan` 分支、`.tools/worktrees/profession-profit-scan` 独立目录开发，以提交 `1e532f0`（0.8.1）为基线。主工作区已有「单品转售与限量商店价」未提交改动，本目录不包含、不覆盖该改动。本次交付源码、测试包与报告；未合并、推送或写入游戏目录，离线验证不代表实机验收。
