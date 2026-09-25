import { expect, test } from '@playwright/test'

const screenshotDir = 'docs/verification/v0.4-screenshots'

async function expectGlyphsLoaded(page: import('@playwright/test').Page) {
  const widths = await page.locator('.process-glyph').evaluateAll((images) =>
    images.map((img) => (img as HTMLImageElement).naturalWidth),
  )
  expect(widths.length).toBeGreaterThan(0)
  expect(widths.every((width) => width > 0)).toBe(true)
}

test.describe('PortMaster v0.4 preview fixtures', () => {
  test.use({ viewport: { width: 760, height: 520 } })

  test('process overview at 760x520', async ({ page }) => {
    await page.goto('/')
    const viewport = page.viewportSize()
    expect(viewport?.width).toBe(760)
    expect(viewport?.height).toBe(520)
    await expect(page.getByRole('group', { name: 'Primary view' }).getByRole('button', { name: 'Processes' })).toBeVisible()
    await expect(page.getByText('Preview fixture')).toBeVisible()
    await expect(page.locator('.process-table')).toBeVisible()
    await expectGlyphsLoaded(page)
    await page.screenshot({ path: `${screenshotDir}/01-processes-overview.png`, fullPage: true })
  })

  test('inspector split view', async ({ page }) => {
    await page.goto('/')
    await page.locator('.process-table tbody tr').filter({ hasText: 'api-red' }).first().locator('.process-cell').click()
    await expect(page.getByRole('complementary', { name: 'Process inspector' })).toBeVisible()
    await expect(page.locator('.inspector-title')).toContainText('48291')
    await expect(page.getByRole('button', { name: 'Terminal' })).toBeVisible()
    await expectGlyphsLoaded(page)
    await page.screenshot({ path: `${screenshotDir}/02-process-inspector.png`, fullPage: true })
  })

  test('search filter state for two node processes', async ({ page }) => {
    await page.goto('/')
    await page.getByLabel('Search').fill('node')
    await expect(page.getByText('2 matching processes')).toBeVisible()
    await expect(page.locator('.process-table tbody tr')).toHaveCount(2)
    await page.screenshot({ path: `${screenshotDir}/03-search-filter.png`, fullPage: true })
  })

  test('cpu sort state', async ({ page }) => {
    await page.goto('/')
    await page.locator('.process-table thead button', { hasText: 'CPU' }).click()
    await expect(page.locator('.process-table th[aria-sort="ascending"]')).toContainText('CPU')
    await page.locator('.process-table thead button', { hasText: 'CPU' }).click()
    await expect(page.locator('.process-table th[aria-sort="descending"]')).toContainText('CPU')
    const firstCpu = page.locator('.process-table tbody tr').first().locator('.cpu')
    await expect(firstCpu).toContainText('38.4%')
    await page.screenshot({ path: `${screenshotDir}/04-cpu-sort.png`, fullPage: true })
  })

  test('ports secondary view', async ({ page }) => {
    await page.goto('/')
    await page.getByRole('group', { name: 'Primary view' }).getByRole('button', { name: 'Ports' }).click()
    await expect(page.locator('.ports-table')).toBeVisible()
    await page.screenshot({ path: `${screenshotDir}/05-ports-secondary.png`, fullPage: true })
  })

  test('numeric search returns only port owner', async ({ page }) => {
    await page.goto('/')
    await page.getByLabel('Search').fill('8787')
    await expect(page.locator('.process-table tbody tr')).toHaveCount(1)
    await expect(page.locator('.process-table tbody tr').first()).toContainText('api-red')
  })

  test('keyboard opens and closes inspector and clears an empty search', async ({ page }) => {
    await page.goto('/')
    const row = page.locator('.process-table tbody tr').filter({ hasText: 'api-red' }).first()
    await row.focus()
    await row.press('Enter')
    await expect(page.getByRole('complementary', { name: 'Process inspector' })).toBeVisible()
    await page.keyboard.press('Escape')
    await expect(page.getByRole('complementary', { name: 'Process inspector' })).toHaveCount(0)
    await page.getByLabel('Search', { exact: true }).fill('no-such-fixture-12345')
    await expect(page.getByText('No matching processes', { exact: true })).toBeVisible()
    await page.getByRole('button', { name: 'Clear search', exact: true }).focus()
    await page.keyboard.press('Space')
    await expect(page.locator('.process-table tbody tr')).toHaveCount(8)
  })

  test('compact overview at 640x420', async ({ page }) => {
    await page.setViewportSize({ width: 640, height: 420 })
    await page.goto('/')
    await expect(page.locator('.process-table')).toBeVisible()
    await expect(page.getByRole('complementary', { name: 'Process inspector' })).toHaveCount(0)
    await page.screenshot({ path: `${screenshotDir}/06-compact-overview.png`, fullPage: true })
  })

  test('compact inspector at 640x420', async ({ page }) => {
    await page.setViewportSize({ width: 640, height: 420 })
    await page.goto('/')
    await page.locator('.process-table tbody tr').filter({ hasText: 'api-red' }).first().locator('.process-cell').click()
    await expect(page.getByRole('button', { name: '← Back' })).toBeVisible()
    await page.screenshot({ path: `${screenshotDir}/07-compact-inspector.png`, fullPage: true })
  })
})
