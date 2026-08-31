-- 第三階段：角色權限、邀請碼期限、學生離開老師、指派任務。
-- 密碼重設（原本第4項）刻意不做，你本來就是 Supabase 專案擁有者，有學生忘記密碼時
-- 直接去 Supabase 後台的 Authentication → Users 幫他重設就好，不需要另外開發功能
-- （自己刻一個「代改密碼」的功能，反而會多一個容易被濫用的高風險缺口）。

-- ===== 1. 老師身分：獨立表格，一般使用者完全不能自己新增/修改 =====
-- 只開放 SELECT（讓前端能判斷「我是不是老師」），沒有任何 insert/update/delete policy，
-- 代表只有你自己用 SQL Editor 才能讓某個帳號變成老師，不會有帳號能自己冒充老師。
create table if not exists teacher_roles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  granted_at timestamptz not null default now()
);

alter table teacher_roles enable row level security;

create policy "users can check their own teacher role"
  on teacher_roles for select
  using (user_id = auth.uid());

-- ★★★ 執行完這份 SQL 後，記得把你自己的帳號設成老師，才能繼續使用「產生邀請碼」功能：
-- 1. 到 Supabase 後台 Authentication → Users 找到你自己登入用的那個帳號，複製它的 email
--    （如果你是用帳號登入，這裡看到的 email 會是「你的帳號@word-app.local」）
-- 2. 把下面這行的 'YOUR_LOGIN_EMAIL_HERE' 換成剛剛複製的 email，執行：
--
-- insert into teacher_roles (user_id)
-- select id from auth.users where email = 'YOUR_LOGIN_EMAIL_HERE';

-- ===== 2. 產生邀請碼現在要求本人是登記過的老師 =====
drop policy if exists "teachers manage own invite codes" on invite_codes;

create policy "teachers manage own invite codes"
  on invite_codes for all
  using (teacher_id = auth.uid())
  with check (
    teacher_id = auth.uid()
    and exists (select 1 from teacher_roles tr where tr.user_id = auth.uid())
  );

-- ===== 3. 邀請碼加上期限（預設 7 天），過期就不能再兌換 =====
alter table invite_codes add column if not exists expires_at timestamptz not null default (now() + interval '7 days');

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
  where code = p_code and redeemed_by is null and expires_at > now();

  if v_teacher_id is null then
    raise exception '邀請碼無效、已被使用或已過期';
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

-- ===== 4. 學生可以自己離開老師 =====
create policy "students can leave their teacher"
  on teacher_links for delete
  using (student_id = auth.uid());

-- ===== 5. 指派任務：老師從學生「已經有的單元」裡選一個、設定期限 =====
-- 完成度不是靠手動打勾，是直接算這個單元裡有多少字「已穩定掌握」（跟統計頁同一套標準），
-- 比較不會被隨便點一下就騙過去。
create table if not exists assignments (
  id uuid primary key default gen_random_uuid(),
  teacher_id uuid not null references auth.users(id) on delete cascade,
  student_id uuid not null references auth.users(id) on delete cascade,
  unit_id uuid not null references units(id) on delete cascade,
  due_date date,
  note text,
  created_at timestamptz not null default now()
);

alter table assignments enable row level security;

create policy "teachers manage assignments for their students"
  on assignments for all
  using (
    teacher_id = auth.uid()
    and exists (select 1 from teacher_links tl where tl.teacher_id = auth.uid() and tl.student_id = assignments.student_id)
  )
  with check (
    teacher_id = auth.uid()
    and exists (select 1 from teacher_links tl where tl.teacher_id = auth.uid() and tl.student_id = assignments.student_id)
  );

create policy "students can view their own assignments"
  on assignments for select
  using (student_id = auth.uid());
