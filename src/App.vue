<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { useRoute } from 'vue-router'
import { sessao, pode, sair, carregarSessao, rpc, sb } from './lib/supabase'
import { telas } from './router'
import Icone from './components/Icone.vue'
import Avisos from './components/Avisos.vue'
import Confirmacao from './components/Confirmacao.vue'
import Entrar from './views/Entrar.vue'
import DuasEtapas from './views/DuasEtapas.vue'
import SemAcesso from './views/SemAcesso.vue'

const route = useRoute()
const menuAberto = ref(false)
const selos = ref({ denuncias: 0, chamados: 0 })

const liberado = computed(() => sessao.user && sessao.eu?.membro && sessao.aal === 'aal2')
const grupos = computed(() => {
  const g = {}
  for (const t of telas.filter((t) => pode(t.perm))) (g[t.grupo] ??= []).push(t)
  return g
})

async function atualizarSelos() {
  if (!liberado.value) return
  try {
    if (pode('comunidade.moderar')) selos.value.denuncias = (await rpc('adm_denuncias'))?.length ?? 0
    if (pode('suporte.atender')) selos.value.chamados = (await rpc('adm_chamados', { p_status: 'aberto' }))?.length ?? 0
  } catch { /* silencioso */ }
}

let intervalo
onMounted(async () => {
  sb.auth.onAuthStateChange((ev) => { if (ev === 'SIGNED_IN' || ev === 'SIGNED_OUT' || ev === 'MFA_CHALLENGE_VERIFIED') carregarSessao() })
  if (sessao.carregando) await carregarSessao()
  atualizarSelos()
  intervalo = setInterval(atualizarSelos, 60000)
})
onUnmounted(() => clearInterval(intervalo))

const iniciais = computed(() => (sessao.eu?.nome || '?').split(' ').map((p) => p[0]).slice(0, 2).join('').toUpperCase())
</script>

<template>
  <div v-if="sessao.carregando" class="carregando" style="height: 100%"><div class="spinner" /></div>
  <Entrar v-else-if="!sessao.user" />
  <SemAcesso v-else-if="!sessao.eu?.membro" />
  <DuasEtapas v-else-if="sessao.aal !== 'aal2'" />

  <div v-else class="casca" :class="{ 'menu-aberto': menuAberto }">
    <aside class="lateral">
      <div class="marca">
        <img src="/icone.svg" alt="" width="30" height="30" />
        <div>
          <div class="titulo" style="font-size: 16px; font-weight: 800">BroGym</div>
          <small>Admin</small>
        </div>
      </div>
      <nav>
        <template v-for="(itens, grupo) in grupos" :key="grupo">
          <div class="grupo">{{ grupo }}</div>
          <RouterLink v-for="t in itens" :key="t.path" :to="t.path" class="item" :class="{ ativo: route.path === t.path || (t.path !== '/' && route.path.startsWith(t.path)) }" @click="menuAberto = false">
            <Icone :nome="t.icone" />
            <span class="espaco">{{ t.nome }}</span>
            <span v-if="t.selo && selos[t.selo]" class="tag vermelho">{{ selos[t.selo] }}</span>
          </RouterLink>
        </template>
      </nav>
      <div class="eu">
        <img v-if="sessao.eu.avatar" :src="sessao.eu.avatar" class="avatar" referrerpolicy="no-referrer" alt="" />
        <span v-else class="avatar">{{ iniciais }}</span>
        <div style="min-width: 0" class="espaco">
          <div class="corta" style="font-weight: 600; max-width: 140px">{{ sessao.eu.nome }}</div>
          <small>{{ sessao.eu.dono ? 'Dono' : sessao.eu.cargo || 'Equipe' }}</small>
        </div>
        <button class="btn fantasma pequeno" title="Sair" @click="sair"><Icone nome="sair" /></button>
      </div>
    </aside>

    <header class="topo-celular">
      <button class="btn fantasma" @click="menuAberto = !menuAberto"><Icone nome="menu" /></button>
      <strong class="titulo">BroGym Admin</strong>
    </header>
    <div class="veu" @click="menuAberto = false" />

    <main class="conteudo">
      <RouterView v-slot="{ Component }">
        <component :is="Component" @mudou="atualizarSelos" />
      </RouterView>
    </main>
  </div>

  <Avisos />
  <Confirmacao />
</template>

<style scoped>
.casca { display: grid; grid-template-columns: 248px 1fr; min-height: 100%; }
.lateral { position: sticky; top: 0; height: 100vh; display: flex; flex-direction: column; border-right: 1px solid var(--line); background: var(--surface); padding: 16px 12px; gap: 8px; }
.marca { display: flex; align-items: center; gap: 10px; padding: 4px 8px 12px; }
nav { flex: 1; overflow-y: auto; display: flex; flex-direction: column; gap: 2px; }
.grupo { font: 600 10.5px Inter, sans-serif; text-transform: uppercase; letter-spacing: .08em; color: var(--muted); padding: 14px 10px 6px; }
.item { display: flex; align-items: center; gap: 10px; padding: 9px 10px; border-radius: 10px; color: var(--muted); font-weight: 600; font-size: 13.5px; transition: background .12s, color .12s; }
.item:hover { background: var(--surface2); color: var(--text); }
.item.ativo { background: var(--accent-soft); color: var(--accent-text); }
.eu { display: flex; align-items: center; gap: 10px; border-top: 1px solid var(--line); padding: 12px 6px 0; }
.conteudo { padding: 28px 32px 60px; max-width: 1280px; width: 100%; }
.topo-celular, .veu { display: none; }
@media (max-width: 900px) {
  .casca { grid-template-columns: 1fr; }
  .lateral { position: fixed; z-index: 40; left: 0; top: 0; width: 260px; transform: translateX(-100%); transition: transform .2s; }
  .menu-aberto .lateral { transform: none; }
  .menu-aberto .veu { display: block; position: fixed; inset: 0; background: rgba(0,0,0,.5); z-index: 30; }
  .topo-celular { display: flex; align-items: center; gap: 8px; padding: 10px 12px; border-bottom: 1px solid var(--line); position: sticky; top: 0; background: var(--bg); z-index: 20; }
  .conteudo { padding: 18px 14px 50px; }
}
</style>
