-- Phase 2 資料庫變更：
-- 1. grade_card 改成回傳新插入的 review_logs.id，前端才能在「復原上一題」時
--    知道要刪哪一筆紀錄。回傳型態變了，要先 drop 再重建。
-- 2. 新增 undo_last_grade：復原剛剛那次評分，把 review_state 還原、刪掉那筆 review_logs。
--    用 SECURITY DEFINER，但函式內部會先確認卡片和紀錄都屬於呼叫者本人才動手，
--    不會因此讓使用者能動別人的資料。
-- 3. user_settings 加一欄 example_before_flip，控制例句要翻面前就看到、還是翻面後才顯示。

drop function if exists grade_card(uuid, text, float, integer, integer, integer, boolean, date, integer, text);

create or replace function grade_card(
  p_card_id uuid,
  p_grade text,
  p_ease_factor float,
  p_interval_days integer,
  p_repetitions integer,
  p_learning_step integer,
  p_is_learning boolean,
  p_next_review_date date,
  p_duration_ms integer default null,
  p_category text default null
)
returns uuid
language plpgsql
as $$
declare
  v_log_id uuid;
begin
  update review_state
  set
    ease_factor = p_ease_factor,
    interval_days = p_interval_days,
    repetitions = p_repetitions,
    learning_step = p_learning_step,
    is_learning = p_is_learning,
    next_review_date = p_next_review_date,
    last_reviewed_at = now(),
    last_grade = p_grade
  where card_id = p_card_id;

  insert into review_logs (card_id, user_id, grade, duration_ms, category)
  values (p_card_id, auth.uid(), p_grade, p_duration_ms, p_category)
  returning id into v_log_id;

  return v_log_id;
end;
$$;

create or replace function undo_last_grade(
  p_log_id uuid,
  p_card_id uuid,
  p_ease_factor float,
  p_interval_days integer,
  p_repetitions integer,
  p_learning_step integer,
  p_is_learning boolean,
  p_next_review_date date,
  p_last_reviewed_at timestamptz,
  p_last_grade text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from cards c where c.id = p_card_id and c.user_id = auth.uid()) then
    raise exception '沒有權限復原這張卡';
  end if;

  if not exists (select 1 from review_logs rl where rl.id = p_log_id and rl.card_id = p_card_id and rl.user_id = auth.uid()) then
    raise exception '找不到這筆複習紀錄，可能已經復原過或太久了';
  end if;

  update review_state
  set
    ease_factor = p_ease_factor,
    interval_days = p_interval_days,
    repetitions = p_repetitions,
    learning_step = p_learning_step,
    is_learning = p_is_learning,
    next_review_date = p_next_review_date,
    last_reviewed_at = p_last_reviewed_at,
    last_grade = p_last_grade
  where card_id = p_card_id;

  delete from review_logs where id = p_log_id;
end;
$$;

grant execute on function undo_last_grade(uuid, uuid, float, integer, integer, integer, boolean, date, timestamptz, text) to authenticated;

alter table user_settings add column if not exists example_before_flip boolean not null default true;
