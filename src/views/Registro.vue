<script setup>
import { ref, onMounted, watch } from 'vue'
import { rpc } from '../lib/supabase'
import { dataHora, erro } from '../lib/util'

const lista = ref([])
const busca = ref('')
const carregando = ref(true)
const fim = ref(false)
const aberto = ref(null)

const nomes = {
  'equipe.salvar': 'Mudou acesso da equipe', 'equipe.remover': 'Tirou da equipe', 'usuario.pro': 'Deu/tirou PRO', 'usuario.editar': 'Editou usuário',
  'usuario.pontos': 'Ajustou pontos', 'usuario.banir': 'Baniu', 'usuario.desbanir': 'Desbaniu', 'usuario.apagar': 'Apagou conta',
  'denuncia.remover': 'Removeu denunciado', 'denuncia.ignorar': 'Ignorou denúncia', 'comunidade.apagar_post': 'Apagou post', 'comunidade.apagar_story': 'Apagou story',
  'comunidade.apagar_comentario': 'Apagou comentário', 'grupo.salvar': 'Salvou grupo', 'grupo.apagar': 'Apagou grupo', 'exercicio.salvar': 'Salvou exercício',
  'categoria.salvar': 'Salvou grupo muscular', 'evento.salvar': 'Salvou evento', 'evento.cancelar': 'Cancelou evento', 'evento.reativar': 'Reativou evento',
  'pergunta.salvar': 'Salvou pergunta', 'pergunta.apagar': 'Apagou pergunta', 'push.enviar': 'Enviou push', 'config.manutencao': 'Mudou manutenção',
  'config.versao_minima': 'Mudou versão mínima', 'config.aviso': 'Mudou aviso da Home', 'suporte.responder': 'Respondeu chamado', 'suporte.status': 'Mudou status do chamado', 'sistema.limpar_anonimos': 'Limpeza automática de contas sem cadastro',
}
const perigosas = ['usuario.apagar', 'usuario.banir', 'push.enviar', 'config.manutencao', 'equipe.salvar', 'equipe.remover']

async function carregar(mais = false) {
  carregando.value = true
  try {
    const novos = await rpc('adm_log_listar', { p_limite: 100, p_antes: mais ? lista.value.at(-1)?.id : null, p_busca: busca.value || null })
    lista.value = mais ? [...lista.value, ...novos] : novos
    fim.value = novos.length < 100
  } catch (e) { erro(e) } finally { carregando.value = false }
}
let t
watch(busca, () => { clearTimeout(t); t = setTimeout(() => carregar(), 300) })
onMounted(() => carregar())
</script>

<template>
  <div>
    <div class="cabecalho"><div><h1>Registro</h1><p>Tudo que a equipe muda no admin fica aqui. Ninguém apaga.</p></div></div>
    <input v-model="busca" placeholder="Filtrar por ação ou pessoa" style="max-width: 320px; margin-bottom: 14px" />
    <div class="tabela-wrap">
      <table>
        <thead><tr><th>Quando</th><th>Quem</th><th>O quê</th><th>Alvo</th></tr></thead>
        <tbody>
          <template v-for="l in lista" :key="l.id">
            <tr class="clicavel" @click="aberto = aberto === l.id ? null : l.id">
              <td><small>{{ dataHora(l.em) }}</small></td>
              <td>{{ l.quem || '—' }}</td>
              <td><span class="tag" :class="perigosas.includes(l.acao) ? 'vermelho' : ''">{{ nomes[l.acao] || l.acao }}</span></td>
              <td><RouterLink v-if="l.alvo_nome" :to="`/usuarios/${l.alvo}`" @click.stop>{{ l.alvo_nome }}</RouterLink><small v-else class="corta" style="display: block; max-width: 260px">{{ l.detalhes?.titulo || l.detalhes?.nome || l.alvo }}</small></td>
            </tr>
            <tr v-if="aberto === l.id"><td colspan="4"><pre class="det">{{ JSON.stringify(l.detalhes, null, 2) }}</pre></td></tr>
          </template>
          <tr v-if="!lista.length && !carregando"><td colspan="4" class="vazio">Nada registrado ainda.</td></tr>
        </tbody>
      </table>
    </div>
    <div v-if="!fim && lista.length" class="linha" style="justify-content: center; margin-top: 14px"><button class="btn" :disabled="carregando" @click="carregar(true)">Carregar mais</button></div>
  </div>
</template>

<style scoped>
.det { margin: 0; background: var(--surface2); padding: 12px; border-radius: 10px; font-size: 12px; overflow-x: auto; }
</style>
