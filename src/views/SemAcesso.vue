<script setup>
import { sessao, sair } from '../lib/supabase'
</script>
<template>
  <div style="min-height: 100%; display: grid; place-items: center; padding: 20px">
    <div class="card surge" style="width: min(420px, 100%); padding: 28px; text-align: center">
      <img src="/icone.svg" width="44" height="44" alt="" />
      <h1 style="margin-top: 12px; font-size: 22px">Sem acesso ao admin</h1>
      <p class="muted" style="margin: 8px 0 20px">
        A conta <strong style="color: var(--text)">{{ sessao.user?.email || 'atual' }}</strong> não faz parte da equipe do BroGym.
        Peça pra quem gerencia a equipe te adicionar.
      </p>
      <button class="btn primario" @click="sair">Sair e usar outra conta</button>
    </div>
  </div>
</template>
