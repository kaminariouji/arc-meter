import { chromium } from 'playwright'
const ctx = await chromium.launchPersistentContext('', { channel: 'chrome', headless: true, viewport: { width: 640, height: 820 }, deviceScaleFactor: 2 })
const page = ctx.pages()[0] ?? (await ctx.newPage())
await page.goto('https://arc-meter.pages.dev/', { waitUntil: 'networkidle', timeout: 45000 })
await page.waitForTimeout(3000)
await page.screenshot({ path: 'C:/CRYPTO MONEY MAKER/tmp/arc-meter/cover.png', clip: { x: 0, y: 0, width: 640, height: 640 } })
console.log('saved')
await ctx.close()
