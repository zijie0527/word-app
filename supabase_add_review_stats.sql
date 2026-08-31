-- 給 review_logs 加兩個欄位，用來支援 Anki 風格的統計頁：
--   duration_ms：這張卡從顯示到按下評分按鈕花了多少毫秒
--   category：這次複習當下卡片的狀態（'new' 全新卡片 / 'review' 複習已畢業卡片 / 'relearn' 畢業後又忘記重新學習）
-- 都允許 null，因為這個功能上線之前的舊紀錄沒有這兩個資料，不影響既有資料。

alter table review_logs add column if not exists duration_ms integer;
alter table review_logs add column if not exists category text;

-- grade_card 加兩個新參數（都給預設值 null，不會破壞舊的呼叫方式），
-- 一起寫進 review_logs。
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

  insert into review_logs (card_id, user_id, grade, duration_ms, category)
  values (p_card_id, auth.uid(), p_grade, p_duration_ms, p_category);
end;
$$;
