--name: create-flyable_npcs
create table if not exists
world.flyable_npcs (
         full_name text
       ,short_name text
         ,location text
       ,stationary boolean
             ,area text
             ,note text
                 ) ;

--name: create-maps
create table if not exists
   world.maps (
       map_id integer
    ,filename text
,display_name text
      ,domain text
            ) ;

--name: insert-map
insert into world.maps
     values
          ( :map_id
          , :filename
          , :display_name
          , :domain
          ) ;

--name: create-view-flyable-npcs-formatted
create view if not exists world.flyable_npcs_formatted
    as
select printf('%-18s', short_name)
    as short_name
     , printf('%-46s', full_name)
    as full_name
     , printf('%+s', (substr(location, 1, 30)))
    as location
     , stationary
     , area
     , note
  from flyable_npcs
       ;

--name: create-charstate-table
create table if not exists
charstate (
char_name text
    ,name text
   ,value text
    ,data json
          default '{}'
      ,ts datetime
          default current_timestamp
  ,unique (char_name, name, value)
        ) ;

--name: create-table-skills
create table if not exists
   skills (
char_name text
          not null
    ,tree text
          not null
    ,leaf text
  ,levels integer
          not null
   ,bonus integer
          not null
      ,ts datetime
          default current_timestamp
  ,unique (char_name, tree, leaf, bonus)
           on conflict ignore
        ) ;

--name: create-table-logs
create table if not exists
   logs.play (
   char_name text
   ,mud_data text
    ,room_id text
       ,gmcp json
             default '{}'
 ,char_state integer
         ,ts datetime
             not null
             default current_timestamp
,primary key (char_name, ts desc, mud_data)
,foreign key (char_state)
             references vitals(rowid)
           ) ;

--name: create-table-vitals
create table if not exists
      vitals (
        name text
             not null
  ,alignment text
     ,burden integer
         ,gp integer
         ,hp integer
     ,max_gp integer
     ,max_hp integer
         ,xp integer
         ,ts datetime
             not null
             default current_timestamp
,primary key (name, ts desc)
           ) ;
