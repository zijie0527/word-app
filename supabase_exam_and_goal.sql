-- 加考試日期（一二三段）跟本週目標張數，存在 user_settings。
-- 老師要能幫已連結的學生修改這兩項，所以額外開一條 policy 給老師（不只是唯讀，這裡是刻意讓老師能寫入）。

alter table user_settings add column if not exists exam_date_1 date;
alter table user_settings add column if not exists exam_date_2 date;
alter table user_settings add column if not exists exam_date_3 date;
alter table user_settings add column if not exists weekly_goal integer not null default 100;

create policy "teachers can manage linked students settings"
  on user_settings for all
  using (
    exists (
      select 1 from teacher_links tl
      where tl.teacher_id = auth.uid() and tl.student_id = user_settings.user_id
    )
  )
  with check (
    exists (
      select 1 from teacher_links tl
      where tl.teacher_id = auth.uid() and tl.student_id = user_settings.user_id
    )
  );
