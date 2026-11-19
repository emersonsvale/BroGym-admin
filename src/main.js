import { createApp } from 'vue'
import App from './App.vue'
import { router, telas } from './router'
import { sessao, pode, carregarSessao, vigiarInatividade } from './lib/supabase'
import './style.css'

// Rota sem permissão vai pra primeira tela que a pessoa pode ver.
router.beforeEach(async (to) => {
  if (sessao.carregando) await carregarSessao()
  if (!sessao.eu?.membro || sessao.aal !== 'aal2') return true // App.vue mostra login / 2 etapas
  if (to.meta?.perm && !pode(to.meta.perm)) {
    const primeira = telas.find((t) => pode(t.perm))
    return primeira && primeira.path !== to.path ? primeira.path : true
  }
  return true
})

router.afterEach((to) => { document.title = `${to.meta?.nome ?? 'Admin'} · BroGym Admin` })

vigiarInatividade()
createApp(App).use(router).mount('#app')
