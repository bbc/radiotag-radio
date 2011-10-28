#!/bin/sh
cat <<EOF | mysql -uradiotag -pradiotag radiotag_development
delete from tags;\
delete from users;\
delete from devices;\
delete from tokens;\
insert into users (id, name, password) values (1, 'sean', NULL);\
insert into tokens (token, value) values
 ('b86bfdfb-5ff5-4cc7-8c61-daaa4804f188', '{ "scope": "unpaired" }'),
 ('ddc7f510-9353-45ad-9202-746ffe3b663a', '{ "scope": "can_register" }');
EOF

cat <<EOF | mysql -uradiotag -pradiotag radiotag_development
select * from users;\
select * from tags;\
select * from devices;\
select * from tokens;
EOF
