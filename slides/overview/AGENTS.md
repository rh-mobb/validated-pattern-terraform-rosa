# AGENTS.md  -  mobb-deck-template

This is a Red Hat-themed [Slidev](https://sli.dev/) presentation template. It uses Markdown for content, Vue 3 SFCs for reusable components, and a custom CSS layer over the Slidev default theme. This document is the authoritative guide for AI agents making changes to this template or to any deck derived from it.

---

## Files in this template

| File | Purpose |
|------|---------|
| `slides.md` | 15 example slide formats  -  the pattern library |
| `AGENTS.md` | This file  -  authoring rules for AI agents |
| `README.md` | Human usage guide  -  setup, components, customisation |
| `PROMPT.md` | Ready-to-paste kickoff prompt for generating a first-draft deck from a project repo |
| `styles/index.css` | Red Hat palette, typography, layout helpers |
| `components/` | Vue components: `RhTwoColumn`, `RhTable`, `RhTimeline`, `RhSpectrum` |
| `public/` | Example images; replace with your own |

When helping a user build a new presentation, always check `PROMPT.md`  -  it defines the expected workflow and output structure.

---

## Stack overview

| Layer | Choice | Notes |
|-------|--------|-------|
| Deck engine | Slidev (`@slidev/cli` ~0.49) | Vite-powered; Markdown → slides |
| Base theme | `@slidev/theme-default` | Customised via `styles/index.css`, not forked |
| UI framework | Vue 3 | Components in `components/` are auto-registered |
| Syntax highlighting | Shiki | Set in frontmatter: `highlighter: shiki` |
| Diagrams | Mermaid | In-Markdown fenced blocks only  -  see constraints below |
| Styling | Custom CSS + UnoCSS utilities | `styles/index.css` + Tailwind-compatible class names |
| Fonts | Google Fonts  -  Red Hat Display / Text / JetBrains Mono | Loaded via `@import` in `styles/index.css` |

---

## How to run and review

### Start the dev server

From the template directory:

```bash
npm install
npm run dev
# or: make dev
```

The server starts at **http://localhost:3030**. Navigate to slide `N` at `/N`.

### Mandatory review workflow for slide changes

Do not judge slide quality from Markdown source alone. Layout issues, overflow, and contrast only appear in the browser.

1. Start (or reuse) the dev server.
2. Navigate to the changed slide.
3. Capture a screenshot of the full slide area using the IDE browser tool or equivalent.
4. Evaluate using the screenshot **and** the source:
   - Is anything clipped, overflowing, or overlapping?
   - Does the slide have one clear main idea?
   - Does the red accent, typography, and spacing read well at full-slide scale?
   - If the slide has a diagram or animation, does it still support the spoken story?
5. Propose the smallest fix that solves the issue (spacing class, `text-sm`, splitting a slide).
6. Ask for human feedback before sweeping restyles or large restructures  -  slides are subjective.

Repeat for **every slide you materially change**.

---

## Editing map

| File | What it controls |
|------|-----------------|
| `slides.md` | All slide content, frontmatter, Mermaid diagrams, speaker notes |
| `styles/index.css` | RH palette variables, typography, layout helpers (`.cols-2`, `.rh-tag`, `.rh-image-slide`) |
| `components/RhTwoColumn.vue` | Two-column slot wrapper |
| `components/RhTable.vue` | Props-driven HTML table with RH styling |
| `components/RhTimeline.vue` | Horizontal milestone timeline  -  takes `milestones[]` and optional `legend[]` props |
| `components/RhSpectrum.vue` | Maturity/spectrum scale  -  takes `stages[]` prop |
| `public/` | Static assets (images, SVGs) served at `/filename` |
| `package.json` | Slidev version, npm scripts |

Do not modify `node_modules/`. Do not hard-code version numbers in Terraform-style dependency pins inside `package.json`  -  let npm resolve ranges (`^0.49.0`).

---

## Slide frontmatter reference

Every slide is separated by `---` on its own line. A slide can carry optional frontmatter:

```yaml
---
layout: section       # Use with class: section-header for landmark slides
class: section-header # Applies the .section-header CSS class to the slide
---
```

```yaml
---
layout: center        # Centres all content; good for quote/closing slides
class: text-center    # Adds Tailwind text-center to the slide root
---
```

Available layouts from `@slidev/theme-default`:

| Layout | Use case |
|--------|----------|
| `default` | Standard content slide (no frontmatter needed) |
| `section` | Section landmark; large heading |
| `center` | Centred content; good for quotes and closing |
| `two-cols` | Built-in two-column with `::right::` divider |
| `image-right` | Image on the right, content on the left |
| `cover` | Full-bleed title slide variant |

The `section-header` class is custom (defined in `styles/index.css`) and must be paired with `layout: section`.

---

## Component authoring patterns

### Props-driven components

Prefer props over slots for structured data (tables, timelines, spectrum stages). This makes the component easy to use in Markdown without JSX-style syntax.

```vue
<script setup>
defineProps({
  items: { type: Array, required: true },
  title: { type: String, default: '' },
})
</script>
```

### Named slots for layout wrappers

Use named slots for layout components where the content is rich Markdown:

```vue
<template>
  <div class="cols-2">
    <div><slot name="left" /></div>
    <div><slot name="right" /></div>
  </div>
</template>
```

Called in Markdown as:

```md
<MyLayout>
  <template #left>

  Left content  -  Markdown works here, including **bold** and lists.

  </template>
  <template #right>

  Right content

  </template>
</MyLayout>
```

**Important:** leave a blank line after `<template #left>` and before `</template>`. Without it, Slidev does not parse the slot content as Markdown.

### Scoped styles

Use `<style scoped>` for component-specific CSS. For slide-level overrides that need specificity, scope under `.slidev-layout`:

```vue
<style scoped>
.my-component {
  color: var(--rh-red);
}
</style>
```

Do not override `.slidev-layout` styles from inside a component  -  that belongs in `styles/index.css`.

### Animated components

Slidev auto-registers everything in `components/` as a Vue 3 component. This means you can build fully interactive, animated diagrams in plain Vue  -  no Mermaid limitations, no click-progression required, loop forever or respond to presenter interaction.

#### Two patterns

**Pattern A  -  CSS keyframe / SVG animation**
For simple looping visuals (spinners, flow arrows, pulsing nodes):
- Inline SVG directly in the template so `<style scoped>` can target SVG element IDs.
- Use `@keyframes` + `animation:` for looping effects.
- Wrap timing in CSS custom properties so they can be overridden per-instance via `:style`.
- Reference `var(--rh-*)` palette tokens rather than hard-coded hex.

**Pattern B  -  Reactive phase animation (recommended for diagrams with state)**
For diagrams that cycle through multiple states (before/during/after, steady/spike/restore):

```vue
<script setup lang="ts">
import { ref, computed, watch, onUnmounted } from 'vue'
import { useIsSlideActive } from '@slidev/client'

// 1. Define your phases as static data  -  each phase is a complete
//    snapshot of what the diagram should show, not a delta.
const PHASES = [
  { label: 'At Rest',  sublabel: '...', nodes: [ /* ... */ ] },
  { label: 'Spike',    sublabel: '...', nodes: [ /* ... */ ] },
  { label: 'Restored', sublabel: '...', nodes: [ /* ... */ ] },
]

const PHASE_MS = 4000   // time per phase
const TICK_MS  = 60     // progress bar refresh rate

const phaseIndex = ref(0)
const progress   = ref(0)
const paused     = ref(false)
const current    = computed(() => PHASES[phaseIndex.value])

let phaseTimer:    ReturnType<typeof setInterval> | null = null
let progressTimer: ReturnType<typeof setInterval> | null = null

function stopTimers() {
  if (phaseTimer)    { clearInterval(phaseTimer);    phaseTimer    = null }
  if (progressTimer) { clearInterval(progressTimer); progressTimer = null }
}
function startTimers() {
  stopTimers()
  phaseTimer = setInterval(() => {
    phaseIndex.value = (phaseIndex.value + 1) % PHASES.length
    progress.value = 0
  }, PHASE_MS)
  progressTimer = setInterval(() => {
    progress.value = Math.min(100, progress.value + (TICK_MS / PHASE_MS) * 100)
  }, TICK_MS)
}

// 2. Click a dot to jump to that phase and pause.
//    Click the active dot again to resume.
function selectPhase(i: number) {
  if (paused.value && i === phaseIndex.value) {
    paused.value = false
    progress.value = 0
    startTimers()
  } else {
    phaseIndex.value = i
    paused.value = true
    progress.value = 100
    stopTimers()
  }
}

// 3. Only animate when this slide is actually visible.
//    useIsSlideActive() returns false for off-screen slides even when
//    Slidev keeps them mounted for transitions.
const isActive = useIsSlideActive()
watch(isActive, (active) => {
  if (active) {
    paused.value     = false
    phaseIndex.value = 0
    progress.value   = 0
    startTimers()
  } else {
    stopTimers()
    phaseIndex.value = 0
    progress.value   = 0
    paused.value     = false
  }
}, { immediate: true })

onUnmounted(() => stopTimers())
</script>
```

Key design rules for Pattern B:

- **Phases are snapshots, not deltas.** Each phase defines the complete visual state of every element. Never try to compute "what changed"  -  just describe "what it looks like now." Vue's reactivity and CSS `transition:` handle the visual interpolation automatically.
- **Use index as `v-for` key inside a stable container.** When an element exists in every phase but changes type/colour (e.g. a pod going from `balloon` to `evicted`), key it by position so Vue reuses the DOM node and the CSS transition fires. When an element enters or leaves (e.g. a new node appearing), key it by a stable ID and wrap with `<TransitionGroup>` or use `v-show` with opacity/transform transitions.
- **CSS `transition: all 0.4s ease` on leaf elements** is all you need for smooth colour/border changes between phases  -  no JavaScript animation required.
- **Keep invisible elements in the DOM** rather than `v-if`-ing them out of every phase. Use `opacity: 0; transform: scale(0.9); pointer-events: none` for hidden state. This preserves layout stability (no reflow when they appear) and keeps transitions smooth.
- **Progress bar + phase dots** give the audience a visual cue that the diagram is animated without requiring explanation. Dots as clickable phase-jump targets let the presenter pause on any state during Q&A.
- **Use `useIsSlideActive()` instead of `onMounted` to start timers.** Slidev pre-mounts adjacent slides for transitions, so `onMounted` fires before the slide is actually visible. `useIsSlideActive()` from `@slidev/client` returns a reactive boolean that is only `true` when the slide is the current presenter view. Reset the phase index to 0 when the slide becomes active so the audience always sees the animation from the start. Stop and reset when the slide leaves view.
- **`onUnmounted` must also stop all timers** as a safety net for full component teardown.

#### Styling conventions for animated diagrams

```css
/* Pod / node colour tokens  -  consistent with dark slide backgrounds */
.pod.app         { background: rgba(34,197,94,.1);  border: 1px solid #22c55e; color: #22c55e; }
.pod.balloon     { background: rgba(245,158,11,.1); border: 1px solid #f59e0b; color: #f59e0b; }
.pod.evicting    { background: rgba(239,68,68,.12); border: 1px solid #ef4444; color: #ef4444;
                   animation: blink 0.7s ease-in-out infinite; }
.pod.provisioning{ background: rgba(99,102,241,.1); border: 1px dashed #6366f1; color: #818cf8;
                   animation: pulse 1.3s ease-in-out infinite; }
.pod.empty       { background: transparent; border: 1px dashed #383838; color: transparent; }

/* Transition all visual properties when class changes between phases */
.pod { transition: background 0.4s ease, border-color 0.4s ease, color 0.4s ease; }

@keyframes blink { 0%,100% { opacity: 1; } 50% { opacity: 0.2; } }
@keyframes pulse { 0%,100% { opacity: 0.5; } 50% { opacity: 1; } }
```

Avoid `var(--rh-*)` tokens inside animated components because the palette is designed for slide typography, not diagram elements. Use explicit RGBA values with low opacity backgrounds so diagrams work on both light and dark slide backgrounds.

#### Reference implementation

`components/PhaseAnimation.vue` in this template is a complete working example of Pattern B. It animates a four-phase Kubernetes balloon-pod lifecycle (at rest → spike → provisioning → restored) and demonstrates all the techniques above: phase snapshots, index-keyed CSS transitions, invisible-but-present node-5, click-to-pause dots, progress bar, and timer cleanup.

---

## Mermaid rules (critical)

### Rule 1: Mermaid blocks must be in plain slide Markdown

Mermaid fenced blocks **only render when placed directly in slide Markdown**  -  not inside Vue component template slots. Slot content bypasses the Mermaid transform pipeline.

```md
<!-- CORRECT: block is in normal slide Markdown -->
# My Slide

Some text.

\```mermaid
flowchart LR
  A --> B
\```
```

```md
<!-- WRONG: block is inside a Vue slot  -  renders as raw text -->
<RhTwoColumn>
  <template #right>

  \```mermaid
  flowchart LR
    A --> B
  \```

  </template>
</RhTwoColumn>
```

### Rule 2: Use the built-in two-cols layout for Mermaid + text columns

When you need a diagram alongside text, use Slidev's built-in `two-cols` layout:

```md
---
layout: two-cols
---

Left column Markdown content here.

::right::

\```mermaid
flowchart LR
  A --> B
\```
```

### Rule 3: Quote edge labels containing special characters

```
A -->|"O(1) lookup"| B    ← correct: quoted
A -->|O(1) lookup| B      ← breaks: parens parsed as node syntax
```

### Rule 4: Do not use explicit `fill:` / `color:` style statements in Mermaid

Hard-coded `style A fill:#EE0000` breaks in the Slidev Mermaid pipeline and looks bad in dark/light mode transitions. Use the default theme colours or rely on node shape to signal meaning.

### Rule 5: Avoid `end`, `subgraph`, `graph` as bare node IDs

These are reserved keywords that conflict with Mermaid parser rules. Use `endNode`, `processEnd`, etc. instead.

### Fallback: complex topology → PNG in public/

For diagrams that are too dense for Mermaid (many nodes, complex layout), generate a PNG/SVG externally, add it to `public/`, and use the `.rh-image-slide` pattern:

```md
<div class="rh-image-slide">

Caption text

<div class="rh-image-slide__figure">
<img src="/my-diagram.png" alt="Descriptive alt text" />
</div>

</div>
```

---

## CSS scoping rules

All slide typography and layout overrides must be scoped under `.slidev-layout`:

```css
/* Correct: scoped, won't bleed into presenter UI */
.slidev-layout h2 {
  color: var(--rh-blue);
}

/* Wrong: global, can break Slidev's own navigation UI */
h2 {
  color: var(--rh-blue);
}
```

Utility classes like `text-sm`, `mt-4`, `flex`, `items-center` are from Slidev's UnoCSS layer (Tailwind-compatible). Use them freely on elements inside slides. For arbitrary values, use bracket notation: `text-[var(--rh-muted)]`, `bg-[var(--rh-surface)]`.

---

## Sizing images correctly

`max-h-[Xvh]` on images is **relative to the browser viewport**, not Slidev's scaled slide canvas. At small browser windows or in presenter mode, this causes unexpected overflow.

Use the `.rh-image-slide` flex wrapper instead  -  it fills the available height below the title and caption without overflowing the slide canvas:

```md
<div class="rh-image-slide">

Caption text

<div class="rh-image-slide__figure">
<img src="/diagram.png" alt="Alt text" />
</div>

</div>
```

The supporting CSS in `styles/index.css` handles the flex layout automatically.

---

## Known pitfalls

| Pitfall | Symptom | Fix |
|---------|---------|-----|
| Mermaid in a Vue slot | Raw fenced block rendered as text | Move to plain slide Markdown or use `two-cols` layout |
| `max-h-[Xvh]` on images | Image overflows at small viewports | Use `.rh-image-slide` flex wrapper |
| Goto dialog list visible when closed | Stray list on the right edge of every slide | Patched in `styles/index.css` (`#slidev-goto-dialog:has(input:disabled)`)  -  do not remove |
| `--base` in `dev` script | 404 on assets during local dev | `--base` belongs only in the `build` script |
| Mermaid edge labels with parens | Diagram parse error | Wrap label in quotes |
| Reserved keyword as node ID | Diagram parse error | Use `endNode`, not `end` |
| Props in Markdown arrays with single quotes | Vue template parse error | Use double quotes inside `:rows="[...]"` |
| Missing blank line inside slot `<template>` | Slot content rendered as raw HTML, not Markdown | Add blank line after `<template #slot>` and before `</template>` |

---

## Speaker notes

Every slide should include a speaker note  -  an HTML comment block below the slide body:

```md
# My Slide

Slide content here.

<!--
Speaker note: What to say for this slide. What to emphasise.
Transition: how to bridge to the next slide.
-->
```

Notes appear in presenter view. Write them as speaking prompts, not full scripts  -  one or two sentences per slide is enough.

---

## Self-review checklist

Before handing off any slide work:

- [ ] Dev server runs without errors (`npm run dev`)
- [ ] Every changed slide has been screenshot-reviewed in the browser
- [ ] No text is clipped, overflowing, or overlapping any other element
- [ ] Mermaid diagrams render correctly (not as raw code fences)
- [ ] Images use the `.rh-image-slide` wrapper or explicit `max-h` tuned to the slide
- [ ] Every slide has a speaker note
- [ ] No hard-coded hex colours that conflict with `--rh-*` palette variables
- [ ] `npm run build` succeeds before declaring the deck ready for production

---

## Adding a new slide format

1. Identify the information type and the closest existing format in `slides.md`.
2. Add the new slide **after** the existing examples, with a comment header explaining the format.
3. If the format requires a new component, create it in `components/` following the authoring patterns above.
4. Document the new component in `README.md` (props table, usage example).
5. Screenshot-review the new slide before committing.

---

## Typography

**Never use em-dashes (`—`, U+2014) in any source file.**
Use a spaced hyphen (` - `) instead. Em-dashes are invisible to most linters, cause encoding issues in scripts that do string matching, and are inconsistent across editors and copy-paste contexts.

This applies to: `.md` files, `.vue` components, `.ts`/`.js` source, YAML, speaker notes, inline HTML in slides  -  everywhere.

---

## Promoting to its own git repo

When extracting this template to a standalone repository:

1. Copy the directory contents (not the parent repo).
2. Run `git init && git add . && git commit -m "Initial commit"`.
3. Update `package.json` `name` and the `build --base` flag to match the new repo name.
4. Remove any references to the parent repo from `README.md`.
5. Verify `make build` succeeds in the new location.
