# 닉네임 신고 운영 절차

앱의 닉네임 신고는 `public.nickname_reports`에 `pending` 상태로 저장된다.
출시 후 운영 담당자는 최소 주 1회, 이용량이 늘면 매일 확인한다.

## 확인

Supabase SQL Editor에서 서비스 역할 권한으로 다음 쿼리를 실행한다.

```sql
select
  r.id,
  r.created_at,
  r.nickname_snapshot,
  r.reported_user_id,
  count(*) over (
    partition by r.reported_user_id, r.nickname_snapshot
  ) as matching_report_count
from public.nickname_reports r
where r.status = 'pending'
order by matching_report_count desc, r.created_at asc;
```

## 조치

명백한 욕설·혐오·연락처·사칭·광고라면 닉네임을 초기화하고 신고를
`actioned`로 바꾼다.

```sql
begin;

update public.profiles
set nickname = null, updated_at = now()
where id = '<reported_user_id>';

update public.nickname_reports
set status = 'actioned', reviewed_at = now()
where id = '<report_id>';

commit;
```

위반이 아니면 `dismissed`로 처리한다.

```sql
update public.nickname_reports
set status = 'dismissed', reviewed_at = now()
where id = '<report_id>';
```

계정 정지 기능은 아직 자동화하지 않았다. 반복적인 부정행위나 위협 등 계정
제한이 필요한 사례는 증거를 보존하고 별도 운영 판단 후 처리한다.
