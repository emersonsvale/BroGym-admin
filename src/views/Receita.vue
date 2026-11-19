<script setup>
import { ref, computed, onMounted } from 'vue'
import { rpc } from '../lib/supabase'
import { num, data, dinheiro, erro } from '../lib/util'
import Kpi from '../components/Kpi.vue'
import Barras from '../components/Barras.vue'

const r = ref(null)
onMounted(async () => { try { r.value = await rpc('adm_receita') } catch (e) { erro(e) } })

const mrr = computed(() => Object.entries(r.value?.mrr || {}).map(([m, c]) => dinheiro(c, m)).join(' + ') || dinheiro(0))
const meses = computed(() => (r.value?.por_mes || []).map((m) => ({ rotulo: m.mes, curto: m.mes.slice(5) + '/' + m.mes.slice(2, 4), valor: m.novas })))
const plano = (p) => (/anual|year|annual/i.test(p || '') ? 'Anual' : /month|mensal|pm1/i.test(p || '') ? 'Mensal' : p || '—')
const ativo = (a) => a.ativo && (!a.expira || new Date(a.expira) > new Date())
</script>

<template>
  <div>
    <div class="cabecalho">
      <div><h1>Assinaturas e receita</h1><p>Do que o app sincroniza do RevenueCat. Valores brutos (antes da taxa da Google).</p></div>
      <a class="btn" href="https://app.revenuecat.com/" target="_blank" rel="noopener">Abrir RevenueCat</a>
    </div>
    <div v-if="!r" class="carregando"><div class="spinner" /></div>
    <template v-else>
      <div class="grade g4">
        <Kpi rotulo="Assinantes ativos" :valor="num(r.ativos)" :detalhe="`${num(r.renovam)} renovam · ${num(r.cancelaram)} cancelaram a renovação`" destaque />
        <Kpi rotulo="Receita mensal (estimada)" :valor="mrr" detalhe="Anual dividido por 12" />
        <Kpi rotulo="Venceram (30 dias)" :valor="num(r.expirados_30d)" detalhe="Não renovaram" />
        <Kpi rotulo="PRO de cortesia" :valor="num(r.cortesias)" detalhe="Convites e liberações do admin" />
      </div>
      <div class="grade g2" style="margin-top: 14px">
        <div class="card"><h3 style="margin-bottom: 14px">Assinaturas novas por mês</h3><Barras v-if="meses.length" :dados="meses" :altura="170" /><p v-else class="vazio">Sem vendas ainda.</p></div>
        <div class="card">
          <h3 style="margin-bottom: 10px">Por plano (ativos)</h3>
          <div v-for="p in r.por_plano" :key="p.plano + p.moeda" class="linha entre" style="padding: 8px 0; border-bottom: 1px solid var(--line)">
            <span>{{ plano(p.plano) }} <small>{{ p.plano }}</small></span><strong>{{ num(p.qtd) }} · {{ dinheiro(p.total_cents, p.moeda) }}</strong>
          </div>
          <p v-if="!r.por_plano.length" class="vazio">Nenhum assinante ativo.</p>
        </div>
      </div>
      <h2 style="margin: 28px 0 12px">Assinantes</h2>
      <div class="tabela-wrap">
        <table>
          <thead><tr><th>Pessoa</th><th>Plano</th><th>Valor</th><th>Comprou</th><th>Vence</th><th>Situação</th></tr></thead>
          <tbody>
            <tr v-for="a in r.assinantes" :key="a.user_id + a.compra">
              <td><RouterLink :to="`/usuarios/${a.user_id}`" style="color: var(--text); font-weight: 600">{{ a.nome || a.email }}</RouterLink><br /><small>{{ a.email }}</small></td>
              <td>{{ plano(a.plano) }}</td>
              <td>{{ dinheiro(a.price_cents, a.moeda) }}</td>
              <td><small>{{ data(a.compra) }}</small></td>
              <td><small>{{ data(a.expira) }}</small></td>
              <td><span class="tag" :class="ativo(a) ? (a.renova === false ? 'ambar' : 'verde') : ''">{{ ativo(a) ? (a.renova === false ? 'Não vai renovar' : 'Ativa') : 'Encerrada' }}</span></td>
            </tr>
            <tr v-if="!r.assinantes.length"><td colspan="6" class="vazio">Ninguém assinou ainda.</td></tr>
          </tbody>
        </table>
      </div>
    </template>
  </div>
</template>
