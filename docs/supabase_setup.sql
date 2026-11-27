-- Run once in a new Supabase project used for demonstration.
-- Create the public food_tracker_bk bucket using the README before running.
begin;

create table public.food_tracker_tb (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  "foodDate" text not null,
  "foodMeal" text not null,
  "foodName" text not null,
  "foodPrice" float8 not null,
  "foodPerson" int4 not null,
  "foodImageUrl" text,
  constraint food_tracker_date_check check (
    case
      when "foodDate" ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
      then "foodDate"::date >= date '0001-01-01'
      else false
    end
  ),
  constraint food_tracker_meal_check
    check ("foodMeal" in ('เช้า', 'กลางวัน', 'เย็น', 'ว่าง')),
  constraint food_tracker_name_check check ("foodName" ~ '[^[:space:]]'),
  constraint food_tracker_price_check
    check ("foodPrice" >= 0 and "foodPrice" < 'Infinity'::float8),
  constraint food_tracker_person_check check ("foodPerson" >= 1),
  constraint food_tracker_image_check
    check ("foodImageUrl" is null or btrim("foodImageUrl") <> '')
);

alter table public.food_tracker_tb enable row level security;
revoke all privileges on table public.food_tracker_tb from public, anon, authenticated;
grant select, delete on table public.food_tracker_tb to anon;
grant
  insert ("foodDate", "foodMeal", "foodName", "foodPrice", "foodPerson", "foodImageUrl"),
  update ("foodDate", "foodMeal", "foodName", "foodPrice", "foodPerson", "foodImageUrl")
on table public.food_tracker_tb to anon;

create policy a09_food_select on public.food_tracker_tb
  for select to anon using (true);
create policy a09_food_insert on public.food_tracker_tb
  for insert to anon with check (true);
create policy a09_food_update on public.food_tracker_tb
  for update to anon using (true) with check (true);
create policy a09_food_delete on public.food_tracker_tb
  for delete to anon using (true);

create policy a09_food_files_select on storage.objects
  for select to anon using (
    bucket_id = 'food_tracker_bk'
    and name ~ '^foods/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}[.](jpg|jpeg|png|webp)$'
  );
create policy a09_food_files_insert on storage.objects
  for insert to anon with check (
    bucket_id = 'food_tracker_bk'
    and name ~ '^foods/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}[.](jpg|jpeg|png|webp)$'
  );
create policy a09_food_files_delete on storage.objects
  for delete to anon using (
    bucket_id = 'food_tracker_bk'
    and name ~ '^foods/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}[.](jpg|jpeg|png|webp)$'
  );

commit;

