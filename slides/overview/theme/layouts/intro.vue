<template>
  <div class="slidev-layout rh-intro">
    <div class="rh-accent-bar" />
    <div class="rh-intro-content">
      <div v-if="$frontmatter.image" class="rh-intro-photo">
        <img :src="$frontmatter.image" :alt="$frontmatter.imageAlt || 'Speaker photo'" />
      </div>
      <div class="rh-intro-text">
        <slot />
      </div>
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
.rh-intro {
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

.rh-intro-content {
  flex: 1;
  display: flex;
  align-items: center;
  gap: var(--slidev-rh-space-2xl);
  padding: var(--slidev-rh-space-2xl);
}

.rh-intro-photo {
  flex-shrink: 0;
}

.rh-intro-photo img {
  width: 200px;
  height: 200px;
  border-radius: 50%;
  object-fit: cover;
  border: 4px solid var(--slidev-rh-brand-red);
}

.rh-intro-text {
  flex: 1;
}

.rh-intro-text :deep(h1) {
  font-size: 1.75rem;
  margin-bottom: var(--slidev-rh-space-md);
}

.rh-intro-text :deep(h2) {
  font-size: 1.15rem;
  font-weight: 400;
  color: var(--slidev-rh-text-secondary);
  margin-bottom: var(--slidev-rh-space-xl);
}

.rh-intro-text :deep(p) {
  color: var(--slidev-rh-text-secondary);
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
