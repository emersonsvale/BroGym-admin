<script setup>
import { ref, onMounted, watch } from 'vue'
import { rpc } from '../lib/supabase'
import { num, dataHora, avisar, erro, confirmar } from '../lib/util'
import Icone from '../components/Icone.vue'

const f = ref({ publico: 'todos', idioma: '', titulo: '', texto: '', rota: '/home' })
const alcance = ref(null)
const historico = ref([])
const enviando = ref(false)

const publicos = { todos: 'Todo mundo', novos: 'Novos (7 dias)', inativos: 'Sumidos há 7+ dias', sem_treino: 'Nunca treinaram', gratis: 'Plano grátis', pro: 'PRO', anonimos: 'Sem cadastro', equipe: 'Só a equipe (teste)' }
const rotas = { '/home': 'Início', '/chat': 'Coach IA', '/social/eventos': 'Eventos', '/relatorio': 'Relatório da semana', '/paywall': 'Assinar PRO', '/dieta/cardapio': 'Cardápio', '/convidar': 'Convidar amigos', '/treino/historico': 'Histórico de treinos', '/notificacoes': 'Notificações' }

async function contar() {
  try { alcance.value = await rpc('adm_push_contar', { p_publico: f.value.publico, p_idioma: f.value.idioma || null }) } catch (e) { erro(e) }
}
async function carregarHistorico() { try { historico.value = await rpc('adm_push_historico') } catch (e) { erro(e) } }
watch(() => [f.value.publico, f.value.idioma], contar)
onMounted(() => { contar(); carregarHistorico() })

async function testar() {
  try { await rpc('adm_push_enviar', { p_publico: 'eu', p_titulo: f.value.titulo, p_texto: f.value.texto, p_rota: f.value.rota }); avisar('Push de teste enviado pro seu celular.') } catch (e) { erro(e) }
}
async function enviar() {
  const ok = await confirmar({ titulo: `Mandar pra ${num(alcance.value)} pessoas?`, texto: `"${f.value.titulo}"\n${f.value.texto}\n\nNão dá pra desfazer.`, botao: 'Enviar agora', perigo: alcance.value > 50, digitar: alcance.value > 50 ? 'ENVIAR' : '' })
  if (!ok) return
  enviando.value = true
  try {
    const n = await rpc('adm_push_enviar', { p_publico: f.value.publico, p_titulo: f.value.titulo, p_texto: f.value.texto, p_rota: f.value.rota, p_idioma: f.value.idioma || null })
    avisar(`Push na fila pra ${num(n)} pessoas.`)
    f.value.titulo = ''; f.value.texto = ''
    carregarHistorico()
  } catch (e) { erro(e) } finally { enviando.value = false }
}
</script>

<template>
  <div>
    <div class="cabecalho"><div><h1>Enviar push</h1><p>Notificação no celular. O texto vai como você escrever (não é traduzido): use o filtro de idioma.</p></div></div>
    <div class="grade" style="grid-template-columns: 1.1fr .9fr">
      <div class="card coluna">
        <div class="grade g2">
          <label class="campo">Pra quem<select v-model="f.publico"><option v-for="(n, k) in publicos" :key="k" :value="k">{{ n }}</option></select></label>
          <label class="campo">Idioma do app<select v-model="f.idioma"><option value="">Todos</option><option value="pt">Português</option><option value="en">Inglês</option><option value="es">Espanhol</option></select></label>
        </div>
        <label class="campo">Título <small>{{ f.titulo.length }}/65</small><input v-model="f.titulo" maxlength="65" placeholder="Ex.: Bora treinar hoje? 💪" /></label>
        <label class="campo">Texto <small>{{ f.texto.length }}/240</small><textarea v-model="f.texto" maxlength="240" rows="3" placeholder="Ex.: Seu treino de hoje já está pronto no app." /></label>
        <label class="campo">Abre em<select v-model="f.rota"><option v-for="(n, k) in rotas" :key="k" :value="k">{{ n }}</option></select></label>
        <div class="linha">
          <span class="tag" :class="alcance ? 'vermelho' : ''">{{ alcance == null ? '…' : num(alcance) }} pessoas</span>
          <span class="espaco" />
          <button class="btn" :disabled="!f.titulo || !f.texto" @click="testar">Testar em mim</button>
          <button class="btn primario" :disabled="!f.titulo || !f.texto || !alcance || enviando" @click="enviar"><Icone nome="envio" :tam="16" /> Enviar</button>
        </div>
        <small>Trava de segurança: 1 envio em massa a cada 10 minutos.</small>
      </div>
      <div class="card">
        <small style="font-weight: 600">Prévia</small>
        <div class="previa">
          <div class="linha" style="gap: 8px; flex-wrap: nowrap"><img src="/icone.svg" width="20" height="20" alt="" /><small>BroGym · agora</small></div>
          <strong style="display: block; margin-top: 6px">{{ f.titulo || 'Título do push' }}</strong>
          <span class="muted">{{ f.texto || 'Texto do push aparece aqui.' }}</span>
        </div>
      </div>
    </div>

    <h2 style="margin: 28px 0 12px">Enviados</h2>
    <div class="tabela-wrap">
      <table>
        <thead><tr><th>Quando</th><th>Quem mandou</th><th>Público</th><th>Mensagem</th><th class="num">Pessoas</th></tr></thead>
        <tbody>
          <tr v-for="(h, i) in historico" :key="i"><td><small>{{ dataHora(h.em) }}</small></td><td>{{ h.quem }}</td><td><span class="tag">{{ publicos[h.publico] || h.publico }}</span></td><td><strong>{{ h.titulo }}</strong><br /><small>{{ h.texto }}</small></td><td class="num">{{ num(h.enviados) }}</td></tr>
          <tr v-if="!historico.length"><td colspan="5" class="vazio">Nenhum push em massa ainda.</td></tr>
        </tbody>
      </table>
    </div>
  </div>
</template>

<style scoped>
.previa { margin-top: 12px; background: var(--surface2); border-radius: 16px; padding: 14px; border: 1px solid var(--line); }
@media (max-width: 900px) { .grade[style] { grid-template-columns: 1fr !important; } }
</style>
