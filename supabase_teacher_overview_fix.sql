-- 修正 get_my_students / get_my_teachers 的型別錯誤（auth.users.email 是
-- character varying，跟宣告的 text 不完全相符，要明確 cast）。
-- 只需要執行這個檔案，不用重跑整份 supabase_teacher_overview.sql
-- （裡面的 create table / create policy 重複執行會報錯，因為已經建立過了）。

create or replace function get_my_students()
returns table(student_id uuid, email text, linked_at timestamptz)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
    select tl.student_id, u.email::text, tl.created_at
    from teacher_links tl
    join auth.users u on u.id = tl.student_id
    where tl.teacher_id = auth.uid();
end;
$$;

create or replace function get_my_teachers()
returns table(teacher_id uuid, email text, linked_at timestamptz)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
    select tl.teacher_id, u.email::text, tl.created_at
    from teacher_links tl
    join auth.users u on u.id = tl.teacher_id
    where tl.student_id = auth.uid();
end;
$$;
