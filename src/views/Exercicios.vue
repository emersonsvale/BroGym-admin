<script setup>
import { ref, computed, onMounted, watch } from 'vue'
import { rpc, enviarMidia } from '../lib/supabase'
import { num, avisar, erro } from '../lib/util'
import Icone from '../components/Icone.vue'
import Modal from '../components/Modal.vue'

const lista = ref([])
const categorias = ref([])
const busca = ref('')
const categoria = ref('')
const soSemTraducao = ref(false)
const soInativos = ref(false)
const carregando = ref(true)
const ex = ref(null)
const cat = ref(null)
const enviando = ref(false)
const limite = ref(60)

async function carregar() {
  carregando.value = true
  try {
    const [a, b] = await Promise.all([rpc('adm_exercicios', { p_busca: busca.value || null, p_categoria: categoria.value || null }), rpc('adm_categorias')])
    lista.value = a; categorias.value = b
  } catch (e) { erro(e) } finally { carregando.value = false }
}
let t
watch([busca, categoria], () => { clearTimeout(t); limite.value = 60; t = setTimeout(carregar, 300) })
onMounted(carregar)

const filtrados = computed(() => lista.value.filter((e) => (!soSemTraducao.value || !e.nome_en || !e.nome_es) && (!soInativos.value || !e.ativo)))
const semTraducao = computed(() => lista.value.filter((e) => !e.nome_en || !e.nome_es).length)
const ehVideo = (u) => /\.(mp4|webm|mov)(\?|$)/i.test(u || '')

function novo() { ex.value = { id: null, nome: '', nome_en: '', nome_es: '', categoria_id: categoria.value || categorias.value[0]?.id, media_url: '', media_type: 'image', ativo: true } }
function editar(e) { ex.value = { ...e } }
async function midia(ev) {
  const a = ev.target.files?.[0]; if (!a) return
  enviando.value = true
  try {
    ex.value.media_url = await enviarMidia(a, 'exercicios')
    ex.value.media_type = a.type.startsWith('video') ? 'video' : a.type === 'image/gif' ? 'gif' : 'image'
  } catch (e) { erro(e) } finally { enviando.value = false }
}
async function salvar() {
  try {
    await rpc('adm_exercicio_salvar', { p_id: ex.value.id, p_dados: ex.value })
    avisar('Exercício salvo.'); ex.value = null; carregar()
  } catch (e) { erro(e) }
}
async function salvarCat() {
  try { await rpc('adm_categoria_salvar', { p_id: cat.value.id, p_nome: cat.value.nome, p_nome_en: cat.value.nome_en, p_nome_es: cat.value.nome_es }); avisar('Grupo muscular salvo.'); cat.value = null; carregar() } catch (e) { erro(e) }
}
</script>

<template>
  <div>
    <div class="cabecalho">
      <div><h1>Exercícios</h1><p>{{ num(lista.length) }} exercícios · {{ num(semTraducao) }} sem tradução completa</p></div>
      <div class="linha">
        <button class="btn" @click="cat = { id: null, nome: '', nome_en: '', nome_es: '' }">Grupos musculares</button>
        <button class="btn primario" @click="novo"><Icone nome="mais" :tam="16" /> Novo exercício</button>
      </div>
    </div>

    <div class="linha" style="margin-bottom: 14px">
      <input v-model="busca" placeholder="Buscar (PT, EN ou ES)" style="max-width: 300px" />
      <select v-model="categoria" style="width: auto"><option value="">Todos os grupos</option><option v-for="c in categorias" :key="c.id" :value="c.id">{{ c.nome }} ({{ c.exercicios }})</option></select>
      <label class="linha-check"><input v-model="soSemTraducao" type="checkbox" /> Falta tradução</label>
      <label class="linha-check"><input v-model="soInativos" type="checkbox" /> Desativados</label>
    </div>

    <div v-if="carregando" class="carregando"><div class="spinner" /></div>
    <div v-else class="grade g4">
      <button v-for="e in filtrados.slice(0, limite)" :key="e.id" class="card ex" @click="editar(e)">
        <video v-if="ehVideo(e.media_url)" :src="e.media_url" muted preload="none" class="midia-ex" />
        <img v-else-if="e.media_url" :src="e.media_url" loading="lazy" class="midia-ex" alt="" />
        <div v-else class="midia-ex vazia"><Icone nome="imagem" :tam="26" /></div>
        <strong style="text-align: left">{{ e.nome }}</strong>
        <div class="linha" style="gap: 4px">
          <span class="tag">{{ e.categoria }}</span>
          <span v-if="!e.nome_en" class="tag ambar">sem EN</span>
          <span v-if="!e.nome_es" class="tag ambar">sem ES</span>
          <span v-if="!e.ativo" class="tag vermelho">desativado</span>
        </div>
      </button>
    </div>
    <div v-if="filtrados.length > limite" class="linha" style="justify-content: center; margin-top: 16px"><button class="btn" @click="limite += 60">Mostrar mais ({{ filtrados.length - limite }})</button></div>

    <Modal v-if="ex" :titulo="ex.id ? 'Editar exercício' : 'Novo exercício'" largura="620px" @fechar="ex = null">
      <div class="coluna">
        <label class="campo">Nome (português)<input v-model="ex.nome" /></label>
        <div class="grade g2">
          <label class="campo">Inglês<input v-model="ex.nome_en" /></label>
          <label class="campo">Espanhol<input v-model="ex.nome_es" /></label>
        </div>
        <label class="campo">Grupo muscular<select v-model="ex.categoria_id"><option v-for="c in categorias" :key="c.id" :value="c.id">{{ c.nome }}</option></select></label>
        <label class="campo">Mídia (GIF, WEBP, MP4)<input type="file" accept="image/*,video/mp4" @change="midia" /></label>
        <small v-if="enviando">Enviando…</small>
        <label class="campo">Ou cole o link<input v-model="ex.media_url" placeholder="https://cnd.valeapps.com.br/..." /></label>
        <video v-if="ehVideo(ex.media_url)" :src="ex.media_url" class="midia" autoplay loop muted />
        <img v-else-if="ex.media_url" :src="ex.media_url" class="midia" style="object-fit: contain" alt="" />
        <label class="linha-check"><input v-model="ex.ativo" type="checkbox" /> Ativo (aparece no app)</label>
        <button class="btn primario" :disabled="!ex.nome || !ex.categoria_id || enviando" @click="salvar">Salvar</button>
      </div>
    </Modal>

    <Modal v-if="cat" titulo="Grupos musculares" largura="620px" @fechar="cat = null">
      <div class="coluna">
        <div class="tabela-wrap" style="max-height: 280px; overflow-y: auto">
          <table><tbody>
            <tr v-for="c in categorias" :key="c.id" class="clicavel" @click="cat = { ...c }"><td><strong>{{ c.nome }}</strong></td><td><small>{{ c.nome_en || '—' }} · {{ c.nome_es || '—' }}</small></td><td class="num">{{ c.exercicios }}</td></tr>
          </tbody></table>
        </div>
        <h3>{{ cat.id ? 'Editar' : 'Novo grupo' }}</h3>
        <label class="campo">Nome<input v-model="cat.nome" /></label>
        <div class="grade g2"><label class="campo">Inglês<input v-model="cat.nome_en" /></label><label class="campo">Espanhol<input v-model="cat.nome_es" /></label></div>
        <div class="linha"><button class="btn primario" :disabled="!cat.nome" @click="salvarCat">Salvar</button><button v-if="cat.id" class="btn fantasma" @click="cat = { id: null, nome: '', nome_en: '', nome_es: '' }">Novo</button></div>
      </div>
    </Modal>
  </div>
</template>

<style scoped>
.ex { display: flex; flex-direction: column; gap: 8px; cursor: pointer; color: var(--text); font: inherit; text-align: left; padding: 12px; transition: border-color .15s, transform .1s; }
.ex:hover { border-color: var(--muted); transform: translateY(-1px); }
.midia-ex { width: 100%; aspect-ratio: 1; object-fit: cover; border-radius: 10px; background: var(--surface2); }
.midia-ex.vazia { display: grid; place-items: center; color: var(--muted); }
</style>
