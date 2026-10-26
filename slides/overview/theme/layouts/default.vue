<template>
  <div class="slidev-layout rh-default">
    <div class="rh-accent-bar" />
    <div class="rh-content">
      <slot />
    </div>
    <div class="rh-footer">
      <slot name="footer" />
    </div>
  </div>
</template>

<style scoped>
.rh-default {
  display: flex;
  flex-direction: column;
  padding: 0;
  height: 100%;
  overflow: hidden;
}

.rh-accent-bar {
  height: 4px;
  background: var(--slidev-rh-brand-red);
  flex-shrink: 0;
}

.rh-content {
  flex: 1;
  padding: var(--slidev-rh-space-2xl);
  overflow: auto;
}

.rh-footer {
  flex-shrink: 0;
  padding: 0 var(--slidev-rh-space-2xl) var(--slidev-rh-space-lg);
}

.rh-footer:empty {
  display: none;
}
</style>
