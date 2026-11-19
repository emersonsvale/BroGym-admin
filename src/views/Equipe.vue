<script setup>
import { ref, computed, onMounted } from 'vue'
import { rpc, sessao, pode } from '../lib/supabase'
import { data, avisar, erro, confirmar } from '../lib/util'
import Avatar from '../components/Avatar.vue'
import Icone from '../components/Icone.vue'
import Modal from '../components/Modal.vue'

const equipe = ref([])
const catalogo = ref([])
const pessoa = ref(null)
const carregando = ref(true)

async function carregar() {
  carregando.value = true
  try { [equipe.value, catalogo.value] = await Promise.all([rpc('adm_equipe_listar'), rpc('adm_catalogo')]) } catch (e) { erro(e) } finally { carregando.value = false }
}
onMounted(carregar)

const grupos = computed(() => {
  const g = {}
  for (const c of catalogo.value) (g[c.grupo] ??= []).push(c)
  return g
})
// Pacotes prontos pra agilizar (dá pra ajustar item por item depois).
const pacotes = {
  Moderador: ['comunidade.moderar', 'usuarios.ver', 'usuarios.banir'],
  Suporte: ['suporte.atender', 'usuarios.ver', 'usuarios.pro'],
  Conteúdo: ['conteudo.exercicios', 'conteudo.eventos', 'conteudo.perguntas', 'push.enviar'],
  Marketing: ['numeros.ver', 'push.enviar', 'conteudo.eventos'],
  Financeiro: ['numeros.ver', 'receita.ver', 'ia.ver'],
}

function nova() { pessoa.value = { novo: true, quem: '', cargo: '', ativo: true, permissoes: [] } }
function editar(m) { pessoa.value = { novo: false, quem: m.email, nome: m.nome, cargo: m.cargo || '', ativo: m.ativo, permissoes: [...m.permissoes], dono: m.dono, user_id: m.user_id } }
function alternar(p) {
  const l = pessoa.value.permissoes
  const i = l.indexOf(p)
  i >= 0 ? l.splice(i, 1) : l.push(p)
}
function aplicarPacote(lista) { pessoa.value.permissoes = [...new Set([...pessoa.value.permissoes, ...lista.filter((p) => pode(p))])] }

async function salvar() {
  try {
    await rpc('adm_equipe_salvar', { p_quem: pessoa.value.quem, p_cargo: pessoa.value.cargo, p_permissoes: pessoa.value.permissoes, p_ativo: pessoa.value.ativo })
    avisar(pessoa.value.novo ? 'Pessoa adicionada. No primeiro acesso ela cadastra o código de 2 etapas.' : 'Acesso atualizado.')
    pessoa.value = null; carregar()
  } catch (e) { erro(e) }
}
async function remover() {
  if (!(await confirmar({ titulo: `Tirar ${pessoa.value.nome} da equipe?`, texto: 'Ela perde o acesso ao admin na hora.', botao: 'Tirar da equipe', perigo: true }))) return
  try { await rpc('adm_equipe_remover', { p_user: pessoa.value.user_id }); avisar('Removida da equipe.'); pessoa.value = null; carregar() } catch (e) { erro(e) }
}
const nomePerm = (p) => catalogo.value.find((c) => c.permissao === p)?.nome || p
</script>

<template>
  <div>
    <div class="cabecalho">
      <div><h1>Equipe</h1><p>Quem entra no admin e o que cada um pode fazer. Todo mundo usa código de 2 etapas.</p></div>
      <button class="btn primario" @click="nova"><Icone nome="mais" :tam="16" /> Adicionar pessoa</button>
    </div>
    <div v-if="carregando" class="carregando"><div class="spinner" /></div>
    <div v-else class="tabela-wrap">
      <table>
        <thead><tr><th>Pessoa</th><th>Pode</th><th>2 etapas</th><th>Desde</th></tr></thead>
        <tbody>
          <tr v-for="m in equipe" :key="m.user_id" class="clicavel" @click="editar(m)">
            <td>
              <div class="linha" style="flex-wrap: nowrap">
                <Avatar :src="m.avatar" :nome="m.nome" />
                <div><strong>{{ m.nome }}</strong> <span v-if="m.dono" class="tag vermelho">Dono</span><span v-else-if="!m.ativo" class="tag">desativado</span><br /><small>{{ m.cargo || '—' }} · {{ m.email }}</small></div>
              </div>
            </td>
            <td>
              <span v-if="m.dono" class="tag ouro">Tudo</span>
              <div v-else class="linha" style="gap: 4px"><span v-for="p in m.permissoes" :key="p" class="tag">{{ nomePerm(p) }}</span><small v-if="!m.permissoes.length">Nada ainda</small></div>
            </td>
            <td><span class="tag" :class="m.tem_2fa ? 'verde' : 'ambar'">{{ m.tem_2fa ? 'Ativo' : 'Falta cadastrar' }}</span></td>
            <td><small>{{ data(m.criado_em) }}</small></td>
          </tr>
        </tbody>
      </table>
    </div>

    <Modal v-if="pessoa" :titulo="pessoa.novo ? 'Adicionar à equipe' : pessoa.nome" largura="680px" @fechar="pessoa = null">
      <div class="coluna">
        <template v-if="pessoa.novo">
          <label class="campo">E-mail ou @ da pessoa no BroGym<input v-model="pessoa.quem" placeholder="nome@email.com ou @usuario" /></label>
          <small>A pessoa precisa ter conta salva no app (com Google ou e-mail).</small>
        </template>
        <div v-if="pessoa.dono" class="card" style="background: var(--surface2)">Dono tem acesso a tudo e não pode ser removido.</div>
        <template v-else>
          <div class="grade g2">
            <label class="campo">Cargo<input v-model="pessoa.cargo" placeholder="Ex.: Moderadora, Suporte" /></label>
            <label class="linha-check" style="align-self: end; padding-bottom: 10px"><input v-model="pessoa.ativo" type="checkbox" :disabled="pessoa.user_id === sessao.user?.id" /> Acesso ativo</label>
          </div>
          <div>
            <small style="font-weight: 600">Atalhos</small>
            <div class="linha" style="gap: 6px; margin-top: 6px">
              <button v-for="(l, n) in pacotes" :key="n" class="btn pequeno" @click="aplicarPacote(l)">+ {{ n }}</button>
              <button class="btn pequeno fantasma" @click="pessoa.permissoes = []">Limpar</button>
            </div>
          </div>
          <div v-for="(itens, g) in grupos" :key="g">
            <h3 style="margin: 8px 0 6px">{{ g }}</h3>
            <label v-for="c in itens" :key="c.permissao" class="perm" :class="{ off: !pode(c.permissao) }">
              <input type="checkbox" :checked="pessoa.permissoes.includes(c.permissao)" :disabled="!pode(c.permissao)" @change="alternar(c.permissao)" />
              <div><strong>{{ c.nome }}</strong><small style="display: block">{{ c.descricao }}</small></div>
              <span v-if="['usuarios.apagar', 'equipe.gerenciar', 'push.enviar', 'app.config'].includes(c.permissao)" class="tag vermelho">sensível</span>
            </label>
          </div>
        </template>
        <div class="linha">
          <button v-if="!pessoa.dono" class="btn primario" :disabled="!pessoa.quem" @click="salvar">Salvar</button>
          <span class="espaco" />
          <button v-if="!pessoa.novo && !pessoa.dono && pessoa.user_id !== sessao.user?.id" class="btn perigo" @click="remover">Tirar da equipe</button>
        </div>
      </div>
    </Modal>
  </div>
</template>

<style scoped>
.perm { display: flex; align-items: center; gap: 12px; padding: 10px 12px; border: 1px solid var(--line); border-radius: 10px; margin-bottom: 6px; cursor: pointer; }
.perm:hover { border-color: var(--muted); }
.perm.off { opacity: .45; cursor: not-allowed; }
.perm div { flex: 1; }
</style>
