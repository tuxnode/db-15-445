WITH groups AS (
  SELECT
    a.id AS artist_id,
    a.begin_date_year
  FROM artist a

  JOIN artist_type atp ON atp.id = a.type
  JOIN area aarea ON aarea.id = a.area  

  WHERE
    a.begin_date_year >= 1930
    AND a.begin_date_year <= 1979
    AND atp.name = 'Group'
    AND aarea.name = 'United States'
),

release_count AS (
  SELECT
    g.artist_id,
    (g.begin_date_year / 10) * 10 AS decade,
    COUNT(DISTINCT r.id) AS total_releases
  FROM groups g

  JOIN artist_credit_name acn ON acn.artist = g.artist_id
  JOIN artist_credit ac ON ac.id = acn.artist_credit
  JOIN release r ON r.artist_credit = ac.id
  JOIN release_info ri ON ri.release = r.id
  JOIN area ar ON ar.id = ri.area

  WHERE
    ri.date_year IS NOT NULL
    AND ri.area IS NOT NULL
    AND ar.name != 'United States'
    AND (ri.date_year / 10) = (g.begin_date_year / 10)

  GROUP BY
    g.artist_id,
    (g.begin_date_year / 10) * 10
)

SELECT
  CAST(decade AS TEXT) || 's' AS DECADE,
  SUM(total_releases) AS RELEASE_COUNT
FROM release_count
GROUP BY decade
ORDER BY decade ASC;

