from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import math

# ---------------------------------------------------------------------------
# Store catalogue with real Vilnius coordinates
# ---------------------------------------------------------------------------
STORES = {
    "Maxima": {"lat": 54.7154, "lon": 25.2539, "address": "Šeškinės g. 24, Vilnius"},
    "Rimi":   {"lat": 54.6634, "lon": 25.2897, "address": "Bičiulių g. 2, Vilnius"},
    "Iki":    {"lat": 54.6891, "lon": 25.2012, "address": "Erfurto g. 2, Vilnius"},
    "Lidl":   {"lat": 54.7032, "lon": 25.2205, "address": "Viršuliškių g. 34, Vilnius"},
    "Norfa":  {"lat": 54.7021, "lon": 25.3221, "address": "Antakalnio g. 36, Vilnius"},
}

DEALS = [
    {
        "id": 101, "name": "Chicken Breast", "brand": "FreshFarm",
        "emoji": "🍗", "store": "Maxima", "originalPrice": 8.99, "discountedPrice": 5.99,
        "discount": 33, "category": "Meat", "kcalPer100g": 165,
        "proteinPer100g": 31.0, "carbsPer100g": 0.0, "fatPer100g": 3.6,
        "weeklyQty": 2, "unit": "kg", "expiresIn": "Sunday", "allergens": []
    },
    {
        "id": 102, "name": "Avocado", "brand": "NatureGood",
        "emoji": "🥑", "store": "Rimi", "originalPrice": 1.99, "discountedPrice": 0.99,
        "discount": 50, "category": "Produce", "kcalPer100g": 160,
        "proteinPer100g": 2.0, "carbsPer100g": 9.0, "fatPer100g": 15.0,
        "weeklyQty": 5, "unit": "pcs", "expiresIn": "Today", "allergens": []
    },
    {
        "id": 103, "name": "Greek Yogurt", "brand": "Danone",
        "emoji": "🥛", "store": "Iki", "originalPrice": 2.49, "discountedPrice": 1.49,
        "discount": 40, "category": "Dairy", "kcalPer100g": 97,
        "proteinPer100g": 9.0, "carbsPer100g": 6.0, "fatPer100g": 5.0,
        "weeklyQty": 4, "unit": "pcs", "expiresIn": "Saturday", "allergens": ["milk"]
    },
    {
        "id": 104, "name": "Rolled Oats", "brand": "Quaker",
        "emoji": "🌾", "store": "Maxima", "originalPrice": 3.29, "discountedPrice": 1.99,
        "discount": 39, "category": "Grains", "kcalPer100g": 379,
        "proteinPer100g": 13.0, "carbsPer100g": 68.0, "fatPer100g": 6.5,
        "weeklyQty": 1, "unit": "kg", "expiresIn": "Sunday", "allergens": ["gluten"]
    },
    {
        "id": 105, "name": "Salmon Fillet", "brand": "OceanFresh",
        "emoji": "🐟", "store": "Rimi", "originalPrice": 12.99, "discountedPrice": 8.99,
        "discount": 31, "category": "Fish", "kcalPer100g": 208,
        "proteinPer100g": 20.0, "carbsPer100g": 0.0, "fatPer100g": 13.0,
        "weeklyQty": 2, "unit": "kg", "expiresIn": "Today", "allergens": ["fish"]
    },
    {
        "id": 106, "name": "Broccoli", "brand": "GreenFarm",
        "emoji": "🥦", "store": "Iki", "originalPrice": 1.49, "discountedPrice": 0.89,
        "discount": 40, "category": "Produce", "kcalPer100g": 34,
        "proteinPer100g": 2.8, "carbsPer100g": 7.0, "fatPer100g": 0.4,
        "weeklyQty": 3, "unit": "pcs", "expiresIn": "Today", "allergens": []
    },
    {
        "id": 107, "name": "Buckwheat", "brand": "HarvestTime",
        "emoji": "🌿", "store": "Lidl", "originalPrice": 2.29, "discountedPrice": 1.39,
        "discount": 39, "category": "Grains", "kcalPer100g": 343,
        "proteinPer100g": 13.0, "carbsPer100g": 72.0, "fatPer100g": 3.4,
        "weeklyQty": 2, "unit": "kg", "expiresIn": "Sunday", "allergens": ["gluten"]
    },
    {
        "id": 108, "name": "Eggs (10-pack)", "brand": "FarmFresh",
        "emoji": "🥚", "store": "Norfa", "originalPrice": 2.99, "discountedPrice": 1.99,
        "discount": 33, "category": "Dairy", "kcalPer100g": 155,
        "proteinPer100g": 13.0, "carbsPer100g": 1.1, "fatPer100g": 11.0,
        "weeklyQty": 10, "unit": "pcs", "expiresIn": "Saturday", "allergens": ["eggs"]
    },
]

def haversine_km(lat1, lon1, lat2, lon2):
    R = 6371.0
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    a = math.sin(dlat/2)**2 + math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) * math.sin(dlon/2)**2
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))

def enrich_deal(deal):
    """Add store lat/lon to a deal dict."""
    store_info = STORES.get(deal["store"], {})
    return {**deal, "latitude": store_info.get("lat", 54.6872), "longitude": store_info.get("lon", 25.2797)}


class MockBackendHandler(BaseHTTPRequestHandler):

    def log_message(self, format, *args):
        pass  # silence default request log

    def _set_headers(self, status=200):
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type, ngrok-skip-browser-warning')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.end_headers()

    def _read_body(self):
        try:
            length = int(self.headers.get('Content-Length', 0))
            raw = self.rfile.read(length) if length > 0 else b'{}'
            return json.loads(raw) if raw else {}, None
        except (ValueError, json.JSONDecodeError) as e:
            return None, str(e)

    def _send_json(self, data, status=200):
        self._set_headers(status)
        self.wfile.write(json.dumps(data).encode())

    def do_OPTIONS(self):
        self._set_headers(200)

    def do_GET(self):
        if self.path == '/api/health':
            self._send_json({"status": "healthy", "agent": "active"})

        elif self.path.startswith('/api/deals'):
            # Optional proximity filter: /api/deals?lat=54.69&lon=25.27&radius=5
            from urllib.parse import urlparse, parse_qs
            params = parse_qs(urlparse(self.path).query)
            try:
                user_lat = float(params.get('lat', [None])[0])
                user_lon = float(params.get('lon', [None])[0])
                radius   = float(params.get('radius', [8])[0])
                nearby = [d for d in DEALS
                          if haversine_km(user_lat, user_lon,
                                         STORES[d['store']]['lat'],
                                         STORES[d['store']]['lon']) <= radius]
                self._send_json([enrich_deal(d) for d in nearby])
            except (TypeError, KeyError):
                # No valid coords supplied — return all deals enriched
                self._send_json([enrich_deal(d) for d in DEALS])
        else:
            self._send_json({"error": "Not found"}, 404)

    def do_POST(self):
        body, err = self._read_body()
        if body is None:
            self._send_json({"error": f"Bad request: {err}"}, 400)
            return

        if self.path == '/api/bmr':
            required = ['weight', 'height', 'age', 'gender', 'activityLevel']
            missing = [f for f in required if f not in body]
            if missing:
                self._send_json({"error": f"Missing fields: {missing}"}, 400)
                return
            # Mifflin-St Jeor BMR
            w, h, a = float(body['weight']), float(body['height']), int(body['age'])
            gender = body['gender'].lower()
            bmr = (10*w + 6.25*h - 5*a + (5 if gender == 'male' else -161))
            multipliers = {
                "sedentary": 1.2, "light": 1.375, "moderate": 1.55,
                "active": 1.725, "very_active": 1.9
            }
            m = multipliers.get(body.get('activityLevel', 'moderate'), 1.55)
            tdee = round(bmr * m)
            self._send_json({
                "bmr": round(bmr),
                "tdee": tdee,
                "loseCalories": round(tdee * 0.85),
                "maintainCalories": tdee,
                "gainCalories": round(tdee * 1.15),
                "macros": {
                    "protein": round(w * 1.6),
                    "carbs": round(tdee * 0.45 / 4),
                    "fat": round(tdee * 0.30 / 9)
                }
            })

        elif self.path == '/api/meal-plan':
            if 'user' not in body or 'goal' not in body:
                self._send_json({"error": "Missing 'user' or 'goal'"}, 400)
                return

            day_plan = {
                "pusryciai":  {"pavadinimas": "Oatmeal with Berries",   "ingredientai": ["oats","blueberries","honey"],          "kcal": 380},
                "pietūs":     {"pavadinimas": "Grilled Chicken Salad",  "ingredientai": ["chicken breast","lettuce","olive oil"],"kcal": 520},
                "vakariene":  {"pavadinimas": "Salmon with Vegetables", "ingredientai": ["salmon","broccoli","lemon"],           "kcal": 580},
                "uzkandziai": {"pavadinimas": "Greek Yogurt & Nuts",    "ingredientai": ["yogurt","almonds","honey"],            "kcal": 220},
                "visoKcal":   1700
            }
            self._send_json({
                "agentMessage": "Based on your favourite foods and current nearby deals I built a balanced week keeping you on track for your goal. Chicken Breast is 33% off at Maxima this week — I've included it in your lunches.",
                "pirmadienis":    day_plan,
                "antradienis":    {**day_plan, "pusryciai": {"pavadinimas": "Scrambled Eggs & Avocado", "ingredientai": ["eggs","avocado","spinach"], "kcal": 420}},
                "treciadienis":   day_plan,
                "ketvirtadienis": {**day_plan, "pietūs": {"pavadinimas": "Salmon Bowl", "ingredientai": ["salmon","rice","cucumber"], "kcal": 560}},
                "pentadienis":    day_plan,
                "sestadienis":    {**day_plan, "vakariene": {"pavadinimas": "Buckwheat & Chicken", "ingredientai": ["buckwheat","chicken","herbs"], "kcal": 510}},
                "sekmadienis":    day_plan,
            })

        elif self.path == '/api/gap-fillers':
            self._send_json([
                {"food": "Broccoli", "reason": "Missing micronutrients", "store": "Iki", "price": 0.89},
                {"food": "Greek Yogurt", "reason": "Protein gap", "store": "Iki", "price": 1.49},
            ])

        elif self.path == '/api/shopping-advice':
            self._send_json({
                "items": [
                    {"food_name": "Chicken Breast", "reason": "33% off at Maxima — covers your weekly protein target",
                     "store_name": "Maxima", "estimated_price": 5.99, "priority": "high"},
                    {"food_name": "Rolled Oats",    "reason": "39% off — great breakfast base",
                     "store_name": "Maxima", "estimated_price": 1.99, "priority": "medium"},
                    {"food_name": "Salmon Fillet",  "reason": "31% off — omega-3 boost for the week",
                     "store_name": "Rimi",   "estimated_price": 8.99, "priority": "medium"},
                ],
                "reasoning": "Prioritising high-discount items that align with your macro targets."
            })

        else:
            self._send_json({"error": "Not found"}, 404)


def run(port=5000):
    httpd = HTTPServer(('', port), MockBackendHandler)
    print(f"🚀  SmartMarket backend on port {port}")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        httpd.server_close()

if __name__ == '__main__':
    run()
