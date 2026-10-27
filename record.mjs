import { chromium } from 'playwright'
import fs from 'fs'
const OUT = 'C:/CRYPTO MONEY MAKER/tmp/arc-meter/video-raw'
fs.rmSync(OUT, { recursive: true, force: true })
fs.mkdirSync(OUT, { recursive: true })
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))
const ctx = await chromium.launchPersistentContext('', {
  channel: 'chrome', headless: true,
  viewport: { width: 1280, height: 720 },
  recordVideo: { dir: OUT, size: { width: 1280, height: 720 } }
})
const page = ctx.pages()[0] ?? (await ctx.newPage())
page.setDefaultTimeout(45000)
async function visit (url, waitMs, label) {
  console.log('[video]', label, url)
  try { await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 45000 }) } catch (e) { console.log('[video] warn', e.message.slice(0, 60)) }
  await sleep(waitMs)
}
await visit('https://github.com/kaminariouji/arc-meter', 5000, 'repo + demo table')
await page.mouse.wheel(0, 420); await sleep(2600)
await visit('https://arc-meter.pages.dev/', 6500, 'live app, closed channel')
await page.mouse.move(640, 420); await page.mouse.wheel(0, 300); await sleep(2400)
await page.mouse.wheel(0, -300); await sleep(1200)
await visit('https://github.com/kaminariouji/arc-meter/blob/master/media/arc-studio-test-run.txt', 5500, 'arc studio test run')
await page.mouse.wheel(0, 300); await sleep(2200)
await visit('https://github.com/kaminariouji/arc-meter/blob/master/media/receipts.json', 5500, 'mainnet receipts')
await page.mouse.wheel(0, 320); await sleep(2400)
await ctx.close()
const files = fs.readdirSync(OUT)
console.log('[video] done', files.join(', '))
