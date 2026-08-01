FROM artist a
JOIN area ar ON a.area = ar.id
JOIN artist_type art_type ON a.type = art_type.id
JOIN artist_credit_name acn ON a.id = acn.artist
JOIN artist_credit ac ON acn.artist_credit = ac.id

SELECT DISTINCT a.name

WHERE a.begin_date_year >= 1970 
  AND a.begin_date_year <= 1979
  AND art_type.name = 'Person'
  AND ar.name = 'England'
  AND ac.artist_count = 1

ORDER BY a.name;
