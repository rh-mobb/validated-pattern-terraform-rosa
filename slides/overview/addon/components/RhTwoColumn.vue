<template>
  <div :class="['cols-2', { divided }]">
    <div class="left"><slot name="left" /></div>
    <div class="right"><slot name="right" /></div>
  </div>
</template>

<script setup>
defineProps({ divided: { type: Boolean, default: false } })
</script>
