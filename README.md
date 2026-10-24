# Codex Battery

原生 macOS 菜单栏工具，电池内部显示 Codex **剩余额度**百分比。已安装到 `~/Applications/Codex Battery.app`。

- 默认显示 5 小时周期，每 30 秒读取一次真实账号用量。
- 点击图标可查看 5 小时 / 每周额度、重置时间和最后更新时间。
- 「电池显示」可切换每周额度，或两个周期中较低的剩余额度。
- 电池内部的电量填充默认 ≥70% 为绿色、20%–不足70% 为橙色、<20% 为红色。
- 「电量颜色区间…」可自定义绿色起点和红色上限，保存后立即生效并在重启后保留。阈值须为 0–100 的整数，红色上限须小于绿色起点；可恢复默认值后保存。
- 可手动刷新，或选择 15 / 30 / 60 / 300 秒刷新。
- 「登录时启动」可开关开机登录后自动运行，默认关闭。
- 网络或登录失败时图标显示 `?`，菜单保留标注为上次数据的额度；所选周期不存在时显示 `—`。
- 百分比数字保持黑白对比，颜色用于电量填充条；图标随系统菜单栏自动适配深浅色，无 Dock 图标。

使用已登录的 Codex CLI，通过官方 `account/rateLimits/read` 接口读取；不创建对话或发起模型生成，不自行读取、复制或保存登录凭证。CLI 与桌面 Codex 应登录同一账号。运行需要已安装并登录的 Codex CLI（`codex login`）。

## 重新构建和验证

需要 macOS 13+ 和 Xcode Command Line Tools。产物跟随本机架构。

```sh
./build.sh
"$HOME/Applications/Codex Battery.app/Contents/MacOS/CodexBattery" --check
```

构建脚本在系统临时目录构建并签名，生成 `Codex Battery.zip`，解压即可得到应用，避免 iCloud 文稿同步元数据影响应用签名。构建脚本会运行内置解析与颜色边界检查；`--check` 在同一个 app-server 连接中连续读取两次实际用量。应用使用本地临时签名，供本机使用。

退出：点击电池图标 →「退出 Codex Battery」。卸载前先关闭「登录时启动」，退出后删除应用。

官方接口说明：https://learn.chatgpt.com/docs/app-server
