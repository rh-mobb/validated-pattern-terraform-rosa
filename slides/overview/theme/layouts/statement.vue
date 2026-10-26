<template>
  <div class="slidev-layout rh-statement">
    <div class="rh-accent-bar" />
    <div class="rh-statement-content">
      <slot />
    </div>
    <div class="rh-footer">
      <slot name="footer" />
    </div>
  </div>
</template>

<style scoped>
.rh-statement {
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

.rh-statement-content {
  flex: 1;
  display: flex;
  flex-direction: column;
  justify-content: center;
  align-items: center;
  text-align: center;
  padding: var(--slidev-rh-space-2xl) var(--slidev-rh-space-3xl);
}

.rh-statement-content :deep(h1),
.rh-statement-content :deep(h2) {
  font-family: var(--slidev-rh-font-heading);
  font-size: 1.75rem;
  font-weight: 500;
  line-height: 1.3;
  max-width: 80%;
}

.rh-statement-content :deep(p) {
  font-size: 0.95rem;
  color: var(--slidev-rh-text-secondary);
  margin-top: var(--slidev-rh-space-xl);
  max-width: 70%;
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
