-- The product no longer exposes nickname reporting or user blocking.
-- Keep legacy tables because ranking functions may still read old blocks,
-- but remove every authenticated mutation endpoint.

drop function if exists public.report_nickname(uuid);
drop function if exists public.block_user(uuid);
