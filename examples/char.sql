--name: save-skill
insert into skills
          ( char_name
          , tree
          , leaf
          , levels
          , bonus
          )
     values
          ( :name
          , :tree
          , :leaf
          , :levels
          , :bonus
          ) ;
