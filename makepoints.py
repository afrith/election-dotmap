#!/usr/bin/env python3

import sys
import psycopg2
from shapely import wkb
from shapely.geometry import Point
from ghalton import Halton
from binascii import a2b_hex

prefix = sys.argv[1]

# con = psycopg2.connect('host=127.0.0.1 port=54321 user=postgres password=algebra2009 dbname=dotelec')
con = psycopg2.connect('host=db1 port=5432 user=postgres password=algebra2009 dbname=dotelec')
cur1 = con.cursor()
cur2 = con.cursor()

cur1.execute('SELECT COUNT(*) FROM isec JOIN vd ON vd_gid = vd.gid WHERE LEFT(vd.code, %s) = %s', (len(prefix), prefix))
count = cur1.fetchone()[0]

cur1.execute('SELECT vd.code, isec.anc, isec.da, isec.eff, isec.ifp, isec.other, isec.geom FROM isec JOIN vd ON vd_gid = vd.gid WHERE LEFT(vd.code, %s) = %s', (len(prefix), prefix))

i = 0
for record in cur1:
    (vdcode, anc, da, eff, ifp, other, geom) = record
    shape = wkb.loads(a2b_hex(geom))

    (minx, miny, maxx, maxy) = shape.bounds
    sizex = maxx - minx
    sizey = maxy - miny

    seq = Halton(2)

    def genpoints(party, howmany):
        made = 0
        while made < howmany:
            (hx, hy) = seq.get(1)[0]
            x = minx + (hx * sizex)
            y = miny + (hy * sizey)
            pt = Point(x, y)
            if pt.within(shape):
                cur2.execute('INSERT INTO voter (party, geom) SELECT %s, ST_SetSRID(ST_MakePoint(%s, %s), 4326)', (party, x, y))
                made = made + 1

    genpoints(0, anc)
    genpoints(1, da)
    genpoints(2, eff)
    genpoints(3, ifp)
    genpoints(4, other)

    i = i + 1

    print('done %d of %d (%f percent)' % (i, count, i*100.0/count))

    con.commit()
