-- Keep the tester PIN server-authoritative and store only its bcrypt hash.
update public.app_runtime_config
set tester_pin_hash =
  '$2a$12$3njXt4rSQ4/ylQ.rtEr0duCQsYYlK5/rFvaS2jTDiC3GzqsqOKwwK'
where id;
