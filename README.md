# Portscan

查看这台 Mac 上已经打开的套接字。采集走本机接口，不会去连别的主机。

数据从 netstat2 读出，关联 PID，再用 sysinfo 补上进程名，归一化成 `SocketSnapshot`，由 Tauri 事件交给 Svelte 的 `RenderState`。

## 开发

```bash
pnpm install
pnpm tauri dev
```
