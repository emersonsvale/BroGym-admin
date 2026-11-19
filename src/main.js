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

// Saiu versão nova do painel com a página aberta: recarrega uma vez em vez de quebrar.
window.addEventListener('vite:preloadError', (e) => {
  e.preventDefault()
  if (!sessionStorage.getItem('recarregou')) { sessionStorage.setItem('recarregou', '1'); location.reload() }
})
window.addEventListener('load', () => setTimeout(() => sessionStorage.removeItem('recarregou'), 5000))

vigiarInatividade()
createApp(App).use(router).mount('#app')
