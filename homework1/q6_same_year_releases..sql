WITH same_year AS (
  SELECT DISTINCT
    a.id AS artist_id,
    a.name AS artist_name,
    r.name AS release_name,
    ri.date_year,
    ri.date_month,
    ri.date_day
    
  FROM artist a
  JOIN artist_type at ON a.type = at.id
  JOIN artist_credit_name acn ON acn.artist = a.id
  JOIN artist_credit ac ON ac.id = acn.artist_credit
  JOIN release r ON r.artist_credit = ac.id
  JOIN release_info ri ON ri.release = r.id

  WHERE
    at.name = 'Orchestra'
    AND ri.date_year IS NOT NULL
),

ranked_releases AS (
  SELECT
    artist_id,
    artist_name,
    release_name,
    date_year,
    ROW_NUMBER() OVER (
      PARTITION BY artist_id
      ORDER BY
        date_year ASC,
        COALESCE(date_month, 0) ASC,
        COALESCE(date_day, 0) ASC,
        release_name ASC
    ) AS rn
  FROM same_year
)

SELECT 
  r1.date_year || '|' || r1.artist_name || '|' || r1.release_name || '|' || r2.release_name
FROM ranked_releases r1
JOIN ranked_releases r2 
  ON r1.artist_id = r2.artist_id 
  AND r1.rn = 1 
  AND r2.rn = 2
WHERE 
  r1.date_year = r2.date_year
  AND r1.date_year BETWEEN 2001 AND 2010
ORDER BY 
  r1.date_year ASC, 
  r1.artist_name ASC, 
  r1.release_name ASC, 
  r2.release_name ASC;
