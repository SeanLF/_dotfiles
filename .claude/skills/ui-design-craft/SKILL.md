---
name: ui-design-craft
description: Use when building or refining web UI chrome and components (tables, badges, status indicators, focus states, colour tokens, dark mode, editorial layout) and you want evidence-grounded, non-templated design decisions instead of framework defaults or AI-default "warm editorial" clichés. A decision reference with vendor citations, not an essay.
---

# UI design craft: evidence-grounded chrome decisions

A decision reference for web UI chrome and components. Every claim is cited to a
vendor system, standard, or study so you can verify rather than trust. Distilled
from research on colour/comprehension, icons, modern-vs-dated signals, product
design-system teardowns, and editorial devices. When in doubt, open devtools and
check the real value; several popular numbers are third-party folklore (see the
sourcing caution at the end).

## 1. Status and meaning without colour-alone

The single most-broken rule. Colour is preattentive (found in ~200-250ms across a
whole display, search time roughly flat as rows grow) but colour _alone_ is a weak
carrier of meaning.

- **Redundant coding wins, not colour.** Colour + shape-distinct icon + text ~= **88%**
  selection accuracy vs **66%** colour-alone, **58%** shape-alone [Nothelfer et al.,
  "Redundant Encoding in Data Visualizations"]. Redundancy also blunts the density
  penalty and covers the colour-vision-deficient (CVD) population for free.
- **One alarm axis per screen.** People reliably distinguish ~5-7 categorical
  colours; for status you want <=3-4. Multiple competing colour axes mean nothing
  pops [NN/g; gov.uk Design System].
- **RAG (green/amber/red) for _operational_ status only** (the traffic-light
  convention is near-universal signalling, even though colour _symbolism_ is
  cultural). Do not spend the alarm axis on ordinal or brand meaning; a green "very
  good" reads as a verdict and fights the real health axis. Use a shape meter or
  weight for ordinal scales, and reserve hue.
- **CVD is the binding constraint** (~8% of men, ~0.5% of women). Red/green is
  maximally hostile to the commonest deficiency. **WCAG 1.4.1 (Level A)** forbids
  colour as the only channel. **Every status must survive greyscale** = icon + label
  [Colour Blind Awareness; W3C WAI].
- **Icon + label, never icon-only.** Unlabeled icons are routinely misread; **ISO
  9186** sets a ~67% comprehension bar many icons fail; adding a word (e.g. "MENU")
  lifted clicks ~20% [NN/g; ISO 9186]. Carbon defines a state as "the sum of colour,
  shape, and symbol," with the text label "the most important element"; Polaris /
  Primer / Material / Lightning all pair icon + colour + text plus visually-hidden
  text for a11y.
- **Tiny, non-decorative glyph set** (~4 semantic marks: check / triangle / circle-x
  / info). Decorative or ambiguous icons measurably _raise_ cognitive load [EEG study
  PMC11142986].
- **A bare coloured dot is colour-only** = insufficient for actionable status.
  Reserve the dot for ambient presence (online / unread); switch to a shape-distinct
  glyph the moment severity matters.

Pattern that satisfies all of the above: `✓ Healthy / ▲ Degraded / ✕ Down` =
shape-distinct mark + colour + word.

## 2. Modern vs dated (radius / depth / density)

"Dated" is the _ensemble_, not any single token.

- **0px is NOT inherently dated.** Sharp/flat is a live, respected editorial/Swiss
  camp (Vercel marketing, brutalist). It reads _un-designed_ only when flatness pairs
  with cramped rows + heavy borders + default web serifs.
- **Modern radius band:** respected systems cluster at **6px** inputs/buttons, **8px**
  cards, **full-pill** badges. Geist restricts to 4/6/9999; Tailwind `rounded-md`=6px;
  Polaris 4-8px; Radix contextual 3-8px [vendor docs]. A timid 3px is neither
  committed-sharp nor modern-soft; pick a side.
- **Flat is over; subtle depth is back.** NN/g measured weak-signifier flat UIs at
  +22% time / +25% fixations. The modern move is a **hairline border + one soft
  low-opacity shadow**, never bevels/gloss. Use sparingly; a calm tool leans on
  borders, not shadows.
- **Spacious, not cramped.** "Start with too much whitespace." Data tables get
  _taller rows + generous padding_, not tiny type [Refactoring UI].
- **Type-role split is THE anti-newspaper move** = serif for display/headlines, clean
  sans/mono for chrome/labels/data. **Georgia/Times as body text is a genuine dated
  tell** (and previews lie if you haven't embedded the real webfont).

## 3. The design-system steal-list

The reusable craft, ranked best-first. All vendor-published unless flagged.

1. **Radix 12-step colour scale as the token model.** Fixed semantic rungs:
   1-2 app bg, 3-5 component bg (3 rest / 4 hover / 5 selected), 6-8 borders
   (6 separator / 7 element / 8 strong+focus), 9-10 solid fill (9 = the _one_ pure
   accent), 11-12 text (11 secondary / 12 primary) with **APCA-guaranteed contrast**.
   A matching **alpha** variant per step composites over any surface. Dark mode is
   NOT lightness-inverted: 9/10 stay ~fixed, backgrounds keep a whisper of hue, raised
   surfaces get _lighter_ [radix-ui.com/colors]. This retires the manual "lock to AA
   at ship time" chore and fixes the recurring dark-mode white-on-accent button bug
   (filled accent = step 9 + computed `accent-contrast` text, not hardcoded white).
2. **Alpha hairlines** = borders/dividers as translucent ink (`rgba(0,0,0,.08)` light
   / `rgba(255,255,255,.08)` dark, or Radix `grayA6`). One token pair works in both
   themes over any background [Geist gray-alpha; Raycast .08/.16].
3. **Two-layer focus ring** `box-shadow: 0 0 0 2px var(--bg), 0 0 0 4px var(--accent)`
   = bg-gap ring + accent ring, legible over any surface with no dark override (verify
   accent-on-bg >=3:1) [Geist]. A calmer single 2px @50% is the fallback.
4. **Badge variants.** Radix `soft` = accent-A3 bg + accent-A11 text (AA-guaranteed)
   as the calm default; a **transparent hairline-pill label** (no fill = no contrast
   pair to fail) as the most editorial tag; `solid` (step 9) reserved for one urgent
   flag [Radix Badge; Primer Label].
5. **Table craft.** ~44px rows, ~12px cell padding, **alpha-hairline dividers, no
   zebra**, `tabular-nums` right-aligned on numerics, a subtle **hover wash** (~10%
   alpha, not a solid swap), two density tiers (comfortable ~40 / compact ~32), sticky
   header [Radix Table; Primer DataTable; Carbon; Polaris].
6. **Border folded into the shadow.** Cards use one `box-shadow` = crisp 1px edge
   layer + 1-2 soft blur layers, not a separate `border` + `box-shadow` [Radix +
   Primer + Geist].
7. **Dark mode = mute the accent (not the greys)**, keep a whisper of hue in the
   near-black bg (a warm or cool near-black, not `#000`), raised surfaces step
   _lighter_ by small fixed deltas [Primer `dark_dimmed`; Carbon; Stripe layered
   greys].
8. **Split the UI/label type scale from the reading scale.** The serif reading scale
   stays generous; a separate, tighter sans/mono scale handles nav/cells/timestamps/
   badges [Carbon; Geist].
9. **Radix space (4/8/12/16/24/32/40/48/64) + radius (3/4/6/8/12/16) scales** =
   adopt verbatim; both sit on a 4px grid.
10. **Motion tokens** 150/200/300ms, one easing; nothing <150ms (jittery) or >300ms
    (laggy). Radix ships _no_ transitions at all (calm); pick one philosophy and hold
    it [Geist; Polaris].
11. **Calm empty/loading.** A 1s two-step alpha-pulse skeleton (no shimmer sweep);
    empty state = one calm sentence + whitespace, no marketing illustration [Radix;
    Primer Blankslate; Polaris EmptyState].

## 4. Editorial devices (the transferable subset)

- **Enforce type roles with no bleed.** A metadata line is always mono, a headline
  always serif, never the reverse. The single highest-leverage move and mostly
  discipline/deletion, not new fonts [Rest of World style guide].
- **Wide full-width hairline over a narrow ~60-68ch measure.** Rules span the grid;
  prose stays in a narrow column. Reads "designed grid" more than any font choice
  [NYT/Economist fronts].
- **Single-accent discipline.** Accent on links-on-hover / a live signal / one
  word-splash, never on rules or labels. A _subtractive_ steal [Economist red].
- **Invisible micro-typography, zero downside:** `tabular-nums` for aligned figures;
  `text-wrap: pretty` (body) / `balance` (headlines); `hanging-punctuation: first
last` (Safari, degrades gracefully elsewhere).
- **Restrained motion.** Hover link-underline draw via `background-size` 0->100%, not
  `text-decoration`; optional sticky mono section label on long pages. Nothing with a
  canvas. Always honour `prefers-reduced-motion`.

## 5. Honest skips and do-not-fabricate

Deliberately reject (evidence, not taste):

- **Zebra striping** on tables (alpha-hairline dividers + hover wash beat it).
- **Uppercase institutional badges** and 5-tier density ladders (over-built for most
  tools).
- **Shadow-based dark elevation** (use lighter-surface deltas instead).
- **Cartoon/illustration empty states** (one calm sentence wins).
- **The AI-default "warm editorial" palette:** cream (`#faf3e8`-ish) + terracotta as
  the _whole_ palette. Cool the paper and make the warm accent rare instead. Also skip
  drop-caps + pull-quotes unless there is genuinely long prose to carry them, and
  never `#000`/`#fff` for a dark _reading_ surface.

Sourcing caution (verify before hardcoding):

- **Stripe's exact focus-ring CSS and internal Dashboard table metrics are not
  public** = community "Stripe values" are folklore. Its face is Söhne, not the
  often-cited alternatives.
- **Linear/Raycast px/hex are third-party-scraped.** Spot-check in devtools before
  treating any specific value as canonical.
- General rule: if a number would drive a layout decision, confirm it in the vendor's
  published docs or your own devtools, not a blog post.

## Sources

Primary anchors: Nothelfer et al. (redundant encoding), NN/g (icon usability, flat
design), W3C WAI 1.4.1, gov.uk Design System, ISO 9186, Radix Colors/Themes, Vercel
Geist, GitHub Primer, IBM Carbon, Shopify Polaris, Rest of World style guide,
Refactoring UI.
