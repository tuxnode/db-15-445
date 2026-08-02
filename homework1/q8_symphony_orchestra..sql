WITH ranked_release AS (
  SELECT DISTINCT
    a.id AS artist_id,
    a.name AS artist_name,
    ri.date_year AS release_year,
    COUNT(DISTINCT r.id) AS cd_count
  FROM artist a

  JOIN artist_type atp ON atp.id = a.type
  JOIN artist_credit_name acn ON acn.artist = a.id
  JOIN artist_credit ac ON ac.id = acn.artist_credit
  JOIN release r ON r.artist_credit = ac.id
  JOIN release_info ri ON r.id = ri.release
  JOIN medium m ON r.id = m.release
  JOIN medium_format mf ON mf.id = m.format

  WHERE
    a.name LIKE '%symphony%'
    AND atp.name = 'Orchestra'
    AND ri.date_year IS NOT NULL
    AND mf.name LIKE '%CD%'

  GROUP BY 
    a.id,
    a.name, 
    ri.date_year

  HAVING
    COUNT(DISTINCT r.id) >= 3
),

ranked_cd_releases AS (
  SELECT 
    artist_name,
    release_year,
    cd_count,
    ROW_NUMBER() OVER (
      PARTITION BY artist_id 
      ORDER BY cd_count DESC, release_year ASC
    ) AS rn
  FROM ranked_release
)


SELECT 
  artist_name || '|' || release_year || '|' || cd_count AS result
FROM ranked_cd_releases
WHERE rn = 1
ORDER BY
  cd_count DESC,
  release_year ASC
;
