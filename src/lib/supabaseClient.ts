import { createClient } from '@supabase/supabase-js'

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY

if (!supabaseUrl || !supabaseAnonKey) {
  throw new Error('VITE_SUPABASE_URL e VITE_SUPABASE_ANON_KEY precisam estar definidas (ver .env.example).')
}

// O AgendaServ vive no schema "agendaserv" do projeto Supabase compartilhado com o iCaixa.
// Os tipos (src/types/database.types.ts) serão gerados com `supabase gen types --schema agendaserv`.
export const supabase = createClient(supabaseUrl, supabaseAnonKey, {
  db: { schema: 'agendaserv' },
  auth: { storageKey: 'agendaserv-auth' },
})
