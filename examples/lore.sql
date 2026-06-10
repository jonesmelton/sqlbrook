--name: find-flyables
select location
     , short_name
     , full_name
  from flyable_npcs_formatted
 where full_name
         like '%' || :term || '%'
       ;

--name: find-flyables-by-loc
select location
     , short_name
     , full_name
  from flyable_npcs_formatted
 where area = :area
   and full_name
         like '%' || :term || '%'
       ;

--name: flyables-in-loc
select location
     , short_name
     , full_name
  from flyable_npcs_formatted
 where area = :area
       ;
