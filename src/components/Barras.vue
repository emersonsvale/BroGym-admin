<script setup>
// Gráfico de barras simples por dia. Uma série em destaque (vermelho); dica ao passar o mouse.
import { computed, ref } from 'vue'
const props = defineProps({
  dados: { type: Array, default: () => [] }, // [{ rotulo, valor }]
  altura: { type: Number, default: 160 },
  formato: { type: Function, default: (v) => Number(v).toLocaleString('pt-BR') },
})
const foco = ref(-1)
const max = computed(() => Math.max(1, ...props.dados.map((d) => Number(d.valor) || 0)))
const larg = 100 / Math.max(1, props.dados.length)
const marcas = computed(() => {
  const n = props.dados.length
  if (n <= 8) return props.dados.map((_, i) => i)
  const passo = Math.ceil(n / 6)
  return props.dados.map((_, i) => i).filter((i) => i % passo === 0 || i === n - 1)
})
</script>
<template>
  <div class="barras" :style="{ height: altura + 'px' }" @mouseleave="foco = -1">
    <div class="area">
      <div v-for="(d, i) in dados" :key="i" class="col" :style="{ width: larg + '%' }" @mouseenter="foco = i">
        <div class="barra" :class="{ ativa: foco === i, zero: !d.valor }" :style="{ height: Math.max(2, (Number(d.valor) || 0) / max * 100) + '%' }" />
      </div>
      <div v-if="foco >= 0" class="dica" :style="{ left: `calc(${(foco + 0.5) * larg}% )` }">
        <strong>{{ formato(dados[foco].valor) }}</strong><small>{{ dados[foco].rotulo }}</small>
      </div>
    </div>
    <div class="eixo">
      <span v-for="i in marcas" :key="i" :style="{ left: `${(i + 0.5) * larg}%` }">{{ dados[i]?.curto ?? dados[i]?.rotulo }}</span>
    </div>
  </div>
</template>
<style scoped>
.barras { display: flex; flex-direction: column; }
.area { position: relative; flex: 1; display: flex; align-items: flex-end; border-bottom: 1px solid var(--line); }
.col { height: 100%; display: flex; align-items: flex-end; justify-content: center; padding: 0 1.5px; }
.barra { width: 100%; max-width: 26px; background: var(--accent); border-radius: 4px 4px 0 0; opacity: .85; transition: opacity .12s; }
.barra.zero { background: var(--line); }
.barra.ativa { opacity: 1; }
.dica { position: absolute; top: -6px; transform: translate(-50%, -100%); background: var(--surface2); border: 1px solid var(--line); border-radius: 8px; padding: 5px 9px; display: flex; flex-direction: column; align-items: center; pointer-events: none; white-space: nowrap; box-shadow: var(--sombra); z-index: 2; }
.eixo { position: relative; height: 20px; }
.eixo span { position: absolute; transform: translateX(-50%); font-size: 11px; color: var(--muted); top: 4px; white-space: nowrap; }
</style>
