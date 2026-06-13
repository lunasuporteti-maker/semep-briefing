-- Briefing SEMEP — versão final das perguntas (21 perguntas, 5 seções).
-- Espelha as regras de negócio que o agente de IA precisa (modelo Sofia).
-- Aditivo sobre 001: adiciona colunas novas e recria a RPC com os parâmetros finais.
-- Rodar no Supabase Studio (SQL Editor). Idempotente.
-- Obs: colunas legadas da 001 (psicologos, ordem_chegada, problemas) permanecem na
-- tabela mas não são mais preenchidas — perguntas removidas a pedido do dono.

-- ── 1) Colunas novas ─────────────────────────────────────────────────────────
alter table public.semep_briefing add column if not exists exames               text;
alter table public.semep_briefing add column if not exists exames_quais         text;
alter table public.semep_briefing add column if not exists restricoes_perfil    text;
alter table public.semep_briefing add column if not exists primeira_retorno     text;
alter table public.semep_briefing add column if not exists cancelamento         text;
alter table public.semep_briefing add column if not exists sinal_antecipado     text;
alter table public.semep_briefing add column if not exists fora_escopo          text;
alter table public.semep_briefing add column if not exists receita_atestado     text;
alter table public.semep_briefing add column if not exists urgencia             text;
alter table public.semep_briefing add column if not exists confirmacao_presenca text;
alter table public.semep_briefing add column if not exists demandas_comuns      text;

-- ── 2) Recria a RPC ──────────────────────────────────────────────────────────
-- Remove a assinatura antiga (14 params da 001) para não criar overload ambíguo.
drop function if exists public.salvar_briefing_semep(
  text,text,text,text,text,text,text,text,text,text,text,text,text,text
);

create or replace function public.salvar_briefing_semep(
  p_nome text, p_cargo text, p_tipo text, p_planos text, p_precos text,
  p_exames text, p_exames_quais text, p_agendamento text, p_medico_fixo text,
  p_restricoes text, p_primeira text, p_intervalo text, p_cancelamento text,
  p_sinal text, p_fora_escopo text, p_receita_atestado text, p_urgencia text,
  p_confirmacao text, p_horario text, p_relatorios text, p_demandas text,
  p_observacoes text
) returns boolean
language plpgsql security definer set search_path = public as $$
declare
  v_recent int;
begin
  -- obrigatórios mínimos
  if coalesce(trim(p_nome),'') = '' or coalesce(trim(p_horario),'') = '' then
    raise exception 'Campos obrigatórios ausentes';
  end if;

  -- rate-limit anti-flood: no máximo 10 envios em 1 minuto (global)
  select count(*) into v_recent from semep_briefing
   where criado_em > now() - interval '1 minute';
  if v_recent >= 10 then
    raise exception 'Muitos envios em pouco tempo. Tente novamente em instantes.';
  end if;

  insert into semep_briefing (
    nome, cargo, tipo_atendimento, planos, precos_whatsapp, exames, exames_quais,
    agendamento_hoje, medico_fixo, restricoes_perfil, primeira_retorno, intervalo_minimo,
    cancelamento, sinal_antecipado, fora_escopo, receita_atestado, urgencia,
    confirmacao_presenca, horario, relatorios, demandas_comuns, observacoes
  ) values (
    left(p_nome,160), left(p_cargo,120), left(p_tipo,40), left(p_planos,1000),
    left(p_precos,40), left(p_exames,40), left(p_exames_quais,2000), left(p_agendamento,80),
    left(p_medico_fixo,80), left(p_restricoes,3000), left(p_primeira,2000),
    left(p_intervalo,1000), left(p_cancelamento,3000), left(p_sinal,40),
    left(p_fora_escopo,3000), left(p_receita_atestado,2000), left(p_urgencia,2000),
    left(p_confirmacao,3000), left(p_horario,200), left(p_relatorios,40),
    left(p_demandas,4000), left(p_observacoes,4000)
  );
  return true;
end; $$;

-- anon (formulário público) só pode EXECUTAR a função; nunca tocar a tabela
grant execute on function public.salvar_briefing_semep(
  text,text,text,text,text,text,text,text,text,text,text,
  text,text,text,text,text,text,text,text,text,text,text
) to anon, authenticated;

notify pgrst, 'reload schema';
