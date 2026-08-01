FROM artist
  JOIN artist_credit_name AS acn ON acn.artist = artist.id
  JOIN artist_credit AS ac ON acn.artist_credit = ac.id
  JOIN release AS r ON r.artist_credit = ac.id
  JOIN language AS l ON l.id = r.language
  JOIN gender AS g ON g.id = artist.gender
  JOIN release_info AS ri ON ri.release = r.id

SELECT DISTINCT 
  make_date(ri.date_year, ri.date_month, ri.date_day) AS RELEASE_DATE,
  r.name AS RELEASE_NAME,
  artist.name AS ARTIST_NAME

  WHERE
    l.name = 'German'
    AND g.name = 'Female'
    AND ri.date_day IS NOT NULL
    AND ri.date_month IS NOT NULL
    AND ri.date_year IS NOT NULL
  

  ORDER BY
    RELEASE_DATE DESC,
    RELEASE_NAME ASC,
    ARTIST_NAME ASC
  LIMIT 10
;

