# MusicBrainz SQL 练习总结笔记

CMU 15-445 风格的家庭作业：在一份 MusicBrainz 数据集（`musicbrainz-cmudb2026.db`，SQLite）上写了 10 条查询，从最普通的查字典到三层 CTE 加窗口函数。下面把每个题怎么想、怎么写、踩了什么坑，以及最后提炼出来的公共知识都记下来。

## 数据模型：先把这张关系图背下来

作业里实际用到的表只有 16 张里的 14 张，核心关系是这样：

```
artist (id, name, begin_date_*, end_date_*, type, area, gender)
  ├─ type   → artist_type   (Character / Choir / Group / Orchestra / Other / Person)
  ├─ area   → area          (地区，如 England, United States, Z 开头的一堆城市)
  └─ gender → gender        (Male / Female)

artist_credit (id, name, artist_count)      ← 一张"署名"
artist_credit_name (artist_credit, position, artist, name)
  ├─ artist_credit → artist_credit.id
  └─ artist        → artist.id

release (id, name, artist_credit, status, language)
  ├─ artist_credit → artist_credit.id
  └─ language      → language.id
release_info (release, area, date_year, date_month, date_day)
  ├─ release → release.id
  └─ area    → area.id
medium (id, release, position, format, name)
  ├─ release → release.id
  └─ format  → medium_format.id
```

**整份作业的关键，是理解 `artist_credit` 这层桥。** MusicBrainz 里一张专辑（release）不是直接挂一个艺人，而是挂一条 `artist_credit`（署名），这条署名再挂一个或多个艺人（`artist_credit_name`）。所以：

- `artist_count = 1` 意味着这条署名只有一个人 → 独唱专辑（q2 用）。
- 一条 `artist_credit` 上挂了两个人，说明他们共享了同一次署名 → "合作"（q7 用）。
- 判断一个艺人出了什么专辑，永远要绕 `artist → artist_credit_name → artist_credit → release` 这一圈。

日期被拆成三个字段存（`date_year / date_month / date_day`），而不是一个 DATE。这是数据模型设计的历史遗留，也是 q3、q5、q6 里一堆 `IS NOT NULL` 和拼接的源头。

## 逐题讲解

### q1：热身：看看有哪些艺术家类型

```sql
SELECT DISTINCT(name) FROM artist_type ORDER BY name;
```

结果：Character, Choir, Group, Orchestra, Other, Person。就一条查询，作用是把数据字典摸一遍，后面的题都要按 `type` 过滤。

坑：原文件名里把表名拼成了 `artitt_type`，跑会报错，正确是 `artist_type`。

### q2：1970 年代出生的英格兰独唱艺人

```sql
SELECT DISTINCT artist.name FROM artist
  JOIN area AS ar ON artist.area = ar.id
  JOIN artist_type AS at ON artist.type = at.id
  JOIN artist_credit_name AS acn ON artist.id = acn.artist
  JOIN artist_credit ac ON acn.artist_credit = ac.id
  WHERE artist.begin_date_year BETWEEN 1970 AND 1979
    AND at.name = 'Person'
    AND ar.name = 'England'
    AND ac.artist_count = 1
  ORDER BY artist.name;
```

思路：三个独立条件，分别需要连 `area`、`artist_type`、`artist_credit` 三张表，一次 JOIN 链全部满足。

学到的东西：

- `DISTINCT` 是必须的。一个艺人出很多专辑，每次挂 credit 都进结果，不去重就全是重复行。
- 独唱的判断是 `ac.artist_count = 1`，别想在 `artist_credit_name` 上数行数，那会漏掉 `DISTINCT` 之外的细节，直接看署名记录里的人数最稳。
- 这题有个 duckdb 版（`q2_solo_artist.duckdb.sql`），把 `SELECT` 挪到了 `FROM` 后面：`FROM artist JOIN ... SELECT DISTINCT a.name WHERE ...`。这是 DuckDB 的 modern SQL 风格（先读数据再投影），习惯 PostgreSQL 的人看着别扭，但它是合法的。

### q3：德语女歌手的近期发行

```sql
SELECT DISTINCT
  CAST(ri.date_year AS VARCHAR) || '-' ||
  CAST(ri.date_month AS VARCHAR) || '-' ||
  CAST(ri.date_day AS VARCHAR) AS RELEASE_DATE,
  r.name AS RELEASE_NAME, artist.name AS ARTIST_NAME
FROM artist
  JOIN artist_credit_name AS acn ON acn.artist = artist.id
  JOIN artist_credit AS ac ON acn.artist_credit = ac.id
  JOIN release AS r ON r.artist_credit = ac.id
  JOIN language AS l ON l.id = r.language
  JOIN gender AS g ON g.id = artist.gender
  JOIN release_info AS ri ON ri.release = r.id
  WHERE l.name = 'German'
    AND g.name = "Female"
    AND ri.date_day IS NOT NULL
    AND ri.date_month IS NOT NULL
    AND ri.date_year IS NOT NULL
  ORDER BY ri.date_year DESC, ri.date_month DESC, ri.date_day DESC,
    RELEASE_NAME ASC, ARTIST_NAME ASC
  LIMIT 10;
```

要点：

- `release.language` 判定语种，`artist.gender` 判定性别，两个都走查字典表。
- 日期在 SQLite 里用 `CAST(... AS VARCHAR) || '-' || ...` 手拼成 `2020-9-25`。duckdb 版直接 `make_date(date_year, date_month, date_day)`，一行搞定，这题就是为对比两种写法准备的。
- **三个日期字段都要 `IS NOT NULL`**，否则拼出来的日期会是 `2020--` 这种残次品。数据里确实大量存在只有年份的发行。
- 注意 `"Female"` 用的是双引号。SQLite 里双引号本应是标识符，找不到对应列时才回退成字符串，语法能跑但这是隐患，统一写单引号 `'Female'` 才是规范做法。

结果的前 10 条是 2020 年的德语音乐，Sophie Rennert 的 Brahms 到 Genuva 的 No Mercy，一眼能看出 ORDER BY 生效了。

### q4：每个 Z 字头地区里名字最长的乐队

```sql
WITH ranked_artists AS (
    SELECT ar.name AS AREA_NAME, a.name AS ARTIST_NAME,
        LENGTH(a.name) AS name_length,
        RANK() OVER (PARTITION BY ar.name ORDER BY LENGTH(a.name) DESC) AS rnk
    FROM artist a
    JOIN area ar ON a.area = ar.id
    JOIN artist_type at ON a.type = at.id
    WHERE ar.name LIKE 'Z%' AND at.name = 'Group'
)
SELECT AREA_NAME, ARTIST_NAME
FROM ranked_artists
WHERE rnk = 1
ORDER BY AREA_NAME ASC, ARTIST_NAME ASC;
```

核心是 `RANK() OVER (PARTITION BY 地区 ORDER BY LENGTH(name) DESC)`：

- `PARTITION BY` 让每个地区独立排名。
- `RANK()` 遇到并列会给出相同名次且**不跳过后续编号**……不对，RANK 会跳过（并列两个第 1，下一个是第 3）。这里要的正是"并列的都保留"，所以选 RANK 而不是 ROW_NUMBER。如果题目只要一个，就该用 ROW_NUMBER。
- 外层再包一层 CTE 取 `rnk = 1`，这是窗口函数的标准套路：窗口函数算出来的别名不能在 WHERE 里直接用，得先投影出来再过滤。

顺带记住 `LENGTH()` 和 `LIKE 'Z%'` 这两个小工具，后面题还会用。

### q5：1989 年成立的美国艺人，各挑 5 张最早发行的专辑

三条 CTE 层层递进，是整份作业里最完整的"流水线"：

```sql
WITH top_10_artists AS (
  SELECT a.id, a.name, COUNT(DISTINCT r.id) AS release_count
  FROM artist a
  JOIN area ar ON ar.id = a.area
  JOIN artist_credit_name acn ON a.id = acn.artist
  JOIN release r ON acn.artist_credit = r.artist_credit
  WHERE ar.name = 'United States' AND a.begin_date_year = 1989
  GROUP BY a.id, a.name
  ORDER BY release_count DESC, a.id ASC
  LIMIT 10
),
unique_releases AS (
  SELECT DISTINCT t10.artist_id, t10.artist_name, t10.release_count,
    r.name AS release_name, ri.date_year, ri.date_month, ri.date_day
  FROM top_10_artists t10
  JOIN artist_credit_name acn ON t10.artist_id = acn.artist
  JOIN release r ON acn.artist_credit = r.artist_credit
  JOIN release_info ri ON r.id = ri.release
  WHERE ri.date_year IS NOT NULL AND ri.date_month IS NOT NULL AND ri.date_day IS NOT NULL
),
ranked_release AS (
  SELECT ..., date_year || '-' || date_month || '-' || date_day AS release_date,
    ROW_NUMBER() OVER (PARTITION BY artist_id
      ORDER BY date_year ASC, date_month ASC, date_day ASC, release_name ASC) AS release_rank
  FROM unique_releases
)
SELECT artist_name, release_name, release_date
FROM ranked_release
WHERE release_rank <= 5
ORDER BY release_count DESC, artist_name ASC, ...;
```

结构很清楚：第一步选出头部艺人（聚合 + LIMIT），第二步展开他们的发行并去重，第三步给每个艺人的发行按日期排序编号，最后截前 5。

三个值得记住的细节：

- **COUNT(DISTINCT r.id) 防坑。** 一个 release 可能对应多条 `release_info`（不同地区/日期版本），不 `DISTINCT` 会重复计数，榜单就错了。
- 排序时 `release_count DESC` 放在最外层，保证艺人顺序跟着第一步的排名走，而不是被中间步骤打乱。
- 结果里能看到真实的 MusicBrainz 脏数据：Green Day 的专辑名里塞了场地名（`1990-05-25 924 Gilman St,. Berkeley, CA`），同名专辑出现在两个日期。数据不干净正是练习的一部分。

### q6：头两张专辑同年发行的交响乐团

```sql
WITH same_year AS (
  SELECT DISTINCT a.id, a.name, r.name, ri.date_year, ri.date_month, ri.date_day
  FROM artist a
  JOIN artist_type at ON a.type = at.id
  JOIN artist_credit_name acn ON acn.artist = a.id
  JOIN artist_credit ac ON ac.id = acn.artist_credit
  JOIN release r ON r.artist_credit = ac.id
  JOIN release_info ri ON ri.release = r.id
  WHERE at.name = 'Orchestra' AND ri.date_year IS NOT NULL
),
ranked_releases AS (
  SELECT artist_id, artist_name, release_name, date_year,
    ROW_NUMBER() OVER (PARTITION BY artist_id
      ORDER BY date_year ASC, COALESCE(date_month, 0) ASC,
        COALESCE(date_day, 0) ASC, release_name ASC) AS rn
  FROM same_year
)
SELECT r1.date_year || '|' || r1.artist_name || '|' || r1.release_name || '|' || r2.release_name
FROM ranked_releases r1
JOIN ranked_releases r2
  ON r1.artist_id = r2.artist_id AND r1.rn = 1 AND r2.rn = 2
WHERE r1.date_year = r2.date_year AND r1.date_year BETWEEN 2001 AND 2010
ORDER BY r1.date_year ASC, r1.artist_name ASC, ...;
```

这题的妙处在**自连接**（self-join）：把同一个表当两张表用。

- 先给每个乐团的全部发行按时间编号（`rn=1` 是第一个，`rn=2` 是第二个）。
- 然后 `ranked_releases r1 JOIN ranked_releases r2`，让 r1 取第 1 张、r2 取第 2 张，二者年份相等，就是"头两张同一年"。
- 只靠"年份相等"还不够，还得限定在 2001–2010，不然范围太宽。
- `COALESCE(date_month, 0)` 处理只有年份、没有月份的发行，NULL 顶到 0，保证排序不崩。

这个"给行编号再自连接取相邻行"的技巧，在做"同一人连续事件"类问题时比任何子查询都清爽。

### q7：匹兹堡交响乐团的好友榜

```sql
WITH favorite_collaborator AS (
  SELECT a_collaborator.name AS collaborator_name,
    COUNT(r.id) AS collaboration_count
  FROM artist a_target
  JOIN artist_credit_name acn_target ON acn_target.artist = a_target.id
  JOIN artist_credit_name acn_collaborator ON acn_collaborator.artist_credit = acn_target.artist_credit
  JOIN artist a_collaborator ON a_collaborator.id = acn_collaborator.artist
  JOIN release r ON r.artist_credit = acn_target.artist_credit
  WHERE a_target.name = 'Pittsburgh Symphony Orchestra'
    AND a_collaborator.id != a_target.id
  GROUP BY a_collaborator.id, a_collaborator.name
  ORDER BY collaboration_count DESC
  LIMIT 15
)
SELECT * FROM favorite_collaborator
  ORDER BY collaboration_count DESC, collaborator_name ASC;
```

这是典型的 **artist_credit_name 自连接**：同一张 credit 上同时挂的两个人 = 一次合作。

- `acn_target` 拿匹兹堡交响，`acn_collaborator` 找同一条 credit 上的其他人，`a_collaborator.id != a_target.id` 把自己摘出去。
- 注意这题统计的是"共享署名的发行数"，所以 `COUNT(r.id)` 是对整个 credit 的发行计数，一个 credit 一次。
- 结果很符合直觉：指挥和乐团长期绑定，Lorin Maazel 合作 24 次稳坐榜首，Manfred Honeck 15 次，后面全是 Sibelius、Brahms 这类作曲家和客座独奏家。

### q8：交响乐团最"高产"的年份

```sql
WITH ranked_release AS (
  SELECT DISTINCT a.id AS artist_id, a.name AS artist_name,
    ri.date_year AS release_year, COUNT(DISTINCT r.id) AS cd_count
  FROM artist a
  JOIN artist_type atp ON atp.id = a.type
  JOIN artist_credit_name acn ON acn.artist = a.id
  JOIN artist_credit ac ON ac.id = acn.artist_credit
  JOIN release r ON r.artist_credit = ac.id
  JOIN release_info ri ON r.id = ri.release
  JOIN medium m ON r.id = m.release
  JOIN medium_format mf ON mf.id = m.format
  WHERE a.name LIKE '%symphony%' AND atp.name = 'Orchestra'
    AND ri.date_year IS NOT NULL AND mf.name LIKE '%CD%'
  GROUP BY a.id, a.name, ri.date_year
  HAVING COUNT(DISTINCT r.id) >= 3
),
ranked_cd_releases AS (
  SELECT artist_name, release_year, cd_count,
    ROW_NUMBER() OVER (PARTITION BY artist_id
      ORDER BY cd_count DESC, release_year ASC) AS rn
  FROM ranked_release
)
SELECT artist_name || '|' || release_year || '|' || cd_count AS result
FROM ranked_cd_releases
WHERE rn = 1
ORDER BY cd_count DESC, release_year ASC;
```

一层层拆开看：

- **CD 的判断藏在介质表里**：`release → medium → medium_format`，`mf.name LIKE '%CD%'` 涵盖 "CD"、"CD-R"、"2×CD" 这类变体。发行量是按 release 数算的，不是按介质数。
- **`GROUP BY a.id, a.name, ri.date_year` 加 `HAVING >= 3`**：每个乐团每年至少出 3 张 CD 才进候选。
- 第二层再按 `cd_count` 排名取 `rn = 1`，找出每个乐团最猛的一年。注意 `HAVING` 已经保证候选都是年产量 3+，所以不会出现没货的年份。
- 结果第一位是 London Symphony Orchestra 1994 年 63 张 CD，实打实的录音工厂。

组合拳：`LIKE` + `HAVING` + 窗口函数排名，正好把前面几题的工具都用上了。

### q9：非美国地区的发行量按十年汇总

```sql
WITH groups AS (
  SELECT a.id AS artist_id, a.begin_date_year
  FROM artist a
  JOIN artist_type atp ON atp.id = a.type
  JOIN area aarea ON aarea.id = a.area
  WHERE a.begin_date_year BETWEEN 1930 AND 1979
    AND atp.name = 'Group' AND aarea.name = 'United States'
),
release_count AS (
  SELECT g.artist_id,
    (g.begin_date_year / 10) * 10 AS decade,
    COUNT(DISTINCT r.id) AS total_releases
  FROM groups g
  JOIN artist_credit_name acn ON acn.artist = g.artist_id
  JOIN artist_credit ac ON ac.id = acn.artist_credit
  JOIN release r ON r.artist_credit = ac.id
  JOIN release_info ri ON ri.release = r.id
  JOIN area ar ON ar.id = ri.area
  WHERE ri.date_year IS NOT NULL AND ri.area IS NOT NULL
    AND ar.name != 'United States'
    AND (ri.date_year / 10) = (g.begin_date_year / 10)
  GROUP BY g.artist_id, (g.begin_date_year / 10) * 10
)
SELECT CAST(decade AS TEXT) || 's' AS DECADE,
  SUM(total_releases) AS RELEASE_COUNT
FROM release_count
GROUP BY decade
ORDER BY decade ASC;
```

思路：1930–1979 年成立的美国乐队，只统计他们"成立那个年代"里非美国地区发行的作品，最后按十年分组求和。

几个要点：

- **十年档位 = 整数除法**：`(year / 10) * 10`，SQLite 整数除法直接截断，1989 → 1980。GROUP BY 和 SELECT 里要写同样的表达式，SQL 不允许用别名参与 GROUP BY（除非支持 position/organizer 的方言）。
- **两个 decade 必须相等**：发行年份所在年代 == 乐队成立年代，保证只统计乐队当打之年的海外发行。
- 第二层已经按 `artist_id, decade` 分组了，最后还要 `SUM(total_releases) GROUP BY decade`，因为一个 decade 里有多个乐队，得把每个乐队的计数再汇总起来。
- 结果是一条漂亮的曲线：1930s 只有 2，1960s 跳到 382，1970s 冲到 752。数据本身讲了一个故事。

### q10：只在加拿大卖、从不进美国的 Will 们

```sql
WITH artist_areas AS (
  SELECT DISTINCT a.id AS artist_id, a.name AS artist_name,
    release_ar.name AS area_name
  FROM artist a
  JOIN artist_credit_name acn ON acn.artist = a.id
  JOIN artist_credit ac ON ac.id = acn.artist_credit
  JOIN release r ON r.artist_credit = ac.id
  JOIN release_info ri ON ri.release = r.id
  JOIN area release_ar ON release_ar.id = ri.area
  WHERE a.name LIKE 'will%' AND release_ar.name IS NOT NULL
  ORDER BY a.id, release_ar.name ASC
),
artist_filter AS (
  SELECT artist_name,
    COUNT(area_name) AS area_count,
    GROUP_CONCAT(area_name, ',') AS area_names
  FROM artist_areas
  GROUP BY artist_id, artist_name
  HAVING SUM(CASE WHEN area_name = 'Canada' THEN 1 ELSE 0 END) > 0
    AND SUM(CASE WHEN area_name = 'United States' THEN 1 ELSE 0 END) = 0
)
SELECT artist_name || '|' || area_count || '|' || area_names
FROM artist_filter
ORDER BY area_count DESC, artist_name ASC;
```

这是整份作业里最精妙的 HAVING 用法：

- **`SUM(CASE WHEN ...)` 做存在性判断**：在 HAVING 里对"是加拿大"和"是美国"分别累加。大于 0 表示出现过，等于 0 表示从没出现过。比 `IN`/`NOT IN` 干净，也不怕重复行。
- 于是"在加拿大发行过，且从未在美国发行"就写成两个 CASE 的和。这是标准技巧，面试题里"出现过 X 没出现过 Y"都用这招。
- `GROUP_CONCAT(area_name, ',')` 把地区名拼成一个字段，顺带展示了 SQLite 的字符串聚合（其他库是 `STRING_AGG`）。
- 结果里有意思的是 `[Worldwide]` 这个地区：它既不是加拿大也不是美国，所以不影响过滤条件，但会出现在拼接结果里，比如 `Canada,Japan,[Worldwide]`。数据里把"全球发行"当成了一个假地区。

## 公共知识点提炼

把这些题过完一遍，真正值得带走的是下面这五件事：

**1. JOIN 链条是 MusicBrainz 的主干。**
`artist → artist_credit_name → artist_credit → release → release_info` 这条线在 9 道题里出现了 8 次。JOIN 的 ON 条件永远写在"引用方 = 被引用方的 id"这个方向，表多了也不会乱。q2 一次连 5 张表，q8 连 8 张，保持每个 ON 独立、WHERE 条件集中，可读性就有保障。

**2. 窗口函数三件套：`ROW_NUMBER()`、`RANK()`、`PARTITION BY`。**
- 要唯一的顺序编号（q5、q6、q8）→ `ROW_NUMBER()`。
- 要并列保留（q4 每个地区名字最长的不止一个）→ `RANK()`。
- 窗口函数算出的别名不能直接在 WHERE 里用，必须先包一层 CTE / 子查询再过滤（q4、q5、q8 都是这么写的）。

**3. `GROUP BY` 配 `HAVING` 能做行级过滤做不到的事。**
`HAVING COUNT(DISTINCT r.id) >= 3`（q8）过滤的是"聚合后的数量"，`HAVING SUM(CASE WHEN ...) > 0 AND ... = 0`（q10）过滤的是"是否存在"。这两类判断在任何 SQL 里都是高频需求。

**4. 脏数据是最好的教材。**
MusicBrainz 的日期缺字段、专辑重复、名字里混场地信息、全球发行被当成地区。所以每个题几乎都要 `IS NOT NULL` 过滤、`DISTINCT` 去重、`COUNT(DISTINCT ...)` 计数。真实世界的 SQL 有一半工作是在跟数据质量搏斗，这作业提前模拟了。

**5. SQLite 与 DuckDB 的写法差异。**
- 字符串拼接：SQLite `a || b`，DuckDB 也支持，但日期组装 DuckDB 有 `make_date()`。
- 字符串字面量统一用单引号，别学 q3 里 `"Female"` 那种双引号写法。
- DuckDB 支持 modern SQL：`FROM ... JOIN ... SELECT`（q2 的 duckdb 版），SQLite 只认传统 `SELECT ... FROM`。
- 分组聚合：SQLite `GROUP_CONCAT`，PostgreSQL/DuckDB 叫 `STRING_AGG`，换库时要记得改。

一句话总结这份作业：**一张数据模型，十道题，把所有 SQL 基本功（JOIN、CTE、窗口函数、聚合、过滤、字符串处理）都过了一遍，顺带让所有人见识了真实音乐数据库能有多乱。**
