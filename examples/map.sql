--name: find
--fn: first
    select r.room_id
         , r.map_id
         , r.xpos
         , r.ypos
         , m.filename
         , m.display_name
         , m.domain
      from rooms r
inner join maps m
        on r.map_id = m.map_id
     where r.room_id = :room_id
           ;
