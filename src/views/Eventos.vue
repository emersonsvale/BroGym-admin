<script setup>
import { ref, computed, onMounted } from 'vue'
import { rpc, enviarMidia } from '../lib/supabase'
import { num, data, dataHora, paraInput, deInput, avisar, erro, confirmar } from '../lib/util'
import Icone from '../components/Icone.vue'
import Modal from '../components/Modal.vue'

const lista = ref([])
const soOficiais = ref(true)
const carregando = ref(true)
const ev = ref(null)
const enviando = ref(false)

async function carregar() {
  carregando.value = true
  try { lista.value = await rpc('adm_eventos', { p_so_oficiais: soOficiais.value }) } catch (e) { erro(e) } finally { carregando.value = false }
}
onMounted(carregar)

const tipos = { corrida: 'Corrida', caminhada: 'Caminhada', ciclismo: 'Ciclismo', crossfit: 'Crossfit', treino: 'Treino junto' }
const status = (e) => e.cancelado ? ['Cancelado', 'vermelho'] : e.fechado_em ? ['Encerrado', ''] : new Date(e.inicio) > new Date() ? ['Em breve', 'ciano'] : new Date(e.fim) > new Date() ? ['Acontecendo', 'verde'] : ['Terminou', '']

function novo() {
  const ini = new Date(Date.now() + 7 * 864e5); ini.setHours(7, 0, 0, 0)
  const fim = new Date(ini.getTime() + 3 * 3600e3)
  ev.value = { id: null, titulo: '', descricao: '', tipo: 'corrida', inicio: paraInput(ini), fim: paraInput(fim), local_nome: '', lat: null, lng: null, meta_km: null, placar: 'maior', premio: '', publico: true, capa_url: '', conta_treinos: false, em_dupla: false }
}
function editar(e) { ev.value = { ...e, inicio: paraInput(e.inicio), fim: paraInput(e.fim) } }
async function capa(x) {
  const a = x.target.files?.[0]; if (!a) return
  enviando.value = true
  try { ev.value.capa_url = await enviarMidia(a, 'eventos') } catch (e) { erro(e) } finally { enviando.value = false }
}
const duracaoOk = computed(() => {
  if (!ev.value) return true
  const i = new Date(deInput(ev.value.inicio)), f = new Date(deInput(ev.value.fim))
  return f > i && f - i <= 31 * 864e5
})
async function salvar() {
  try {
    const d = { ...ev.value, inicio: deInput(ev.value.inicio), fim: deInput(ev.value.fim), meta_km: ev.value.meta_km || null, lat: ev.value.lat || null, lng: ev.value.lng || null }
    await rpc('adm_evento_salvar', { p_id: ev.value.id, p_dados: d })
    avisar('Evento salvo.'); ev.value = null; carregar()
  } catch (e) { erro(e) }
}
async function cancelar(e, valor) {
  if (valor && !(await confirmar({ titulo: `Cancelar "${e.titulo}"?`, texto: `${e.inscritos} inscritos. O evento some da lista do app.`, botao: 'Cancelar evento', perigo: true }))) return
  try { await rpc('adm_evento_cancelar', { p_id: e.id, p_cancelar: valor }); avisar(valor ? 'Evento cancelado.' : 'Evento reativado.'); carregar() } catch (x) { erro(x) }
}
</script>

<template>
  <div>
    <div class="cabecalho">
      <div><h1>Eventos oficiais</h1><p>Eventos com selo do BroGym. Organizador: conta @brogym.</p></div>
      <div class="linha">
        <label class="linha-check"><input v-model="soOficiais" type="checkbox" @change="carregar" /> Só oficiais</label>
        <button class="btn primario" @click="novo"><Icone nome="mais" :tam="16" /> Novo evento</button>
      </div>
    </div>

    <div v-if="carregando" class="carregando"><div class="spinner" /></div>
    <div v-else class="grade g3">
      <div v-for="e in lista" :key="e.id" class="card coluna">
        <img v-if="e.capa_url" :src="e.capa_url" class="midia" style="max-height: 150px" alt="" />
        <div class="linha">
          <span class="tag" :class="status(e)[1]">{{ status(e)[0] }}</span>
          <span class="tag">{{ tipos[e.tipo] }}</span>
          <span v-if="e.oficial" class="tag vermelho">Oficial</span>
          <span v-if="e.em_dupla" class="tag ouro">Dupla</span>
        </div>
        <h3>{{ e.titulo }}</h3>
        <small>{{ dataHora(e.inicio) }} → {{ dataHora(e.fim) }}</small>
        <small>{{ num(e.inscritos) }} inscritos · código <code>{{ e.codigo }}</code>{{ e.oficial ? '' : ' · por ' + (e.criador || '—') }}</small>
        <div class="linha" style="margin-top: auto">
          <button v-if="e.oficial && !e.fechado_em" class="btn pequeno" @click="editar(e)">Editar</button>
          <button v-if="!e.cancelado && !e.fechado_em" class="btn perigo pequeno" @click="cancelar(e, true)">Cancelar</button>
          <button v-if="e.cancelado" class="btn pequeno" @click="cancelar(e, false)">Reativar</button>
        </div>
      </div>
      <div v-if="!lista.length" class="card vazio" style="grid-column: 1 / -1">Nenhum evento.</div>
    </div>

    <Modal v-if="ev" :titulo="ev.id ? 'Editar evento oficial' : 'Novo evento oficial'" largura="640px" @fechar="ev = null">
      <div class="coluna">
        <label class="campo">Título<input v-model="ev.titulo" maxlength="60" /></label>
        <label class="campo">Descrição<textarea v-model="ev.descricao" maxlength="600" /></label>
        <div class="grade g2">
          <label class="campo">Tipo<select v-model="ev.tipo"><option v-for="(n, k) in tipos" :key="k" :value="k">{{ n }}</option></select></label>
          <label class="campo">Placar<select v-model="ev.placar"><option value="maior">Maior vence (km, treinos)</option><option value="menor">Menor vence (tempo)</option></select></label>
          <label class="campo">Começa (Brasília)<input v-model="ev.inicio" type="datetime-local" /></label>
          <label class="campo">Termina (Brasília)<input v-model="ev.fim" type="datetime-local" /></label>
        </div>
        <small v-if="!duracaoOk" style="color: var(--accent-text)">O fim precisa ser depois do início, e o evento dura no máximo 31 dias.</small>
        <div class="grade g3">
          <label class="campo">Meta em km<input v-model.number="ev.meta_km" type="number" step="0.5" /></label>
          <label class="campo">Latitude<input v-model.number="ev.lat" type="number" step="any" /></label>
          <label class="campo">Longitude<input v-model.number="ev.lng" type="number" step="any" /></label>
        </div>
        <label class="campo">Local<input v-model="ev.local_nome" placeholder="Ex.: Beira-Rio, Imperatriz" /></label>
        <label class="campo">Prêmio<input v-model="ev.premio" placeholder="Ex.: medalha no app + kit do patrocinador" /></label>
        <div class="linha">
          <label class="linha-check"><input v-model="ev.publico" type="checkbox" /> Público</label>
          <label class="linha-check"><input v-model="ev.conta_treinos" type="checkbox" /> Placar = dias com treino</label>
          <label class="linha-check"><input v-model="ev.em_dupla" type="checkbox" /> Inscrição em dupla</label>
        </div>
        <label class="campo">Capa<input type="file" accept="image/*" @change="capa" /></label>
        <img v-if="ev.capa_url" :src="ev.capa_url" class="midia" alt="" />
        <button class="btn primario" :disabled="!ev.titulo || !duracaoOk || enviando" @click="salvar">Salvar evento</button>
      </div>
    </Modal>
  </div>
</template>
