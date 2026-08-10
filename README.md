# Netflix Content Analytics

A Power BI report over the Netflix titles catalogue, backed by SQL Server, with
a standalone HTML version of the same dashboard.

**Status:** working, with three data-integrity defects that must be fixed before
any number here is quotable. See [Evaluation](#evaluation).

## Live Dashboard

**Live link:** https://anushar-214.github.io/Netflix-Data-analysis--Project-3/netflix_dashboard.html

This is the `netflix_dashboard.html` file above, served live via GitHub Pages.

## Power BI Report

**Report link (requires sign-in):** https://app.powerbi.com/groups/me/reports/9bf97408-3df5-4674-92ad-311e1a37afdd?ctid=d3de91d7-5bb6-4ce1-a775-489e8e7143a8&pbi_source=linkShare

This opens the Power BI report in the Power BI Service. It is **not** anonymously public — you
need a Microsoft account that has been granted access to the workspace. If you hit a sign-in
wall, use the live HTML dashboard above instead.

To explore the report yourself, download `Netflix_dashboard_v4_indigo.pbix` from this repo and
open it in Power BI Desktop (free from Microsoft).

---

## Contents

| File | What it is |
|---|---|
| `Netflix_dashboard_v4_indigo.pbix` | The report. Midnight Indigo theme, repaired filters, corrected line chart. |
| `netflix_project.sql` | Schema, cleaning views, bridge views, and one query per visual. |
| `netflix_dataset.csv` | 5,336 rows exported from the model. UTF-8 with BOM. |
| `netflix_dashboard.html` | Self-contained interactive dashboard. No server, no CDN, 139 KB. |
| `MidnightIndigo_theme.json` | The theme on its own, for `View → Themes → Browse`. |
| `icon_*.png` | Four KPI icons — film strip, clapperboard, TV, globe. |
| `Netflix_PBIX_fix_notes.md` | Step-by-step fixes that must be applied in Power BI Desktop. |

---

## The data

One table, `dbo.netflix`, one row per title.

| Column | Notes |
|---|---|
| `show_id` | Primary key, `s1`–`s8807` in the source |
| `type` | `Movie` or `TV Show` |
| `title`, `director`, `cast`, `description` | Free text |
| `country` | **Comma-separated list.** `"United States, India, France"` is one value. |
| `listed_in` | **Comma-separated list** of genres. Same problem. |
| `date_added` | 2008-01-01 → 2021-09-24 |
| `release_year` | 1942 → 2021 |
| `rating` | 15 real maturity ratings, plus 3 rows corrupted by column shift |
| `duration` | **Mixed units.** `"90 min"` for movies, `"2 Seasons"` for shows. |

The two multi-value columns and the mixed-unit duration are the three things
that make this dataset harder than it looks. Every defect in the Evaluation
section traces back to one of them.

---

## Architecture

```
netflix_titles.csv
        │
        ▼
  SQL Server  ──  dbo.netflix
        │
        ├── vw_netflix_clean     blanks filled, rating/duration repaired,
        │                        duration split into value + unit
        ├── vw_title_country     one row per title-country pair
        └── vw_title_genre       one row per title-genre pair
                │
                ▼
         Power BI import
                │
                ├── measures (DAX)
                └── report page → 4 KPI cards, 5 charts, 4 slicers
```

The bridge views exist because `DISTINCTCOUNT` on a comma-separated column
counts combinations. The raw `country` column has 604 distinct values for about
120 real countries; `listed_in` has 335 for 42 real genres.

---

## Setup

**Database**

```sql
-- runs top to bottom, creates DB, table, indexes and all four views
:r netflix_project.sql
```

Then load the data — uncomment the `BULK INSERT` block in section 1 and point it
at your CSV.

**Power BI**

1. Open the `.pbix`.
2. `Transform data → Manage Parameters`. Create `SqlServer` and `SqlDatabase`
   as text parameters. The file currently hardcodes
   `DESKTOP-8ONM2ET\SQLEXPRESS`, which only resolves on one machine.
3. Repoint the `netflix` query at `vw_netflix_clean` and add two more against
   the bridge views.
4. `File → Options → Current File → Data Load` → untick **Auto date/time**.

**HTML dashboard**

Double-click it. Data is embedded; nothing to install.

---

## Measures

```dax
Total Titles = DISTINCTCOUNT ( netflix[show_id] )
Total Movies = CALCULATE ( [Total Titles], netflix[type] = "Movie" )
Total TV Shows = CALCULATE ( [Total Titles], netflix[type] = "TV Show" )
Number of Countries = DISTINCTCOUNT ( Title_Country[country] )
Number of Genres = DISTINCTCOUNT ( Title_Genre[genre] )
Movie Share % = DIVIDE ( [Total Movies], [Total Titles] )
Avg Movie Runtime (min) =
    CALCULATE ( AVERAGE ( netflix[duration_value] ), netflix[duration_unit] = "min" )
```

`Number of Countries` and `Number of Genres` depend on the bridge tables. Point
them at the raw columns and they inflate roughly 5x and 8x respectively.

---

## Evaluation

### What the report gets right

The metric selection is sensible — catalogue size, the movie/TV split, growth
over time, and geographic and genre concentration are the four questions anyone
asks of a content catalogue. The visual grammar mostly fits the data: a donut
for a two-way split, bars for ranked categories, a line for a time series. Four
slicers on the dimensions that matter. As a structure it holds up.

### Severity 1 — numbers are wrong

**The catalogue is 39% smaller than it should be.** Power Query drops every row
where `director` or `cast` is blank:

```m
#"Filtered Rows"  = Table.SelectRows(dbo_netflix, each [director] <> null and [director] <> ""),
#"Filtered Rows2" = Table.SelectRows(#"Filtered Rows1", each [cast] <> null and [cast] <> ""),
```

Netflix has no director credit for roughly a third of titles and no cast for
most stand-up specials. Those are valid titles. 8,807 becomes 5,336.

**TV shows are effectively gone.** The same filter removes almost every series,
because the source leaves `cast` empty for most of them. The model holds **147**
TV shows against a true count near **2,676** — a 94% loss. The donut reads 97%
movies. That is not a finding about Netflix; it is the bug, rendered as a chart.
This is the single most misleading thing on the page.

**Country and genre counts count combinations.** `DISTINCTCOUNT(netflix[country])`
returns 604. There are 109 real countries in this data.

### Severity 2 — the report opened lying

Found and fixed, but worth recording because each was invisible in the UI:

- The `type` slicer had `"Movie"` **saved as its selection**. The report opened
  pre-filtered. The *Total TV Shows* card read blank and nobody could see why.
- A page-level filter on `country` with **require single select**, silently
  collapsing every visual to one country.
- A page-level filter on `show_id` in **inverted selection mode** — invisible
  row exclusion with no indication in the filter pane.
- A malformed Advanced arithmetic filter on the *Total Titles* card.
- Two duplicate empty report-level filters on `show_id`.

### Severity 2 — a chart that meant nothing

The line chart plotted `SUM(release_year)` against `title`. Summing calendar
years across thousands of rows produces a number with no interpretation, on an
axis of several thousand categories. Rebuilt as count of titles by release year,
which is the trend the chart was clearly reaching for.

### Severity 3 — model hygiene

- An empty measure named `Measure`, which is the red error triangle in the field
  list and blocks model validation. Delete it.
- Auto date/time is on, generating two hidden date tables and giving no usable
  calendar. Replace with a proper `Date` table.
- Three `Table.Sort` steps in Power Query that do nothing for a tabular model and
  cost refresh time.
- The data source hardcodes a local instance, so refresh fails everywhere else
  and it cannot be published without a gateway.

### Severity 3 — presentation

Original layout had zero page margins, zero gutters, and a 114px-tall donut.
Slicers were unlabelled, so nothing indicated what filtered what. Fonts mixed
Constantia with Power BI defaults. All rebuilt on a 16px grid with one type
family.

### Verdict

| Dimension | Rating |
|---|---|
| Question selection | Strong |
| Chart-to-data fit | Good, after the line chart fix |
| Data integrity | **Failing** — three defects, one severe |
| Model hygiene | Weak — broken measure, auto date tables, no date dimension |
| Portability | **Failing** — hardcoded local server |
| Presentation | Good, after rework |

The analysis is sound in shape and unreliable in substance. Nothing here needs
rethinking; it needs the Power Query filters corrected and the two multi-value
columns split. That is perhaps an hour of work, and it is the difference between
a dashboard that looks finished and one that is.

---

## What the data actually says

From the model as it stands — **movies only**, so read these as a movie
catalogue, not the Netflix catalogue.

- **5,336 titles**, 5,189 movies and 147 series.
- **63% released since 2015.** Only 8% predate 2000. This is a recent-content
  library, not an archive.
- **2017 was the peak release year** at 658 titles; the count falls away sharply
  through 2021, though recency effects in the source explain part of that.
- **Additions peaked in 2019** at 1,265 titles, then flattened.
- **The United States supplies 2,488 titles**, India 940, the United Kingdom
  485. The top three account for over half the catalogue.
- **International Movies (2,369) and Dramas (2,294)** dominate genres, with
  Comedies third at 1,553.
- **Average movie runtime is 103 minutes**, median 101 — a tight distribution.
- **TV-MA (1,822) and TV-14 (1,214)** cover 57% of titles.

---

## Known limitations

- Counts are per title, so a title in three countries contributes to three
  country bars. Country and genre bars do not sum to the catalogue size, by
  design.
- `duration` mixes minutes and seasons. Never average the raw column.
- Three rows carry a duration string in the `rating` column, a column-shift
  defect in the source CSV. `vw_netflix_clean` repairs them.
- `date_added` reflects when a title entered the catalogue, not when it left.
  The dataset is a snapshot; removed titles are absent, so trends before 2021
  are survivorship-biased.
- The HTML dashboard embeds a static snapshot. Refresh the SQL layer and it will
  not update on its own.

---

## Roadmap

1. Fix the Power Query filters and rebuild the bridge tables. Everything below
   depends on this.
2. Add the `Date` table and time-intelligence measures.
3. Second page for TV shows specifically — season counts, series longevity —
   which only becomes possible once the 2,676 shows come back.
4. Cast and director network analysis; the `cast` column is unused.
5. Text analysis over `description` for theme clustering.
