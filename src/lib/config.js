// Chaves PÚBLICAS do Supabase (as mesmas do app). A segurança do painel fica no banco:
// toda função adm_* confere equipe, permissão e login com 2 etapas.
export const SUPABASE_URL = import.meta.env.VITE_SUPABASE_URL || 'https://soloxmcolcblqkerugas.supabase.co'
export const SUPABASE_ANON_KEY = import.meta.env.VITE_SUPABASE_ANON_KEY || 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNvbG94bWNvbGNibHFrZXJ1Z2FzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjY4ODg3ODgsImV4cCI6MjA4MjQ2NDc4OH0.cwqtLug_3oUn5xCqXiC6oRFiLf-NR1H6PmfLlJYutRE'

// Sai sozinho depois de 30 min parado.
export const INATIVIDADE_MIN = 30
