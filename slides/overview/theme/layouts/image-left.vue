<template>
  <div class="slidev-layout rh-image-left">
    <div class="rh-image-side" :style="imageStyle" />
    <div class="rh-content-side">
      <div class="rh-accent-bar" />
      <div class="rh-content-inner">
        <slot />
      </div>
      <div class="rh-footer">
        <slot name="footer" />
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed } from 'vue'
import { useSlideContext } from '@slidev/client'
const { $frontmatter } = useSlideContext()
const imageStyle = computed(() => ({
  backgroundImage: `url(${$frontmatter.image})`,
  backgroundSize: $frontmatter.backgroundSize || 'cover',
  backgroundPosition: $frontmatter.backgroundPosition || 'center',
}))
</script>

<style scoped>
.rh-image-left {
  display: flex;
  padding: 0;
  height: 100%;
  overflow: hidden;
}

.rh-image-side {
  width: 50%;
  flex-shrink: 0;
}

.rh-content-side {
  width: 50%;
  display: flex;
  flex-direction: column;
  position: relative;
}

.rh-accent-bar {
  height: 4px;
  background: var(--slidev-rh-brand-red);
  flex-shrink: 0;
}

.rh-content-inner {
  flex: 1;
  padding: var(--slidev-rh-space-2xl);
  overflow: auto;
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
