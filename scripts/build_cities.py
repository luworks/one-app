#!/usr/bin/env python3
"""Builds ios/One/cities.json, the offline city list behind World Clock's "Choose a City".

Data: GeoNames (https://www.geonames.org), licensed CC BY 4.0. Download these into one folder (not into the repo):
  https://download.geonames.org/export/dump/cities15000.zip        (unzip -> cities15000.txt)
  https://download.geonames.org/export/dump/countryInfo.txt
  https://download.geonames.org/export/dump/alternateNamesV2.zip   (kept zipped; only Chinese names are read)

Run:  python3 -I scripts/build_cities.py <folder> ios/One/cities.json

Which cities: every national capital, every city of 1.5 million or more, the largest city of each country, larger cities
of countries that span many time zones (lower thresholds), plus a hand-picked list of business and tourism hubs.
Output per city: GeoNames id, English name, Chinese name (when GeoNames has one), country code, IANA time zone,
latitude, longitude, population rank (1 = largest of the list) and a capital flag. Standard library only.
"""
import json
import re
import sys
import zipfile

ZH_LANGS = {"zh", "zh-CN", "zh-Hans", "zh-SG", "zh-TW", "zh-Hant", "zh-HK", "zh-MO", "yue"}
SIMPLIFIED = {"zh", "zh-CN", "zh-Hans", "zh-SG"}
HAN = re.compile(r"^[㐀-鿿·・]+$")

# Lower population thresholds for countries with many time zones or many well-known cities.
COUNTRY_MIN_POP = {
    "US": 400_000, "CA": 300_000, "AU": 250_000, "GB": 300_000, "DE": 450_000, "FR": 250_000, "IT": 300_000,
    "ES": 300_000, "JP": 600_000, "KR": 700_000, "RU": 1_000_000, "BR": 1_000_000, "MX": 900_000, "AR": 700_000,
    "CN": 1_000_000, "IN": 1_000_000, "ID": 700_000, "NZ": 100_000, "NL": 250_000, "SE": 200_000, "NO": 150_000,
    "CH": 100_000, "AT": 200_000, "PL": 400_000, "PT": 200_000, "ZA": 400_000, "NG": 800_000, "TR": 1_000_000,
    "CL": 400_000, "CO": 600_000, "PE": 500_000, "VN": 700_000, "TH": 500_000, "PH": 700_000, "MY": 400_000,
}
GLOBAL_MIN_POP = 1_500_000

# (name, country code): business and tourism hubs and the cities named in the Overlap reference screens.
HUBS = [
    ("Aba", "NG"), ("San Jose", "US"), ("Dallas", "US"), ("Boston", "US"), ("Seattle", "US"), ("San Francisco", "US"),
    ("Los Angeles", "US"), ("Chicago", "US"), ("Houston", "US"), ("Miami", "US"), ("Denver", "US"), ("Atlanta", "US"),
    ("Las Vegas", "US"), ("Orlando", "US"), ("Honolulu", "US"), ("Anchorage", "US"), ("Salt Lake City", "US"),
    ("Toronto", "CA"), ("Vancouver", "CA"), ("Montréal", "CA"), ("Calgary", "CA"), ("Halifax", "CA"),
    ("Sydney", "AU"), ("Melbourne", "AU"), ("Perth", "AU"), ("Brisbane", "AU"), ("Adelaide", "AU"), ("Darwin", "AU"),
    ("Hobart", "AU"), ("Auckland", "NZ"), ("Wellington", "NZ"), ("Christchurch", "NZ"),
    ("Beijing", "CN"), ("Shanghai", "CN"), ("Shenzhen", "CN"), ("Guangzhou", "CN"), ("Chengdu", "CN"), ("Hangzhou", "CN"),
    ("Hong Kong", "HK"), ("Macau", "MO"), ("Taipei", "TW"), ("Tokyo", "JP"), ("Osaka", "JP"), ("Kyoto", "JP"),
    ("Seoul", "KR"), ("Singapore", "SG"), ("Mumbai", "IN"), ("Delhi", "IN"), ("Bengaluru", "IN"), ("Kolkata", "IN"),
    ("Dubai", "AE"), ("Abu Dhabi", "AE"), ("Doha", "QA"), ("Istanbul", "TR"), ("Moscow", "RU"),
    ("London", "GB"), ("Edinburgh", "GB"), ("Paris", "FR"), ("Nice", "FR"), ("Berlin", "DE"), ("Frankfurt am Main", "DE"),
    ("Munich", "DE"), ("Madrid", "ES"), ("Barcelona", "ES"), ("Rome", "IT"), ("Milan", "IT"), ("Venice", "IT"),
    ("Zürich", "CH"), ("Geneva", "CH"), ("Amsterdam", "NL"), ("Lisbon", "PT"), ("Dublin", "IE"),
    ("Cairo", "EG"), ("Lagos", "NG"), ("Nairobi", "KE"), ("Johannesburg", "ZA"), ("Cape Town", "ZA"), ("Marrakesh", "MA"),
    ("São Paulo", "BR"), ("Rio de Janeiro", "BR"), ("Buenos Aires", "AR"), ("Mexico City", "MX"), ("Cancún", "MX"),
    ("Bogotá", "CO"), ("Lima", "PE"), ("Santiago", "CL"), ("Panama City", "PA"), ("Reykjavík", "IS"),
    ("Bangkok", "TH"), ("Phuket", "TH"), ("Denpasar", "ID"), ("Jakarta", "ID"), ("Manila", "PH"), ("Hanoi", "VN"),
    ("Ho Chi Minh City", "VN"), ("Kuala Lumpur", "MY"), ("George Town", "MY"), ("Kathmandu", "NP"), ("Colombo", "LK"),
    ("Tel Aviv", "IL"), ("Jerusalem", "IL"), ("Papeete", "PF"), ("Suva", "FJ"), ("Nouméa", "NC"),
]
# Capitals GeoNames does not list as PPLC in cities15000.
EXTRA_CAPITALS = [("Jerusalem", "IL"), ("Laayoune", "EH"), ("Ramallah", "PS")]
DISPLAY_NAME = {
    "New York City": "New York", "Frankfurt am Main": "Frankfurt", "Kolkāta": "Kolkata", "Bengaluru": "Bengaluru",
    "Ho Chi Minh City": "Ho Chi Minh City", "Zürich": "Zurich", "Reykjavík": "Reykjavik", "Montréal": "Montreal",
    "Bogotá": "Bogota", "São Paulo": "Sao Paulo", "Cancún": "Cancun", "Nouméa": "Noumea",
}


def fold(s):
    import unicodedata
    return "".join(c for c in unicodedata.normalize("NFD", s) if unicodedata.category(c) != "Mn").lower()


def read_cities(folder):
    rows = []
    with open(folder + "/cities15000.txt", encoding="utf-8") as f:
        for line in f:
            p = line.rstrip("\n").split("\t")
            rows.append({
                "id": int(p[0]), "name": p[1], "ascii": p[2], "lat": float(p[4]), "lon": float(p[5]), "fcode": p[7],
                "cc": p[8], "pop": int(p[14]), "tz": p[17],
            })
    return rows


def pick_zh(folder, ids, country_of):
    best = {}  # id -> (score, text)
    with zipfile.ZipFile(folder + "/alternateNamesV2.zip") as z:
        name = next(n for n in z.namelist() if n.startswith("alternateNamesV2") and n.endswith(".txt"))
        with z.open(name) as f:
            for raw in f:
                p = raw.decode("utf-8", "replace").rstrip("\n").split("\t")
                if len(p) < 8:
                    continue
                gid = p[1]
                if not gid.isdigit() or int(gid) not in ids or p[2] not in ZH_LANGS:
                    continue
                text = p[3].strip()
                if not HAN.match(text) or p[7] == "1" or p[6] == "1":   # historic / colloquial
                    continue
                # Simplified wins over traditional (the app converts the rest at load), then the preferred and
                # short forms, then the shortest text.
                score = (10 if p[2] in SIMPLIFIED else 1) + (2 if p[4] == "1" else 0) + (1 if p[5] == "1" else 0)
                score = score * 100 - len(text)
                cur = best.get(int(gid))
                if cur is None or score > cur[0]:
                    best[int(gid)] = (score, text)
    out = {}
    for gid, (_, text) in best.items():
        for suffix in ("特别市", "特別市", "市"):   # "北京市" -> "北京", "首尔特别市" -> "首尔"
            if country_of[gid] in ("CN", "HK", "MO", "TW", "SG", "KR") and len(text) > len(suffix) + 1 and text.endswith(suffix):
                text = text[:-len(suffix)]
                break
        out[gid] = text
    return out


def main(folder, out_path):
    rows = read_cities(folder)
    by_id = {r["id"]: r for r in rows}
    picked = {}

    def take(r):
        picked[r["id"]] = r

    for r in rows:
        if r["fcode"] == "PPLC" or r["pop"] >= GLOBAL_MIN_POP or r["pop"] >= COUNTRY_MIN_POP.get(r["cc"], 10**12):
            take(r)
    largest = {}
    for r in rows:
        if r["cc"] not in largest or r["pop"] > largest[r["cc"]]["pop"]:
            largest[r["cc"]] = r
    for r in largest.values():
        take(r)
    missing = []
    for name, cc in HUBS + EXTRA_CAPITALS:
        hits = [r for r in rows if r["cc"] == cc and (r["name"] == name or r["ascii"] == name or fold(r["name"]) == fold(name))]
        if not hits:
            missing.append((name, cc))
            continue
        take(max(hits, key=lambda r: r["pop"]))
    if missing:
        print("not found in cities15000:", missing, file=sys.stderr)

    zh = pick_zh(folder, set(picked), {i: r["cc"] for i, r in picked.items()})
    capital_ids = {r["id"] for r in picked.values() if r["fcode"] == "PPLC"}
    capital_ids |= {r["id"] for r in picked.values() if (r["name"], r["cc"]) in set(EXTRA_CAPITALS)}
    ordered = sorted(picked.values(), key=lambda r: (-r["pop"], r["id"]))
    cities = []
    for rank, r in enumerate(ordered, 1):
        c = {"id": r["id"], "name": DISPLAY_NAME.get(r["name"], r["name"]), "cc": r["cc"], "tz": r["tz"],
             "lat": round(r["lat"], 2), "lon": round(r["lon"], 2), "rank": rank}
        if r["id"] in zh:
            c["zh"] = zh[r["id"]]
        if r["id"] in capital_ids:
            c["capital"] = True
        cities.append(c)
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(cities, f, ensure_ascii=False, separators=(",", ":"))
        f.write("\n")
    print(len(cities), "cities;", sum(1 for c in cities if "zh" in c), "with a Chinese name;",
          len(capital_ids), "capitals", file=sys.stderr)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
