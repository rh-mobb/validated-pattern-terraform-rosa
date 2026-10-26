<template>
  <div class="slidev-layout rh-cover" :style="backgroundStyle">
    <div class="rh-cover-overlay" />
    <div class="rh-cover-content">
      <slot />
    </div>
    <div class="rh-cover-footer">
      <slot name="footer" />
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed } from 'vue'
import { useSlideContext } from '@slidev/client'

const { $frontmatter } = useSlideContext()

const backgroundStyle = computed(() => {
  const image = $frontmatter.image
  if (!image) return {}
  return {
    backgroundImage: `url(${image})`,
    backgroundSize: 'cover',
    backgroundPosition: 'center',
  }
})
</script>

<style scoped>
.rh-cover {
  display: flex;
  flex-direction: column;
  justify-content: center;
  align-items: center;
  text-align: center;
  padding: var(--slidev-rh-space-2xl);
  position: relative;
  background: var(--slidev-rh-bg);
  height: 100%;
  overflow: hidden;
}

.rh-cover-overlay {
  position: absolute;
  inset: 0;
  background: linear-gradient(135deg, var(--slidev-rh-brand-red) 0%, var(--slidev-rh-brand-red-dark) 100%);
  opacity: 0.05;
  pointer-events: none;
}

.rh-cover-content {
  position: relative;
  z-index: 1;
  max-width: 80%;
}

.rh-cover-content :deep(h1) {
  font-size: 2.25rem;
  font-weight: 700;
  margin-bottom: var(--slidev-rh-space-xl);
}

.rh-cover-content :deep(p) {
  font-size: 1rem;
  color: var(--slidev-rh-text-secondary);
}

.rh-cover-footer {
  position: absolute;
  bottom: var(--slidev-rh-space-xl);
  left: var(--slidev-rh-space-2xl);
  right: var(--slidev-rh-space-2xl);
  text-align: center;
  z-index: 1;
}

.rh-cover-footer:empty {
  display: none;
}

.rh-cover::before {
  content: '';
  position: absolute;
  bottom: 0;
  left: 0;
  right: 0;
  height: 6px;
  background: var(--slidev-rh-brand-red);
}
</style>
