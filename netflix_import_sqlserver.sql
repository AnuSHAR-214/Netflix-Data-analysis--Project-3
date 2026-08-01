-- =========================================================
-- NETFLIX DATA ANALYSIS PROJECT — SQL SERVER / SSMS VERSION
-- =========================================================

-- ---------------------------------------------------------
-- 1. DATABASE & TABLE SETUP
-- ---------------------------------------------------------
CREATE DATABASE NetflixDB;
GO                              -- CREATE DATABASE must be alone in its batch

USE NetflixDB;
GO

DROP TABLE IF EXISTS netflix;
CREATE TABLE netflix (
    show_id      VARCHAR(10)  PRIMARY KEY,
    type         VARCHAR(20),
    title        VARCHAR(300),
    director     VARCHAR(300),
    [cast]       VARCHAR(MAX),   -- CAST is reserved in T-SQL, must be bracketed
    country      VARCHAR(300),
    date_added   VARCHAR(50),
    release_year INT,
    rating       VARCHAR(20),
    duration     VARCHAR(50),
    listed_in    VARCHAR(300),
    description  VARCHAR(MAX)
);
GO

-- ---------------------------------------------------------
-- 2. IMPORT THE CSV
-- ---------------------------------------------------------
-- Requires SQL Server 2017+ (for FORMAT = 'CSV').
--
-- IMPORTANT: the file path below must be readable by the SQL SERVER
-- SERVICE ACCOUNT, not just your Windows login. If you get "Access is
-- denied" or "Cannot bulk load", the file is probably sitting somewhere
-- only your user account can read (e.g. your personal Downloads folder).
-- Copy it to a simple shared path like C:\Temp\netflix_titles.csv and
-- grant read access to the service account (Task Manager > Services tab
-- to find it, usually NT SERVICE\MSSQLSERVER).

BULK INSERT NetflixDB.dbo.netflix
FROM 'C:\Temp\netflix_titles.csv'      -- <-- update to your actual path
WITH (
    FORMAT          = 'CSV',
    FIRSTROW        = 2,               -- skip the header row
    FIELDTERMINATOR = ',',
    FIELDQUOTE      = '"',
    ROWTERMINATOR   = '0x0a',          -- this file has plain LF endings;
                                       -- '\n' gets rewritten to '\r\n' on
                                       -- Windows and silently fails to match
    CODEPAGE        = '65001',         -- file is UTF-8
    TABLOCK
);
GO

-- ---------------------------------------------------------
-- 3. VERIFY THE IMPORT
-- ---------------------------------------------------------
SELECT COUNT(*) AS RowsImported FROM netflix;   -- should read 8807
SELECT * FROM netflix WHERE show_id IS NULL;    -- should return 0 rows
SELECT show_id, title, rating, duration
FROM netflix
WHERE rating LIKE '%min%';                      -- the 3 known bad rows (Louis C.K. titles)
GO
