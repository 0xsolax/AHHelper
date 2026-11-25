# 拍卖助手开发目录

负责人：Solazhu

- `AuctionPilot/`：可直接安装的插件源码和使用说明。
- `dist/AuctionPilot-0.8.0-test.zip`：测试包，记录关注成品价格时间序列、原生搜索最近价并保留会话利润，撤下数量活跃度。保留自动刷新、材料最低档采购额、四项价格来源和原生上架准备；仅包含运行文件、说明和第三方许可证。
- `tests/`：Lua 5.1 逻辑、界面事件模拟和离线布局检查。
- `.tools/python/`：仅用于本项目测试的 `lupa==2.6`，不参与游戏运行或打包。
- `design/`：设计参考和明确标注的离线布局预览。
- `pdoc/design/`、`pdoc/report/`：实现边界与交付证据。

测试命令（当前机器）：

```powershell
& 'C:\Users\Admin\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' .\tests\run_tests.py
& 'C:\Users\Admin\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' .\tests\render_layout.py
.\tools\package.ps1
```

更换开发机器时，将 Python 包 `lupa==2.6` 安装到本项目 `.tools/python`；布局预览还使用 Pillow 和 Windows 微软雅黑字体。它们都不是插件运行依赖。

本次功能在 `codex/price-timestamp-history` 分支开发，以已合并的 0.7.0 为基线。用户已授权提交、推送、合并到 `main` 并安装到现有游戏插件目录；版本为 `0.8.0-test`。安装前备份旧插件，覆盖后可在游戏内 `/reload`，保留 SavedVariables；离线验证不代表实机验收。
