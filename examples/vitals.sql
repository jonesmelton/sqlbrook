--name: insert-vitals
insert into vitals
          ( name
          , alignment
          , burden
          , gp
          , max_gp
          , hp
          , max_hp
          , xp
          )
     values
          ( :name
          , :alignment
          , :burden
          , :gp
          , :max_gp
          , :hp
          , :max_hp
          , :xp
          ) ;

--name: current-vitals
--fn: first
select name
     , alignment
     , burden
     , max_gp
     , gp
     , gp - lag(gp)
  over (order by rowid rows between 1 preceding and 1 following)
    as delta_gp
     , max_hp
     , hp
     , hp - lag(hp)
  over (order by rowid rows between 1 preceding and 1 following)
    as delta_hp
     , xp
     , xp - lag(xp)
  over (order by rowid rows between 1 preceding and 1 following)
    as delta_xp
     , ts
  from vitals
 where name = :name
 order by ts desc
 limit 1
       ;

--name: xp-rate
--fn: first
    with xp_per_h
      as (
  select xp
       , min(xp)
  filter (where ts > datetime('now', '-1 hour'))
    over last_hour
      as min_xp
       , max(xp)
  filter (where ts > datetime('now', '-1 hour'))
    over last_hour
      as max_xp
       , min(ts)
  filter (where ts > datetime('now', '-1 hour'))
    over last_hour
      as earliest
       , max(ts)
  filter (where ts > datetime('now', '-1 hour'))
    over last_hour
      as latest
    from vitals
   where name = :name
  window last_hour
      as (order by ts desc range between unbounded preceding and unbounded following)
order by ts desc
   limit 1
         )
       , xp_rate
      as (
  select (max_xp - min_xp)
      as xp_gain
       , earliest
       , latest
       , (strftime('%s', latest) - strftime('%s', earliest)) / 60
      as minutes_elapsed
    from xp_per_h
         )
  select minutes_elapsed
       , xp_gain
       , xp_gain / minutes_elapsed * 60
      as xp_per_hour
       , (xp_gain / minutes_elapsed * 60) / 1000
      as kxp_per_hour
    from xp_rate
         ;
