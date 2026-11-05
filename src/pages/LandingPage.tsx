import { PERIODOS } from '../lib/periodos'

export default function LandingPage() {
  return (
    <main className="mx-auto flex min-h-full max-w-md flex-col justify-center gap-8 px-6 py-12">
      <div className="flex items-center gap-3">
        <img src="/favicon.svg" alt="" className="h-12 w-12" />
        <div>
          <h1 className="text-2xl font-bold text-marca-900">AgendaServ</h1>
          <p className="text-sm text-slate-500">Serviços no seu condomínio, sem complicação</p>
        </div>
      </div>

      <ul className="space-y-3 text-slate-700">
        <li>Peça arrumadeira, encanador, eletricista e outros serviços pelo celular.</li>
        <li>
          Escolha o profissional, a data e o período ({PERIODOS.manha.rotulo} das {PERIODOS.manha.inicio} às{' '}
          {PERIODOS.manha.fim} ou {PERIODOS.tarde.rotulo.toLowerCase()} das {PERIODOS.tarde.inicio} às{' '}
          {PERIODOS.tarde.fim}).
        </li>
        <li>A administração confirma e você recebe o aviso no WhatsApp.</li>
      </ul>

      <button
        type="button"
        disabled
        className="rounded-xl bg-marca-700 px-4 py-3 font-semibold text-white opacity-60"
      >
        Entrar com celular (em breve)
      </button>
    </main>
  )
}
