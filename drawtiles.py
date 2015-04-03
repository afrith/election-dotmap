from dotmap import TileDrawer, deg2num

import math, subprocess, os, sys

zoom = int(sys.argv[1])

(minx, miny) = deg2num(-22.127,16.45, zoom)
(maxx, maxy) = deg2num(-34.834,32.892, zoom)

#(minx, miny) = deg2num(-33.67,18.21, zoom)
#(maxx, maxy) = deg2num(-34.38,18.98, zoom)

#(minx, miny) = deg2num(-33.8887,18.3790, zoom)
#(maxx, maxy) = deg2num(-33.9923,18.5373, zoom)

os.mkdir("tiles/%d" % zoom)

td = TileDrawer()

for x in range(minx, maxx + 1):
    #print("%d" % ((x - minx)*100/(maxx + 1 - minx)))
    os.mkdir("tiles/%d/%d" % (zoom, x))
    for y in range(miny, maxy + 1):
        print('rendering (%d, %d)' % (x, y))
        name = "tiles/%d/%d/%d.png" % (zoom, x, y)
        td.render_to_file(zoom, x, y, name)
