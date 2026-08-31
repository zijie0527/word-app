-- 這次要做兩件事：
-- 1. 學生/老師的顯示名稱（display_name，存在 auth.users 的 user_metadata 裡，
--    前端註冊時會用 signUp 的 options.data.display_name 帶進來）要能讓對方看到，
--    取代原本顯示 email 的地方（因為改用帳號登入後，email 是內部合成的假信箱，
--    直接顯示給人看沒有意義）。
-- 2. 老師要能看到已連結學生的完整統計（含各單元進度），
--    所以要多開放 units / card_units 這兩張表給老師唯讀。

-- ===== 1. get_my_students / get_my_teachers 加 display_name =====
-- 回傳的欄位結構變了（多一欄），Postgres 不允許用 CREATE OR REPLACE 直接改，
-- 要先把舊函式刪掉再重建。
drop function if exists get_my_students();
drop function if exists get_my_teachers();

create or replace function get_my_students()
returns table(student_id uuid, email text, display_name text, linked_at timestamptz)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
    select tl.student_id, u.email::text, (u.raw_user_meta_data->>'display_name')::text, tl.created_at
    from teacher_links tl
    join auth.users u on u.id = tl.student_id
    where tl.teacher_id = auth.uid();
end;
$$;

create or replace function get_my_teachers()
returns table(teacher_id uuid, email text, display_name text, linked_at timestamptz)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
    select tl.teacher_id, u.email::text, (u.raw_user_meta_data->>'display_name')::text, tl.created_at
    from teacher_links tl
    join auth.users u on u.id = tl.teacher_id
    where tl.student_id = auth.uid();
end;
$$;

-- redeem_invite_code 原本回傳老師的 email，改成優先回傳老師的姓名（沒有姓名才退回 email）
create or replace function redeem_invite_code(p_code text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_teacher_id uuid;
  v_teacher_label text;
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

  select coalesce(raw_user_meta_data->>'display_name', email::text) into v_teacher_label
  from auth.users where id = v_teacher_id;

  return v_teacher_label;
end;
$$;

-- ===== 2. 老師唯讀看到已連結學生的 units / card_units（給統計頁的單元進度用）=====
create policy "teachers can view linked students units"
  on units for select
  using (
    exists (
      select 1 from teacher_links tl
      where tl.teacher_id = auth.uid() and tl.student_id = units.user_id
    )
  );

create policy "teachers can view linked students card_units"
  on card_units for select
  using (
    exists (
      select 1 from cards c
      join teacher_links tl on tl.student_id = c.user_id
      where c.id = card_units.card_id and tl.teacher_id = auth.uid()
    )
  );
