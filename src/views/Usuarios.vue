<script setup>
import { ref, onMounted, watch } from 'vue'
import { useRouter } from 'vue-router'
import { rpc } from '../lib/supabase'
import { num, desde, data, dataHora, erro, nomesOrigem } from '../lib/util'
import Avatar from '../components/Avatar.vue'
import Icone from '../components/Icone.vue'

const router = useRouter()
const busca = ref('')
const filtro = ref('todos')
const lista = ref([])
const total = ref(0)
const pagina = ref(0)
const POR = 50
const carregando = ref(false)
const ordem = ref('criado_desc')

const filtros = { todos: 'Todos', novos: 'Novos (7d)', pro: 'PRO', pagos: 'Pagantes', anonimos: 'Sem cadastro', inativos: 'Sumidos (14d)', banidos: 'Banidos' }

async function carregar() {
  carregando.value = true
  try {
    lista.value = await rpc('adm_usuarios', { p_busca: busca.value || null, p_filtro: filtro.value, p_limite: POR, p_offset: pagina.value * POR, p_ordem: ordem.value })
    total.value = lista.value[0]?.total ?? 0
  } catch (e) { erro(e) } finally { carregando.value = false }
}
let t
watch(busca, () => { clearTimeout(t); t = setTimeout(() => { pagina.value = 0; carregar() }, 300) })
watch(filtro, () => { pagina.value = 0; carregar() })
// Clicar no título da coluna ordena; clicar de novo inverte.
function ordenar(campo, primeiro = 'desc') {
  const [atual, dir] = ordem.value.split('_')
  ordem.value = atual === campo ? `${campo}_${dir === 'desc' ? 'asc' : 'desc'}` : `${campo}_${primeiro}`
  pagina.value = 0
  carregar()
}
const seta = (campo) => (ordem.value.startsWith(campo + '_') ? (ordem.value.endsWith('desc') ? ' ↓' : ' ↑') : '')
onMounted(carregar)
</script>

<template>
  <div>
    <div class="cabecalho">
      <div><h1>Usuários</h1><p>{{ num(total) }} {{ filtro === 'todos' && !busca ? 'contas no total' : 'encontrados' }}</p></div>
    </div>

    <div class="linha" style="margin-bottom: 14px">
      <div class="busca espaco">
        <Icone nome="busca" :tam="16" />
        <input v-model="busca" placeholder="Nome, e-mail, @usuário ou ID" />
      </div>
    </div>
    <div class="linha" style="margin-bottom: 14px; gap: 6px">
      <button v-for="(n, k) in filtros" :key="k" class="btn pequeno" :class="filtro === k ? 'primario' : ''" @click="filtro = k">{{ n }}</button>
    </div>

    <div class="tabela-wrap">
      <table>
        <thead><tr>
          <th class="ordena" @click="ordenar('nome', 'asc')">Pessoa{{ seta('nome') }}</th><th>Plano</th><th>Origem</th>
          <th class="num ordena" @click="ordenar('treinos')">Treinos{{ seta('treinos') }}</th>
          <th class="ordena" @click="ordenar('criado')">Criou{{ seta('criado') }}</th>
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
            <td class="num">{{ num(u.treinos) }}</td>
            <td><small>{{ data(u.criado_em) }}</small></td>
            <td><small :title="dataHora(u.ultimo_acesso)">{{ desde(u.ultimo_acesso) }}</small></td>
          </tr>
          <tr v-if="!lista.length && !carregando"><td colspan="6" class="vazio">Ninguém encontrado.</td></tr>
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
