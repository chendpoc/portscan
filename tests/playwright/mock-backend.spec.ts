import { expect, test } from '@playwright/test'

declare global {
  interface Window { __test: ReturnType<typeof mockBackendScript> }
}

function mockBackendScript({ count: rowCount }: { count: number }) {
    const now = () => new Date().toISOString()
    const evidence = (path: string) => ({ state: 'available', path, message: null })
    const entries = Array.from({ length: rowCount }, (_, i) => ({
      key: { pid: 70001 + i, startSec: 100, startUsec: i + 1 },
      name: `fixture-worker-${i}`,
      cpuPercent: i === 0 ? 10 : 1,
      rssBytes: 1048576,
      status: 'sleeping',
      parentPid: null,
      cwd: evidence(`/tmp/fixture-project-${i}`),
      executable: evidence('/usr/bin/test-worker'),
      contextDisplay: `/tmp/fixture-project-${i}`,
      contextKind: 'cwd',
    }))
    const sockets = entries.slice(0, 2).map((p, i) => ({
      pid: p.key.pid,
      processName: p.name,
      processKey: p.key,
      protocol: i ? 'udp' : 'tcp',
      state: i ? 'none' : 'listen',
      localAddress: '127.0.0.1',
      localPort: 31001 + i,
      remoteAddress: i ? null : '10.0.0.2',
      remotePort: i ? null : 443,
    }))
    const state = {
      processes: { generation: 1, capturedAt: now(), entries },
      sockets: { generation: 1, capturedAt: now(), sockets, interfaces: [] },
      processError: null,
      socketError: null,
      processErrorGeneration: null,
      socketErrorGeneration: null,
    }
    let refreshGeneration = 1
    let id = 1
    const callbacks = new Map<number, (payload: unknown) => void>()
    const listeners = new Map<string, number[]>()
    const control = {
      state,
      detailCalls: [] as unknown[],
      hold: false,
      failDetail: false,
      pending: [] as Array<() => void>,
      copied: null as string | null,
      emit(event: string, payload: unknown) {
        for (const handler of listeners.get(event) ?? []) callbacks.get(handler)?.({ event, id: handler, payload })
      },
      resolveAll() {
        for (const pending of control.pending.splice(0)) pending()
      },
    }
    ;(window as unknown as { __test: typeof control }).__test = control
    ;(window as unknown as { isTauri: boolean }).isTauri = true
    ;(window as unknown as Record<string, unknown>).__TAURI_EVENT_PLUGIN_INTERNALS__ = { unregisterListener() {} }
    ;(window as unknown as Record<string, unknown>).__TAURI_INTERNALS__ = {
      transformCallback(fn: (payload: unknown) => void) {
        const key = id++
        callbacks.set(key, fn)
        return key
      },
      async invoke(cmd: string, args: Record<string, unknown> = {}) {
        if (cmd === 'get_settings') return { intervalMs: 2000, paused: true, includeUdp: true, includeIpv6: true }
        if (cmd === 'get_monitor_state') return structuredClone(state)
        if (cmd === 'plugin:event|listen') {
          listeners.set(args.event as string, [...(listeners.get(args.event as string) ?? []), args.handler as number])
          return args.handler
        }
        if (cmd === 'plugin:event|unlisten') return
        if (cmd === 'request_refresh') {
          refreshGeneration += 1
          setTimeout(() => control.emit('refresh-complete', refreshGeneration), 0)
          return
        }
        if (cmd === 'update_settings') return args.settings
        if (cmd === 'get_process_detail') {
          control.detailCalls.push(args.key)
          if (control.failDetail) throw new Error('detail denied')
          const finish = () => ({
            key: args.key,
            command: ['verified-command', String((args.key as { pid: number }).pid), 'argument with space'],
            exe: '/usr/bin/test-worker',
            cwd: evidence(`/tmp/fixture-project-${(args.key as { pid: number }).pid - 70001}`),
            executable: evidence('/usr/bin/test-worker'),
            appBundle: null,
            collectedAt: now(),
            verifiedAt: now(),
            ancestry: [{ key: { pid: 1, startSec: 1, startUsec: 1 }, name: 'launchd', relationshipVerified: true }],
            ancestryIncomplete: true,
            startTimeIso: '1970-01-01T00:01:40Z',
          })
          if (control.hold) await new Promise<void>((resolve) => control.pending.push(resolve))
          return finish()
        }
        if (cmd.includes('clipboard') || cmd === 'copy_text') {
          control.copied = args.text as string
          return
        }
        if (cmd === 'open_process_terminal') return
        throw new Error(`Unexpected mock IPC ${cmd}`)
      },
    }
    document.addEventListener('DOMContentLoaded', () => {
      const badge = document.createElement('div')
      badge.textContent = 'TEST BACKEND FIXTURE'
      badge.style.cssText = 'position:fixed;bottom:25px;right:4px;z-index:9999;background:#fff2b3;font:9px monospace;pointer-events:none'
      document.body.append(badge)
    })
    Object.defineProperty(navigator, 'clipboard', {
      value: { writeText: async (text: string) => { control.copied = text } },
    })
    return control
}

test.describe('mock backend integration', () => {
  test.use({ viewport: { width: 760, height: 520 } })

  async function setup(page: import('@playwright/test').Page, count = 2) {
    await page.addInitScript(mockBackendScript, { count })
    await page.goto('/')
    await expect(page.getByText('TEST BACKEND FIXTURE')).toBeVisible()
    await expect(page.locator('.process-table tbody tr')).toHaveCount(count)
  }

  test('async detail rerenders while monitoring is paused', async ({ page }) => {
    await setup(page)
    await page.locator('.process-table tbody tr').first().locator('.process-cell').click()
    await expect(page.locator('.inspector-pane')).toContainText('verified-command', { timeout: 2000 })
    await expect(page.getByRole('button', { name: 'Terminal', exact: true })).toBeEnabled()
  })

  test('per-view selection persistence', async ({ page }) => {
    await setup(page)
    await page.locator('.process-table tbody tr').first().locator('.process-cell').click()
    await page.getByRole('group', { name: 'Primary view' }).getByRole('button', { name: 'Ports', exact: true }).click()
    await page.locator('.ports-table tbody tr').filter({ hasText: '70002' }).click()
    await page.getByRole('group', { name: 'Primary view' }).getByRole('button', { name: 'Processes', exact: true }).click()
    await expect(page.locator('.inspector-title')).toContainText('70001')
  })

  test('late detail reply cannot replace latest selection', async ({ page }) => {
    await setup(page)
    await page.evaluate(() => { (window as unknown as { __test: { hold: boolean } }).__test.hold = true })
    await page.locator('.process-table tbody tr').first().locator('.process-cell').click()
    await page.locator('.process-table tbody tr').nth(1).locator('.process-cell').click()
    expect(await page.evaluate(() => (window as unknown as { __test: { detailCalls: unknown[] } }).__test.detailCalls.length)).toBe(1)
    await page.evaluate(() => {
      const t = (window as unknown as { __test: { hold: boolean; resolveAll: () => void } }).__test
      t.hold = false
      t.resolveAll()
    })
    await expect(page.locator('.inspector-pane')).toContainText('70002', { timeout: 2000 })
    await expect(page.locator('.inspector-pane')).toContainText('verified-command', { timeout: 2000 })
  })

  test('detail first failure does not keep spinning', async ({ page }) => {
    await setup(page)
    await page.evaluate(() => { (window as unknown as { __test: { failDetail: boolean } }).__test.failDetail = true })
    await page.locator('.process-table tbody tr').first().locator('.process-cell').click()
    await expect(page.locator('.inspector-pane')).toContainText('detail denied', { timeout: 2000 })
    await expect(page.locator('.inspector-pane')).not.toContainText('Reading…')
  })

  test('port chip keeps processes slot and opens ports inspector', async ({ page }) => {
    await setup(page)
    await page.locator('.process-table tbody tr').first().locator('.process-cell').click()
    await page.locator('.port-chip').first().click()
    await expect(page.getByRole('group', { name: 'Primary view' }).getByRole('button', { name: 'Ports', exact: true })).toHaveAttribute('aria-pressed', 'true')
    await expect(page.locator('.inspector-pane')).toContainText('70001')
    await page.getByRole('group', { name: 'Primary view' }).getByRole('button', { name: 'Processes', exact: true }).click()
    await expect(page.locator('.inspector-pane')).toContainText('70001')
  })

  test('1000 rows preserve scroll position across view switches', async ({ page }) => {
    await setup(page, 1000)
    const before = await page.locator('.table-scroll[data-view="processes"]').evaluate((el) => {
      el.scrollTop = 400
      return el.scrollTop
    })
    expect(before).toBeGreaterThan(0)
    await page.getByRole('group', { name: 'Primary view' }).getByRole('button', { name: 'Ports', exact: true }).click()
    await page.getByRole('group', { name: 'Primary view' }).getByRole('button', { name: 'Processes', exact: true }).click()
    expect(await page.locator('.table-scroll[data-view="processes"]').evaluate((el) => el.scrollTop)).toBe(before)
  })

  test('compact layout hides PID column', async ({ page }) => {
    await page.setViewportSize({ width: 640, height: 420 })
    await setup(page)
    await expect(page.locator('.process-table thead th').filter({ hasText: 'PID' })).toHaveCount(0)
  })
  test('hidden selection retains latest facts, capture times and completed detail after exit', async ({ page }) => {
    await setup(page)
    await page.locator('.process-table tbody tr').first().locator('.process-cell').click()
    await expect(page.locator('.inspector-pane')).toContainText('verified-command')
    await page.getByRole('group', { name: 'Primary view' }).getByRole('button', { name: 'Ports', exact: true }).click()
    await page.locator('.ports-table tbody tr').filter({ hasText: '70002' }).locator('td').first().click()
    await expect(page.locator('.inspector-pane')).toContainText('verified-command')
    await page.evaluate(() => {
      const t = window.__test
      const entries = t.state.processes.entries.map((entry, index) => index === 0 ? { ...entry, name: 'updated fixture worker' } : entry)
      const sockets = t.state.sockets.sockets.map((entry, index) => index === 0 ? { ...entry, localPort: 31999 } : entry)
      t.emit('process-snapshot', { ...t.state.processes, generation: 3, capturedAt: '2026-09-24T01:02:03Z', entries })
      t.emit('snapshot', { ...t.state.sockets, generation: 3, capturedAt: '2026-09-24T01:02:04Z', sockets })
      t.emit('process-snapshot', { ...t.state.processes, generation: 4, capturedAt: '2026-09-24T01:02:05Z', entries: entries.slice(1) })
      t.emit('snapshot', { ...t.state.sockets, generation: 4, capturedAt: '2026-09-24T01:02:06Z', sockets: sockets.slice(1) })
      t.failDetail = true
    })
    await page.getByRole('group', { name: 'Primary view' }).getByRole('button', { name: 'Processes', exact: true }).click()
    await expect(page.locator('.inspector-title')).toContainText('updated fixture worker')
    await expect(page.locator('.inspector-source-lines')).toContainText('Process historical')
    await expect(page.locator('.inspector-source-lines')).toContainText('Sockets historical')
    await expect(page.locator('.metric-row')).toContainText('Uptime at last observation')
    await expect(page.getByRole('button', { name: 'Terminal', exact: true })).toBeDisabled()
    await page.getByRole('button', { name: 'Copy', exact: true }).click()
    const report = await page.evaluate(() => window.__test.copied)
    expect(report).toContain('2026-09-24T01:02:03Z')
    expect(report).toContain('2026-09-24T01:02:04Z')
    expect(report).toContain('31999')
    expect(report).toContain('verified-command')
    expect(report).toContain('70001')
  })

  test('older lifecycle events cannot overtake a newer source observation', async ({ page }) => {
    await setup(page)
    await page.locator('.process-table tbody tr').first().locator('.process-cell').click()
    await expect(page.locator('.inspector-pane')).toContainText('verified-command')
    const before = await page.evaluate(() => window.__test.detailCalls.length)
    await page.evaluate(() => {
      const t = window.__test
      t.emit('process-snapshot', { ...t.state.processes, generation: 10, capturedAt: new Date().toISOString() })
      t.emit('refresh-complete', 9)
      t.emit('refresh-fatal', { generation: 9, message: 'obsolete failure' })
    })
    await expect(page.getByRole('alert')).toHaveCount(0)
    expect(await page.evaluate(() => window.__test.detailCalls.length)).toBe(before)
    await page.evaluate(() => window.__test.emit('refresh-complete', 10))
    await expect.poll(() => page.evaluate(() => window.__test.detailCalls.length)).toBe(before + 1)
    await page.evaluate(() => window.__test.emit('refresh-complete', 10))
    expect(await page.evaluate(() => window.__test.detailCalls.length)).toBe(before + 1)
  })

})
