<template>
  <div class="slidev-layout rh-image" :style="{ backgroundImage: `url(${$frontmatter.image})`, backgroundSize: $frontmatter.backgroundSize || 'cover', backgroundPosition: $frontmatter.backgroundPosition || 'center' }">
    <div class="rh-image-overlay" />
    <div class="rh-image-content">
      <slot />
    </div>
    <div class="rh-footer">
      <slot name="footer" />
    </div>
  </div>
</template>

<script setup lang="ts">
import { useSlideContext } from '@slidev/client'
const { $frontmatter } = useSlideContext()
</script>

<style scoped>
.rh-image {
  display: flex;
  flex-direction: column;
  justify-content: flex-end;
  position: relative;
  height: 100%;
  overflow: hidden;
}

.rh-image-overlay {
  position: absolute;
  inset: 0;
  background: linear-gradient(to top, rgba(0, 0, 0, 0.7) 0%, rgba(0, 0, 0, 0.2) 50%, transparent 100%);
  pointer-events: none;
}

.rh-image-content {
  position: relative;
  z-index: 1;
  padding: var(--slidev-rh-space-2xl);
  color: #FFFFFF;
}

.rh-image-content :deep(h1),
.rh-image-content :deep(h2),
.rh-image-content :deep(h3),
.rh-image-content :deep(p) {
  color: #FFFFFF;
}

.rh-footer {
  position: absolute;
  bottom: var(--slidev-rh-space-md);
  left: var(--slidev-rh-space-2xl);
  right: var(--slidev-rh-space-2xl);
  font-size: 0.75rem;
  color: #FFFFFF;
}

.rh-footer:empty {
  display: none;
}
</style>
