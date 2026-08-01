SELECT DISTINCT artist.name FROM artist
  -- for seleting Area -> England
  JOIN area AS ar ON artist.area = ar.id
  --  personal producer
  JOIN artist_type AS at ON artist.type = at.id
  -- Release log
  JOIN artist_credit_name AS acn ON artist.id = acn.artist
  JOIN artist_credit ac ON acn.artist_credit = ac.id
  
  WHERE
    artist.begin_date_year BETWEEN 1970 AND 1979
    AND at.name = 'Person'
    AND ar.name = 'England'
    AND ac.artist_count = 1
  
  ORDER BY artist.name;
;
