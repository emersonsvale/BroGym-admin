<script setup>
import { computed } from 'vue'
import { nomePais, bandeira } from '../lib/util'
const props = defineProps({ codigo: String, curto: Boolean })
const img = computed(() => bandeira(props.codigo))
</script>

<template>
  <span class="pais">
    <img v-if="img" :src="img" alt="" loading="lazy" />
    <span v-else class="sem">?</span>
    <span>{{ curto ? (codigo || '—') : nomePais(codigo) }}</span>
  </span>
</template>

<style scoped>
.pais { display: inline-flex; align-items: center; gap: 6px; white-space: nowrap; }
img { width: 18px; height: 13px; object-fit: cover; border-radius: 2px; box-shadow: 0 0 0 1px var(--line); flex: none; }
.sem { width: 18px; height: 13px; border-radius: 2px; background: var(--surface2); font-size: 9px; display: inline-grid; place-items: center; color: var(--muted); flex: none; }
</style>
