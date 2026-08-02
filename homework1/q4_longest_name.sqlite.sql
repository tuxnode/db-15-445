WITH ranked_artists AS (
    SELECT 
        ar.name AS AREA_NAME,
        a.name AS ARTIST_NAME,
        LENGTH(a.name) AS name_length,
        RANK() OVER (
            PARTITION BY ar.name 
            ORDER BY LENGTH(a.name) DESC
        ) as rnk
    FROM artist a
    JOIN area ar ON a.area = ar.id
    JOIN artist_type at ON a.type = at.id
    WHERE 
        ar.name LIKE 'Z%' 
        AND at.name = 'Group'
)
SELECT 
    AREA_NAME,
    ARTIST_NAME
FROM ranked_artists
WHERE rnk = 1
ORDER BY 
    AREA_NAME ASC,
    ARTIST_NAME ASC;
