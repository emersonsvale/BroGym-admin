<script setup>
import { ref, onMounted, watch } from 'vue'
import { rpc, enviarMidia } from '../lib/supabase'
import { desde, num, avisar, erro, confirmar } from '../lib/util'
import Avatar from '../components/Avatar.vue'
import Icone from '../components/Icone.vue'
import Modal from '../components/Modal.vue'

const emit = defineEmits(['mudou'])
const aba = ref('denuncias')
const carregando = ref(false)
const denuncias = ref([])
const posts = ref([])
const stories = ref([])
const comentarios = ref([])
const grupos = ref([])
const busca = ref('')
const tipoPost = ref('')
const grupo = ref(null)

const nomesTipo = { post: 'Post', video: 'Vídeo', story: 'Story', comentario: 'Comentário', usuario: 'Perfil' }
const nomesMotivo = { spam: 'Spam', ofensivo: 'Ofensivo', nudez: 'Nudez', assedio: 'Assédio', violencia: 'Violência', falso: 'Falso', outro: 'Outro' }

async function carregar() {
  carregando.value = true
  try {
    if (aba.value === 'denuncias') denuncias.value = await rpc('adm_denuncias')
    if (aba.value === 'posts') posts.value = await rpc('adm_posts', { p_busca: busca.value || null, p_tipo: tipoPost.value || null, p_limite: 60 })
    if (aba.value === 'stories') stories.value = await rpc('adm_stories')
    if (aba.value === 'comentarios') comentarios.value = await rpc('adm_comentarios', { p_limite: 120 })
    if (aba.value === 'grupos') grupos.value = await rpc('adm_grupos')
  } catch (e) { erro(e) } finally { carregando.value = false }
}
watch(aba, carregar)
let t
watch([busca, tipoPost], () => { clearTimeout(t); t = setTimeout(carregar, 300) })
onMounted(carregar)

async function resolver(d, acao) {
  if (acao === 'remover') {
    const extra = d.tipo === 'usuario' ? ' Isso apaga TODOS os posts, vídeos e stories dessa pessoa.' : ''
    if (!(await confirmar({ titulo: `Remover ${nomesTipo[d.tipo].toLowerCase()}?`, texto: `Sai do app na hora.${extra}`, botao: 'Remover', perigo: true }))) return
  }
  try {
    await rpc('adm_resolver_denuncia', { p_tipo: d.tipo, p_alvo: d.alvo_id, p_acao: acao })
    avisar(acao === 'remover' ? 'Removido.' : 'Denúncia ignorada.')
    emit('mudou'); carregar()
  } catch (e) { erro(e) }
}

async function apagar(tipo, item) {
  if (!(await confirmar({ titulo: `Apagar ${nomesTipo[tipo].toLowerCase()}?`, texto: 'A pessoa recebe um aviso de que a publicação foi removida por não seguir as regras.', botao: 'Apagar', perigo: true }))) return
  try {
    await rpc('adm_apagar_conteudo', { p_tipo: tipo, p_id: item.id, p_motivo: null, p_avisar: true })
    avisar('Apagado.')
    carregar()
  } catch (e) { erro(e) }
}

function novoGrupo() { grupo.value = { id: null, nome: '', descricao: '', categoria: 'objetivo', capa: null } }
function editarGrupo(g) { grupo.value = { id: g.id, nome: g.nome, descricao: g.descricao, categoria: g.categoria || '', capa: g.capa } }
async function capaGrupo(ev) {
  const a = ev.target.files?.[0]; if (!a) return
  try { grupo.value.capa = await enviarMidia(a, 'grupos') } catch (e) { erro(e) }
}
async function salvarGrupo() {
  try {
    await rpc('adm_grupo_salvar', { p_id: grupo.value.id, p_nome: grupo.value.nome, p_descricao: grupo.value.descricao, p_categoria: grupo.value.categoria, p_capa: grupo.value.capa })
    avisar('Grupo salvo.'); grupo.value = null; carregar()
  } catch (e) { erro(e) }
}
async function apagarGrupo(g) {
  if (!(await confirmar({ titulo: `Apagar o grupo "${g.nome}"?`, texto: `${g.membros} membros saem do grupo. Não tem volta.`, botao: 'Apagar grupo', perigo: true, digitar: g.membros > 5 ? 'APAGAR' : '' }))) return
  try { await rpc('adm_grupo_apagar', { p_id: g.id }); avisar('Grupo apagado.'); carregar() } catch (e) { erro(e) }
}
</script>

<template>
  <div>
    <div class="cabecalho"><div><h1>Comunidade</h1><p>Denúncias, posts, stories, comentários e grupos.</p></div></div>
    <div class="abas">
      <button class="aba" :class="{ ativa: aba === 'denuncias' }" @click="aba = 'denuncias'">Denúncias <span v-if="denuncias.length" class="tag vermelho">{{ denuncias.length }}</span></button>
      <button class="aba" :class="{ ativa: aba === 'posts' }" @click="aba = 'posts'">Posts e vídeos</button>
      <button class="aba" :class="{ ativa: aba === 'stories' }" @click="aba = 'stories'">Stories</button>
      <button class="aba" :class="{ ativa: aba === 'comentarios' }" @click="aba = 'comentarios'">Comentários</button>
      <button class="aba" :class="{ ativa: aba === 'grupos' }" @click="aba = 'grupos'">Grupos</button>
    </div>

    <div v-if="carregando" class="carregando"><div class="spinner" /></div>

    <template v-else-if="aba === 'denuncias'">
      <div v-if="!denuncias.length" class="card vazio"><Icone nome="check" :tam="28" /><p>Nenhuma denúncia aberta. Comunidade em paz.</p></div>
      <div class="grade g2">
        <div v-for="d in denuncias" :key="d.tipo + d.alvo_id" class="card surge coluna">
          <div class="linha">
            <span class="tag vermelho">{{ d.qtd }} denúncia{{ d.qtd > 1 ? 's' : '' }}</span>
            <span class="tag">{{ nomesTipo[d.tipo] }}</span>
            <span v-for="m in d.motivos" :key="m" class="tag ambar">{{ nomesMotivo[m] || m }}</span>
            <small class="espaco" style="text-align: right">{{ desde(d.ultima) }}</small>
          </div>
          <div v-if="d.autor_id" class="linha"><RouterLink :to="`/usuarios/${d.autor_id}`" style="font-weight: 600">{{ d.autor_nome || 'Autor' }}</RouterLink></div>
          <img v-if="d.imagem" :src="d.imagem" class="midia" loading="lazy" alt="" />
          <video v-if="d.video" :src="d.video" class="midia" controls preload="metadata" />
          <p v-if="d.texto" class="texto-quebra" style="margin: 0">{{ d.texto }}</p>
          <p v-if="!d.texto && !d.imagem && !d.video" class="muted" style="margin: 0">Conteúdo já não existe mais.</p>
          <div class="linha" style="justify-content: flex-end">
            <button class="btn" @click="resolver(d, 'ignorar')">Ignorar</button>
            <button class="btn perigo" @click="resolver(d, 'remover')"><Icone nome="lixo" :tam="15" /> Remover</button>
          </div>
        </div>
      </div>
    </template>

    <template v-else-if="aba === 'posts'">
      <div class="linha" style="margin-bottom: 14px">
        <input v-model="busca" placeholder="Buscar no texto ou autor" style="max-width: 320px" />
        <select v-model="tipoPost" style="width: auto"><option value="">Todos</option><option value="foto">Com foto</option><option value="video">Vídeos</option><option value="treino">Treinos</option></select>
      </div>
      <div class="grade g3">
        <div v-for="p in posts" :key="p.id" class="card coluna">
          <div class="linha" style="flex-wrap: nowrap">
            <Avatar :src="p.autor_avatar" :nome="p.autor" />
            <div class="espaco" style="min-width: 0"><RouterLink :to="`/usuarios/${p.user_id}`" class="corta" style="display: block; font-weight: 600; color: var(--text)">{{ p.autor }}</RouterLink><small>{{ desde(p.criado_em) }}</small></div>
            <span v-if="p.denuncias" class="tag vermelho">{{ p.denuncias }}</span>
          </div>
          <img v-if="p.imagem" :src="p.imagem" class="midia" loading="lazy" alt="" />
          <video v-if="p.video" :src="p.video" class="midia" controls preload="none" />
          <p v-if="p.conteudo" class="texto-quebra" style="margin: 0; max-height: 120px; overflow: hidden">{{ p.conteudo }}</p>
          <div class="linha">
            <small>♥ {{ num(p.curtidas) }} · 💬 {{ num(p.comentarios) }}</small>
            <span class="espaco" />
            <button class="btn perigo pequeno" @click="apagar('post', p)"><Icone nome="lixo" :tam="14" /> Apagar</button>
          </div>
        </div>
      </div>
      <div v-if="!posts.length" class="card vazio">Nenhum post.</div>
    </template>

    <template v-else-if="aba === 'stories'">
      <div class="grade g4">
        <div v-for="s in stories" :key="s.id" class="card coluna story">
          <div class="linha"><Avatar :src="s.autor_avatar" :nome="s.autor" /><div class="espaco"><strong class="corta" style="display: block">{{ s.autor }}</strong><small>{{ desde(s.criado_em) }} · {{ s.vistas }} viram</small></div></div>
          <video v-if="s.tipo === 'video'" :src="s.media" class="midia vertical" controls preload="none" />
          <img v-else :src="s.media" class="midia vertical" loading="lazy" alt="" />
          <p v-if="s.legenda" style="margin: 0">{{ s.legenda }}</p>
          <div class="linha"><span class="tag" :class="new Date(s.expira_em) > new Date() ? 'verde' : ''">{{ new Date(s.expira_em) > new Date() ? 'no ar' : 'expirado' }}</span><span class="espaco" /><button class="btn perigo pequeno" @click="apagar('story', s)">Apagar</button></div>
        </div>
      </div>
      <div v-if="!stories.length" class="card vazio">Nenhum story nos últimos dias.</div>
    </template>

    <template v-else-if="aba === 'comentarios'">
      <div class="tabela-wrap">
        <table>
          <thead><tr><th>Quem</th><th>Comentário</th><th>Quando</th><th /></tr></thead>
          <tbody>
            <tr v-for="c in comentarios" :key="c.id">
              <td><div class="linha" style="flex-wrap: nowrap"><Avatar :src="c.autor_avatar" :nome="c.autor" /><RouterLink :to="`/usuarios/${c.user_id}`" style="color: var(--text); font-weight: 600">{{ c.autor }}</RouterLink></div></td>
              <td class="texto-quebra">{{ c.conteudo }}</td>
              <td><small>{{ desde(c.criado_em) }}</small></td>
              <td><button class="btn perigo pequeno" @click="apagar('comentario', c)">Apagar</button></td>
            </tr>
            <tr v-if="!comentarios.length"><td colspan="4" class="vazio">Nenhum comentário.</td></tr>
          </tbody>
        </table>
      </div>
    </template>

    <template v-else-if="aba === 'grupos'">
      <div class="linha" style="margin-bottom: 14px"><button class="btn primario" @click="novoGrupo"><Icone nome="mais" :tam="16" /> Grupo oficial</button></div>
      <div class="tabela-wrap">
        <table>
          <thead><tr><th>Grupo</th><th>Tipo</th><th>Dono</th><th class="num">Membros</th><th /></tr></thead>
          <tbody>
            <tr v-for="g in grupos" :key="g.id">
              <td><div class="linha" style="flex-wrap: nowrap"><img v-if="g.capa" :src="g.capa" class="miniatura" alt="" /><div><strong>{{ g.nome }}</strong><small class="corta" style="display: block">{{ g.descricao }}</small></div></div></td>
              <td><span v-if="g.oficial" class="tag vermelho">Oficial</span> <span v-if="g.categoria" class="tag">{{ g.categoria }}{{ g.cidade ? ' · ' + g.cidade : '' }}</span><span v-if="!g.oficial && !g.publico" class="tag">Fechado</span></td>
              <td><small>{{ g.dono || 'BroGym' }}</small></td>
              <td class="num">{{ num(g.membros) }}</td>
              <td><div class="linha" style="justify-content: flex-end; flex-wrap: nowrap"><button class="btn pequeno" @click="editarGrupo(g)">Editar</button><button class="btn perigo pequeno" @click="apagarGrupo(g)">Apagar</button></div></td>
            </tr>
          </tbody>
        </table>
      </div>
    </template>

    <Modal v-if="grupo" :titulo="grupo.id ? 'Editar grupo' : 'Novo grupo oficial'" @fechar="grupo = null">
      <div class="coluna">
        <label class="campo">Nome<input v-model="grupo.nome" /></label>
        <label class="campo">Descrição<textarea v-model="grupo.descricao" /></label>
        <label class="campo">Tipo<select v-model="grupo.categoria"><option value="objetivo">Por objetivo</option><option value="modalidade">Por modalidade</option><option value="cidade">Por cidade</option><option value="desafio">Desafio do mês</option><option value="">Outro</option></select></label>
        <label class="campo">Capa<input type="file" accept="image/*" @change="capaGrupo" /></label>
        <img v-if="grupo.capa" :src="grupo.capa" class="midia" alt="" />
        <button class="btn primario" :disabled="!grupo.nome" @click="salvarGrupo">Salvar</button>
      </div>
    </Modal>
  </div>
</template>

<style scoped>
.midia.vertical { aspect-ratio: 9 / 16; max-height: 360px; }
</style>
