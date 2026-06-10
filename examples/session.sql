
--name: new
insert into sessions
          ( capname
          , guild
          , guildspec
          , name
          , role
          )
     values
          ( :capname
          , :guild
          , :guildspec
          , :name
          , :role
          )
  returning *
            ;

--name: current
   select *
     from sessions
    where end_time is null
 order by start_time desc
    limit 1
          ;

--name: end
   update sessions
      set end_time = current_timestamp
    where start_time = :start_time
returning *
          ;

--name:save-fruitbat
insert or replace
  into charstate
     ( char_name
     , name
     , value
     , data
     )
values
     ( :char_name
     , :name
     , :value
     , :data
     ) returning *
       ;

--name: get-fruitbat
--fn: first
select data
  from charstate
 where name = 'fruitbat'
   and char_name = :char
 limit 1
       ;

--name: play-log
  with recent_vitals
    as (
select max(rowid)
       as last
  from vitals
 where name = :char_name
       )

insert into logs.play
          ( char_name
          , mud_data
          , room_id
          , gmcp
          , char_state
          )
     values
          ( :char_name
          , :mud_data
          , :room_id
          , :gmcp
          , (select last from recent_vitals)
          ) ;
