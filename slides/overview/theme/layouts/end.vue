<template>
  <div class="slidev-layout rh-end">
    <div class="rh-end-content">
      <slot />
    </div>
    <div class="rh-footer">
      <slot name="footer" />
    </div>
    <div class="rh-end-bar" />
  </div>
</template>

<style scoped>
.rh-end {
  display: flex;
  flex-direction: column;
  justify-content: center;
  align-items: center;
  text-align: center;
  padding: var(--slidev-rh-space-2xl);
  position: relative;
  height: 100%;
  overflow: hidden;
}

.rh-end-content {
  flex: 1;
  display: flex;
  flex-direction: column;
  justify-content: center;
  align-items: center;
}

.rh-end-content :deep(h1) {
  font-size: 2rem;
  font-weight: 700;
  margin-bottom: var(--slidev-rh-space-xl);
}

.rh-end-content :deep(p) {
  color: var(--slidev-rh-text-secondary);
  font-size: 0.95rem;
  margin-bottom: var(--slidev-rh-space-md);
}

.rh-end-content :deep(a) {
  color: var(--slidev-rh-link);
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

.rh-end-bar {
  position: absolute;
  bottom: 0;
  left: 0;
  right: 0;
  height: 6px;
  background: var(--slidev-rh-brand-red);
}
</style>
