DROP VIEW IF EXISTS vd_excess_anc;
DROP VIEW IF EXISTS isec_sort_anc;
DROP VIEW IF EXISTS vd_excess_da;
DROP VIEW IF EXISTS isec_sort_da;
DROP VIEW IF EXISTS vd_excess_eff;
DROP VIEW IF EXISTS isec_sort_eff;
DROP VIEW IF EXISTS vd_excess_ifp;
DROP VIEW IF EXISTS isec_sort_ifp;
DROP VIEW IF EXISTS vd_excess_other;
DROP VIEW IF EXISTS isec_sort_other;

DROP TABLE IF EXISTS isec;
DROP TABLE IF EXISTS sa;
DROP TABLE IF EXISTS vd;

-- VDs

CREATE TABLE vd (
    gid SERIAL PRIMARY KEY,
    code CHAR(8) UNIQUE,
    geom GEOMETRY(MultiPolygon, 4326),
    area FLOAT,
    pop FLOAT,
    votes INT,
    anc INT,
    da INT,
    eff INT,
    ifp INT,
    other INT
);
CREATE INDEX vd_geom ON vd USING gist(geom);

INSERT INTO vd (code, geom, area, votes)
    SELECT vd_code, geom, ST_Area(geom::GEOGRAPHY), votes
    FROM imp_vd INNER JOIN imp_votecount
        ON imp_vd.vdnumber::CHAR(8) = imp_votecount.vd_code;

UPDATE vd SET
        anc = i.anc,
        da = i.da,
        eff = i.eff,
        ifp = i.ifp,
        other = vd.votes - (i.anc + i.da + i.eff + i.ifp)
    FROM imp_results i where vd.code = vd_code;

VACUUM ANALYZE vd;

-- SAs

CREATE TABLE sa (
    gid SERIAL PRIMARY KEY,
    code CHAR(7) UNIQUE,
    geom GEOMETRY(MultiPolygon, 4326),
    area FLOAT,
    pop FLOAT
);
CREATE INDEX sa_geom ON sa USING gist(geom);

INSERT INTO sa (code, geom, area, pop)
    SELECT sa_code, geom, ST_Area(geom::GEOGRAPHY), pop
    FROM imp_sa INNER JOIN imp_sa_pop
        ON imp_sa.sal_code::CHAR(7) = imp_sa_pop.sa_code;

VACUUM ANALYZE sa;

-- Intersections

CREATE TABLE isec (
    gid SERIAL PRIMARY KEY,
    vd_gid INT REFERENCES vd(gid),
    sa_gid INT REFERENCES sa(gid),
    geom GEOMETRY(MultiPolygon, 4326),
    area FLOAT,
    pop FLOAT,
    anc INT,
    rem_anc FLOAT,
    da INT,
    rem_da FLOAT,
    eff INT,
    rem_eff FLOAT,
    ifp INT,
    rem_ifp FLOAT,
    other INT,
    rem_other FLOAT
);
CREATE INDEX isec_vd_gid ON isec(vd_gid);
CREATE INDEX isec_sa_gid ON isec(sa_gid);
CREATE INDEX isec_geom ON isec USING gist(geom);

INSERT INTO isec (vd_gid, sa_gid, geom)
    SELECT vd.gid, sa.gid,
        ST_Multi(ST_CollectionExtract(ST_Intersection(vd.geom, sa.geom), 3))
    FROM vd JOIN sa ON vd.geom && sa.geom;

DELETE FROM isec WHERE ST_IsEmpty(geom);
VACUUM isec;

UPDATE isec SET area = ST_Area(geom::GEOGRAPHY);
VACUUM isec;

UPDATE isec SET pop = sa.pop * isec.area / sa.area FROM sa WHERE sa_gid = sa.gid;
VACUUM isec;

DELETE FROM isec WHERE pop < 6;
VACUUM isec;

-- One VD has no overlap with SAs
INSERT INTO isec (vd_gid, geom, area, pop)
    SELECT vd.gid, vd.geom, ST_Area(vd.geom::GEOGRAPHY), 1
    FROM vd LEFT JOIN isec ON vd.gid = vd_gid WHERE vd_gid IS NULL;

-- Calculate votes per isec

UPDATE vd SET pop = sum_pop
    FROM (SELECT vd_gid, SUM(pop) AS sum_pop FROM isec GROUP BY vd_gid) s
    WHERE vd.gid = vd_gid;
VACUUM vd;

UPDATE isec SET
        anc = FLOOR(vd.anc * isec.pop / vd.pop),
        rem_anc = (vd.anc * isec.pop / vd.pop) - FLOOR(vd.anc * isec.pop / vd.pop),
        da = FLOOR(vd.da * isec.pop / vd.pop),
        rem_da = (vd.da * isec.pop / vd.pop) - FLOOR(vd.da * isec.pop / vd.pop),
        eff = FLOOR(vd.eff * isec.pop / vd.pop),
        rem_eff = (vd.eff * isec.pop / vd.pop) - FLOOR(vd.eff * isec.pop / vd.pop),
        ifp = FLOOR(vd.ifp * isec.pop / vd.pop),
        rem_ifp = (vd.ifp * isec.pop / vd.pop) - FLOOR(vd.ifp * isec.pop / vd.pop),
        other = FLOOR(vd.other * isec.pop / vd.pop),
        rem_other = (vd.other * isec.pop / vd.pop) - FLOOR(vd.other * isec.pop / vd.pop)
    FROM vd WHERE vd_gid = vd.gid;
VACUUM isec;

-- Handle the rounding excess - anc

CREATE OR REPLACE VIEW vd_excess_anc AS
    SELECT vd_gid, vd.anc - SUM(isec.anc) AS excess
    FROM vd JOIN isec ON vd.gid = vd_gid
    GROUP by vd_gid, vd.anc
    HAVING vd.anc > SUM(isec.anc);

CREATE OR REPLACE VIEW isec_sort_anc AS
    SELECT gid, vd_gid, 
        ROW_NUMBER() OVER (PARTITION BY vd_gid ORDER BY rem_anc DESC) as rownum
    FROM isec;

UPDATE isec SET anc = anc + 1
    FROM isec_sort_anc s JOIN vd_excess_anc e ON s.vd_gid = e.vd_gid
    WHERE s.rownum <= e.excess AND isec.gid = s.gid;
VACUUM isec;

-- Handle the rounding excess - da

CREATE OR REPLACE VIEW vd_excess_da AS
    SELECT vd_gid, vd.da - SUM(isec.da) AS excess
    FROM vd JOIN isec ON vd.gid = vd_gid
    GROUP by vd_gid, vd.da
    HAVING vd.da > SUM(isec.da);

CREATE OR REPLACE VIEW isec_sort_da AS
    SELECT gid, vd_gid, 
        ROW_NUMBER() OVER (PARTITION BY vd_gid ORDER BY rem_da DESC) as rownum
    FROM isec;

UPDATE isec SET da = da + 1
    FROM isec_sort_da s JOIN vd_excess_da e ON s.vd_gid = e.vd_gid
    WHERE s.rownum <= e.excess AND isec.gid = s.gid;
VACUUM isec;

-- Handle the rounding excess - eff

CREATE OR REPLACE VIEW vd_excess_eff AS
    SELECT vd_gid, vd.eff - SUM(isec.eff) AS excess
    FROM vd JOIN isec ON vd.gid = vd_gid
    GROUP by vd_gid, vd.eff
    HAVING vd.eff > SUM(isec.eff);

CREATE OR REPLACE VIEW isec_sort_eff AS
    SELECT gid, vd_gid, 
        ROW_NUMBER() OVER (PARTITION BY vd_gid ORDER BY rem_eff DESC) as rownum
    FROM isec;

UPDATE isec SET eff = eff + 1
    FROM isec_sort_eff s JOIN vd_excess_eff e ON s.vd_gid = e.vd_gid
    WHERE s.rownum <= e.excess AND isec.gid = s.gid;
VACUUM isec;

-- Handle the rounding excess - ifp

CREATE OR REPLACE VIEW vd_excess_ifp AS
    SELECT vd_gid, vd.ifp - SUM(isec.ifp) AS excess
    FROM vd JOIN isec ON vd.gid = vd_gid
    GROUP by vd_gid, vd.ifp
    HAVING vd.ifp > SUM(isec.ifp);

CREATE OR REPLACE VIEW isec_sort_ifp AS
    SELECT gid, vd_gid, 
        ROW_NUMBER() OVER (PARTITION BY vd_gid ORDER BY rem_ifp DESC) as rownum
    FROM isec;

UPDATE isec SET ifp = ifp + 1
    FROM isec_sort_ifp s JOIN vd_excess_ifp e ON s.vd_gid = e.vd_gid
    WHERE s.rownum <= e.excess AND isec.gid = s.gid;
VACUUM isec;

-- Handle the rounding excess - other

CREATE OR REPLACE VIEW vd_excess_other AS
    SELECT vd_gid, vd.other - SUM(isec.other) AS excess
    FROM vd JOIN isec ON vd.gid = vd_gid
    GROUP by vd_gid, vd.other
    HAVING vd.other > SUM(isec.other);

CREATE OR REPLACE VIEW isec_sort_other AS
    SELECT gid, vd_gid, 
        ROW_NUMBER() OVER (PARTITION BY vd_gid ORDER BY rem_other DESC) as rownum
    FROM isec;

UPDATE isec SET other = other + 1
    FROM isec_sort_other s JOIN vd_excess_other e ON s.vd_gid = e.vd_gid
    WHERE s.rownum <= e.excess AND isec.gid = s.gid;
VACUUM isec;

-- Point table

CREATE TABLE voter (
    gid SERIAL PRIMARY KEY,
    party INT,
    geom GEOMETRY(Point, 4326)
);
CREATE INDEX voter_geom ON voter USING gist(geom);
