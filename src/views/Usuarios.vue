<script setup>
import { ref, onMounted, watch } from 'vue'
import { useRouter, useRoute } from 'vue-router'
import { rpc } from '../lib/supabase'
import { num, desde, data, dataHora, erro, nomesOrigem, nomePais } from '../lib/util'
import Avatar from '../components/Avatar.vue'
import Icone from '../components/Icone.vue'
import Pais from '../components/Pais.vue'

const router = useRouter()
const route = useRoute()
const pais = ref(route.query.pais || '')
const paises = ref([])
const busca = ref('')
const filtro = ref('todos')
const lista = ref([])
const total = ref(0)
const pagina = ref(0)
const POR = 50
const carregando = ref(false)
const ordem = ref('criado_desc')

const filtros = { todos: 'Todos', novos: 'Novos (7d)', pro: 'PRO', pagos: 'Pagantes', anonimos: 'Sem cadastro', inativos: 'Sumidos (14d)', sem_onboarding: 'Sem onboarding', banidos: 'Banidos' }

async function carregar() {
  carregando.value = true
  try {
    lista.value = await rpc('adm_usuarios', { p_busca: busca.value || null, p_filtro: filtro.value, p_limite: POR, p_offset: pagina.value * POR, p_ordem: ordem.value, p_pais: pais.value || null })
    total.value = lista.value[0]?.total ?? 0
  } catch (e) { erro(e) } finally { carregando.value = false }
}
let t
watch(busca, () => { clearTimeout(t); t = setTimeout(() => { pagina.value = 0; carregar() }, 300) })
watch(filtro, () => { pagina.value = 0; carregar() })
watch(pais, (v) => { router.replace({ query: v ? { pais: v } : {} }); pagina.value = 0; carregar() })
// Lista de países pro filtro (precisa ver Números; sem isso o filtro some).
async function carregarPaises() {
  try { paises.value = (await rpc('adm_distribuicao'))?.pais || [] } catch { paises.value = [] }
}
// Clicar no título da coluna ordena; clicar de novo inverte.
function ordenar(campo, primeiro = 'desc') {
  const [atual, dir] = ordem.value.split('_')
  ordem.value = atual === campo ? `${campo}_${dir === 'desc' ? 'asc' : 'desc'}` : `${campo}_${primeiro}`
  pagina.value = 0
  carregar()
}
const seta = (campo) => (ordem.value.startsWith(campo + '_') ? (ordem.value.endsWith('desc') ? ' ↓' : ' ↑') : '')
onMounted(() => { carregar(); carregarPaises() })
</script>

<template>
  <div>
    <div class="cabecalho">
      <div><h1>Usuários</h1><p>{{ num(total) }} {{ filtro === 'todos' && !busca ? 'contas no total' : 'encontrados' }}</p></div>
    </div>

    <div class="linha" style="margin-bottom: 14px">
      <div class="busca espaco">
        <Icone nome="busca" :tam="16" />
        <input v-model="busca" placeholder="Nome, e-mail, @usuário, cidade ou ID" />
      </div>
      <select v-if="paises.length" v-model="pais" style="width: auto; min-width: 190px">
        <option value="">Todos os países</option>
        <option v-for="x in paises" :key="x.pais" :value="x.pais">{{ nomePais(x.pais) }} ({{ x.n }})</option>
      </select>
    </div>
    <div class="linha" style="margin-bottom: 14px; gap: 6px">
      <button v-for="(n, k) in filtros" :key="k" class="btn pequeno" :class="filtro === k ? 'primario' : ''" @click="filtro = k">{{ n }}</button>
    </div>

    <div class="tabela-wrap">
      <table>
        <thead><tr>
          <th class="ordena" @click="ordenar('nome', 'asc')">Pessoa{{ seta('nome') }}</th><th>Plano</th><th>Origem</th>
          <th class="ordena" @click="ordenar('local', 'asc')" title="País do celular quando o app manda; senão, pelo IP do último login. Cidade sempre pelo IP (aproximada).">Local{{ seta('local') }}</th>
          <th class="num ordena" @click="ordenar('treinos')">Treinos{{ seta('treinos') }}</th>
          <th class="ordena" @click="ordenar('criado')">Criou{{ seta('criado') }}</th>
          <th class="ordena" @click="ordenar('onboarding')" title="Quando terminou o onboarding. ~ = data aproximada (contas antigas)">Onboarding{{ seta('onboarding') }}</th>
          <th class="ordena" @click="ordenar('acesso')">Último acesso{{ seta('acesso') }}</th>
        </tr></thead>
        <tbody>
          <tr v-for="u in lista" :key="u.id" class="clicavel" @click="router.push(`/usuarios/${u.id}`)">
            <td>
              <div class="linha" style="flex-wrap: nowrap">
                <Avatar :src="u.avatar" :nome="u.nome" />
                <div style="min-width: 0">
                  <div class="corta" style="font-weight: 600">{{ u.nome || 'Sem nome' }} <span v-if="u.banido_ate && new Date(u.banido_ate) > new Date()" class="tag vermelho">banido</span></div>
                  <small class="corta" style="display: block">{{ u.username ? '@' + u.username : '' }} {{ u.email || 'sem cadastro' }}</small>
                </div>
              </div>
            </td>
            <td>
              <span v-if="u.pro === 'pago'" class="tag ouro">PRO pago</span>
              <span v-else-if="u.pro === 'cortesia'" class="tag ciano">PRO cortesia</span>
              <span v-else class="tag">Grátis</span>
            </td>
            <td><small>{{ nomesOrigem(u.origem || 'orgânico') }}</small></td>
            <td :title="[u.cidade, u.estado, nomePais(u.pais)].filter(Boolean).join(', ') + (u.pais_fonte === 'aparelho' ? ' · país pelo celular' : u.pais_fonte === 'ip' ? ' · pelo IP' : '') + (u.rede ? ' · rede: ' + u.rede : '')">
              <template v-if="u.pais"><Pais :codigo="u.pais" curto /><small v-if="u.cidade" class="corta" style="display: block; max-width: 150px">{{ u.cidade }}</small></template>
              <small v-else class="muted">—</small>
            </td>
            <td class="num">{{ num(u.treinos) }}</td>
            <td><small>{{ data(u.criado_em) }}</small></td>
            <td><small :title="u.onboarding_em ? dataHora(u.onboarding_em) + (u.onboarding_aprox ? ' (aproximada: 1º treino gerado pela IA)' : '') : ''">{{ u.onboarding_em ? (u.onboarding_aprox ? '~' : '') + data(u.onboarding_em) : (u.onboarding_feito ? 'Sim (sem data)' : '—') }}</small></td>
            <td><small :title="dataHora(u.ultimo_acesso)">{{ desde(u.ultimo_acesso) }}</small></td>
          </tr>
          <tr v-if="!lista.length && !carregando"><td colspan="8" class="vazio">Ninguém encontrado.</td></tr>
        </tbody>
      </table>
      <div v-if="carregando" class="carregando"><div class="spinner" /></div>
    </div>

    <div v-if="total > POR" class="linha" style="justify-content: flex-end; margin-top: 12px">
      <small>{{ pagina * POR + 1 }}–{{ Math.min((pagina + 1) * POR, total) }} de {{ num(total) }}</small>
      <button class="btn pequeno" :disabled="pagina === 0" @click="pagina--; carregar()"><Icone nome="voltar" :tam="14" /></button>
      <button class="btn pequeno" :disabled="(pagina + 1) * POR >= total" @click="pagina++; carregar()"><Icone nome="seta" :tam="14" /></button>
    </div>
  </div>
</template>

<style scoped>
.busca { display: flex; align-items: center; gap: 8px; background: var(--surface2); border: 1px solid var(--line); border-radius: 12px; padding: 0 12px; color: var(--muted); }
th.ordena { cursor: pointer; user-select: none; }
th.ordena:hover { color: var(--text); }
.busca input { border: 0; background: transparent; box-shadow: none; padding: 11px 0; }
</style>
