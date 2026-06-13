-- Persistência das respostas do formulário de briefing da SEMEP no Supabase.
-- Mesmo padrão de segurança do sistema de chamados do site IAQueAtende:
--   tabela com RLS + deny policies para anon/authenticated, sem acesso direto;
--   gravação SOMENTE via função (RPC) SECURITY DEFINER com search_path travado.
-- Rodar no Supabase Studio (SQL Editor). É idempotente — pode rodar mais de uma vez.

-- ── 1) Tabela ──────────────────────────────────────────────────────────────
create table if not exists public.semep_briefing (
  id                uuid primary key default gen_random_uuid(),
  nome              text not null,
  cargo             text,
  psicologos        text,
  tipo_atendimento  text,
  planos            text,
  precos_whatsapp   text,
  agendamento_hoje  text,
  ordem_chegada     text,
  medico_fixo       text,
  intervalo_minimo  text,
  problemas         text,
  horario           text,
  relatorios        text,
  observacoes       text,
  criado_em         timestamptz not null default now()
);

-- ── 2) RLS: ninguém acessa a tabela diretamente (só via RPC abaixo) ──────────
alter table public.semep_briefing enable row level security;

drop policy if exists anon_deny_semep on public.semep_briefing;
create policy anon_deny_semep on public.semep_briefing
  for all to anon using (false) with check (false);

drop policy if exists auth_deny_semep on public.semep_briefing;
create policy auth_deny_semep on public.semep_briefing
  for all to authenticated using (false) with check (false);

-- service_role (uso interno / Studio) mantém acesso total
grant all on public.semep_briefing to service_role;

-- Remove qualquer acesso direto de anon/authenticated (gravação é só via RPC)
revoke select, insert, update, delete on public.semep_briefing from anon, authenticated, public;

-- ── 3) RPC de gravação (SECURITY DEFINER — roda como dono, ignora RLS) ───────
create or replace function public.salvar_briefing_semep(
  p_nome text, p_cargo text, p_psicologos text, p_tipo text, p_planos text,
  p_precos text, p_agendamento text, p_ordem text, p_medico_fixo text,
  p_intervalo text, p_problemas text, p_horario text, p_relatorios text,
  p_observacoes text
) returns boolean
language plpgsql security definer set search_path = public as $$
declare
  v_recent int;
begin
  -- obrigatórios mínimos
  if coalesce(trim(p_nome),'') = '' or coalesce(trim(p_problemas),'') = ''
     or coalesce(trim(p_horario),'') = '' then
    raise exception 'Campos obrigatórios ausentes';
  end if;

  -- rate-limit anti-flood: no máximo 10 envios em 1 minuto (global)
  select count(*) into v_recent from semep_briefing
   where criado_em > now() - interval '1 minute';
  if v_recent >= 10 then
    raise exception 'Muitos envios em pouco tempo. Tente novamente em instantes.';
  end if;

  insert into semep_briefing (
    nome, cargo, psicologos, tipo_atendimento, planos, precos_whatsapp,
    agendamento_hoje, ordem_chegada, medico_fixo, intervalo_minimo,
    problemas, horario, relatorios, observacoes
  ) values (
    left(p_nome,160), left(p_cargo,120), left(p_psicologos,40), left(p_tipo,40),
    left(p_planos,1000), left(p_precos,40), left(p_agendamento,80), left(p_ordem,120),
    left(p_medico_fixo,80), left(p_intervalo,1000), left(p_problemas,4000),
    left(p_horario,200), left(p_relatorios,40), left(p_observacoes,4000)
  );
  return true;
end; $$;

-- anon (formulário público) só pode EXECUTAR a função; nunca tocar a tabela
grant execute on function public.salvar_briefing_semep(
  text,text,text,text,text,text,text,text,text,text,text,text,text,text
) to anon, authenticated;

notify pgrst, 'reload schema';
