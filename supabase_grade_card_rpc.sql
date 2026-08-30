-- 把「更新 review_state」+「寫入 review_logs」包成一個資料庫函式，
-- 讓評分寫入變成單一交易（原子性）：要嘛兩個都成功，要嘛兩個都不會發生。
--
-- 用預設的 SECURITY INVOKER（不加 SECURITY DEFINER）：
-- 函式執行時仍然是「呼叫者本人」的身份，review_state / review_logs 現有的
-- RLS policy 會照常生效，不會因為用了 RPC 就繞過權限檢查。
--
-- 使用方式：把整段貼到 Supabase 後台的 SQL Editor 執行一次即可。

create or replace function grade_card(
  p_card_id uuid,
  p_grade text,
  p_ease_factor float,
  p_interval_days integer,
  p_repetitions integer,
  p_learning_step integer,
  p_is_learning boolean,
  p_next_review_date date
)
returns void
language plpgsql
as $$
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

  insert into review_logs (card_id, user_id, grade)
  values (p_card_id, auth.uid(), p_grade);
end;
$$;
