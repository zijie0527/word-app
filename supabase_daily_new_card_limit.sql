-- 每人一筆的簡單設定表，目前只放「每天最多學幾張新卡」。
-- 用 upsert（insert ... on conflict）寫入，前端不用先判斷有沒有這筆資料。

create table if not exists user_settings (
  user_id uuid primary key references auth.users(id) on delete cascade,
  daily_new_limit integer not null default 15
);

alter table user_settings enable row level security;

create policy "users manage own settings"
  on user_settings for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
