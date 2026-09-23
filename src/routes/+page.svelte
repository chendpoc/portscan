<script lang="ts">
  import { onMount } from 'svelte'
  import { formatBytes, formatEndpoint, formatTime, rowKey, stateClass, stateLabel } from '$lib/format'
  import { renderState } from '$lib/render-state.svelte'
  import type { Protocol, SocketState } from '$lib/types'

  const protocols: Array<'all' | Protocol> = ['all', 'tcp', 'udp']
  const protocolLabel: Record<'all' | Protocol, string> = {
    all: '全部',
    tcp: 'TCP',
    udp: 'UDP',
  }
  const states: Array<'all' | SocketState> = [
    'all',
    'listen',
    'established',
    'time_wait',
    'close_wait',
    'syn_sent',
    'none',
  ]

  const statusLabel = {
    loading: '读取中',
    live: '实时',
    paused: '已暂停',
    error: '采集失败',
  }

  onMount(() => {
    void renderState.start()
    return () => {
      void renderState.stop()
    }
  })

  function onQuery(event: Event) {
    const target = event.currentTarget
    if (target instanceof HTMLInputElement) renderState.setQuery(target.value)
  }

  function onState(event: Event) {
    const target = event.currentTarget
    if (target instanceof HTMLSelectElement) {
      renderState.setConnectionState(target.value as 'all' | SocketState)
    }
  }

  function onInterval(event: Event) {
    const target = event.currentTarget
    if (target instanceof HTMLSelectElement) void renderState.setInterval(Number(target.value))
  }

  function onUdp(event: Event) {
    const target = event.currentTarget
    if (target instanceof HTMLInputElement) void renderState.setIncludeUdp(target.checked)
  }

  function onIpv6(event: Event) {
    const target = event.currentTarget
    if (target instanceof HTMLInputElement) void renderState.setIncludeIpv6(target.checked)
  }
</script>

<div class="shell">
  <header class="topbar">
    <div class="brand">
      <h1>Portscan</h1>
      <p>本机套接字</p>
      <span class="status {renderState.status}"><i></i>{statusLabel[renderState.status]}</span>
    </div>
    <div class="controls">
      <input
        class="search"
        type="search"
        placeholder="搜索进程、端口或地址"
        aria-label="搜索套接字"
        value={renderState.query}
        oninput={onQuery}
      />
      <div class="segment" role="group" aria-label="协议">
        {#each protocols as item (item)}
          <button
            type="button"
            aria-pressed={renderState.protocol === item}
            onclick={() => renderState.setProtocol(item)}
          >
            {protocolLabel[item]}
          </button>
        {/each}
      </div>
      <select aria-label="连接状态" value={renderState.connectionState} onchange={onState}>
        {#each states as item (item)}
          <option value={item}>{item === 'all' ? '全部状态' : stateLabel(item)}</option>
        {/each}
      </select>
      <select aria-label="刷新间隔" value={renderState.settings.intervalMs} onchange={onInterval}>
        <option value={1000}>1 秒</option>
        <option value={2000}>2 秒</option>
        <option value={5000}>5 秒</option>
      </select>
      <button type="button" onclick={() => renderState.setPaused(!renderState.settings.paused)}>
        {renderState.settings.paused ? '继续' : '暂停'}
      </button>
      <button
        class="primary"
        type="button"
        disabled={renderState.refreshing}
        onclick={() => renderState.refreshNow()}
      >
        {renderState.refreshing ? '刷新中' : '立即刷新'}
      </button>
    </div>
  </header>

  {#if renderState.preview}
    <p class="banner">浏览器里是示例数据。在 Portscan 窗口中才会读取这台 Mac 的套接字。</p>
  {/if}
  {#if renderState.error}
    <p class="banner error" role="alert">{renderState.error}</p>
  {/if}

  <div class="workspace">
    <aside class="sidebar">
      <div class="stats">
        <div class="stat"><span>套接字</span><strong>{renderState.counts.total}</strong></div>
        <div class="stat"><span>已连接</span><strong>{renderState.counts.established}</strong></div>
        <div class="stat"><span>监听</span><strong>{renderState.counts.listen}</strong></div>
        <div class="stat"><span>UDP</span><strong>{renderState.counts.udp}</strong></div>
      </div>

      <h2>网卡</h2>
      {#if renderState.snapshot && renderState.snapshot.interfaces.length > 0}
        {#each renderState.snapshot.interfaces as iface (iface.name)}
          <div class="iface">
            <b>{iface.name}</b>
            <span class="traffic">
              ↓ {formatBytes(iface.receivedBytes)}<br />
              ↑ {formatBytes(iface.transmittedBytes)}
            </span>
          </div>
        {/each}
      {:else}
        <p class="note">还没有网卡数据。</p>
      {/if}

      <div class="checks">
        <label>
          <input type="checkbox" checked={renderState.settings.includeUdp} onchange={onUdp} />
          包含 UDP
        </label>
        <label>
          <input type="checkbox" checked={renderState.settings.includeIpv6} onchange={onIpv6} />
          包含 IPv6
        </label>
      </div>

      <div class="lsof">
        <button type="button" disabled={renderState.diagnosing} onclick={() => renderState.diagnose()}>
          {renderState.diagnosing ? '正在对照' : '用 lsof 对照'}
        </button>
        {#if renderState.lsof}
          <p>lsof -nP -i 有 {renderState.lsof.lineCount} 行，快照里有 {renderState.counts.total} 条。</p>
        {/if}
      </div>

      <p class="note">
        {#if renderState.snapshot}
          更新于 {formatTime(renderState.snapshot.capturedAt)}，显示 {renderState.visible.length} 条。
        {:else}
          正在等待第一次采集。
        {/if}
        只看这台机器已经打开的套接字。
      </p>
    </aside>

    <div class="table-wrap">
      {#if renderState.status === 'loading' && !renderState.snapshot}
        <p class="empty">正在读取本机套接字</p>
      {:else if renderState.visible.length === 0}
        <p class="empty">没有匹配的套接字</p>
      {:else}
        <table>
          <thead>
            <tr>
              <th>进程</th>
              <th>PID</th>
              <th>协议</th>
              <th>本地</th>
              <th>远端</th>
              <th>状态</th>
            </tr>
          </thead>
          <tbody>
            {#each renderState.visible as entry, index (rowKey(entry, index))}
              <tr>
                <td class="process" title={entry.processName ?? ''}>{entry.processName ?? '—'}</td>
                <td class="mono">{entry.pid ?? '—'}</td>
                <td class="proto {entry.protocol}">{entry.protocol.toUpperCase()}</td>
                <td class="mono">{formatEndpoint(entry.localAddress, entry.localPort)}</td>
                <td class="mono">{formatEndpoint(entry.remoteAddress, entry.remotePort)}</td>
                <td><span class="state {stateClass(entry.state)}">{stateLabel(entry.state)}</span></td>
              </tr>
            {/each}
          </tbody>
        </table>
      {/if}
    </div>
  </div>
</div>
