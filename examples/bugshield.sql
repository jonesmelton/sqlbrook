--name: new-shield
--fn: first
insert into bugshields
          ( initial_size
          , size
          , species
          , raw_line
          )
     values
          ( :size
          , :size
          , :species
          , :raw_line
          ) returning *
            ;

--name: end-shield
--fn: first
with current
   ( rowid
   , ts
   , end_time
   ) as (
        select rowid
             , ts
             , end_time
          from bugshields
         where end_time is null
      order by ts desc
         limit 1
     )
   update bugshields
      set end_time = time('now')
    where rowid = (select rowid from current)
returning *
          ;

--name: end-all
update bugshields
   set end_time = 1
 where end_time is null
       ;

--name: register-hit
--fn: first
with current
   ( rowid
   , ts
   , end_time
   ) as (
        select rowid
             , ts
             , end_time
          from bugshields
         where end_time is null
      order by ts desc
         limit 1
     )
   update bugshields
      set hits = hits + 1
    where rowid = (select rowid from current)
returning *
          ;

--name: weaken-shield
--fn: first
with current
   ( rowid
   , size
   , ts
   , end_time
   ) as (
        select rowid
             , size
             , ts
             , end_time
          from bugshields
         where end_time is null
      order by ts desc
         limit 1
     )
   update bugshields
      set size = :size
    where rowid = (select rowid from current)
returning *
          ;

--name: current
--fn: first
  select size
       , species
       , hits
    from bugshields
   where end_time is null
order by ts desc
   limit 1
         ;
