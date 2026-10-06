-- PostgreSQL requires a commit before a newly added enum value is used.
alter type public.attempt_grant_type add value if not exists 'store_ticket';
