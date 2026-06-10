-- name: find-by-name
select *
  from items
 where item_name
       like '%' || :term || '%'
 limit 10
       ;
