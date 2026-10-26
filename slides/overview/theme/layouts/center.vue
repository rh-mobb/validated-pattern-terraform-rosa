<template>
  <div class="slidev-layout rh-center">
    <div class="rh-accent-bar" />
    <div class="rh-center-content">
      <slot />
    </div>
    <div class="rh-footer">
      <slot name="footer" />
    </div>
  </div>
</template>

<style scoped>
.rh-center {
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

.rh-center-content {
  flex: 1;
  display: flex;
  flex-direction: column;
  justify-content: center;
  align-items: center;
  padding: var(--slidev-rh-space-2xl);
}

.rh-center-content :deep(h1),
.rh-center-content :deep(h2),
.rh-center-content :deep(h3) {
  text-align: center;
}

.rh-center-content :deep(p),
.rh-center-content :deep(.v-clicks) {
  text-align: left;
  width: 100%;
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
