---
layout: home

hero:
  name: PortMaster
  text: macOS 上的 Windows 任务管理器
  tagline: 谁在吃 CPU、谁占了 8787 端口、它是哪个项目起的——一个 760×520 的小窗口，全部看清。纯本地采集，只读，不联网。
  image:
    src: /demo-overview.png
    alt: PortMaster 界面演示：进程总览、搜索过滤、进程详情与端口视图
  actions:
    - theme: brand
      text: 开始使用
      link: /guide
    - theme: alt
      text: GitHub 仓库
      link: https://github.com/chendpoc/portscan

features:
  - icon: 🧮
    title: 进程总览
    details: 列出当前用户可见的全部进程，CPU / RSS 默认每 2 秒刷新，按 CPU 降序排列。刚启动的进程显示「采样中」，绝不编一个 0.0%。
  - icon: 🔌
    title: 端口归属一目了然
    details: 每个进程持有的监听端口直接标在行内；端口视图按端口号搜索，EADDRINUSE 之后两步直达肇事进程。
  - icon: 🔍
    title: 进程身份详情
    details: 完整启动命令、可执行文件路径、工作目录、父进程链——两个同名的 node 进程，看项目目录就能分清谁是谁。
  - icon: 🕒
    title: 数据新鲜度可见
    details: 每条数据都带采集时间。刷新失败时保留上一份结果并明确标记「已过期」，绝不拿旧数据冒充实时。
  - icon: 🛡️
    title: 只读，不碰你的系统
    details: 不提供杀进程按钮，不终止、不重启、不自动修复。看清之后，回到你自己的终端里做决定。
  - icon: 🪶
    title: 原生轻量
    details: SwiftUI 原生应用，基于 Darwin libproc 与本机套接字扫描采集，没有 Electron，没有后台守护进程。
---

<div class="pm-section pm-reveal">

## 端口被占了？别再 lsof → ps → 再 lsof

<div class="pm-section-sub">
切项目时撞端口是家常便饭。传统的排查要在终端里来回切换好几趟；PortMaster 把这条链路压进一个窗口。
</div>

<div class="pm-steps">
  <div class="pm-step">
    <span class="pm-step-num">1</span>
    <h3>搜端口</h3>
    <p>服务起不来，报 <code>EADDRINUSE 127.0.0.1:8787</code>。在端口视图直接输入 <code>8787</code>。</p>
  </div>
  <div class="pm-step">
    <span class="pm-step-num">2</span>
    <h3>看是谁</h3>
    <p>监听者、PID、协议与状态逐行列出，点开就是进程详情：完整命令、工作目录、父进程链。</p>
  </div>
  <div class="pm-step">
    <span class="pm-step-num">3</span>
    <h3>回终端处理</h3>
    <p>确认是上个项目残留的 node 进程后，复制信息回到你自己的工作流里收尾。决定权始终在你手里。</p>
  </div>
</div>

</div>

<div class="pm-section pm-reveal">

## 界面实况

<div class="pm-section-sub">
以下是应用真实运行界面的录屏。
</div>

<div class="pm-shot-grid">
  <div class="pm-shot">
    <img src="/demo-overview.png" alt="PortMaster 主窗口演示：进程总览、搜索过滤、进程详情、端口视图" loading="lazy" />
    <div class="pm-shot-caption">主窗口 · 760×520 · 进程 / 端口双视图实时刷新</div>
  </div>
  <div class="pm-shot">
    <img src="/demo-compact.png" alt="PortMaster 紧凑窗口演示" loading="lazy" />
    <div class="pm-shot-caption">紧凑模式 · 小窗口下的进程检查器</div>
  </div>
</div>

</div>

<div class="pm-section pm-reveal">

## 几条认真守住的边界

<div class="pm-principles">
  <div class="pm-principle">
    <strong>零 ≠ 不可用 ≠ 过期</strong>
    <span>读不到的字段明确标「macOS 未提供」，刷新失败标「已过期」。一个空值永远不会被误当成零。</span>
  </div>
  <div class="pm-principle">
    <strong>PID 复用不会骗过你</strong>
    <span>选中状态绑定进程实例而非 PID。进程退出或被替换后，详情页如实提示，不会静默挂到新进程上。</span>
  </div>
  <div class="pm-principle">
    <strong>命令行不外泄</strong>
    <span>启动命令只在详情页按需展示，复制是你的显式操作；不写日志、不留历史、不上传。</span>
  </div>
  <div class="pm-principle">
    <strong>克制功能边界</strong>
    <span>不做进程管控、不画历史曲线、不监控别的主机。它是一盏灯，不是一个遥控器。</span>
  </div>
</div>

</div>

<div class="pm-section pm-reveal">

## 五分钟跑起来

```bash
git clone https://github.com/chendpoc/portscan.git
cd portscan
xcodebuild -project macos/PortMaster.xcodeproj -scheme PortMaster build
```

<div class="pm-section-sub">
需要 macOS 14+ 与 Xcode 15+。也可以在 Xcode 中打开 <code>macos/PortMaster.xcodeproj</code>，选择 PortMaster scheme 直接运行。详见<a href="/portscan/guide">使用指南</a>。
</div>

</div>
