<script setup>
import { ref, onMounted, nextTick } from 'vue'
import { sb, sessao, carregarSessao, sair } from '../lib/supabase'

const modo = ref('carregando') // cadastrar | verificar
const qr = ref('')
const segredo = ref('')
const fatorId = ref('')
const codigo = ref('')
const ocupado = ref(false)
const msgErro = ref('')
const campo = ref(null)

onMounted(async () => {
  const { data } = await sb.auth.mfa.listFactors()
  const verificado = (data?.totp ?? []).find((f) => f.status === 'verified')
  if (verificado) {
    fatorId.value = verificado.id
    modo.value = 'verificar'
  } else {
    // Limpa tentativas de cadastro que ficaram pela metade.
    for (const f of (data?.all ?? []).filter((f) => f.status !== 'verified')) await sb.auth.mfa.unenroll({ factorId: f.id })
    const { data: novo, error } = await sb.auth.mfa.enroll({ factorType: 'totp', friendlyName: `BroGym Admin ${Date.now()}`, issuer: 'BroGym Admin' })
    if (error) { msgErro.value = error.message; modo.value = 'erro'; return }
    fatorId.value = novo.id
    qr.value = novo.totp.qr_code
    segredo.value = novo.totp.secret
    modo.value = 'cadastrar'
  }
  await nextTick()
  campo.value?.focus()
})

async function confirmar() {
  msgErro.value = ''
  const c = codigo.value.replace(/\D/g, '')
  if (c.length !== 6) { msgErro.value = 'O código tem 6 números.'; return }
  ocupado.value = true
  const { error } = await sb.auth.mfa.challengeAndVerify({ factorId: fatorId.value, code: c })
  ocupado.value = false
  if (error) { msgErro.value = 'Código errado ou vencido. Tenta o próximo.'; codigo.value = ''; return }
  await carregarSessao()
  location.replace('/')
}
</script>

<template>
  <div class="tela">
    <div class="card surge caixa">
      <img src="/icone.svg" width="44" height="44" alt="" />
      <h1 style="margin-top: 12px; font-size: 22px">Verificação em 2 etapas</h1>
      <p class="muted" style="margin: 6px 0 18px">Olá, {{ sessao.eu?.nome?.split(' ')[0] }}. Todo acesso ao admin pede um código do seu app autenticador.</p>

      <div v-if="modo === 'carregando'" class="carregando"><div class="spinner" /></div>

      <template v-else-if="modo === 'cadastrar'">
        <ol class="passos">
          <li>Abra o <strong>Google Authenticator</strong>, Microsoft Authenticator ou 1Password.</li>
          <li>Leia o QR Code abaixo (ou digite a chave).</li>
          <li>Digite o código de 6 números que aparecer.</li>
        </ol>
        <div class="qr"><img :src="qr" alt="QR Code" width="180" height="180" /></div>
        <p class="muted" style="font-size: 12px; margin: 8px 0 16px">Chave: <code style="user-select: all">{{ segredo }}</code></p>
      </template>

      <template v-if="modo === 'cadastrar' || modo === 'verificar'">
        <input ref="campo" v-model="codigo" class="codigo" inputmode="numeric" maxlength="7" placeholder="000000" autocomplete="one-time-code" @keydown.enter="confirmar" />
        <button class="btn primario grande" style="width: 100%; justify-content: center; margin-top: 12px" :disabled="ocupado" @click="confirmar">
          {{ ocupado ? 'Conferindo…' : 'Entrar' }}
        </button>
      </template>

      <p v-if="msgErro" style="color: var(--accent-text); margin: 12px 0 0">{{ msgErro }}</p>
      <button class="btn fantasma pequeno" style="margin-top: 16px" @click="sair">Usar outra conta</button>
    </div>
  </div>
</template>

<style scoped>
.tela { min-height: 100%; display: grid; place-items: center; padding: 20px; }
.caixa { width: min(420px, 100%); padding: 28px; text-align: center; }
.passos { text-align: left; padding-left: 18px; color: var(--muted); margin: 0 0 14px; display: grid; gap: 4px; }
.passos strong { color: var(--text); }
.qr { background: #fff; border-radius: 14px; padding: 10px; display: inline-block; }
.codigo { text-align: center; font: 700 26px 'Inter Tight', sans-serif; letter-spacing: .35em; padding: 12px; }
</style>
