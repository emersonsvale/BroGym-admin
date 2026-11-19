import { createClient } from '@supabase/supabase-js'
import { reactive } from 'vue'
import { SUPABASE_URL, SUPABASE_ANON_KEY, INATIVIDADE_MIN } from './config'

export const sb = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: true,
    flowType: 'pkce',
    // Sessão do painel separada da de qualquer outro site.
    storageKey: 'brogym-admin-auth',
  },
})

// Estado da sessão do painel.
export const sessao = reactive({
  carregando: true,
  user: null,
  eu: null, // retorno de adm_eu()
  aal: 'aal1',
  temFator: false,
})

export const pode = (perm) => !!sessao.eu?.permissoes?.includes(perm)

const traduzir = (msg = '') => {
  if (msg.includes('SEM_PERMISSAO')) return 'Você não tem permissão pra isso.'
  if (msg.includes('JWT expired')) return 'Sua sessão expirou. Entre de novo.'
  if (msg.includes('Failed to fetch')) return 'Sem conexão com o servidor.'
  return msg
}

// Chama uma função adm_* e devolve os dados (ou lança erro já traduzido).
export async function rpc(nome, args = {}) {
  const { data, error } = await sb.rpc(nome, args)
  if (error) throw new Error(traduzir(error.message))
  return data
}

export async function carregarSessao() {
  sessao.carregando = true
  try {
    const { data: { session } } = await sb.auth.getSession()
    sessao.user = session?.user ?? null
    if (!sessao.user) { sessao.eu = null; return }
    const { data: aal } = await sb.auth.mfa.getAuthenticatorAssuranceLevel()
    sessao.aal = aal?.currentLevel ?? 'aal1'
    const { data: fatores } = await sb.auth.mfa.listFactors()
    sessao.temFator = (fatores?.totp ?? []).some((f) => f.status === 'verified')
    sessao.eu = await rpc('adm_eu')
  } catch (e) {
    console.error(e)
    sessao.eu = null
  } finally {
    sessao.carregando = false
  }
}

export async function sair() {
  await sb.auth.signOut()
  sessao.user = null
  sessao.eu = null
  sessao.aal = 'aal1'
  location.href = '/'
}

// Saída automática por inatividade.
let timer
export function vigiarInatividade() {
  const reiniciar = () => {
    clearTimeout(timer)
    timer = setTimeout(() => { if (sessao.user) sair() }, INATIVIDADE_MIN * 60 * 1000)
  }
  ;['click', 'keydown', 'mousemove', 'touchstart', 'scroll'].forEach((ev) => window.addEventListener(ev, reiniciar, { passive: true }))
  reiniciar()
}

// Envia arquivo pro bucket público do painel e devolve a URL.
export async function enviarMidia(arquivo, pasta = 'geral') {
  const ext = (arquivo.name.split('.').pop() || 'bin').toLowerCase()
  const caminho = `${pasta}/${Date.now()}-${Math.random().toString(36).slice(2, 8)}.${ext}`
  const { error } = await sb.storage.from('admin-midias').upload(caminho, arquivo, { contentType: arquivo.type, upsert: false })
  if (error) throw new Error(traduzir(error.message))
  return sb.storage.from('admin-midias').getPublicUrl(caminho).data.publicUrl
}
