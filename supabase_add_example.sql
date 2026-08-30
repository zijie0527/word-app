-- 幫 cards 加一個可為空的例句欄位。純加欄位，不影響任何現有資料，
-- 也不用改 RLS（沿用 cards 表既有的 policy）。

alter table cards add column if not exists example text;
