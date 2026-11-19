<script setup>
import { ref, computed, onMounted } from 'vue'
import { rpc } from '../lib/supabase'
import { num, usd, data, erro } from '../lib/util'
import Kpi from '../components/Kpi.vue'
import Barras from '../components/Barras.vue'

const r = ref(null)
const dias = ref(30)
async function carregar() { try { r.value = await rpc('adm_ia', { p_dias: dias.value }) } catch (e) { erro(e) } }
onMounted(carregar)

const nomes = { coach_chat: 'Coach (conversa)', coach_gerar_treinos: 'Gerar treinos (onboarding/Coach)', refazer_treino: 'Refazer treino', dieta_foto: 'Dieta por foto', relatorio_semanal: 'Relatório semanal' }
const nomesContador = { coach_msg: 'Mensagens no Coach', ai_workout: 'Treinos gerados', diet_ai: 'Fotos de refeição' }
const porDia = computed(() => {
  const mapa = Object.fromEntries((r.value?.por_dia || []).map((d) => [d.dia, d]))
  const out = []
  for (let i = dias.value - 1; i >= 0; i--) {
    const d = new Date(Date.now() - i * 864e5).toLocaleDateString('sv-SE', { timeZone: 'America/Sao_Paulo' })
    out.push({ rotulo: new Date(d + 'T12:00').toLocaleDateString('pt-BR'), curto: d.slice(8) + '/' + d.slice(5, 7), valor: Number(mapa[d]?.custo || 0) })
  }
  return out
})
const projecao = computed(() => {
  if (!r.value) return 0
  const hoje = new Date(); const diasMes = new Date(hoje.getFullYear(), hoje.getMonth() + 1, 0).getDate()
  return (Number(r.value.custo_mes) / hoje.getDate()) * diasMes
})
</script>

<template>
  <div>
    <div class="cabecalho">
      <div><h1>Custo da IA</h1><p>Cada chamada pra OpenAI fica registrada com os tokens usados. Preços de tabela da OpenAI.</p></div>
      <div class="linha">
        <select v-model.number="dias" style="width: auto" @change="carregar"><option :value="7">7 dias</option><option :value="30">30 dias</option><option :value="90">90 dias</option></select>
        <a class="btn" href="https://platform.openai.com/usage" target="_blank" rel="noopener">Painel da OpenAI</a>
      </div>
    </div>
    <div v-if="!r" class="carregando"><div class="spinner" /></div>
    <template v-else>
      <div v-if="!r.desde_registro" class="card" style="margin-bottom: 14px; border-color: var(--amber)">
        O registro de custo começou agora. Os números aparecem conforme as pessoas usam a IA. Enquanto isso, abaixo tem a contagem de uso que já existia.
      </div>
      <div class="grade g4">
        <Kpi rotulo="Hoje" :valor="usd(r.custo_hoje)" destaque />
        <Kpi rotulo="Este mês" :valor="usd(r.custo_mes)" :detalhe="`Projeção do mês: ${usd(projecao)}`" />
        <Kpi :rotulo="`Últimos ${dias} dias`" :valor="usd(r.custo_total)" :detalhe="`${num(r.chamadas)} chamadas`" />
        <Kpi rotulo="Mensagens no Coach" :valor="num(r.mensagens_coach)" :detalhe="`nos últimos ${dias} dias`" />
      </div>
      <div class="card" style="margin-top: 14px"><h3 style="margin-bottom: 14px">Gasto por dia</h3><Barras :dados="porDia" :altura="170" :formato="usd" /></div>
      <div class="grade g2" style="margin-top: 14px">
        <div class="card">
          <h3 style="margin-bottom: 10px">Por função</h3>
          <div v-for="f in r.por_funcao" :key="f.funcao + f.modelo" class="linha entre" style="padding: 8px 0; border-bottom: 1px solid var(--line)">
            <span>{{ nomes[f.funcao] || f.funcao }} <small>{{ f.modelo }} · {{ num(f.chamadas) }}×</small></span><strong>{{ usd(f.custo) }}</strong>
          </div>
          <p v-if="!r.por_funcao.length" class="vazio">Sem chamadas no período.</p>
          <h3 style="margin: 18px 0 10px">Uso contado pelos limites</h3>
          <div v-for="c in r.contadores" :key="c.feature" class="linha entre" style="padding: 6px 0"><span>{{ nomesContador[c.feature] || c.feature }}</span><strong>{{ num(c.usos) }}</strong></div>
        </div>
        <div class="card">
          <h3 style="margin-bottom: 10px">Quem mais gasta</h3>
          <div v-for="t in r.top_usuarios" :key="t.user_id" class="linha entre" style="padding: 8px 0; border-bottom: 1px solid var(--line)">
            <RouterLink :to="`/usuarios/${t.user_id}`" style="color: var(--text)">{{ t.nome || t.email || 'Usuário' }} <span v-if="t.pro" class="tag ouro">PRO</span></RouterLink>
            <span><small>{{ num(t.chamadas) }}× </small><strong>{{ usd(t.custo) }}</strong></span>
          </div>
          <p v-if="!r.top_usuarios.length" class="vazio">Sem dados ainda.</p>
          <small v-if="r.desde_registro">Registro desde {{ data(r.desde_registro) }}.</small>
        </div>
      </div>
    </template>
  </div>
</template>
