import math
import ogr
import cairo
# from PIL import Image, ImageDraw

# starts at index 1
reds = [x/255.0 for x in [77, 55, 228, 255, 153]]
greens = [x/255.0 for x in [175, 126, 26, 127, 153]]
blues = [x/255.0 for x in [74, 184, 28, 0, 153]]

# reds = [77, 55, 228, 255, 153]
# greens = [175, 126, 26, 127, 153]
# blues = [74, 184, 28, 0, 153]

# starts at index 4
opacities = [x/255.0 for x in [153, 153, 179, 179, 204, 204, 230, 230, 255]]
# opacities = [153, 153, 179, 179, 204, 204, 230, 230, 255]
sizes = [0.5, 0.5, 0.5, 0.5, 0.5, 1.0, 1.0, 1.0, 1.0, 1.0]

def num2deg(xtile, ytile, zoom):
    n = 2.0 ** zoom
    lon_deg = xtile / n * 360.0 - 180.0
    lat_rad = math.atan(math.sinh(math.pi * (1 - 2 * ytile / n)))
    lat_deg = math.degrees(lat_rad)
    return (lat_deg, lon_deg)

def deg2num(lat_deg, lon_deg, zoom):
  lat_rad = math.radians(lat_deg)
  n = 2.0 ** zoom
  xtile = int((lon_deg + 180.0) / 360.0 * n)
  ytile = int((1.0 - math.log(math.tan(lat_rad) + (1 / math.cos(lat_rad))) / math.pi) / 2.0 * n)
  return (xtile, ytile)

class TileDrawer(object):

    def __init__(self):
        self.ds = ogr.Open("PG: dbname=voters")

    def render_to_file(self, z, x, y, outfile):
        (maxy, minx) = num2deg(x, y, z)
        (miny, maxx) = num2deg(x+1, y+1, z)

        xfact = 256.0/(maxx - minx)
        yfact = 256.0/(maxy - miny)

        # img = Image.new('RGBA', (256, 256), (255, 255, 255, 0))
        # draw = ImageDraw.Draw(img)

        if maxx > 16.4518 and minx < 32.945 and miny < -22.1248 and maxy > -34.8343:
            srf = cairo.ImageSurface(cairo.FORMAT_ARGB32, 256, 256)
            ctx = cairo.Context(srf)

            opacity = opacities[z - 4]
            size = sizes[z - 4]/2

            lyr = self.ds.ExecuteSQL("SELECT party, geom FROM voter ORDER BY RANDOM()")
            lyr.SetSpatialFilterRect(minx - 10.0/xfact, miny - 10.0/yfact, maxx + 10.0/xfact, maxy + 10.0/yfact)

            keep = False
            for feat in lyr:
                keep = True
                geom = feat.GetGeometryRef()
                code = feat.GetFieldAsInteger(0)

                # x = (geom.GetX() - minx) * xfact
                # y = (maxy - geom.GetY()) * yfact
                # draw.ellipse([x - size, y - size, x + size, y + size], fill = (reds[code], greens[code], blues[code], opacity))
                ctx.set_source_rgba(reds[code], greens[code], blues[code], opacity)
                ctx.arc((geom.GetX() - minx) * xfact, (maxy - geom.GetY()) * yfact, 0.5, 0, 2*math.pi)
                ctx.fill()

            if keep:
                srf.write_to_png(outfile)
        # img.save(outfile, 'PNG')
