import { createRouter, createWebHistory } from 'vue-router'

// Cada tela diz a permissão que precisa. O menu e a rota escondem o que a pessoa não pode;
// mesmo assim, quem barra de verdade é o banco.
export const telas = [
  { path: '/', nome: 'Início', icone: 'inicio', perm: 'numeros.ver', grupo: 'Visão geral', component: () => import('./views/Inicio.vue') },
  { path: '/usuarios', nome: 'Usuários', icone: 'usuarios', perm: 'usuarios.ver', grupo: 'Pessoas', component: () => import('./views/Usuarios.vue') },
  { path: '/suporte', nome: 'Suporte', icone: 'suporte', perm: 'suporte.atender', grupo: 'Pessoas', selo: 'chamados', component: () => import('./views/Suporte.vue') },
  { path: '/comunidade', nome: 'Comunidade', icone: 'comunidade', perm: 'comunidade.moderar', grupo: 'Pessoas', selo: 'denuncias', component: () => import('./views/Comunidade.vue') },
  { path: '/exercicios', nome: 'Exercícios', icone: 'exercicios', perm: 'conteudo.exercicios', grupo: 'Conteúdo', component: () => import('./views/Exercicios.vue') },
  { path: '/eventos', nome: 'Eventos oficiais', icone: 'eventos', perm: 'conteudo.eventos', grupo: 'Conteúdo', component: () => import('./views/Eventos.vue') },
  { path: '/perguntas', nome: 'Pergunta do dia', icone: 'perguntas', perm: 'conteudo.perguntas', grupo: 'Conteúdo', component: () => import('./views/Perguntas.vue') },
  { path: '/push', nome: 'Enviar push', icone: 'push', perm: 'push.enviar', grupo: 'Conteúdo', component: () => import('./views/Push.vue') },
  { path: '/receita', nome: 'Assinaturas', icone: 'receita', perm: 'receita.ver', grupo: 'Negócio', component: () => import('./views/Receita.vue') },
  { path: '/ia', nome: 'Custo da IA', icone: 'ia', perm: 'ia.ver', grupo: 'Negócio', component: () => import('./views/IA.vue') },
  { path: '/app', nome: 'Controle do app', icone: 'app', perm: 'app.config', grupo: 'Negócio', component: () => import('./views/ControleApp.vue') },
  { path: '/equipe', nome: 'Equipe', icone: 'equipe', perm: 'equipe.gerenciar', grupo: 'Admin', component: () => import('./views/Equipe.vue') },
  { path: '/registro', nome: 'Registro', icone: 'registro', perm: 'log.ver', grupo: 'Admin', component: () => import('./views/Registro.vue') },
]

export const router = createRouter({
  history: createWebHistory(),
  routes: [
    ...telas.map((t) => ({ path: t.path, component: t.component, meta: { perm: t.perm, nome: t.nome } })),
    { path: '/usuarios/:id', component: () => import('./views/Usuario.vue'), meta: { perm: 'usuarios.ver', nome: 'Usuário' } },
    { path: '/:pathMatch(.*)*', redirect: '/' },
  ],
  scrollBehavior: () => ({ top: 0 }),
})
