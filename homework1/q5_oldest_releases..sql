WITH top_10_artists AS (
  SELECT 
    a.id AS artist_id,
    a.name AS artist_name,
    COUNT(DISTINCT r.id) AS release_count 
  FROM artist a
  JOIN area ar ON ar.id = a.area
  JOIN artist_credit_name acn ON a.id = acn.artist
  JOIN release r ON acn.artist_credit = r.artist_credit
  WHERE
    ar.name = 'United States'
    AND a.begin_date_year = 1989
  GROUP BY a.id, a.name
  ORDER BY release_count DESC, a.id ASC
  LIMIT 10
),

unique_releases AS (
  SELECT DISTINCT
    t10.artist_id,
    t10.artist_name,
    t10.release_count,
    r.name AS release_name,
    ri.date_year, 
    ri.date_month, 
    ri.date_day
  FROM top_10_artists t10
  JOIN artist_credit_name acn ON t10.artist_id = acn.artist
  JOIN release r ON acn.artist_credit = r.artist_credit
  JOIN release_info ri ON r.id = ri.release

  WHERE 
    ri.date_year IS NOT NULL 
    AND ri.date_month IS NOT NULL 
    AND ri.date_day IS NOT NULL
),

ranked_release AS (
  SELECT
    artist_id,
    artist_name,
    release_count,
    release_name,
    date_year, date_month, date_day,
    date_year || '-' || date_month || '-' || date_day AS release_date,
    ROW_NUMBER() OVER (
      PARTITION BY artist_id 
      ORDER BY 
        date_year ASC, 
        date_month ASC, 
        date_day ASC, 
        release_name ASC
    ) AS release_rank
  FROM unique_releases
)

SELECT 
    artist_name AS ARTIST_NAME,
    release_name AS RELEASE_NAME,
    release_date AS RELEASE_DATE
FROM ranked_release
WHERE release_rank <= 5
ORDER BY 
    release_count DESC,
    artist_name ASC,
    release_name ASC,
    date_year ASC,
    date_month ASC,
    date_day ASC;
