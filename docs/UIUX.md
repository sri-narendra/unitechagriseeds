# UIUX.md — UI/UX Guidelines (static HTML edition)

Visual and interaction design system for the three static surfaces in
`blueprint.md` §2: **`public/`** (company website), **`dealer/`** (Dealer
Portal), **`admin/`** (Admin Portal).

> **How to apply:** there is no build step and no shared CSS file — every HTML
> page embeds the token block (§9) and component styles in its own `<style>`.
> Keep the tokens **byte-identical** across all pages.

> **Hard constraint (from `blueprint.md` §1):** the product is inventory-only.
> There is **no money, price, or currency anywhere** — quantities are plain
> integers with a "units" label, never formatted as currency.

---

## 1. Design principles

- **Calm & legible** — dealers use this daily in shops; admin uses it for
  oversight. Prioritize readability over decoration.
- **Status is color + label** — never rely on color alone (see §8 a11y).
- **One source of truth, instant reflection** — `blueprint.md` §9: a change in
  one portal must feel immediate; use subtle motion to confirm it.
- **Mobile-first** — dealers often use phones; admin can use wider screens.

---

## 2. Color

### 2.1 Brand & surface palette

The canonical tokens are the CSS variables in §9 — paste them into every page
and keep them identical.

| Token | Hex | Use |
|-------|-----|-----|
| `--color-primary` | `#2E7D32` | Leaf green — primary actions, active nav, brand |
| `--color-primary-600` | `#1B5E20` | Hover/pressed primary |
| `--color-primary-50` | `#E8F5E9` | Selected rows, soft fills, backgrounds |
| `--color-warn` | `#EF6C00` | Earth/amber — highlights, low-stock, pending |
| `--color-bg` | `#F4F7F4` | App background (warm off-white) |
| `--color-surface` | `#FFFFFF` | Cards, panels, tables |
| `--color-border` | `#D9E2DC` | Dividers, input borders |
| `--color-text` | `#1B2B22` | Primary text |
| `--color-muted` | `#5B6B61` | Secondary text, hints |

### 2.2 Semantic status colors (map to `blueprint.md` states)

| State | Token | Hex | Maps to |
|-------|-------|-----|---------|
| Success / sent / accepted | `--color-primary` (alias `--color-success`) | `#2E7D32` | Order `sent`, Return `accepted` |
| Warning / pending / low-stock | `--color-warn` | `#EF6C00` | Order `pending`, Return `pending`, low-stock flag |
| Danger / rejected / error | `--color-danger` | `#C62828` | Return `rejected`, validation errors, stock-out |
| Info / excess | `--color-info` | `#1565C0` | Excess-stock dealers (`blueprint.md` §5.1) |
| Neutral | `--color-muted` | `#5B6B61` | Inactive, historical |

**Rule:** status is always shown as a **pill with icon + text** (§6.1), never
color alone.

### 2.3 Portal theming

- **Public (`public/`)** — lighter, more imagery; brand green for CTAs only,
  large whitespace, product photos prominent.
- **Dealer (`dealer/`)** — functional green header + tab nav; dense but airy cards.
- **Admin (`admin/`)** — same green system, denser tables, more data per screen.

---

## 3. Typography

### 3.1 Fonts
- UI / body: **Inter** (system fallback: `-apple-system, Segoe UI, Roboto, sans-serif`).
- Numerals: use **tabular figures** for all quantities so stock counts align in
  tables (`font-variant-numeric: tabular-nums`).
- No display/decorative font needed; weight does the hierarchy.

### 3.2 Type scale (rem, base 16px)

| Role | Size | Weight | Line-height | Example |
|------|------|--------|-------------|---------|
| Display (page title) | 1.75rem | 700 | 1.2 | "Stock Stats" |
| H2 (section) | 1.25rem | 600 | 1.3 | "Order Requests" |
| H3 (card title) | 1rem | 600 | 1.4 | "Rice Seed" |
| Body | 0.875rem | 400 | 1.5 | table cells |
| Quantity (big number) | 2rem | 700 | 1.1 | `150` units |

- Never use font sizes below `0.75rem` (12px) for body text.

---

## 4. Spacing & layout

### 4.1 Spacing scale (4px base)

`--space-1: 4px · --space-2: 8px · --space-3: 12px · --space-4: 16px ·
 --space-5: 24px · --space-6: 32px · --space-8: 48px · --space-10: 64px`

Use the scale exclusively — no ad-hoc margins. Stack gaps default to `--space-4`.

### 4.2 Layout

- **Max content width:** `1080px` centered (`.container` class defined in each
  page's `<style>`); admin tables may use full width.
- **Breakpoints:** `sm 640px`, `md 768px`, `lg 1024px`. Dealer nav collapses to
  a bottom tab bar on `< md` (thumb-reachable).
- **Public site:** centered single-column with generous `--space-8` vertical
  rhythm.
- **Portals:** top header (brand + account/logout) + horizontal **tab nav**
  (`blueprint.md` §9: Dealer = Stock Stats · Return · Sale · Order;
  Admin = Dashboard · Products · Dealers · Orders · Returns).
- **Cards:** `--space-5` padding, `--color-surface`, `1px` `--color-border`,
  `8px` radius, subtle shadow `0 1px 2px rgba(0,0,0,0.04)`.

---

## 5. Component style

### 5.1 Buttons
- **Primary** (green fill): main action — Submit Sale, Send Stock, Approve.
- **Secondary** (white + green border): alternate action — Cancel, Back.
- **Ghost** (text only): low-emphasis — view details.
- **Danger** (red outline/fill): Reject, Remove product.
- Height `40px`, radius `8px`, label weight 600, min-width to fit + `--space-4`
  padding. Disabled = 40% opacity, no pointer. While a write is in flight the
  button shows an inline spinner and stays disabled (double-click guard).

### 5.2 Inputs / selects
- Height `40px`, radius `8px`, `1px` `--color-border`, `12px` padding.
- Focus: `2px` `--color-primary` ring (never remove outline for a11y).
- Quantity inputs are **integer-only**, show unit label ("units") beside.
- **Search inputs** (list header): same input style but with a subtle
  "Search…" placeholder; filter is client-side and re-runs on `input`.
- **Quantity steppers** (multi-item carts): `−` / `+` ghost buttons with the
  current count between them (`tabular-nums`); buttons disable at the bounds
  (1 min, stock max).
- Labels sit above inputs, `--color-text`, weight 500.

### 5.3 Tables (core to dealer/admin)
- Header row: `--color-primary-50` background, weight 600, left-aligned.
- Rows: `12px` vertical padding; hover = `--color-primary-50`.
- Right-align numeric/quantity columns (tabular nums).
- Empty state row: "No records yet" with icon (§6.2).

### 5.4 Product card / catalogue (`blueprint.md` §4.3, §5.2)
- Square product **image** (object-fit cover, `8px` radius) + **Name** below.
- "Add to Cart" button; selected state = green border + check overlay.
- Admin product grid: image + name + Edit/Remove actions.

### 5.5 Tabs (portal nav)
- Active tab: green underline (2px) + `--color-text`; inactive: `--color-muted`.
- Bottom tab bar on mobile (`< md`) with icon + label (`blueprint.md` §9).

### 5.6 Modals & toasts
- Modal: dimmed scrim `rgba(0,0,0,0.4)`, centered card, Esc/outside-click
  close, focus trapped.
- Toast: top-right, auto-dismiss `3s`; success green, error red — always with
  text (not color alone).

### 5.7 Stock Stats view (dealer landing, `blueprint.md` §4.0)
- Per-product card: **Name** + big **quantity** number + low-stock pill if
  flagged.
- Recent movement list: each row shows direction icon (in/out) + product +
  quantity + relative time.

---

## 6. Status & badges

### 6.1 Status pills
Rounded full (`999px`), `0.75rem` text, icon + label:
- `pending` → amber bg/text
- `sent` / `accepted` → green
- `rejected` → red
- `low-stock` → amber with warning icon
- `excess` → blue info

### 6.2 State feedback
| State | Treatment |
|-------|-----------|
| Loading | Skeleton shimmer (not spinners) for lists/cards; button shows inline spinner + disabled |
| Empty | Centered icon + "Nothing here yet" + contextual action |
| Error | Inline red text under field; page error = toast + Retry |
| Success | Toast + subtle highlight pulse on the changed row |

---

## 7. Animation rules

### 7.1 Tokens
- `--motion-fast: 150ms` · `--motion-base: 200ms` · `--motion-slow: 300ms`
- Easing: `cubic-bezier(0.2, 0, 0, 1)` (ease-out) for enters; reverse for exits.

### 7.2 What to animate (subtle only)
- Tab/content switch: fade + `4px` slide up (`--motion-base`).
- Modal: scrim fade + card scale `0.98 → 1`.
- Toast: slide in from right.
- Stock change confirmation: the affected row/card gets a one-time
  `--color-primary-50` highlight pulse (`--motion-slow`), then settles.
- Hover: `background-color` / `border-color` transition `--motion-fast`.

### 7.3 What NOT to animate
- No entrance animations on initial page load (except hero on public site).
- No parallax, no looping motion, no confetti.
- No layout-shifting transitions on data tables.

### 7.4 Reduced motion (mandatory)
```css
@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after {
    animation-duration: 0.01ms !important;
    transition-duration: 0.01ms !important;
  }
}
```
All motion is enhancement only — every state must be readable with motion off.

---

## 8. Accessibility

- **Contrast:** text vs background ≥ WCAG AA (4.5:1); large text 3:1.
- **Color + label:** every status uses icon + text, never color alone (§6.1).
- **Focus:** visible `2px` primary ring on all interactive elements; logical tab
  order (nav → content → actions).
- **Forms:** every input has a `<label>`; errors announced via
  `aria-describedby`.
- **Touch targets:** ≥ `40px` on mobile.
- **Images:** product images need `alt` = product name; decorative imagery
  `alt=""`.

---

## 9. Token reference (paste into every page's `<style>`)

```css
:root {
  /* brand & surface */
  --color-primary: #2E7D32;
  --color-primary-600: #1B5E20;
  --color-primary-50: #E8F5E9;
  --color-warn: #EF6C00;
  --color-warn-50: #FFF3E0;
  --color-bg: #F4F7F4;
  --color-surface: #FFFFFF;
  --color-border: #D9E2DC;
  --color-text: #1B2B22;
  --color-muted: #5B6B61;

  /* semantic (success == primary) */
  --color-danger: #C62828;
  --color-danger-50: #FFEBEE;
  --color-info: #1565C0;
  --color-info-50: #E3F2FD;

  /* spacing (4px base) */
  --space-1: 4px;  --space-2: 8px;  --space-3: 12px; --space-4: 16px;
  --space-5: 24px; --space-6: 32px; --space-8: 48px;

  /* motion */
  --motion-fast: 150ms;
  --motion-base: 200ms;
  --motion-slow: 300ms;

  /* radius */
  --radius: 10px;
  --radius-sm: 6px;
}
```

Keep this block **byte-identical in every HTML page** — with no shared CSS
file, identical copies *are* the design system.

---

## 10. Consistency checklist

- Quantity = integer + "units" label, tabular nums, never currency.
- Status always = pill (icon + text) using §2.2 tokens.
- Portal tab nav matches `blueprint.md` §9 exactly.
- Every motion respects `prefers-reduced-motion`.
- Product = name + image only (`blueprint.md` §5.2) — no price/cost fields.
- Static-HTML hygiene: same `<head>` meta, same token block (§9), same
  config script (`backendStack.md` §3), same header/nav markup in every page of
  a portal — copy, don't improvise.