
/* ----------------------------------------------------------------------------
   1. SCHEMA
   -------------------------------------------------------------------------- */

IF DB_ID('NetflixDBss') IS NULL
    CREATE DATABASE NetflixDBss;
GO

USE NetflixDBss;
GO

IF OBJECT_ID('dbo.netflix', 'U') IS NOT NULL
    DROP TABLE dbo.netflix;
GO

CREATE TABLE dbo.netflix
(
    show_id       VARCHAR(10)    NOT NULL,
    [type]        VARCHAR(20)    NULL,
    title         NVARCHAR(400)  NULL,
    director      NVARCHAR(500)  NULL,
    [cast]        NVARCHAR(1200) NULL,
    country       NVARCHAR(500)  NULL,
    date_added    DATE           NULL,
    release_year  SMALLINT       NULL,
    rating        VARCHAR(20)    NULL,
    duration      VARCHAR(30)    NULL,
    listed_in     NVARCHAR(400)  NULL,
    [description] NVARCHAR(1000) NULL,
    CONSTRAINT PK_netflix PRIMARY KEY CLUSTERED (show_id)
);
GO

CREATE INDEX IX_netflix_type_year ON dbo.netflix ([type], release_year);
CREATE INDEX IX_netflix_rating    ON dbo.netflix (rating);
GO



IF OBJECT_ID('dbo.vw_netflix_clean', 'V') IS NOT NULL
    DROP VIEW dbo.vw_netflix_clean;
GO

CREATE VIEW dbo.vw_netflix_clean
AS
SELECT
    n.show_id,
    NULLIF(LTRIM(RTRIM(n.[type])), '')                       AS [type],
    LTRIM(RTRIM(n.title))                                    AS title,
    COALESCE(NULLIF(LTRIM(RTRIM(n.director)),  ''), 'Unknown') AS director,
    COALESCE(NULLIF(LTRIM(RTRIM(n.[cast])),    ''), 'Unknown') AS [cast],
    COALESCE(NULLIF(LTRIM(RTRIM(n.country)),   ''), 'Unknown') AS country,
    n.date_added,
    n.release_year,

    
    CASE WHEN n.rating LIKE '%min' THEN 'Unrated'
         ELSE COALESCE(NULLIF(LTRIM(RTRIM(n.rating)), ''), 'Unrated')
    END                                                      AS rating,

    CASE WHEN n.rating LIKE '%min' AND NULLIF(n.duration, '') IS NULL
         THEN n.rating ELSE n.duration
    END                                                      AS duration,


    TRY_CAST(LEFT(CASE WHEN n.rating LIKE '%min' AND NULLIF(n.duration,'') IS NULL
                       THEN n.rating ELSE n.duration END,
                  NULLIF(CHARINDEX(' ', CASE WHEN n.rating LIKE '%min'
                                                  AND NULLIF(n.duration,'') IS NULL
                                             THEN n.rating ELSE n.duration END), 0) - 1)
             AS INT)                                         AS duration_value,
    LTRIM(SUBSTRING(CASE WHEN n.rating LIKE '%min' AND NULLIF(n.duration,'') IS NULL
                         THEN n.rating ELSE n.duration END,
                    NULLIF(CHARINDEX(' ', CASE WHEN n.rating LIKE '%min'
                                                    AND NULLIF(n.duration,'') IS NULL
                                               THEN n.rating ELSE n.duration END), 0),
                    30))                                     AS duration_unit,

    n.listed_in,
    n.[description]
FROM dbo.netflix AS n
WHERE NULLIF(LTRIM(RTRIM(n.show_id)), '') IS NOT NULL;
GO




IF OBJECT_ID('dbo.vw_title_country', 'V') IS NOT NULL DROP VIEW dbo.vw_title_country;
GO
CREATE VIEW dbo.vw_title_country
AS
SELECT c.show_id,
       LTRIM(RTRIM(s.value)) AS country
FROM   dbo.vw_netflix_clean AS c
CROSS APPLY STRING_SPLIT(c.country, ',') AS s
WHERE  LTRIM(RTRIM(s.value)) NOT IN ('', 'Unknown');
GO

IF OBJECT_ID('dbo.vw_title_genre', 'V') IS NOT NULL DROP VIEW dbo.vw_title_genre;
GO
CREATE VIEW dbo.vw_title_genre
AS
SELECT g.show_id,
       LTRIM(RTRIM(s.value)) AS genre
FROM   dbo.vw_netflix_clean AS g
CROSS APPLY STRING_SPLIT(g.listed_in, ',') AS s
WHERE  LTRIM(RTRIM(s.value)) <> '';
GO


/* ----------------------------------------------------------------------------
   4. DASHBOARD QUERIES

    COUNT(DISTINCT show_id)                                              AS total_titles,
    COUNT(DISTINCT CASE WHEN [type] = 'Movie'   THEN show_id END)        AS total_movies,
    COUNT(DISTINCT CASE WHEN [type] = 'TV Show' THEN show_id END)        AS total_tv_shows,
    (SELECT COUNT(DISTINCT country) FROM dbo.vw_title_country)           AS number_of_countries,
    CAST(100.0 * COUNT(DISTINCT CASE WHEN [type] = 'Movie' THEN show_id END)
         / NULLIF(COUNT(DISTINCT show_id), 0) AS DECIMAL(5,1))           AS movie_share_pct
FROM dbo.vw_netflix_clean;


/* Movies vs TV shows  */
SELECT
    [type],
    COUNT(*) AS titles,
    CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS DECIMAL(5,1)) AS pct_of_total
FROM dbo.vw_netflix_clean
WHERE [type] IS NOT NULL
GROUP BY [type]
ORDER BY titles DESC;


/*   Titles released per year */

SELECT
    release_year,
    COUNT(*)                                                    AS titles,
    SUM(COUNT(*)) OVER (ORDER BY release_year)                  AS running_total
FROM dbo.vw_netflix_clean
WHERE release_year IS NOT NULL
GROUP BY release_year
ORDER BY release_year;


/*  Top 10 countries  */
SELECT TOP (10)
    country,
    COUNT(DISTINCT show_id) AS titles
FROM dbo.vw_title_country
GROUP BY country
ORDER BY titles DESC;


/* -- 4.5  Titles by maturity rating  (column) ----------------------------- */
SELECT
    rating,
    COUNT(*) AS titles,
    CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS DECIMAL(5,1)) AS pct_of_total
FROM dbo.vw_netflix_clean
GROUP BY rating
ORDER BY titles DESC;


/* -- 4.6  Top 10 genres  (bar) -------------------------------------------- */
SELECT TOP (10)
    genre,
    COUNT(DISTINCT show_id) AS titles
FROM dbo.vw_title_genre
GROUP BY genre
ORDER BY titles DESC;


/* ----------------------------------------------------------------------------
   5. SUPPORTING ANALYSIS
   Not on the dashboard, but each one answers a question the current page
   raises and cannot settle.
   -------------------------------------------------------------------------- */

/* -- 5.1  How much does the blank-director/cast filter actually cost? ------ */
SELECT
    COUNT(*)                                                                AS rows_total,
    SUM(CASE WHEN NULLIF(LTRIM(RTRIM(director)), '') IS NULL THEN 1 ELSE 0 END) AS missing_director,
    SUM(CASE WHEN NULLIF(LTRIM(RTRIM([cast])),   '') IS NULL THEN 1 ELSE 0 END) AS missing_cast,
    SUM(CASE WHEN NULLIF(LTRIM(RTRIM(country)),  '') IS NULL THEN 1 ELSE 0 END) AS missing_country,
    SUM(CASE WHEN NULLIF(LTRIM(RTRIM(director)), '') IS NULL
               OR NULLIF(LTRIM(RTRIM([cast])),   '') IS NULL
               OR NULLIF(LTRIM(RTRIM(country)),  '') IS NULL
             THEN 1 ELSE 0 END)                                             AS dropped_by_current_filters
FROM dbo.netflix;


/* -- 5.2  Average movie runtime and season count by year ------------------ */
SELECT
    release_year,
    AVG(CASE WHEN duration_unit = 'min' THEN duration_value END) AS avg_movie_minutes,
    AVG(CASE WHEN duration_unit LIKE 'Season%' THEN duration_value END) AS avg_seasons
FROM dbo.vw_netflix_clean
WHERE release_year >= 2000
GROUP BY release_year
ORDER BY release_year;


/* -- 5.3  Lag between release and being added to Netflix ------------------ */
SELECT
    YEAR(date_added)                                        AS year_added,
    COUNT(*)                                                AS titles_added,
    AVG(YEAR(date_added) - release_year)                    AS avg_years_since_release
FROM dbo.vw_netflix_clean
WHERE date_added IS NOT NULL AND release_year IS NOT NULL
GROUP BY YEAR(date_added)
ORDER BY year_added;


/* -- 5.4  Top genre within each of the top countries ---------------------- */
WITH ranked AS
(
    SELECT
        c.country,
        g.genre,
        COUNT(*)                                                          AS titles,
        ROW_NUMBER() OVER (PARTITION BY c.country ORDER BY COUNT(*) DESC) AS rn
    FROM dbo.vw_title_country AS c
    JOIN dbo.vw_title_genre   AS g ON g.show_id = c.show_id
    GROUP BY c.country, g.genre
)
SELECT country, genre, titles
FROM ranked
WHERE rn = 1
  AND country IN (SELECT TOP (10) country
                  FROM dbo.vw_title_country
                  GROUP BY country
                  ORDER BY COUNT(DISTINCT show_id) DESC)
ORDER BY titles DESC;


/* -- 5.5  Directors with the most titles ---------------------------------- */
SELECT TOP (15)
    director,
    COUNT(*) AS titles
FROM dbo.vw_netflix_clean
WHERE director <> 'Unknown'
GROUP BY director
ORDER BY titles DESC;


  
