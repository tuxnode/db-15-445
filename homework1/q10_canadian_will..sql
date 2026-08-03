WITH artist_areas AS (
  SELECT DISTINCT
    a.id AS artist_id,
    a.name AS artist_name,
    release_ar.name AS area_name
  FROM artist a
  JOIN artist_credit_name acn ON acn.artist = a.id
  JOIN artist_credit ac ON ac.id = acn.artist_credit
  JOIN release r ON r.artist_credit = ac.id
  JOIN release_info ri ON ri.release = r.id
  JOIN area release_ar ON release_ar.id = ri.area
  WHERE
    a.name LIKE 'will%'
    AND release_ar.name IS NOT NULL
  ORDER BY
    a.id, release_ar.name ASC
),

artist_filter AS (
  SELECT
    artist_name,
    COUNT(area_name) AS area_count,
    GROUP_CONCAT(area_name, ',') AS area_names
  FROM artist_areas
  GROUP BY
    artist_id,
    artist_name
  HAVING 
    SUM(CASE WHEN area_name = 'Canada' THEN 1 ELSE 0 END) > 0
    AND SUM(CASE WHEN area_name = 'United States' THEN 1 ELSE 0 END) = 0
)

SELECT
  artist_name || '|' ||
  area_count || '|' ||
  area_names
FROM artist_filter
ORDER BY
  area_count DESC,
  artist_name ASC;
