# Codex Battery v1.2.0

Your Codex quota, at a glance — a native macOS menu bar battery.

## Highlights

- Remaining percentage inside the battery icon.
- Green, orange and red **charge fill**, with editable boundaries (70% / 20% by default).
- 5-hour quota, weekly quota or whichever has less remaining; reset times in the menu.
- Configurable refresh, manual refresh, light/dark appearance and optional launch at login.
- English, Simplified Chinese and Japanese in both the app and README.
- Universal Apple Silicon / Intel archive targeting macOS 13+.

## Install

1. Install Codex CLI and sign in using a ChatGPT account (`codex login`).
2. Download `CodexBattery-1.2.0-universal.zip` below, unzip it, and move the app into `/Applications` or `~/Applications`.
3. Open the app and click its battery in the menu bar.

The archive is ad-hoc signed and **not Apple-notarized**. macOS may block downloaded builds. You may build from the tagged source instead. `SHA256SUMS` verifies the archive bytes. The app requires an installed CLI that returns Codex account rate limits; API-key-only accounts do not provide this view.

Example quota illustrations use the app's actual icon renderer, not live user account values. The app has no telemetry backend and does not start model turns.

## 中文说明

首个公开版本：将 Codex 剩余额度显示为菜单栏电池，百分比写在内部，**电量填充条**按区间变绿、橙、红；可自定义阈值。支持 5 小时 / 每周额度及重置时间，界面和文档提供中、英、日三种语言。

下载通用版 ZIP，解压并移入应用程序目录即可使用；需要已登录 ChatGPT 账号的 Codex CLI。安装包采用本地签名，尚未经过 Apple 公证，macOS 可能拦截下载版本。也可从标签对应源码构建。

[English](https://github.com/AdvancingTitans/codex-battery#readme) · [简体中文](https://github.com/AdvancingTitans/codex-battery/blob/main/README.zh-CN.md) · [日本語](https://github.com/AdvancingTitans/codex-battery/blob/main/README.ja.md)
