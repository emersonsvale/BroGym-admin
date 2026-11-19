<script setup>
import { ref, computed, onMounted } from 'vue'
import { rpc } from '../lib/supabase'
import { num, pct, avisar, erro, confirmar } from '../lib/util'
import Icone from '../components/Icone.vue'
import Modal from '../components/Modal.vue'

const lista = ref([])
const carregando = ref(true)
const q = ref(null)
const idioma = ref('pt')
const busca = ref('')

async function carregar() {
  carregando.value = true
  try { lista.value = await rpc('adm_perguntas') } catch (e) { erro(e) } finally { carregando.value = false }
}
onMounted(carregar)
const filtradas = computed(() => lista.value.filter((p) => !busca.value || p.texto.toLowerCase().includes(busca.value.toLowerCase())))

const vazia = () => ({ id: null, texto: '', opcoes: ['', '', '', ''], correta: 0, explicacao: '', texto_en: '', opcoes_en: ['', '', '', ''], explicacao_en: '', texto_es: '', opcoes_es: ['', '', '', ''], explicacao_es: '' })
function nova() { q.value = vazia(); idioma.value = 'pt' }
function editar(p) {
  const n = p.opcoes.length
  const pad = (a) => [...(a || []), ...Array(n).fill('')].slice(0, n)
  q.value = { ...p, opcoes: [...p.opcoes], opcoes_en: pad(p.opcoes_en), opcoes_es: pad(p.opcoes_es), texto_en: p.texto_en || '', texto_es: p.texto_es || '', explicacao_en: p.explicacao_en || '', explicacao_es: p.explicacao_es || '' }
  idioma.value = 'pt'
}
const suf = computed(() => (idioma.value === 'pt' ? '' : '_' + idioma.value))
async function salvar() {
  const d = { ...q.value, opcoes: q.value.opcoes.filter((o) => o.trim()) }
  for (const l of ['en', 'es']) d['opcoes_' + l] = d['opcoes_' + l].some((o) => o.trim()) ? d['opcoes_' + l] : []
  try { await rpc('adm_pergunta_salvar', { p_id: q.value.id, p_dados: d }); avisar('Pergunta salva.'); q.value = null; carregar() } catch (e) { erro(e) }
}
async function apagar(p) {
  if (!(await confirmar({ titulo: 'Apagar pergunta?', texto: p.texto, botao: 'Apagar', perigo: true }))) return
  try { await rpc('adm_pergunta_apagar', { p_id: p.id }); avisar('Apagada.'); q.value = null; carregar() } catch (e) { erro(e) }
}
</script>

<template>
  <div>
    <div class="cabecalho">
      <div><h1>Pergunta do dia</h1><p>{{ lista.length }} perguntas no rodízio (uma por dia, +10 pontos pra quem acerta).</p></div>
      <button class="btn primario" @click="nova"><Icone nome="mais" :tam="16" /> Nova pergunta</button>
    </div>
    <input v-model="busca" placeholder="Buscar pergunta" style="max-width: 340px; margin-bottom: 14px" />
    <div v-if="carregando" class="carregando"><div class="spinner" /></div>
    <div v-else class="tabela-wrap">
      <table>
        <thead><tr><th>#</th><th>Pergunta</th><th>Traduções</th><th class="num">Respostas</th><th class="num">Acerto</th></tr></thead>
        <tbody>
          <tr v-for="p in filtradas" :key="p.id" class="clicavel" @click="editar(p)">
            <td><small>{{ p.id }}</small></td>
            <td><strong>{{ p.texto }}</strong><br /><small>✓ {{ p.opcoes[p.correta] }}</small></td>
            <td><span class="tag" :class="p.texto_en ? 'verde' : 'ambar'">EN</span> <span class="tag" :class="p.texto_es ? 'verde' : 'ambar'">ES</span></td>
            <td class="num">{{ num(p.respostas) }}</td>
            <td class="num">{{ pct(p.acertos, p.respostas) }}</td>
          </tr>
        </tbody>
      </table>
    </div>

    <Modal v-if="q" :titulo="q.id ? `Pergunta #${q.id}` : 'Nova pergunta'" largura="640px" @fechar="q = null">
      <div class="coluna">
        <div class="abas" style="margin-bottom: 4px">
          <button v-for="(n, k) in { pt: 'Português', en: 'Inglês', es: 'Espanhol' }" :key="k" class="aba" :class="{ ativa: idioma === k }" @click="idioma = k">{{ n }}</button>
        </div>
        <label class="campo">Pergunta<textarea v-model="q['texto' + suf]" rows="2" /></label>
        <label class="campo">Opções <small>(marque a certa)</small></label>
        <div v-for="(o, i) in q['opcoes' + suf]" :key="i" class="linha" style="flex-wrap: nowrap">
          <input type="radio" :checked="q.correta === i" :disabled="idioma !== 'pt'" style="width: 18px" @change="q.correta = i" />
          <input v-model="q['opcoes' + suf][i]" :placeholder="idioma === 'pt' ? `Opção ${i + 1}` : q.opcoes[i]" />
        </div>
        <label class="campo">Explicação (aparece depois de responder)<textarea v-model="q['explicacao' + suf]" rows="3" /></label>
        <div class="linha">
          <button class="btn primario" :disabled="!q.texto || q.opcoes.filter((o) => o.trim()).length < 2" @click="salvar">Salvar</button>
          <span class="espaco" />
          <button v-if="q.id" class="btn perigo" @click="apagar(q)">Apagar</button>
        </div>
      </div>
    </Modal>
  </div>
</template>
