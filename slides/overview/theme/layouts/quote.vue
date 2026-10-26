<template>
  <div class="slidev-layout rh-quote">
    <div class="rh-accent-bar" />
    <div class="rh-quote-content">
      <slot />
    </div>
    <div class="rh-footer">
      <slot name="footer" />
    </div>
  </div>
</template>

<style scoped>
.rh-quote {
  display: flex;
  flex-direction: column;
  padding: 0;
  position: relative;
  height: 100%;
  overflow: hidden;
}

.rh-accent-bar {
  height: 4px;
  background: var(--slidev-rh-brand-red);
  flex-shrink: 0;
}

.rh-quote-content {
  flex: 1;
  display: flex;
  flex-direction: column;
  justify-content: center;
  padding: var(--slidev-rh-space-2xl) var(--slidev-rh-space-3xl);
}

.rh-quote-content :deep(blockquote) {
  border-left: 4px solid var(--slidev-rh-brand-red);
  padding-left: var(--slidev-rh-space-2xl);
  margin: 0;
  font-size: 1.15rem;
  font-style: italic;
  color: var(--slidev-rh-text-primary);
  line-height: 1.4;
}

.rh-quote-content :deep(blockquote p:last-child) {
  margin-bottom: 0;
}

.rh-quote-content :deep(p:not(blockquote p)) {
  color: var(--slidev-rh-text-secondary);
  font-size: 1rem;
  margin-top: var(--slidev-rh-space-xl);
  padding-left: var(--slidev-rh-space-2xl);
}

.rh-footer {
  position: absolute;
  bottom: var(--slidev-rh-space-md);
  left: var(--slidev-rh-space-2xl);
  right: var(--slidev-rh-space-2xl);
  font-size: 0.75rem;
  color: var(--slidev-rh-text-secondary);
}

.rh-footer:empty {
  display: none;
}
</style>
