-- DECIDE MVP schema. Run in Supabase SQL Editor after enabling Anonymous Sign-ins.
create extension if not exists pgcrypto;

create table if not exists public.posts (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references auth.users(id) on delete cascade,
  title text not null check (char_length(title) between 3 and 90),
  description text not null default '' check (char_length(description) <= 300),
  category text not null check (category in ('쇼핑','패션','음식','연애','직장','여행','생활','디지털','자동차','취미','기타')),
  status text not null default 'published' check (status in ('draft','published','hidden','deleted')),
  view_count bigint not null default 0,
  vote_count bigint not null default 0,
  comment_count bigint not null default 0,
  hot_score numeric not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.post_options (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  label text not null check (char_length(label) between 1 and 50),
  image_url text not null,
  position smallint not null check (position between 0 and 2),
  created_at timestamptz not null default now(),
  unique(post_id, position)
);

create table if not exists public.votes (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  option_id uuid not null references public.post_options(id) on delete cascade,
  voter_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique(post_id, voter_id)
);
create index if not exists posts_new_idx on public.posts(created_at desc) where status='published';
create index if not exists posts_hot_idx on public.posts(hot_score desc, created_at desc) where status='published';
create index if not exists posts_category_idx on public.posts(category, created_at desc) where status='published';
create index if not exists votes_voter_idx on public.votes(voter_id, post_id);
create index if not exists options_post_idx on public.post_options(post_id, position);

create or replace function public.refresh_hot_score(p_post_id uuid)
returns void language sql security definer set search_path=public as $$
  update public.posts p set hot_score =
    (p.vote_count * 4.0) + (p.view_count * 0.25) + (p.comment_count * 2.0)
    + (p.vote_count / greatest(1, extract(epoch from (now()-p.created_at))/3600) * 30.0),
    updated_at=now()
  where p.id=p_post_id;
$$;

create or replace function public.cast_vote(p_post_id uuid, p_option_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_uid uuid; v_total integer; v_counts integer[];
begin
  v_uid := auth.uid();
  if v_uid is null then raise exception '투표 세션이 필요합니다.'; end if;
  if not exists(select 1 from public.posts where id=p_post_id and status='published') then raise exception '게시글을 찾을 수 없습니다.'; end if;
  if not exists(select 1 from public.post_options where id=p_option_id and post_id=p_post_id) then raise exception '잘못된 선택지입니다.'; end if;
  insert into public.votes(post_id, option_id, voter_id) values(p_post_id,p_option_id,v_uid);
  update public.posts set vote_count=vote_count+1 where id=p_post_id;
  perform public.refresh_hot_score(p_post_id);
  select count(*)::integer into v_total from public.votes where post_id=p_post_id;
  select array_agg(coalesce(c.n,0) order by o.position) into v_counts
  from public.post_options o left join (select option_id,count(*)::integer n from public.votes where post_id=p_post_id group by option_id) c on c.option_id=o.id
  where o.post_id=p_post_id;
  return jsonb_build_object('total',v_total,'counts',to_jsonb(v_counts));
end; $$;

create or replace function public.increment_post_view(p_post_id uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
  update public.posts set view_count=view_count+1 where id=p_post_id and status='published';
  perform public.refresh_hot_score(p_post_id);
end; $$;

alter table public.posts enable row level security;
alter table public.post_options enable row level security;
alter table public.votes enable row level security;

-- Public read access to published content.
drop policy if exists "published posts are readable" on public.posts;
create policy "published posts are readable" on public.posts for select using (status='published' or author_id=auth.uid());
drop policy if exists "members create posts" on public.posts;
create policy "members create posts" on public.posts for insert to authenticated with check (author_id=auth.uid() and coalesce((auth.jwt()->>'is_anonymous')::boolean,false)=false);
drop policy if exists "authors update own posts" on public.posts;
create policy "authors update own posts" on public.posts for update to authenticated using (author_id=auth.uid()) with check (author_id=auth.uid());
drop policy if exists "options are readable" on public.post_options;
create policy "options are readable" on public.post_options for select using (exists(select 1 from public.posts p where p.id=post_id and p.status='published'));
drop policy if exists "authors manage options" on public.post_options;
create policy "authors manage options" on public.post_options for insert to authenticated with check (exists(select 1 from public.posts p where p.id=post_id and p.author_id=auth.uid()));
drop policy if exists "voters can read own votes" on public.votes;
create policy "voters can read own votes" on public.votes for select to authenticated using (voter_id=auth.uid());
-- No direct vote insert/update/delete policy: all writes go through cast_vote().

grant select on public.posts, public.post_options to anon, authenticated;
grant insert, update on public.posts to authenticated;
grant insert on public.post_options to authenticated;
grant select on public.votes to authenticated;
grant execute on function public.cast_vote(uuid,uuid) to authenticated;
grant execute on function public.increment_post_view(uuid) to anon, authenticated;

-- Public image bucket. Restrict uploads to authenticated users; production deployments should add file-size/type limits.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('post-images','post-images',true,5242880,array['image/jpeg','image/png','image/webp'])
on conflict(id) do update set public=true, file_size_limit=5242880, allowed_mime_types=array['image/jpeg','image/png','image/webp'];
drop policy if exists "public can view post images" on storage.objects;
create policy "public can view post images" on storage.objects for select using (bucket_id='post-images');
drop policy if exists "authenticated members upload post images" on storage.objects;
create policy "authenticated members upload post images" on storage.objects for insert to authenticated with check (bucket_id='post-images' and coalesce((auth.jwt()->>'is_anonymous')::boolean,false)=false);

-- Validate that a published post has exactly 2 or 3 choices before it becomes visible.
create or replace function public.validate_post_options_count()
returns trigger language plpgsql as $$
declare n integer;
begin
  if new.status='published' then
    select count(*) into n from public.post_options where post_id=new.id;
    if n not in (2,3) then raise exception '게시글 선택지는 2개 또는 3개여야 합니다.'; end if;
  end if;
  return new;
end; $$;
-- This trigger is deferred so a post and its options can be created in one transaction.
drop trigger if exists validate_post_options_count_trigger on public.posts;
create constraint trigger validate_post_options_count_trigger
after insert or update of status on public.posts
deferrable initially deferred for each row execute function public.validate_post_options_count();
