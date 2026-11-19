<script setup>
import { ref, computed, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { rpc, pode, sb } from '../lib/supabase'
import { num, data, dataHora, desde, usd, avisar, erro, confirmar, nomesOrigem } from '../lib/util'
import Avatar from '../components/Avatar.vue'
import Icone from '../components/Icone.vue'
import Modal from '../components/Modal.vue'

const route = useRoute()
const router = useRouter()
const u = ref(null)
const carregando = ref(true)
const modal = ref('') // pro | editar | pontos | banir
const f = ref({})
const ocupado = ref(false)

async function carregar() {
  carregando.value = true
  try {
    const [ficha, acesso] = await Promise.all([rpc('adm_usuario', { p_id: route.params.id }), rpc('adm_usuario_acesso', { p_id: route.params.id })])
    ficha.ultimo_acesso = acesso
    u.value = ficha
  } catch (e) { erro(e) } finally { carregando.value = false }
}
onMounted(carregar)

const p = computed(() => u.value?.perfil ?? {})
const banido = computed(() => p.value.banido_ate && new Date(p.value.banido_ate) > new Date())
const proPago = computed(() => u.value?.assinatura?.is_premium && (!u.value.assinatura.expiration_date || new Date(u.value.assinatura.expiration_date) > new Date()))
const cortesiaAte = computed(() => u.value?.cortesia?.ate && new Date(u.value.cortesia.ate) > new Date() ? u.value.cortesia.ate : null)

function abrir(qual) {
  modal.value = qual
  if (qual === 'pro') f.value = { dias: 30, motivo: '' }
  if (qual === 'editar') f.value = { nome: p.value.full_name, username: p.value.username, bio: p.value.bio }
  if (qual === 'pontos') f.value = { pontos: 50, motivo: '' }
  if (qual === 'banir') f.value = { dias: 7, sempre: false, motivo: '' }
}

async function acao(fn) {
  ocupado.value = true
  try { await fn(); modal.value = ''; await carregar() } catch (e) { erro(e) } finally { ocupado.value = false }
}

const darPro = () => acao(async () => {
  const ate = await rpc('adm_dar_pro', { p_user: p.value.id, p_dias: Number(f.value.dias), p_motivo: f.value.motivo || null })
  avisar(`PRO liberado até ${data(ate)}. A pessoa recebeu um push.`)
})
const tirarPro = async () => {
  if (!(await confirmar({ titulo: 'Tirar PRO de cortesia?', texto: 'A assinatura paga (se tiver) não muda.', botao: 'Tirar', perigo: true }))) return
  acao(async () => { await rpc('adm_dar_pro', { p_user: p.value.id, p_dias: 0, p_motivo: 'removido pelo admin' }); avisar('Cortesia removida.') })
}
const salvarEdicao = () => acao(async () => {
  await rpc('adm_editar_usuario', { p_user: p.value.id, p_nome: f.value.nome, p_username: f.value.username, p_bio: f.value.bio })
  avisar('Dados salvos.')
})
const salvarPontos = () => acao(async () => {
  await rpc('adm_ajustar_pontos', { p_user: p.value.id, p_pontos: Number(f.value.pontos), p_motivo: f.value.motivo })
  avisar('Pontos ajustados.')
})
const banir = () => acao(async () => {
  await rpc('adm_banir', { p_user: p.value.id, p_dias: f.value.sempre ? null : Number(f.value.dias), p_motivo: f.value.motivo })
  avisar('Conta banida. A pessoa foi desconectada.')
})
const desbanir = async () => {
  if (!(await confirmar({ titulo: 'Desbanir?', texto: 'A pessoa volta a conseguir entrar no app.', botao: 'Desbanir' }))) return
  acao(async () => { await rpc('adm_desbanir', { p_user: p.value.id }); avisar('Conta liberada.') })
}
const apagar = async () => {
  const ok = await confirmar({
    titulo: 'Apagar conta de vez?',
    texto: `Some tudo de ${p.value.full_name || p.value.email}: treinos, fotos, posts, dieta, pontos. Não tem volta.`,
    botao: 'Apagar conta', perigo: true, digitar: 'APAGAR',
  })
  if (!ok) return
  ocupado.value = true
  try {
    const { data: r, error } = await sb.functions.invoke('delete-account', { body: { user_id: p.value.id } })
    if (error || r?.erro) throw new Error(r?.erro || 'Não deu pra apagar agora.')
    avisar('Conta apagada.')
    router.replace('/usuarios')
  } catch (e) { erro(e) } finally { ocupado.value = false }
}

const nomeFunil = { abriu: 'Abriu o app', onboarding: 'Fez onboarding', salvou_conta: 'Salvou conta', primeiro_treino: '1º treino', dia_7: 'Voltou no dia 7', entrou_por_link: 'Entrou por link', convidou: 'Convidou alguém' }
</script>

<template>
  <div>
    <button class="btn fantasma pequeno" style="margin-bottom: 12px" @click="router.back()"><Icone nome="voltar" :tam="14" /> Usuários</button>
    <div v-if="carregando" class="carregando"><div class="spinner" /></div>

    <template v-else-if="u">
      <div class="card topo surge">
        <Avatar :src="p.avatar_url" :nome="p.full_name" grande />
        <div class="espaco" style="min-width: 0">
          <h1 style="font-size: 22px">{{ p.full_name || 'Sem nome' }}</h1>
          <div class="muted">{{ p.username ? '@' + p.username + ' · ' : '' }}{{ p.email || 'Conta sem cadastro (anônima)' }}</div>
          <div class="linha" style="margin-top: 8px; gap: 6px">
            <span v-if="proPago" class="tag ouro">PRO pago</span>
            <span v-if="cortesiaAte" class="tag ciano">PRO cortesia até {{ data(cortesiaAte) }}</span>
            <span v-if="!proPago && !cortesiaAte" class="tag">Grátis</span>
            <span v-if="banido" class="tag vermelho">Banido até {{ data(p.banido_ate) }}</span>
            <span v-if="u.equipe" class="tag verde">Equipe</span>
            <span class="tag">{{ nomesOrigem(p.origem || 'orgânico') }}</span>
            <span class="tag">{{ (p.idioma || 'pt').toUpperCase() }}</span>
            <span v-if="u.provedor" class="tag">{{ u.provedor }}</span>
          </div>
        </div>
        <div class="acoes">
          <button v-if="pode('usuarios.pro')" class="btn" @click="abrir('pro')"><Icone nome="coroa" :tam="16" /> Dar PRO</button>
          <button v-if="pode('usuarios.pro') && cortesiaAte" class="btn" @click="tirarPro">Tirar cortesia</button>
          <button v-if="pode('usuarios.editar')" class="btn" @click="abrir('editar')"><Icone nome="editar" :tam="16" /> Editar</button>
          <button v-if="pode('usuarios.editar')" class="btn" @click="abrir('pontos')">± Pontos</button>
          <template v-if="pode('usuarios.banir') && !u.equipe">
            <button v-if="!banido" class="btn perigo" @click="abrir('banir')"><Icone nome="bloqueio" :tam="16" /> Banir</button>
            <button v-else class="btn" @click="desbanir">Desbanir</button>
          </template>
          <button v-if="pode('usuarios.apagar') && !u.equipe" class="btn perigo" :disabled="ocupado" @click="apagar"><Icone nome="lixo" :tam="16" /> Apagar conta</button>
        </div>
      </div>

      <div v-if="banido && p.banido_motivo" class="card" style="margin-top: 12px; border-color: var(--accent)">
        <strong>Motivo do banimento:</strong> {{ p.banido_motivo }}
      </div>

      <div class="grade g4" style="margin-top: 14px">
        <div class="card"><small>Treinos</small><div class="titulo n">{{ num(p.total_workouts) }}</div><small>sequência {{ p.current_streak || 0 }} · recorde {{ p.longest_streak || 0 }}</small></div>
        <div class="card"><small>Pontos</small><div class="titulo n">{{ num(u.pontos) }}</div></div>
        <div class="card"><small>Seguidores</small><div class="titulo n">{{ num(u.seguidores) }}</div><small>segue {{ num(u.seguindo) }} · {{ num(u.posts) }} posts</small></div>
        <div class="card"><small>IA (30 dias)</small><div class="titulo n">{{ usd(u.ia_30d?.custo_usd) }}</div><small>{{ num(u.ia_30d?.chamadas) }} chamadas</small></div>
      </div>

      <div class="grade g2" style="margin-top: 14px">
        <div class="card">
          <h3 style="margin-bottom: 10px">Perfil</h3>
          <div class="kv"><span>Criou a conta</span><strong>{{ dataHora(p.created_at) }}</strong></div>
          <div class="kv"><span>Último acesso</span><strong :title="dataHora(u.ultimo_acesso)">{{ desde(u.ultimo_acesso) }}</strong></div>
          <div class="kv"><span>Último login</span><strong>{{ dataHora(u.ultimo_login) }}</strong></div>
          <div class="kv"><span>Sexo / idade</span><strong>{{ p.gender || '—' }} · {{ p.age || '—' }}</strong></div>
          <div class="kv"><span>Peso / altura</span><strong>{{ p.weight_kg || '—' }} kg · {{ p.height_cm || '—' }} cm</strong></div>
          <div class="kv"><span>Objetivos</span><strong>{{ (p.fitness_goals || []).join(', ') || '—' }}</strong></div>
          <div class="kv"><span>Experiência</span><strong>{{ p.fitness_experience || '—' }}</strong></div>
          <div class="kv"><span>Treinos/semana</span><strong>{{ p.workout_frequency_per_week || '—' }}</strong></div>
          <div class="kv"><span>Cidade</span><strong>{{ p.cidade || '—' }}</strong></div>
          <div class="kv"><span>Código de convite</span><strong>{{ p.convite || '—' }}</strong></div>
          <div v-if="p.bio" class="kv"><span>Bio</span><strong class="texto-quebra">{{ p.bio }}</strong></div>
          <div class="kv"><span>ID</span><code style="user-select: all">{{ p.id }}</code></div>
        </div>
        <div class="coluna">
          <div class="card">
            <h3 style="margin-bottom: 10px">Jornada</h3>
            <div v-for="(n, k) in nomeFunil" :key="k" class="kv">
              <span>{{ n }}</span>
              <strong v-if="u.funil[k]" style="color: var(--success)">{{ dataHora(u.funil[k]) }}</strong>
              <small v-else>—</small>
            </div>
          </div>
          <div class="card">
            <h3 style="margin-bottom: 10px">Assinatura</h3>
            <template v-if="u.assinatura">
              <div class="kv"><span>Plano</span><strong>{{ u.assinatura.product_id || '—' }}</strong></div>
              <div class="kv"><span>Expira</span><strong>{{ dataHora(u.assinatura.expiration_date) }}</strong></div>
              <div class="kv"><span>Renova sozinho</span><strong>{{ u.assinatura.auto_renew_status ? 'Sim' : 'Não' }}</strong></div>
            </template>
            <p v-else class="muted" style="margin: 0">Nunca assinou.</p>
            <div v-if="u.cortesia" class="kv"><span>Cortesia</span><strong>até {{ data(u.cortesia.ate) }} ({{ u.cortesia.motivo }})</strong></div>
          </div>
          <div v-if="u.chamados.length" class="card">
            <h3 style="margin-bottom: 10px">Chamados de suporte</h3>
            <RouterLink v-for="c in u.chamados" :key="c.id" :to="`/suporte?c=${c.id}`" class="kv"><span class="corta">{{ c.assunto }}</span><span class="tag">{{ c.status }}</span></RouterLink>
          </div>
        </div>
      </div>

      <div class="card" style="margin-top: 14px">
        <h3 style="margin-bottom: 10px">Últimos treinos</h3>
        <div class="tabela-wrap" style="border: 0">
          <table>
            <thead><tr><th>Treino</th><th>Começou</th><th>Status</th><th class="num">Minutos</th></tr></thead>
            <tbody>
              <tr v-for="t in u.treinos" :key="t.id"><td>{{ t.name || '—' }}</td><td><small>{{ dataHora(t.started_at) }}</small></td><td><span class="tag" :class="t.completed_at ? 'verde' : ''">{{ t.completed_at ? 'concluído' : t.status }}</span></td><td class="num">{{ t.duration_minutes || '—' }}</td></tr>
              <tr v-if="!u.treinos.length"><td colspan="4" class="vazio">Nenhum treino ainda.</td></tr>
            </tbody>
          </table>
        </div>
      </div>
    </template>

    <Modal v-if="modal === 'pro'" titulo="Dar PRO de cortesia" @fechar="modal = ''">
      <div class="coluna">
        <div class="linha" style="gap: 6px"><button v-for="d in [7, 30, 90, 365]" :key="d" class="btn pequeno" :class="f.dias === d ? 'primario' : ''" @click="f.dias = d">{{ d }} dias</button></div>
        <label class="campo">Dias<input v-model.number="f.dias" type="number" min="1" max="3650" /></label>
        <label class="campo">Motivo (fica no registro)<input v-model="f.motivo" placeholder="Ex.: parceria, influenciador, compensação" /></label>
        <small>Soma com o que a pessoa já tem. Ela recebe um push avisando.</small>
        <button class="btn primario" :disabled="ocupado" @click="darPro">Liberar PRO</button>
      </div>
    </Modal>
    <Modal v-if="modal === 'editar'" titulo="Editar usuário" @fechar="modal = ''">
      <div class="coluna">
        <label class="campo">Nome<input v-model="f.nome" /></label>
        <label class="campo">@ usuário<input v-model="f.username" /></label>
        <label class="campo">Bio<textarea v-model="f.bio" /></label>
        <button class="btn primario" :disabled="ocupado" @click="salvarEdicao">Salvar</button>
      </div>
    </Modal>
    <Modal v-if="modal === 'pontos'" titulo="Ajustar pontos" @fechar="modal = ''">
      <div class="coluna">
        <label class="campo">Pontos (use negativo pra tirar)<input v-model.number="f.pontos" type="number" /></label>
        <label class="campo">Motivo<input v-model="f.motivo" placeholder="Ex.: prêmio do desafio, correção" /></label>
        <button class="btn primario" :disabled="ocupado || !f.pontos" @click="salvarPontos">Aplicar</button>
      </div>
    </Modal>
    <Modal v-if="modal === 'banir'" titulo="Banir conta" @fechar="modal = ''">
      <div class="coluna">
        <p class="muted" style="margin: 0">A pessoa é desconectada na hora e não consegue entrar até o prazo acabar. Posts e dados ficam.</p>
        <label class="linha-check"><input v-model="f.sempre" type="checkbox" /> Sem prazo</label>
        <label v-if="!f.sempre" class="campo">Dias<input v-model.number="f.dias" type="number" min="1" /></label>
        <label class="campo">Motivo<textarea v-model="f.motivo" placeholder="Obrigatório. Fica no registro." /></label>
        <button class="btn perigo" :disabled="ocupado || !f.motivo" @click="banir">Banir agora</button>
      </div>
    </Modal>
  </div>
</template>

<style scoped>
.topo { display: flex; gap: 16px; align-items: flex-start; flex-wrap: wrap; }
.acoes { display: flex; flex-wrap: wrap; gap: 8px; justify-content: flex-end; max-width: 420px; }
.n { font-size: 26px; font-weight: 800; margin: 2px 0; }
.kv { display: flex; justify-content: space-between; gap: 16px; padding: 8px 0; border-bottom: 1px solid var(--line); color: var(--text); }
.kv:last-child { border-bottom: 0; }
.kv > span { color: var(--muted); }
.kv > strong { text-align: right; font-weight: 600; }
</style>
