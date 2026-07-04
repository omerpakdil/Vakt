begin;

drop policy if exists "authenticated users can receive Vakt presence" on realtime.messages;

create policy "authenticated users can receive Vakt channel events"
on realtime.messages
for select
to authenticated
using (
    realtime.messages.extension in ('presence', 'broadcast')
    and private.can_access_presence_topic((select realtime.topic()))
);

commit;
