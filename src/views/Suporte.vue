<script setup>
import { ref, onMounted, watch, nextTick } from 'vue'
import { useRoute } from 'vue-router'
import { rpc, sb } from '../lib/supabase'
import { desde, dataHora, avisar, erro } from '../lib/util'
import Avatar from '../components/Avatar.vue'
import Icone from '../components/Icone.vue'

const emit = defineEmits(['mudou'])
const route = useRoute()
const status = ref('aberto')
const lista = ref([])
const aberto = ref(null)
const resposta = ref('')
const enviando = ref(false)
const carregando = ref(true)
const conversa = ref(null)
const imagens = ref({})

const nomesTipo = { bug: 'Bug', duvida: 'Dúvida', sugestao: 'Sugestão', pagamento: 'Pagamento', outro: 'Outro' }
const respostasProntas = [
  'Oi! Obrigado por avisar. Já estamos olhando isso e te aviso aqui assim que resolver.',
  'Resolvido! Atualiza o app na Play Store e me conta se ficou certo.',
  'Pra assinatura: abre a Play Store > Perfil > Pagamentos e assinaturas > Assinaturas. Lá dá pra ver, trocar ou cancelar.',
  'Valeu pela sugestão! Anotei aqui pro time.',
]

async function carregar() {
  carregando.value = true
  try { lista.value = await rpc('adm_chamados', { p_status: status.value }) } catch (e) { erro(e) } finally { carregando.value = false }
}
async function abrir(id) {
  try {
    aberto.value = await rpc('adm_chamado', { p_id: id })
    resposta.value = ''
    // Prints são privados: gera link temporário.
    for (const m of aberto.value.mensagens.filter((m) => m.imagem && !imagens.value[m.imagem])) {
      const { data } = await sb.storage.from('suporte').createSignedUrl(m.imagem, 3600)
      if (data?.signedUrl) imagens.value[m.imagem] = data.signedUrl
    }
    await nextTick()
    conversa.value?.scrollTo({ top: 1e6 })
  } catch (e) { erro(e) }
}
async function responder(fechar = false) {
  enviando.value = true
  try {
    await rpc('adm_chamado_responder', { p_id: aberto.value.chamado.id, p_texto: resposta.value, p_fechar: fechar })
    avisar(fechar ? 'Respondido e fechado. A pessoa recebeu um push.' : 'Respondido. A pessoa recebeu um push.')
    await abrir(aberto.value.chamado.id); carregar(); emit('mudou')
  } catch (e) { erro(e) } finally { enviando.value = false }
}
async function mudarStatus(s) {
  try { await rpc('adm_chamado_status', { p_id: aberto.value.chamado.id, p_status: s }); await abrir(aberto.value.chamado.id); carregar(); emit('mudou') } catch (e) { erro(e) }
}
watch(status, carregar)
onMounted(async () => { await carregar(); if (route.query.c) abrir(route.query.c) })
</script>

<template>
  <div>
    <div class="cabecalho"><div><h1>Suporte e feedback</h1><p>Chamados abertos pelo app (Configurações › Ajuda e feedback).</p></div></div>
    <div class="painel">
      <div class="lista">
        <div class="abas" style="margin-bottom: 8px">
          <button v-for="(n, k) in { aberto: 'Abertos', respondido: 'Respondidos', fechado: 'Fechados', todos: 'Todos' }" :key="k" class="aba" :class="{ ativa: status === k }" @click="status = k">{{ n }}</button>
        </div>
        <div v-if="carregando" class="carregando"><div class="spinner" /></div>
        <button v-for="c in lista" :key="c.id" class="item-chamado" :class="{ ativo: aberto?.chamado.id === c.id }" @click="abrir(c.id)">
          <Avatar :src="c.avatar" :nome="c.nome" />
          <div style="min-width: 0; flex: 1; text-align: left">
            <div class="linha entre" style="flex-wrap: nowrap"><strong class="corta">{{ c.nome || 'Usuário' }}</strong><small>{{ desde(c.atualizado_em) }}</small></div>
            <small class="corta" style="display: block">{{ c.ultima }}</small>
            <div class="linha" style="gap: 4px; margin-top: 4px"><span class="tag">{{ nomesTipo[c.tipo] }}</span><span v-if="c.versao_app" class="tag">v{{ c.versao_app }}</span></div>
          </div>
        </button>
        <div v-if="!carregando && !lista.length" class="vazio">Nada por aqui.</div>
      </div>

      <div class="card detalhe">
        <div v-if="!aberto" class="vazio" style="margin: auto"><Icone nome="suporte" :tam="30" /><p>Escolha um chamado.</p></div>
        <template v-else>
          <div class="linha entre" style="border-bottom: 1px solid var(--line); padding-bottom: 12px">
            <div class="linha" style="flex-wrap: nowrap">
              <Avatar :src="aberto.usuario.avatar" :nome="aberto.usuario.nome" />
              <div>
                <RouterLink :to="`/usuarios/${aberto.usuario.id}`" style="color: var(--text); font-weight: 700">{{ aberto.usuario.nome }}</RouterLink>
                <small style="display: block">{{ aberto.usuario.email }} · {{ (aberto.usuario.idioma || 'pt').toUpperCase() }} <span v-if="aberto.usuario.pro" class="tag ouro">PRO</span></small>
                <small style="display: block">{{ aberto.chamado.aparelho }} {{ aberto.chamado.versao_app ? '· app ' + aberto.chamado.versao_app : '' }}</small>
              </div>
            </div>
            <select :value="aberto.chamado.status" style="width: auto" @change="mudarStatus($event.target.value)">
              <option value="aberto">Aberto</option><option value="respondido">Respondido</option><option value="fechado">Fechado</option>
            </select>
          </div>
          <div ref="conversa" class="conversa">
            <div v-for="m in aberto.mensagens" :key="m.id" class="msg" :class="{ time: m.do_time }">
              <small>{{ m.do_time ? (m.autor || 'Time') : aberto.usuario.nome }} · {{ dataHora(m.em) }}</small>
              <div class="balao texto-quebra">{{ m.texto }}</div>
              <a v-if="m.imagem && imagens[m.imagem]" :href="imagens[m.imagem]" target="_blank" rel="noopener"><img :src="imagens[m.imagem]" class="print" alt="Print" /></a>
            </div>
          </div>
          <div class="linha" style="gap: 6px; margin-bottom: 8px">
            <button v-for="(r, i) in respostasProntas" :key="i" class="btn pequeno fantasma" style="border: 1px solid var(--line)" @click="resposta = r">{{ r.slice(0, 28) }}…</button>
          </div>
          <textarea v-model="resposta" rows="3" placeholder="Escreva a resposta (a pessoa recebe push)" @keydown.ctrl.enter="responder(false)" />
          <div class="linha" style="justify-content: flex-end; margin-top: 8px">
            <button class="btn" :disabled="!resposta.trim() || enviando" @click="responder(true)">Responder e fechar</button>
            <button class="btn primario" :disabled="!resposta.trim() || enviando" @click="responder(false)"><Icone nome="envio" :tam="15" /> Responder</button>
          </div>
        </template>
      </div>
    </div>
  </div>
</template>

<style scoped>
.painel { display: grid; grid-template-columns: 340px 1fr; gap: 14px; height: calc(100vh - 170px); min-height: 480px; }
.lista { overflow-y: auto; display: flex; flex-direction: column; gap: 6px; }
.item-chamado { display: flex; gap: 10px; padding: 12px; border-radius: 12px; border: 1px solid var(--line); background: var(--surface); cursor: pointer; color: var(--text); font: inherit; }
.item-chamado:hover { border-color: var(--muted); }
.item-chamado.ativo { border-color: var(--accent); background: var(--accent-soft); }
.detalhe { display: flex; flex-direction: column; min-height: 0; }
.conversa { flex: 1; overflow-y: auto; display: flex; flex-direction: column; gap: 12px; padding: 16px 2px; }
.msg { max-width: 78%; display: flex; flex-direction: column; gap: 4px; }
.msg.time { align-self: flex-end; text-align: right; }
.balao { background: var(--surface2); padding: 10px 14px; border-radius: 14px 14px 14px 4px; text-align: left; }
.msg.time .balao { background: var(--accent); color: #fff; border-radius: 14px 14px 4px 14px; }
.print { max-width: 220px; border-radius: 10px; margin-top: 4px; }
@media (max-width: 900px) { .painel { grid-template-columns: 1fr; height: auto; } .lista { max-height: 320px; } .detalhe { min-height: 520px; } }
</style>
