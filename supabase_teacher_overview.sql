-- 老師總覽功能：學生用「邀請碼」加入老師，老師可以唯讀看到已連結學生的
-- 單字數、學會進度、近 7 天正確率。不影響任何現有功能與資料。
--
-- 使用方式：把整段貼到 Supabase 後台的 SQL Editor 執行一次即可。

-- ===== 1. teacher_links：老師與學生的連結關係 =====
create table if not exists teacher_links (
  teacher_id uuid not null references auth.users(id) on delete cascade,
  student_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (teacher_id, student_id)
);

alter table teacher_links enable row level security;

create policy "teachers manage own links"
  on teacher_links for all
  using (teacher_id = auth.uid())
  with check (teacher_id = auth.uid());

create policy "students can view their own links"
  on teacher_links for select
  using (student_id = auth.uid());

-- ===== 2. invite_codes：老師產生的邀請碼 =====
create table if not exists invite_codes (
  code text primary key,
  teacher_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  redeemed_by uuid references auth.users(id),
  redeemed_at timestamptz
);

alter table invite_codes enable row level security;

create policy "teachers manage own invite codes"
  on invite_codes for all
  using (teacher_id = auth.uid())
  with check (teacher_id = auth.uid());

-- ===== 3. redeem_invite_code：學生輸入邀請碼加入老師 =====
-- SECURITY DEFINER：因為學生本來就不能直接讀 invite_codes（怕看到別人的邀請碼），
-- 這個函式代替他「查碼、驗證、建立連結」，內部邏輯已經檢查過權限，是安全的。
create or replace function redeem_invite_code(p_code text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_teacher_id uuid;
  v_teacher_email text;
begin
  select teacher_id into v_teacher_id
  from invite_codes
  where code = p_code and redeemed_by is null;

  if v_teacher_id is null then
    raise exception '邀請碼無效或已被使用';
  end if;

  if v_teacher_id = auth.uid() then
    raise exception '不能加入自己的邀請碼';
  end if;

  update invite_codes set redeemed_by = auth.uid(), redeemed_at = now() where code = p_code;

  insert into teacher_links (teacher_id, student_id)
  values (v_teacher_id, auth.uid())
  on conflict (teacher_id, student_id) do nothing;

  select email into v_teacher_email from auth.users where id = v_teacher_id;
  return v_teacher_email;
end;
$$;

grant execute on function redeem_invite_code(text) to authenticated;

-- ===== 4. get_my_students / get_my_teachers：讀取對方的 email 顯示用 =====
-- auth.users 本身不開放給前端直接查，用這兩個函式各自回傳「我看得到的人」的 email。
create or replace function get_my_students()
returns table(student_id uuid, email text, linked_at timestamptz)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
    select tl.student_id, u.email, tl.created_at
    from teacher_links tl
    join auth.users u on u.id = tl.student_id
    where tl.teacher_id = auth.uid();
end;
$$;

grant execute on function get_my_students() to authenticated;

create or replace function get_my_teachers()
returns table(teacher_id uuid, email text, linked_at timestamptz)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
    select tl.teacher_id, u.email, tl.created_at
    from teacher_links tl
    join auth.users u on u.id = tl.teacher_id
    where tl.student_id = auth.uid();
end;
$$;

grant execute on function get_my_teachers() to authenticated;

-- ===== 5. 讓老師唯讀看到已連結學生的 cards / review_state / review_logs =====
-- 這些都是「額外加一條 SELECT policy」，不會取代或影響學生自己原本的權限，
-- 也完全不給老師寫入/刪除學生資料的權限。
create policy "teachers can view linked students cards"
  on cards for select
  using (
    exists (
      select 1 from teacher_links tl
      where tl.teacher_id = auth.uid() and tl.student_id = cards.user_id
    )
  );

create policy "teachers can view linked students review_state"
  on review_state for select
  using (
    exists (
      select 1 from cards c
      join teacher_links tl on tl.student_id = c.user_id
      where c.id = review_state.card_id and tl.teacher_id = auth.uid()
    )
  );

create policy "teachers can view linked students review_logs"
  on review_logs for select
  using (
    exists (
      select 1 from teacher_links tl
      where tl.teacher_id = auth.uid() and tl.student_id = review_logs.user_id
    )
  );
