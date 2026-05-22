# 新乡2000 UI Mockup image2 提示词

用于生成交易界面和商店界面 Mockup 的完整提示词，方便后续迭代。

---

## 生成参数（两张共用）

```json
{
  "model": "gpt-image-2",
  "size": "1536x1024",
  "quality": "high",
  "output_format": "png"
}
```

---

## 1. 交易界面 Mockup

**输出路径**：`art/ui_newxiang2000/trading_screen_mockup.png`

```
Pixel art game UI mockup for a stock trading card game, 16:9 aspect ratio, dark navy blue background (#1a1a2e), retro financial terminal aesthetic with neon accents.

LAYOUT — follow this exactly:

TOP BAR (full width, thin strip):
- Left side: "Wed Day 3/5 | Round 7/10" in white pixel text
- Right side: golden "MARKET EMOTION" button, golden "EVENT" button, three small round buttons (pause/play/fast-forward)
- No action points here

LEFT EDGE: A tall vertical four-color segmented bar (from top to bottom: blue segment, green segment, yellow segment, red segment) — this is a money health indicator

CENTER AREA (largest area, split into two chart panels stacked vertically):
- Upper chart: labeled "Round K" — shows about 7 candlestick bars (green up, red down) on black background with dark blue grid lines, like a stock chart
- Lower chart: labeled "Intraday K" — shows a more detailed price line/small candles on black background with dark blue grid

BETWEEN CHARTS AND BOTTOM: A horizontal emotion bar spanning the full width — left half is GREEN showing "Bull 65", right half is RED showing "Bear 35", with an arrow shape on each end (like the tug-of-war indicator from image6 reference)

RIGHT PANEL (vertical, beside the charts):
- Four stacked info boxes with pixel borders:
  1. Stock price: "¥156.00" in bright green with up arrow, "+3.2%"
  2. Cash: "¥85,200" in gold
  3. Holdings: "320 shares" with market value
  4. P/L: "+¥35,120 (+35.1%)" in green
- No props/insurance panels

BOTTOM AREA (full width):
- Left: opponent avatar silhouette + small vertical money bar + "Deck" button
- Center: 5 pixel art trading cards in a row (each card has colored top band — mix of green/red/orange/purple), with action point dots ABOVE the cards: "●●○" (2 lit cyan, 1 dark)
- Right: player avatar silhouette + small vertical money bar + "Deck" button

Style: clean pixel art, limited color palette, dark backgrounds, neon glow on important numbers, retro 90s Japanese RPG menu mixed with Bloomberg terminal. All text in pixel font. No anti-aliasing.
```

---

## 2. 商店界面 Mockup

**输出路径**：`art/ui_newxiang2000/shop_screen_mockup.png`

```
Pixel art game UI mockup for a post-market card shop screen in a stock trading card game, 16:9 aspect ratio, dark navy blue background (#1a1a2e), retro pixel art style with neon accents.

LAYOUT — follow this exactly:

TOP BAR (full width):
- Left: "AFTER-HOURS SHOP" title in large pixel font
- Center: "Day 3/5 Complete" in white
- Right: "Cash: ¥85,200" in large gold pixel numbers

UPPER LEFT AREA — "Today's Summary" panel with pixel border:
- Open: ¥100.00
- Close: ¥156.00 (+56%) in green
- Holdings: 320 shares
- Today P/L: +¥35,120 in green
- Total Assets: ¥135,120
- Target: ¥120,000 — showing a green checkmark (target reached)

UPPER RIGHT AREA — "Current Deck" panel with pixel border:
- Grid of small card thumbnails showing the player's deck
- Cards grouped by type with labels: "Buy x3", "Sell x3", "Insider Info x3", "Hype x3"
- "Total: 12 cards" at the bottom

LOWER HALF — Shop area with three tab buttons at the top:
- Three tabs: [BUY CARDS] (active/highlighted), [UPGRADE], [DELETE]
- Below tabs: a row of 4 purchasable cards displayed larger
- Each card shows: card name at top, pixel art icon in center, "¥1,000" price tag, and a green [BUY] button below
- The 4 cards have different colored top bands (green, red, orange, blue) representing different card types
- Cards that player cannot afford should appear grayed out

BOTTOM CENTER:
- Large button: "LEAVE SHOP — Next Day >>" with white border and pixel text

Style: clean pixel art, dark backgrounds, limited color palette, neon cyan and gold accents, retro RPG shop menu aesthetic, all text in pixel font, no anti-aliasing. The shop should feel cozy but functional, like a retro game shop screen.
```

---

## 迭代建议

- 修改提示词中的数字/文字即可生成不同状态的截图（如亏损状态、不同天数）
- 如需中文版，将所有英文文字替换为中文描述即可
- `quality: "low"` 可快速验证构图，确认后再用 `"high"` 出终稿
