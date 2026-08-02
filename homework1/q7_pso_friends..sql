WITH favorite_collaborator AS (
  SELECT
    a_collaborator.name AS collaborator_name,
    COUNT(r.id) AS collaboration_count

  FROM artist a_target
  JOIN artist_credit_name acn_target ON acn_target.artist = a_target.id
  JOIN artist_credit_name acn_collaborator ON acn_collaborator.artist_credit = acn_target.artist_credit
  JOIN artist a_collaborator ON a_collaborator.id = acn_collaborator.artist
  JOIN release r ON r.artist_credit = acn_target.artist_credit
  WHERE
    a_target.name = 'Pittsburgh Symphony Orchestra'
    AND a_collaborator.id != a_target.id

  GROUP BY 
    a_collaborator.id, 
    a_collaborator.name
  
  ORDER BY 
    collaboration_count DESC
  LIMIT 15
)

SELECT * FROM favorite_collaborator 
  ORDER BY 
    collaboration_count DESC,
    collaborator_name ASC
;
