object CONVERT_UTILS [
  import_export_id -> "convert_utils"
]
  name: "Conversion Utils"
  parent: GENERIC_UTILS
  owner: HACKER
  readable: true

  property "%" (owner: HACKER, flags: "r") = "1|100";
  property abampere (owner: HACKER, flags: "r") = "10 amp";
  property abcoulomb (owner: HACKER, flags: "r") = "10 coul";
  property abfarad (owner: HACKER, flags: "r") = "10 farad";
  property abhenry (owner: HACKER, flags: "r") = "10 henry";
  property abmho (owner: HACKER, flags: "r") = "10 mho";
  property abohm (owner: HACKER, flags: "r") = "10 ohm";
  property abvolt (owner: HACKER, flags: "r") = "10 volt";
  property acre (owner: HACKER, flags: "r") = "43560 ft2";
  property amp (owner: HACKER, flags: "r") = "ampere";
  property ampere (owner: HACKER, flags: "r") = "coul/sec";
  property amu (owner: HACKER, flags: "r") = "chemamu";
  property angstrom (owner: HACKER, flags: "r") = "1e-8 meter";
  property apdram (owner: HACKER, flags: "r") = "60 grain";
  property apostilb (owner: HACKER, flags: "r") = "cd/pi m2";
  property apounce (owner: HACKER, flags: "r") = "480 grain";
  property appound (owner: HACKER, flags: "r") = "5760 grain";
  property arcdeg (owner: HACKER, flags: "r") = "1 degree";
  property arcmin (owner: HACKER, flags: "r") = "1|60 arcdeg";
  property arcsec (owner: HACKER, flags: "r") = "1|60 arcmin";
  property are (owner: HACKER, flags: "r") = "100 m2";
  property arpentcan (owner: HACKER, flags: "r") = "27.52 mi";
  property arpentlin (owner: HACKER, flags: "r") = "191.835 ft";
  property astronomicalunit (owner: #2, flags: "r") = "au";
  property atm (owner: HACKER, flags: "r") = "atmosphere";
  property atmosphere (owner: HACKER, flags: "r") = "1.01325 bar";
  property atomicmassunit (owner: HACKER, flags: "r") = "amu";
  property au (owner: HACKER, flags: "r") = "1.49599e11 m";
  property avdram (owner: HACKER, flags: "r") = "1|16 oz";
  property bag (owner: HACKER, flags: "r") = "3 brbushels";
  property bakersdozen (owner: HACKER, flags: "r") = "13";
  property bar (owner: HACKER, flags: "r") = "1e6 dyne/cm2";
  property barie (owner: HACKER, flags: "r") = "1e-1 nt/m2";
  property barleycorn (owner: HACKER, flags: "r") = "1|3 in";
  property barn (owner: HACKER, flags: "r") = "1e-24 cm2";
  property barrel (owner: HACKER, flags: "r") = "31.5 gal";
  property barye (owner: HACKER, flags: "r") = "1e-1 nt/m2";
  property basic_units (owner: HACKER, flags: "r") = {"m", "kg", "s", "coul", "candela", "radian", "bit", "erlang", "kelvin"};
  property basic_units_template (owner: HACKER, flags: "r") = {
    {"m", 0},
    {"kg", 0},
    {"s", 0},
    {"coul", 0},
    {"candela", 0},
    {"radian", 0},
    {"bit", 0},
    {"erlang", 0},
    {"kelvin", 0}
  };
  property baud (owner: HACKER, flags: "r") = "bit/sec";
  property bev (owner: HACKER, flags: "r") = "1e9 ev";
  property biot (owner: HACKER, flags: "r") = "10 amp";
  property block (owner: HACKER, flags: "r") = "512 byte";
  property blondel (owner: HACKER, flags: "r") = "cd/pi m2";
  property boardfeet (owner: HACKER, flags: "r") = "boardfoot";
  property boardfoot (owner: HACKER, flags: "r") = "144 in3";
  property bolt (owner: HACKER, flags: "r") = "120 feet";
  property bottommeasure (owner: HACKER, flags: "r") = "1|40 in";
  property brbarrel (owner: HACKER, flags: "r") = "4.5 brbushels";
  property brbucket (owner: HACKER, flags: "r") = "4 dry british gal";
  property brbushel (owner: HACKER, flags: "r") = "8 dry british gal";
  property brfirkin (owner: HACKER, flags: "r") = "1.125 brbushel";
  property british (owner: HACKER, flags: "r") = "277.4193|231";
  property brknot (owner: HACKER, flags: "r") = "6080 ft/hr";
  property brpeck (owner: HACKER, flags: "r") = "2 dry british gal";
  property btu (owner: HACKER, flags: "r") = "1054.35 joule";
  property bu (owner: HACKER, flags: "r") = "bushel";
  property bushel (owner: HACKER, flags: "r") = "8 dry gal";
  property butt (owner: HACKER, flags: "r") = "126 gal";
  property byte (owner: HACKER, flags: "r") = "8 bit";
  property c (owner: HACKER, flags: "r") = "2.99792458e8 m/sec";
  property cable (owner: HACKER, flags: "r") = "720 ft";
  property cal (owner: HACKER, flags: "r") = "4.1868 joule";
  property caliber (owner: HACKER, flags: "r") = "0.01 in";
  property calorie (owner: HACKER, flags: "r") = "cal";
  property candle (owner: HACKER, flags: "r") = "cd";
  property candlepower (owner: HACKER, flags: "r") = "12.566370 lumen";
  property carat (owner: HACKER, flags: "r") = "205.3 mg";
  property carcel (owner: HACKER, flags: "r") = "9.61 cd";
  property cc (owner: HACKER, flags: "r") = "cm3";
  property ccs (owner: HACKER, flags: "r") = "1|36 erlang";
  property cd (owner: HACKER, flags: "r") = "candela";
  property cental (owner: HACKER, flags: "r") = "100 lb";
  property centare (owner: HACKER, flags: "r") = "0.01 are";
  property centesimalminute (owner: HACKER, flags: "r") = "1e-2 grade";
  property centesimalsecond (owner: HACKER, flags: "r") = "1e-4 grade";
  property century (owner: HACKER, flags: "r") = "100 year";
  property cfs (owner: HACKER, flags: "r") = "ft3/sec";
  property cg (owner: HACKER, flags: "r") = "centigram";
  property chain (owner: HACKER, flags: "r") = "gunterchain";
  property chemamu (owner: HACKER, flags: "r") = "1.66024e-24 g";
  property chemdalton (owner: HACKER, flags: "r") = "chemamu";
  property circle (owner: HACKER, flags: "r") = "2 pi radian";
  property circularinch (owner: HACKER, flags: "r") = "1|4 pi in2";
  property circularmil (owner: HACKER, flags: "r") = "1e-6|4 pi in2";
  property clusec (owner: HACKER, flags: "r") = "1e-8 mm hg m3/s";
  property cm (owner: HACKER, flags: "r") = "centimeter";
  property coomb (owner: HACKER, flags: "r") = "4 bu";
  property cord (owner: HACKER, flags: "r") = "128 ft3";
  property cordfeet (owner: HACKER, flags: "r") = "cordfoot";
  property cordfoot (owner: HACKER, flags: "r") = "0.125 cord";
  property coul (owner: HACKER, flags: "r") = "coulomb";
  property cps (owner: HACKER, flags: "r") = "hertz";
  property crith (owner: HACKER, flags: "r") = "9.06e-2 gram";
  property cubichectare (owner: HACKER, flags: "r") = "1000000 m3";
  property cubit (owner: HACKER, flags: "r") = "18 in";
  property cup (owner: HACKER, flags: "r") = "1|2 pt";
  property curie (owner: HACKER, flags: "r") = "3.7e10/sec";
  property dalton (owner: HACKER, flags: "r") = "chemamu";
  property day (owner: HACKER, flags: "r") = "24 hr";
  property decade (owner: HACKER, flags: "r") = "10 year";
  property degree (owner: HACKER, flags: "r") = "1|180 pi radian";
  property dioptre (owner: HACKER, flags: "r") = "1/m";
  property displacementton (owner: HACKER, flags: "r") = "35 ft3";
  property dopplezentner (owner: HACKER, flags: "r") = "100 kg";
  property dozen (owner: HACKER, flags: "r") = "12";
  property dr (owner: HACKER, flags: "r") = "dram";
  property drachm (owner: HACKER, flags: "r") = "3.551531 ml";
  property dram (owner: HACKER, flags: "r") = "avdram";
  property dry (owner: HACKER, flags: "r") = "268.8025 in3/gallon";
  property dryquartern (owner: HACKER, flags: "r") = "2.272980 l";
  property dyne (owner: HACKER, flags: "r") = "erg/cm";
  property e (owner: HACKER, flags: "r") = "1.6020e-19 coul";
  property electronvolt (owner: HACKER, flags: "r") = "e volt";
  property ell (owner: HACKER, flags: "r") = "45 in";
  property energy (owner: HACKER, flags: "r") = "c2";
  property engcandle (owner: HACKER, flags: "r") = "1.04 cd";
  property engineerschain (owner: HACKER, flags: "r") = "100 ft";
  property engineerslink (owner: HACKER, flags: "r") = "0.01 engineerschain";
  property equivalentfootcandle (owner: HACKER, flags: "r") = "lumen/pi ft2";
  property equivalentlux (owner: HACKER, flags: "r") = "lumen/pi m2";
  property equivalentphot (owner: HACKER, flags: "r") = "cd/pi cm2";
  property erg (owner: HACKER, flags: "r") = "1e-7 joule";
  property ev (owner: HACKER, flags: "r") = "e volt";
  property farad (owner: HACKER, flags: "r") = "coul/volt";
  property faraday (owner: HACKER, flags: "r") = "9.648456e4coul";
  property fathom (owner: HACKER, flags: "r") = "6 ft";
  property feet (owner: HACKER, flags: "r") = "foot";
  property fermi (owner: HACKER, flags: "r") = "1e-13 cm";
  property fifth (owner: HACKER, flags: "r") = "1|5 gal";
  property finger (owner: HACKER, flags: "r") = "7|8 in";
  property firkin (owner: HACKER, flags: "r") = "72 pint";
  property fldr (owner: HACKER, flags: "r") = "1|32 gill";
  property floz (owner: HACKER, flags: "r") = "1|4 gill";
  property fluidounce (owner: #2, flags: "r") = "floz";
  property foot (owner: HACKER, flags: "r") = "12 in";
  property footcandle (owner: HACKER, flags: "r") = "lumen/ft2";
  property footlambert (owner: HACKER, flags: "r") = "cd/pi ft2";
  property force (owner: HACKER, flags: "r") = "g";
  property fortnight (owner: HACKER, flags: "r") = "14 day";
  property franklin (owner: HACKER, flags: "r") = "3.33564e-10 coul";
  property frigorie (owner: HACKER, flags: "r") = "kilocal";
  property ft (owner: HACKER, flags: "r") = "foot";
  property furlong (owner: HACKER, flags: "r") = "660 ft";
  property g (owner: HACKER, flags: "r") = "9.80665 m/sec2";
  property gal (owner: HACKER, flags: "r") = "gallon";
  property galileo (owner: HACKER, flags: "r") = "1e-2 m/sec2";
  property gallon (owner: HACKER, flags: "r") = "231 in3";
  property gamma (owner: HACKER, flags: "r") = "1e-6 g";
  property gauss (owner: HACKER, flags: "r") = "maxwell/cm2";
  property gb (owner: HACKER, flags: "r") = "1024 mb";
  property geographicalmile (owner: HACKER, flags: "r") = "nmile";
  property germancandle (owner: HACKER, flags: "r") = "1.05 cd";
  property gilbert (owner: HACKER, flags: "r") = "0.7957747154 amp";
  property gill (owner: HACKER, flags: "r") = "1|4 pt";
  property gm (owner: HACKER, flags: "r") = "gram";
  property gr (owner: HACKER, flags: "r") = "grain";
  property grad (owner: HACKER, flags: "r") = "1|400 circle";
  property grade (owner: HACKER, flags: "r") = "1|400 circle";
  property grain (owner: HACKER, flags: "r") = "1|7000 lb";
  property gram (owner: HACKER, flags: "r") = "1|1000 kg";
  property gramcalorie (owner: HACKER, flags: "r") = "cal";
  property gross (owner: HACKER, flags: "r") = "144";
  property gunterchain (owner: HACKER, flags: "r") = "66 ft";
  property gunterlink (owner: HACKER, flags: "r") = "0.01 gunterchain";
  property hand (owner: HACKER, flags: "r") = "4 in";
  property hd (owner: HACKER, flags: "r") = "hogshead";
  property hectare (owner: HACKER, flags: "r") = "100 are";
  property hefnercandle (owner: HACKER, flags: "r") = "hefnerunit";
  property hefnerunit (owner: HACKER, flags: "r") = ".92 cd";
  property henry (owner: HACKER, flags: "r") = "sec2/farad";
  property hertz (owner: HACKER, flags: "r") = "1/sec";
  property hg (owner: HACKER, flags: "r") = "mercury";
  property hogshead (owner: HACKER, flags: "r") = "63 gal";
  property homestead (owner: HACKER, flags: "r") = "1|4 mi2";
  property horsepower (owner: HACKER, flags: "r") = "550 ft lb g/sec";
  property hour (owner: HACKER, flags: "r") = "60 min";
  property hp (owner: HACKER, flags: "r") = "horsepower";
  property hr (owner: HACKER, flags: "r") = "hour";
  property hyl (owner: HACKER, flags: "r") = "gram force sec2/m";
  property hz (owner: HACKER, flags: "r") = "hertz";
  property imaginarycubicfoot (owner: HACKER, flags: "r") = "1.4 ft3";
  property imperial (owner: HACKER, flags: "r") = "1.200949";
  property in (owner: HACKER, flags: "r") = "inch";
  property inch (owner: HACKER, flags: "r") = "2.54 cm";
  property inches (owner: HACKER, flags: "r") = "inch";
  property jeroboam (owner: HACKER, flags: "r") = "4|5 gal";
  property joule (owner: HACKER, flags: "r") = "nt m";
  property k (owner: HACKER, flags: "r") = "1.38047e-16 erg/kelvin";
  property karat (owner: HACKER, flags: "r") = "1|24";
  property kb (owner: HACKER, flags: "r") = "1024 byte";
  property kcal (owner: HACKER, flags: "r") = "kilocal";
  property kcalorie (owner: HACKER, flags: "r") = "kilocal";
  property kev (owner: HACKER, flags: "r") = "1e3 ev";
  property khz (owner: HACKER, flags: "r") = "kilohz";
  property kilderkin (owner: HACKER, flags: "r") = "18 imperial gal";
  property km (owner: HACKER, flags: "r") = "kilometer";
  property knot (owner: HACKER, flags: "r") = "nmile/hr";
  property l (owner: HACKER, flags: "r") = "liter";
  property lambert (owner: HACKER, flags: "r") = "cd/pi cm2";
  property langley (owner: HACKER, flags: "r") = "cal/cm cm";
  property last (owner: HACKER, flags: "r") = "80 bu";
  property lb (owner: HACKER, flags: "r") = "0.45359237 kg";
  property lbf (owner: HACKER, flags: "r") = "lb g";
  property league (owner: HACKER, flags: "r") = "3 mi";
  property lightyear (owner: HACKER, flags: "r") = "c yr";
  property line (owner: HACKER, flags: "r") = "1|12 in";
  property link (owner: HACKER, flags: "r") = "66|100 ft";
  property liqquarten (owner: HACKER, flags: "r") = "0.1420613 l";
  property liter (owner: HACKER, flags: "r") = "1000 cc";
  property long (owner: HACKER, flags: "r") = "4 word";
  property longhundredweight (owner: HACKER, flags: "r") = "112 lb";
  property longquarter (owner: HACKER, flags: "r") = "28 lb";
  property longton (owner: HACKER, flags: "r") = "2240 lb";
  property lumen (owner: HACKER, flags: "r") = "cd sr";
  property lusec (owner: HACKER, flags: "r") = "1e-6 mm hg m3/s";
  property lux (owner: HACKER, flags: "r") = "lumen/m2";
  property mach (owner: HACKER, flags: "r") = "331.45 m/sec";
  property magnum (owner: HACKER, flags: "r") = "2 qt";
  property marineleague (owner: HACKER, flags: "r") = "3nmile";
  property maxwell (owner: HACKER, flags: "r") = "1e-8 weber";
  property mb (owner: HACKER, flags: "r") = "1024 kb";
  property mercury (owner: HACKER, flags: "r") = "1.3157895 atm/m";
  property meter (owner: HACKER, flags: "r") = "m";
  property metriccarat (owner: HACKER, flags: "r") = "200 mg";
  property metricton (owner: HACKER, flags: "r") = "1000 kg";
  property mev (owner: HACKER, flags: "r") = "1e6 ev";
  property mg (owner: HACKER, flags: "r") = "milligram";
  property mgd (owner: HACKER, flags: "r") = "megagal/day";
  property mh (owner: HACKER, flags: "r") = "millihenry";
  property mho (owner: HACKER, flags: "r") = "1/ohm";
  property mhz (owner: HACKER, flags: "r") = "megahz";
  property mi (owner: HACKER, flags: "r") = "mile";
  property micron (owner: HACKER, flags: "r") = "1e-6 meter";
  property mil (owner: HACKER, flags: "r") = "0.001 in";
  property mile (owner: HACKER, flags: "r") = "5280 feet";
  property millenium (owner: HACKER, flags: "r") = "1000 year";
  property min (owner: HACKER, flags: "r") = "minute";
  property minersinch (owner: HACKER, flags: "r") = "1.5 ft3/min";
  property minim (owner: HACKER, flags: "r") = "1|480 floz";
  property minute (owner: HACKER, flags: "r") = "60 sec";
  property ml (owner: HACKER, flags: "r") = "milliliter";
  property mm (owner: HACKER, flags: "r") = "millimeter";
  property mo (owner: HACKER, flags: "r") = "month";
  property mole (owner: HACKER, flags: "r") = "6.022045e23";
  property month (owner: HACKER, flags: "r") = "1|12 year";
  property mpg (owner: HACKER, flags: "r") = "mile/gal";
  property mph (owner: HACKER, flags: "r") = "mile/hr";
  property ms (owner: HACKER, flags: "r") = "millisec";
  property myriagram (owner: HACKER, flags: "r") = "10 kg";
  property nail (owner: HACKER, flags: "r") = "1|16 yd";
  property nautleague (owner: HACKER, flags: "r") = "3 nmile";
  property nautmile (owner: HACKER, flags: "r") = "nmile";
  property newton (owner: HACKER, flags: "r") = "kg m/sec2";
  property nit (owner: HACKER, flags: "r") = "cd/m2";
  property nm (owner: HACKER, flags: "r") = "nanometer";
  property nmile (owner: HACKER, flags: "r") = "1852 m";
  property noggin (owner: HACKER, flags: "r") = "1 imperial gill";
  property nox (owner: HACKER, flags: "r") = "1e-3 lux";
  property ns (owner: HACKER, flags: "r") = "nanosec";
  property nt (owner: HACKER, flags: "r") = "newton";
  property oe (owner: HACKER, flags: "r") = "oersted";
  property oersted (owner: HACKER, flags: "r") = "1 gilbert / cm";
  property ohm (owner: HACKER, flags: "r") = "volt/amp";
  property ounce (owner: HACKER, flags: "r") = "1|16 lb";
  property oz (owner: HACKER, flags: "r") = "ounce";
  property pace (owner: HACKER, flags: "r") = "30 inch";
  property palm (owner: HACKER, flags: "r") = "3 in";
  property parsec (owner: HACKER, flags: "r") = "au radian/arcsec";
  property pascal (owner: HACKER, flags: "r") = "nt/m2";
  property pc (owner: HACKER, flags: "r") = "parsec";
  property pdl (owner: HACKER, flags: "r") = "poundal";
  property peck (owner: HACKER, flags: "r") = "2 dry gallon";
  property pennyweight (owner: HACKER, flags: "r") = "24 grain";
  property percent (owner: HACKER, flags: "r") = "%";
  property perch (owner: HACKER, flags: "r") = "24.75 ft3";
  property petrbarrel (owner: HACKER, flags: "r") = "42 gal";
  property pf (owner: HACKER, flags: "r") = "picofarad";
  property phot (owner: HACKER, flags: "r") = "lumen/cm2";
  property physamu (owner: HACKER, flags: "r") = "1.65979e-24 g";
  property physdalton (owner: HACKER, flags: "r") = "physamu";
  property pi (owner: HACKER, flags: "r") = "3.14159265358979323846264338327950288";
  property pica (owner: HACKER, flags: "r") = "0.166044 inch";
  property pieze (owner: HACKER, flags: "r") = "1e3 nt/mt2";
  property pint (owner: HACKER, flags: "r") = "1|2 qt";
  property pipe (owner: HACKER, flags: "r") = "4 barrel";
  property pk (owner: HACKER, flags: "r") = "peck";
  property point (owner: HACKER, flags: "r") = "1|72.27 in";
  property poise (owner: HACKER, flags: "r") = "gram/cm sec";
  property pole (owner: HACKER, flags: "r") = "rd";
  property pound (owner: HACKER, flags: "r") = "lb";
  property poundal (owner: HACKER, flags: "r") = "ft lb/sec2";
  property proof (owner: HACKER, flags: "r") = "1|200";
  property ps (owner: HACKER, flags: "r") = "picosec";
  property psi (owner: HACKER, flags: "r") = "lb g/in2";
  property pt (owner: HACKER, flags: "r") = "pint";
  property puncheon (owner: HACKER, flags: "r") = "84 gal";
  property qt (owner: HACKER, flags: "r") = "quart";
  property quadrant (owner: HACKER, flags: "r") = "5400 minute";
  property quart (owner: HACKER, flags: "r") = "1|4 gal";
  property quarter (owner: HACKER, flags: "r") = "9 in";
  property quartersection (owner: HACKER, flags: "r") = "1|4 mi2";
  property quintal (owner: HACKER, flags: "r") = "100 kg";
  property quire (owner: HACKER, flags: "r") = "25";
  property ra (owner: HACKER, flags: "r") = "100 erg/gram";
  property ramdenchain (owner: HACKER, flags: "r") = "100 ft";
  property ramdenlink (owner: HACKER, flags: "r") = "0.01 ramdenchain";
  property rankine (owner: HACKER, flags: "r") = "1.8 kelvin";
  property rd (owner: HACKER, flags: "r") = "rod";
  property ream (owner: HACKER, flags: "r") = "500";
  property refrigeration (owner: HACKER, flags: "r") = "12000 but/ton hr";
  property registerton (owner: HACKER, flags: "r") = "100 ft3";
  property rehoboam (owner: HACKER, flags: "r") = "156 floz";
  property revolution (owner: HACKER, flags: "r") = "360 degrees";
  property reyn (owner: HACKER, flags: "r") = "6.89476e-6 centipoise";
  property rhe (owner: HACKER, flags: "r") = "1/poise";
  property rod (owner: HACKER, flags: "r") = "16.5 ft";
  property rontgen (owner: HACKER, flags: "r") = "2.58e-4 curie/kg";
  property rood (owner: HACKER, flags: "r") = "0.25 acre";
  property rope (owner: HACKER, flags: "r") = "20 ft";
  property rpm (owner: HACKER, flags: "r") = "revolution/minute";
  property rutherford (owner: HACKER, flags: "r") = "1e6/sec";
  property rydberg (owner: HACKER, flags: "r") = "1.36054e1 ev";
  property sabin (owner: HACKER, flags: "r") = "1 ft2";
  property scruple (owner: HACKER, flags: "r") = "20 grain";
  property seam (owner: HACKER, flags: "r") = "8 brbushels";
  property sec (owner: HACKER, flags: "r") = "second";
  property second (owner: HACKER, flags: "r") = "s";
  property section (owner: HACKER, flags: "r") = "mi2";
  property sennight (owner: HACKER, flags: "r") = "1 week";
  property shippington (owner: HACKER, flags: "r") = "40 ft3";
  property shorthundredweight (owner: HACKER, flags: "r") = "100 lb";
  property shortquarter (owner: HACKER, flags: "r") = "500 lb";
  property shortton (owner: HACKER, flags: "r") = "2000 lb";
  property siemens (owner: HACKER, flags: "r") = "mho";
  property sigma (owner: HACKER, flags: "r") = "microsec";
  property sign (owner: HACKER, flags: "r") = "1|12 circle";
  property skein (owner: HACKER, flags: "r") = "360 feet";
  property skot (owner: HACKER, flags: "r") = "1e-3 apostilb";
  property slug (owner: HACKER, flags: "r") = "lb g sec2/ft";
  property span (owner: HACKER, flags: "r") = "9 in";
  property spat (owner: HACKER, flags: "r") = "sphere";
  property sphere (owner: HACKER, flags: "r") = "4 pi steradian";
  property spindle (owner: HACKER, flags: "r") = "14400 yd";
  property square (owner: HACKER, flags: "r") = "100 ft2";
  property sr (owner: HACKER, flags: "r") = "steradian";
  property statcoul (owner: HACKER, flags: "r") = "3.335635e-10 coul";
  property statfarad (owner: HACKER, flags: "r") = "1.112646e-12 farad";
  property stathenry (owner: HACKER, flags: "r") = "8.987584e11 henry";
  property statvolt (owner: HACKER, flags: "r") = "299.7930 volt";
  property steradian (owner: HACKER, flags: "r") = "radian radian";
  property stere (owner: HACKER, flags: "r") = "m3";
  property sthene (owner: HACKER, flags: "r") = "1e3 nt";
  property stilb (owner: HACKER, flags: "r") = "cd/cm2";
  property stoke (owner: HACKER, flags: "r") = "1 cm2/sec";
  property stone (owner: HACKER, flags: "r") = "14 lb";
  property tablespoon (owner: HACKER, flags: "r") = "4 fldr";
  property tbsp (owner: #2, flags: "r") = "tablespoon";
  property teaspoon (owner: HACKER, flags: "r") = "1|3 tablespoon";
  property tesla (owner: HACKER, flags: "r") = "weber/m2";
  property thermie (owner: HACKER, flags: "r") = "1e6 cal";
  property timberfoot (owner: HACKER, flags: "r") = "ft3";
  property tnt (owner: HACKER, flags: "r") = "4.6e6 m2/sec2";
  property ton (owner: HACKER, flags: "r") = "shortton";
  property tonne (owner: HACKER, flags: "r") = "1e6 gram";
  property torr (owner: HACKER, flags: "r") = "mm hg";
  property township (owner: HACKER, flags: "r") = "36 mi2";
  property tsp (owner: #2, flags: "r") = "teaspoon";
  property tun (owner: HACKER, flags: "r") = "252 gal";
  property turn (owner: HACKER, flags: "r") = "2 pi radian";
  property us (owner: HACKER, flags: "r") = "microsec";
  property usdram (owner: HACKER, flags: "r") = "1|8 oz";
  property v (owner: HACKER, flags: "r") = "volt";
  property volt (owner: HACKER, flags: "r") = "watt/amp";
  property water (owner: HACKER, flags: "r") = "0.22491|2.54 kg/m2 sec2";
  property watt (owner: HACKER, flags: "r") = "joule/sec";
  property weber (owner: HACKER, flags: "r") = "volt sec";
  property week (owner: HACKER, flags: "r") = "7 day";
  property wey (owner: HACKER, flags: "r") = "252 lb";
  property word (owner: HACKER, flags: "r") = "4 byte";
  property xunit (owner: HACKER, flags: "r") = "1.00202e-13 m";
  property yard (owner: HACKER, flags: "r") = "3 ft";
  property yd (owner: HACKER, flags: "r") = "yard";
  property year (owner: HACKER, flags: "r") = "365.24219879 day";
  property yr (owner: HACKER, flags: "r") = "year";

  override aliases (owner: HACKER, flags: "rc") = {"Conversion Utils"};
  override description (owner: HACKER, flags: "rc") = "This is a utilities package for converting from one unit of measurement to another. Type 'help #770' for more details.";
  override help_msg (owner: HACKER, flags: "rc") = {
    "Utility verbs for converting from one unit of measure to another.",
    "",
    "Unusual conversions:",
    ":dd_to_dms => converts decimal (INT or FLOAT) Degrees into Degrees, Minutes,",
    "              and Seconds. (Also works for decimal Hours.)",
    ":dms_to_dd => converts from Degrees (or Hours), Minutes, and Seconds to",
    "              decimal Degrees (or Hours).",
    ":rect_to_polar => converts from cartesian (x,y) coordinates to polar.",
    ":polar_to_rect => converts from polar (r, theta) coordinates to cartesian.",
    ":F_to_C => converts from Fahrenheit to Celsius.",
    ":C_to_F => converts from Celsius to Fahrenheit.",
    ":C_to_K => converts from Celsius to Kelvin.",
    ":K_to_C => converts from Kelvin to Celsius.",
    ":F_to_R => converts from Fahrenheit to Rankine.",
    ":R_to_F => converts from Rankine to Fahrenheit.",
    "",
    "Standard conversions:",
    ":convert => takes two string inputs and attempts to determine the ",
    "            multiplicative conversion factor. See the verb help for details",
    "            and input format.\""
  };
  override object_size (owner: HACKER, flags: "r") = {30721, 1084848672};

  method "dd_to_dms dh_to_hms" owner: HACKER
    "Convert decimal degrees (or hours) to {whole units, minutes, seconds}; negative parts keep their sign.";
    const value = tofloat(args[1]);
    const whole = toint(value);
    const fractional_minutes = (value - tofloat(whole)) * 60.0;
    const minutes = toint(fractional_minutes);
    return {whole, minutes, (fractional_minutes - tofloat(minutes)) * 60.0};
  endmethod

  method "dms_to_dd hms_to_dh" owner: HACKER
    "Convert degrees/minutes/seconds (or hours/minutes/seconds) to a floating-point value.";
    const {whole, minutes, seconds} = args[1..3];
    return tofloat(whole) + tofloat(minutes) / 60.0 + tofloat(seconds) / 3600.0;
  endmethod

  method rect_to_polar owner: HACKER
    "Convert {x, y} arguments to {radius, angle in radians}; the origin has angle zero.";
    const x = tofloat(args[1]);
    const y = tofloat(args[2]);
    const scale = max(abs(x), abs(y));
    !scale && return {0.0, 0.0};
    return {scale * sqrt((x / scale) ^ 2.0 + (y / scale) ^ 2.0), atan(y, x)};
  endmethod

  method polar_to_rect owner: HACKER
    "Convert radius and angle in radians to {x, y}.";
    const radius = tofloat(args[1]);
    const angle = tofloat(args[2]);
    return {radius * cos(angle), radius * sin(angle)};
  endmethod

  method "F_to_C degF_to_degC" owner: HACKER
    "Convert Fahrenheit to Celsius, returning a float.";
    return (tofloat(args[1]) - 32.0) / 1.8;
  endmethod

  method "C_to_F degC_to_degF" owner: HACKER
    "Convert Celsius to Fahrenheit, returning a float.";
    return tofloat(args[1]) * 1.8 + 32.0;
  endmethod

  method convert owner: HACKER
    "Return the multiplicative factor between two unit expressions, including numeric amounts.";
    "Examples: 100 kg m/sec2 to newtons; kilowatt hours to joules.";
    "Return {0, bad_input} for unknown units or {1, {factor, dimensions}, {factor, dimensions}} for mismatched dimensions.";
    "These integer tags identify error records. Temperature offsets use the separate temperature helpers.";
    const {source, destination} = args;
    const have = this:_do_convert(source);
    const want = this:_do_convert(destination);
    !have || !want && return {0, have ? destination | source};
    have[2] == want[2] && return have[1] / want[1];
    return {1, {have[1], this:_format_units(@have[2])}, {want[1], this:_format_units(@want[2])}};
  endmethod

  method _do_convert owner: HACKER
    "Expand a unit expression into {factor, basic dimensions}; unknown terms return 0.";
    "Spaces multiply terms. Each slash toggles numerator/denominator, preserving the unit catalog's syntax.";
    const {expression} = args;
    let words = $string_utils:words(strsub(expression, "/", " / "));
    let units = this.basic_units_template;
    let value = 1.0;
    let numerator = true;
    while (words)
      let word = words[1];
      words = words[2..$];
      if (word == "/")
        numerator = !numerator;
        continue;
      endif
      if (index(word, "|"))
        value = this:_do_value(word, value, numerator);
        continue;
      endif
      if ($string_utils:is_integer(word) || $string_utils:is_float(word))
        value = numerator ? value * tofloat(word) | value / tofloat(word);
        continue;
      endif
      "Recognize catalog names written as two words, such as fluid ounces.";
      if (words && words[1] != "/")
        const joined = word + words[1];
        const singular = joined[$] == "s" ? joined[1..$ - 1] | joined;
        if (typeof(`this.(joined) ! E_PROPNF') == TYPE_STR || typeof(`this.(singular) ! E_PROPNF') == TYPE_STR)
          word = joined;
          words = words[2..$];
        endif
      endif
      let power = 1;
      const powered = match(word, "^%([a-zA-Z]+%)%([0-9]+%)$");
      if (powered)
        power = `fromliteral(substitute("%2", powered)) ! E_INVARG => -1';
        typeof(power) != TYPE_INT || power < 0 || power > 2147483647 && return 0;
        word = substitute("%1", powered);
      endif
      let scale = 1.0;
      const {remaining, prefix_scale, numerator_flag} = this:_try_metric_prefix(word, scale, true);
      word = remaining;
      scale = prefix_scale;
      let position = word in this.basic_units;
      let definition = `this.(word) ! E_PROPNF => 0';
      if (!position && typeof(definition) != TYPE_STR && word && word[$] == "s")
        word = word[1..$ - 1];
        position = word in this.basic_units;
        definition = `this.(word) ! E_PROPNF => 0';
      endif
      let expanded = this.basic_units_template;
      if (position)
        expanded[position][2] = 1;
      elseif (typeof(definition) == TYPE_STR)
        const result = this:_do_convert(definition);
        !result && return 0;
        scale = scale * result[1];
        expanded = result[2];
      else
        return 0;
      endif
      const exponent = numerator ? power | -power;
      value = value * scale ^ tofloat(exponent);
      for dimension in [1..length(units)]
        units[dimension][2] = units[dimension][2] + exponent * expanded[dimension][2];
      endfor
    endwhile
    return {value, units};
  endmethod

  method _try_metric_prefix owner: HACKER
    "Strip spelled-out metric prefixes, including stacked prefixes; leave micron intact.";
    "Return {remaining name, adjusted value, original numerator flag}.";
    let {word, value, numerator} = args;
    const prefixes = {{"yocto", 1e-24}, {"zepto", 1e-21}, {"atto", 1e-18}, {"femto", 1e-15}, {"pico", 1e-12}, {"nano", 1e-9}, {"micro", 1e-6}, {"milli", 0.001}, {"centi", 0.01}, {"deci", 0.1}, {"deca", 10.0}, {"deka", 10.0}, {"hecto", 100.0}, {"kilo", 1000.0}, {"mega", 1000000.0}, {"giga", 1000000000.0}, {"tera", 1000000000000.0}, {"peta", 1000000000000000.0}, {"exa", 1e18}, {"zetta", 1e21}, {"yotta", 1e24}};
    while (true)
      index(word, "micron") == 1 && return {word, value, numerator};
      let found = false;
      for prefix in (prefixes)
        if (index(word, prefix[1]) == 1)
          word = word[length(prefix[1]) + 1..$];
          value = numerator ? value * prefix[2] | value / prefix[2];
          found = true;
          break;
        endif
      endfor
      !found && return {word, value, numerator};
    endwhile
  endmethod

  method _format_units owner: HACKER
    "Format basic-unit/exponent pairs as numerator and denominator terms.";
    let numerator = {};
    let denominator = {};
    for pair in (args)
      const {name, exponent} = pair;
      const term = tostr(name, abs(exponent) > 1 ? abs(exponent) | "");
      exponent > 0 && (numerator = {@numerator, term});
      exponent < 0 && (denominator = {@denominator, term});
    endfor
    const top = $string_utils:from_list(numerator, " ");
    return denominator ? tostr(top, top ? " / " | "/ ", $string_utils:from_list(denominator, " ")) | top;
  endmethod

  method "K_to_C degK_to_degC" owner: HACKER
    "Convert kelvin to Celsius, returning a float.";
    return tofloat(args[1]) - 273.15;
  endmethod

  method "C_to_K degC_to_degK" owner: HACKER
    "Convert Celsius to kelvin, returning a float.";
    return tofloat(args[1]) + 273.15;
  endmethod

  method "F_to_R degF_to_degR" owner: HACKER
    "Convert Fahrenheit to Rankine, returning a float.";
    return tofloat(args[1]) + 459.67;
  endmethod

  method "R_to_F degR_to_degF" owner: HACKER
    "Convert Rankine to Fahrenheit, returning a float.";
    return tofloat(args[1]) - 459.67;
  endmethod

  method _do_value owner: HACKER
    "Apply a numeric numerator|denominator ratio to a running conversion factor.";
    const {text, value, numerator} = args;
    const parts = $string_utils:explode(text, "|");
    length(parts) != 2 && raise(E_INVARG, "Expected a numeric ratio");
    const ratio = tofloat(parts[1]) / tofloat(parts[2]);
    return numerator ? value * ratio | value / ratio;
  endmethod
endobject
