<script setup>
import { ref, onMounted } from 'vue'
import { rpc, sb } from '../lib/supabase'
import { dataHora, paraInput, deInput, avisar, erro, confirmar } from '../lib/util'

const cfg = ref(null)
const atualizado = ref({})
const rotas = { '': 'Nenhuma', '/chat': 'Coach IA', '/social/eventos': 'Eventos', '/relatorio': 'Relatório da semana', '/paywall': 'Assinar PRO', '/convidar': 'Convidar amigos', '/dieta/cardapio': 'Cardápio' }

async function carregar() {
  const { data, error } = await sb.from('app_config').select('*')
  if (error) return erro(error)
  const m = Object.fromEntries(data.map((d) => [d.chave, d.valor]))
  atualizado.value = Object.fromEntries(data.map((d) => [d.chave, d.atualizado_em]))
  m.aviso = { ...m.aviso, ate: paraInput(m.aviso?.ate) }
  cfg.value = m
}
onMounted(carregar)

async function salvar(chave) {
  let valor = { ...cfg.value[chave] }
  if (chave === 'aviso') valor.ate = deInput(valor.ate)
  if (chave === 'manutencao' && valor.ativo) {
    if (!(await confirmar({ titulo: 'Ligar modo manutenção?', texto: 'Todo mundo que abrir o app vai ver a tela de manutenção e não vai conseguir usar até você desligar.', botao: 'Ligar manutenção', perigo: true, digitar: 'MANUTENCAO' }))) return
  }
  if (chave === 'versao_minima' && Number(valor.build) > 0) {
    if (!(await confirmar({ titulo: `Exigir build ${valor.build} ou maior?`, texto: 'Quem estiver numa versão mais antiga fica travado numa tela pedindo pra atualizar na Play Store. Confira se essa versão já está liberada pra todo mundo na loja.', botao: 'Exigir', perigo: true }))) return
  }
  try { await rpc('adm_config_salvar', { p_chave: chave, p_valor: valor }); avisar('Salvo. O app pega na próxima vez que abrir.'); carregar() } catch (e) { erro(e) }
}
</script>

<template>
  <div>
    <div class="cabecalho"><div><h1>Controle do app</h1><p>Muda o app na hora, sem lançar versão. Precisa da versão 2.0.9 ou maior do app.</p></div></div>
    <div v-if="!cfg" class="carregando"><div class="spinner" /></div>
    <div v-else class="grade g3">
      <div class="card coluna" :style="cfg.manutencao.ativo ? 'border-color: var(--accent)' : ''">
        <div class="linha entre"><h3>Modo manutenção</h3><span class="tag" :class="cfg.manutencao.ativo ? 'vermelho' : 'verde'">{{ cfg.manutencao.ativo ? 'LIGADO' : 'desligado' }}</span></div>
        <small>Trava o app com uma tela de aviso. Use em migração ou problema grave.</small>
        <label class="linha-check"><input v-model="cfg.manutencao.ativo" type="checkbox" /> Ligado</label>
        <label class="campo">Título<input v-model="cfg.manutencao.titulo" /></label>
        <label class="campo">Mensagem<textarea v-model="cfg.manutencao.mensagem" /></label>
        <button class="btn" :class="cfg.manutencao.ativo ? 'perigo' : 'primario'" @click="salvar('manutencao')">Salvar</button>
        <small>Atualizado {{ dataHora(atualizado.manutencao) }}</small>
      </div>

      <div class="card coluna">
        <div class="linha entre"><h3>Versão mínima</h3><span class="tag" :class="cfg.versao_minima.build > 0 ? 'ambar' : ''">{{ cfg.versao_minima.build > 0 ? 'build ' + cfg.versao_minima.build : 'livre' }}</span></div>
        <small>Quem estiver numa build menor que essa vê uma tela obrigando a atualizar. 0 = desligado.</small>
        <label class="campo">Build mínima (número depois do +, ex.: 2.0.9+<strong>42</strong>)<input v-model.number="cfg.versao_minima.build" type="number" min="0" /></label>
        <label class="campo">Mensagem<textarea v-model="cfg.versao_minima.mensagem" /></label>
        <button class="btn primario" @click="salvar('versao_minima')">Salvar</button>
        <small>Atualizado {{ dataHora(atualizado.versao_minima) }}</small>
      </div>

      <div class="card coluna">
        <div class="linha entre"><h3>Aviso na Home</h3><span class="tag" :class="cfg.aviso.ativo ? 'verde' : ''">{{ cfg.aviso.ativo ? 'no ar' : 'desligado' }}</span></div>
        <small>Um cartão no topo da Home. Bom pra promoção, evento ou novidade.</small>
        <label class="linha-check"><input v-model="cfg.aviso.ativo" type="checkbox" /> No ar</label>
        <label class="campo">Título<input v-model="cfg.aviso.titulo" maxlength="60" /></label>
        <label class="campo">Texto<textarea v-model="cfg.aviso.texto" maxlength="200" rows="2" /></label>
        <div class="grade g2">
          <label class="campo">Botão<input v-model="cfg.aviso.botao" maxlength="24" placeholder="Ex.: Ver evento" /></label>
          <label class="campo">Abre em<select v-model="cfg.aviso.rota"><option v-for="(n, k) in rotas" :key="k" :value="k">{{ n }}</option></select></label>
        </div>
        <div class="grade g2">
          <label class="campo">Pra quem<select v-model="cfg.aviso.publico"><option value="todos">Todos</option><option value="gratis">Só grátis</option><option value="pro">Só PRO</option></select></label>
          <label class="campo">Cor<input v-model="cfg.aviso.cor" type="color" style="height: 41px; padding: 4px" /></label>
        </div>
        <label class="campo">Sai do ar em (opcional)<input v-model="cfg.aviso.ate" type="datetime-local" /></label>
        <div class="previa" :style="{ borderColor: cfg.aviso.cor }">
          <strong>{{ cfg.aviso.titulo || 'Título do aviso' }}</strong>
          <small style="display: block">{{ cfg.aviso.texto || 'Texto do aviso' }}</small>
          <span v-if="cfg.aviso.botao" class="tag" :style="{ background: cfg.aviso.cor, color: '#fff', marginTop: '8px' }">{{ cfg.aviso.botao }}</span>
        </div>
        <button class="btn primario" @click="salvar('aviso')">Salvar</button>
        <small>Atualizado {{ dataHora(atualizado.aviso) }}</small>
      </div>
    </div>
  </div>
</template>

<style scoped>
.previa { border: 1px solid; border-left-width: 4px; border-radius: 12px; padding: 12px; background: var(--surface2); }
</style>
