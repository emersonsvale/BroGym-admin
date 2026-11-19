<script setup>
import { ref, computed, onMounted } from 'vue'
import { rpc, pode } from '../lib/supabase'
import { num, pct, erro, nomesOrigem } from '../lib/util'
import Kpi from '../components/Kpi.vue'
import Barras from '../components/Barras.vue'
import Icone from '../components/Icone.vue'

const r = ref(null)
const serie = ref([])
const funil = ref([])
const dist = ref(null)
const dias = ref(30)
const metrica = ref('novos')
const carregando = ref(true)

async function carregar() {
  carregando.value = true
  try {
    const desde = new Date(Date.now() - dias.value * 864e5).toISOString().slice(0, 10)
    const [a, b, c, d] = await Promise.all([rpc('adm_resumo'), rpc('adm_serie', { p_dias: dias.value }), rpc('adm_funil', { p_desde: desde }), rpc('adm_distribuicao')])
    r.value = a; serie.value = b; funil.value = c; dist.value = d
  } catch (e) { erro(e) } finally { carregando.value = false }
}
onMounted(carregar)

const nomesMetrica = { novos: 'Contas novas', treinos: 'Treinos concluídos', treinaram: 'Pessoas que treinaram', posts: 'Posts na Comunidade' }
const dadosGrafico = computed(() => serie.value.map((s) => {
  const d = new Date(s.dia + 'T12:00:00')
  return { rotulo: d.toLocaleDateString('pt-BR', { weekday: 'short', day: '2-digit', month: '2-digit' }), curto: d.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' }), valor: s[metrica.value] }
}))
const totalPeriodo = computed(() => serie.value.reduce((a, s) => a + Number(s[metrica.value] || 0), 0))

const meta = computed(() => {
  if (!r.value) return null
  const alvo = r.value.meta_contas
  const fim = new Date(r.value.meta_data + 'T23:59:59-03:00')
  const faltamDias = Math.max(0, Math.ceil((fim - Date.now()) / 864e5))
  // A meta conta só contas salvas (com Google/e-mail). As anônimas aparecem à parte.
  const faltam = Math.max(0, alvo - r.value.salvos)
  return { alvo, faltamDias, faltam, porDia: faltamDias ? Math.ceil(faltam / faltamDias) : faltam, progresso: Math.min(100, (r.value.salvos / alvo) * 100) }
})

const funilTotal = computed(() => funil.value.reduce((t, f) => {
  for (const k of ['contas', 'onboarding', 'salvou_conta', 'primeiro_treino', 'dia_7', 'convidou']) t[k] = (t[k] || 0) + Number(f[k] || 0)
  return t
}, {}))

const traduz = { male: 'Homem', female: 'Mulher', other: 'Outro', pt: 'Português', en: 'Inglês', es: 'Espanhol', weight_loss: 'Emagrecer', muscle_gain: 'Ganhar massa', endurance: 'Resistência', sport_performance: 'Performance', general_fitness: 'Saúde geral', strength: 'Força', flexibility: 'Flexibilidade', '—': 'Não informado' }
const lista = (obj) => {
  const e = Object.entries(obj || {}).sort((a, b) => b[1] - a[1])
  const total = e.reduce((s, [, v]) => s + v, 0) || 1
  return e.map(([k, v]) => ({ nome: traduz[k] || k, v, p: (v / total) * 100 }))
}
</script>

<template>
  <div>
    <div class="cabecalho">
      <div>
        <h1>Início</h1>
        <p>Como o BroGym está indo agora.</p>
      </div>
      <div class="linha">
        <select v-model.number="dias" style="width: auto" @change="carregar">
          <option :value="7">7 dias</option><option :value="30">30 dias</option><option :value="90">90 dias</option>
        </select>
        <button class="btn" @click="carregar"><Icone nome="atualizar" :tam="16" /> Atualizar</button>
      </div>
    </div>

    <div v-if="carregando && !r" class="carregando"><div class="spinner" /></div>
    <template v-else-if="r">
      <div class="card meta surge" style="margin-bottom: 14px">
        <div class="linha entre">
          <div>
            <small style="font-weight: 600">Meta: {{ num(meta.alvo) }} contas salvas até 31/12</small>
            <div class="titulo" style="font-size: 34px; font-weight: 800">{{ num(r.salvos) }} <span class="muted" style="font-size: 18px; font-weight: 600">/ {{ num(meta.alvo) }}</span></div>
            <small>+ {{ num(r.anonimos) }} sem cadastro (ainda não salvaram a conta)</small>
          </div>
          <div style="text-align: right">
            <div class="titulo" style="font-size: 22px; font-weight: 800">{{ num(meta.porDia) }}/dia</div>
            <small>pra bater a meta · faltam {{ num(meta.faltam) }} em {{ meta.faltamDias }} dias</small>
          </div>
        </div>
        <div class="trilho"><div class="enchido" :style="{ width: meta.progresso + '%' }" /></div>
      </div>

      <div class="grade g4">
        <Kpi rotulo="Contas novas hoje" :valor="num(r.novos_hoje)" :detalhe="`${num(r.novos_7d)} em 7 dias · ${num(r.novos_30d)} em 30`" destaque />
        <Kpi rotulo="Ativos (7 dias)" :valor="num(r.ativos_7d)" :detalhe="`${num(r.ativos_hoje)} hoje · ${pct(r.ativos_7d, r.usuarios)} da base`" />
        <Kpi rotulo="Treinos (7 dias)" :valor="num(r.treinos_7d)" :detalhe="`${num(r.treinaram_7d)} pessoas treinaram · ${num(r.treinos_hoje)} hoje`" />
        <Kpi rotulo="PRO" :valor="num(r.pro_pagos + r.pro_cortesia)" :detalhe="`${num(r.pro_pagos)} pagos · ${num(r.pro_cortesia)} cortesia`" />
      </div>

      <div class="grade" style="grid-template-columns: 2fr 1fr; margin-top: 14px">
        <div class="card">
          <div class="linha entre" style="margin-bottom: 14px">
            <div>
              <h3>{{ nomesMetrica[metrica] }}</h3>
              <small>{{ num(totalPeriodo) }} nos últimos {{ dias }} dias</small>
            </div>
            <div class="linha" style="gap: 4px">
              <button v-for="(n, k) in nomesMetrica" :key="k" class="btn pequeno" :class="metrica === k ? 'primario' : 'fantasma'" @click="metrica = k">{{ n.split(' ')[0] }}</button>
            </div>
          </div>
          <Barras :dados="dadosGrafico" :altura="200" />
        </div>
        <div class="coluna">
          <div class="card">
            <h3>Base</h3>
            <div class="linha entre mini"><span>Contas salvas</span><strong>{{ num(r.salvos) }}</strong></div>
            <div class="linha entre mini"><span>Sem cadastro (anônimas)</span><strong>{{ num(r.anonimos) }}</strong></div>
            <div class="linha entre mini"><span>Posts (7 dias)</span><strong>{{ num(r.posts_7d) }}</strong></div>
            <div class="linha entre mini"><span>Stories no ar</span><strong>{{ num(r.stories_ativos) }}</strong></div>
          </div>
          <RouterLink v-if="pode('comunidade.moderar')" to="/comunidade" class="card atalho">
            <Icone nome="alerta" /><span class="espaco">Denúncias abertas</span><span class="tag" :class="r.denuncias_abertas ? 'vermelho' : ''">{{ r.denuncias_abertas }}</span>
          </RouterLink>
          <RouterLink v-if="pode('suporte.atender')" to="/suporte" class="card atalho">
            <Icone nome="suporte" /><span class="espaco">Chamados abertos</span><span class="tag" :class="r.chamados_abertos ? 'vermelho' : ''">{{ r.chamados_abertos }}</span>
          </RouterLink>
        </div>
      </div>

      <div class="card" style="margin-top: 14px">
        <h3>Funil por origem <small style="font-weight: 500">(contas criadas nos últimos {{ dias }} dias)</small></h3>
        <div class="tabela-wrap" style="margin-top: 12px; border: 0">
          <table>
            <thead><tr><th>Origem</th><th class="num">Contas</th><th class="num">Fez onboarding</th><th class="num">Salvou conta</th><th class="num">1º treino</th><th class="num">Voltou dia 7</th><th class="num">Convidou</th></tr></thead>
            <tbody>
              <tr v-for="f in funil" :key="f.origem">
                <td><strong>{{ nomesOrigem(f.origem) }}</strong></td>
                <td class="num">{{ num(f.contas) }}</td>
                <td class="num">{{ num(f.onboarding) }} <small>{{ pct(f.onboarding, f.contas) }}</small></td>
                <td class="num">{{ num(f.salvou_conta) }} <small>{{ pct(f.salvou_conta, f.contas) }}</small></td>
                <td class="num">{{ num(f.primeiro_treino) }} <small>{{ pct(f.primeiro_treino, f.contas) }}</small></td>
                <td class="num">{{ num(f.dia_7) }} <small>{{ pct(f.dia_7, f.contas) }}</small></td>
                <td class="num">{{ num(f.convidou) }}</td>
              </tr>
              <tr v-if="funil.length" class="total">
                <td>Total</td>
                <td class="num">{{ num(funilTotal.contas) }}</td>
                <td class="num">{{ num(funilTotal.onboarding) }} <small>{{ pct(funilTotal.onboarding, funilTotal.contas) }}</small></td>
                <td class="num">{{ num(funilTotal.salvou_conta) }} <small>{{ pct(funilTotal.salvou_conta, funilTotal.contas) }}</small></td>
                <td class="num">{{ num(funilTotal.primeiro_treino) }} <small>{{ pct(funilTotal.primeiro_treino, funilTotal.contas) }}</small></td>
                <td class="num">{{ num(funilTotal.dia_7) }} <small>{{ pct(funilTotal.dia_7, funilTotal.contas) }}</small></td>
                <td class="num">{{ num(funilTotal.convidou) }}</td>
              </tr>
              <tr v-if="!funil.length"><td colspan="7" class="vazio">Nenhuma conta nova no período.</td></tr>
            </tbody>
          </table>
        </div>
      </div>

      <div v-if="dist" class="grade g3" style="margin-top: 14px">
        <div v-for="(t, k) in { idioma: 'Idioma do app', sexo: 'Sexo', objetivo: 'Objetivo principal' }" :key="k" class="card">
          <h3 style="margin-bottom: 10px">{{ t }}</h3>
          <div v-for="i in lista(dist[k])" :key="i.nome" class="dist">
            <div class="linha entre"><span>{{ i.nome }}</span><small>{{ i.v }}</small></div>
            <div class="trilho fino"><div class="enchido" :style="{ width: i.p + '%' }" /></div>
          </div>
        </div>
      </div>
    </template>
  </div>
</template>

<style scoped>
.meta { background: linear-gradient(120deg, var(--accent-soft), var(--surface) 60%); }
.trilho { height: 10px; background: var(--surface2); border-radius: 99px; overflow: hidden; margin-top: 12px; }
.trilho.fino { height: 6px; margin-top: 4px; }
.enchido { height: 100%; background: var(--accent); border-radius: 99px; transition: width .6s cubic-bezier(.2,.8,.2,1); }
.mini { padding: 8px 0; border-bottom: 1px solid var(--line); }
.mini:last-child { border-bottom: 0; }
.atalho { display: flex; align-items: center; gap: 10px; color: var(--text); font-weight: 600; padding: 14px 16px; }
.atalho:hover { border-color: var(--muted); }
.dist { margin-bottom: 10px; }
tr.total td { font-weight: 700; background: var(--surface2); }
@media (max-width: 900px) { .grade[style*='2fr'] { grid-template-columns: 1fr !important; } }
</style>
