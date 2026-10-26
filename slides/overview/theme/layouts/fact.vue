<template>
  <div class="slidev-layout rh-fact">
    <div class="rh-accent-bar" />
    <div class="rh-fact-content">
      <slot />
    </div>
    <div class="rh-footer">
      <slot name="footer" />
    </div>
  </div>
</template>

<style scoped>
.rh-fact {
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

.rh-fact-content {
  flex: 1;
  display: flex;
  flex-direction: column;
  justify-content: center;
  align-items: center;
  text-align: center;
  padding: var(--slidev-rh-space-2xl);
}

.rh-fact-content :deep(h1) {
  font-size: 3.5rem;
  font-weight: 700;
  color: var(--slidev-rh-brand-red);
  margin-bottom: var(--slidev-rh-space-xl);
  line-height: 1.1;
}

.rh-fact-content :deep(p) {
  font-size: 1rem;
  color: var(--slidev-rh-text-secondary);
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
