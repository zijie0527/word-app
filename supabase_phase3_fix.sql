-- 修正一個真正的安全漏洞：teacher_links 原本的 policy 只檢查 teacher_id = auth.uid()，
-- 沒有檢查這個人是不是登記過的老師。這代表任何一般帳號都能繞過邀請碼系統，
-- 直接對 teacher_links 送一筆 insert，把自己連到「任何」學生帳號，
-- 取得該學生 cards / review_state / review_logs / units / card_units / user_settings 的存取權。
--
-- 已經用測試帳號實際重現過這個問題（非老師帳號直接 insert teacher_links 成功），確認是真的漏洞。

drop policy if exists "teachers manage own links" on teacher_links;

create policy "teachers manage own links"
  on teacher_links for all
  using (teacher_id = auth.uid())
  with check (
    teacher_id = auth.uid()
    and exists (select 1 from teacher_roles tr where tr.user_id = auth.uid())
  );
