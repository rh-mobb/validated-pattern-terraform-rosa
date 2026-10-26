<template>
  <div class="slidev-layout rh-two-cols">
    <div class="rh-accent-bar" />
    <div class="rh-cols-container">
      <div class="rh-col rh-col-left">
        <slot />
      </div>
      <div class="rh-col-divider" />
      <div class="rh-col rh-col-right">
        <slot name="right" />
      </div>
    </div>
    <div class="rh-footer">
      <slot name="footer" />
    </div>
  </div>
</template>

<style scoped>
.rh-two-cols {
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

.rh-cols-container {
  flex: 1;
  display: flex;
  gap: 0;
  padding: var(--slidev-rh-space-2xl);
  overflow: auto;
}

.rh-col {
  flex: 1;
  min-width: 0;
}

.rh-col-left {
  padding-right: var(--slidev-rh-space-xl);
}

.rh-col-right {
  padding-left: var(--slidev-rh-space-xl);
}

.rh-col-divider {
  width: 1px;
  background: var(--slidev-rh-border-subtle);
  flex-shrink: 0;
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
