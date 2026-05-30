from http.server import BaseHTTPRequestHandler, HTTPServer
import json

class MockBackendHandler(BaseHTTPRequestHandler):
    def _set_headers(self, status=200):
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        # Allow ngrok and iOS to communicate without CORS issues
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type, ngrok-skip-browser-warning')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.end_headers()

    def do_OPTIONS(self):
        self._set_headers(200)

    def do_GET(self):
        if self.path == '/api/health':
            self._set_headers(200)
            self.wfile.write(json.dumps({"status": "healthy", "agent": "active"}).encode())
        
        elif self.path == '/api/deals':
            self._set_headers(200)
            mock_deals = [
                {
                    "id": 101, "name": "Organic Chicken Breast", "brand": "FreshFarm",
                    "emoji": "🍗", "store": "Maxima", "originalPrice": 8.99, "discountedPrice": 5.99,
                    "discount": 33, "category": "Meat", "kcalPer100g": 165,
                    "proteinPer100g": 31.0, "carbsPer100g": 0.0, "fatPer100g": 3.6,
                    "weeklyQty": 2, "unit": "kg", "expiresIn": "Sunday", "allergens": []
                },
                {
                    "id": 102, "name": "Fresh Avocado", "brand": "NatureGood",
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
                    "id": 105, "name": "Atlantic Salmon Fillet", "brand": "OceanFresh",
                    "emoji": "🐟", "store": "Rimi", "originalPrice": 12.99, "discountedPrice": 8.99,
                    "discount": 31, "category": "Fish", "kcalPer100g": 208,
                    "proteinPer100g": 20.0, "carbsPer100g": 0.0, "fatPer100g": 13.0,
                    "weeklyQty": 2, "unit": "kg", "expiresIn": "Today", "allergens": ["fish"]
                }
            ]
            self.wfile.write(json.dumps(mock_deals).encode())
        else:
            self._set_headers(404)

    def do_POST(self):
        try:
            content_length = int(self.headers.get('Content-Length', 0))
            post_data = self.rfile.read(content_length) if content_length > 0 else b'{}'
        except ValueError:
            self._set_headers(400)
            self.wfile.write(json.dumps({"error": "Invalid Content-Length"}).encode())
            return

        try:
            body = json.loads(post_data) if post_data else {}
        except json.JSONDecodeError:
            self._set_headers(400)
            self.wfile.write(json.dumps({"error": "Invalid JSON body"}).encode())
            return

        if self.path == '/api/bmr':
            required = ['weight', 'height', 'age', 'gender', 'activityLevel']
            missing = [f for f in required if f not in body]
            if missing:
                self._set_headers(400)
                self.wfile.write(json.dumps({"error": f"Missing fields: {missing}"}).encode())
                return
            self._set_headers(200)
            # Mock response structure for BMR data
            bmr_response = {
                "bmr": 1700, "tdee": 2200, "loseCalories": 1850,
                "maintainCalories": 2200, "gainCalories": 2550,
                "macros": {"protein": 165, "carbs": 220, "fat": 73}
            }
            self.wfile.write(json.dumps(bmr_response).encode())

        elif self.path == '/api/meal-plan':
            if 'user' not in body or 'goal' not in body:
                self._set_headers(400)
                self.wfile.write(json.dumps({"error": "Missing 'user' or 'goal' field"}).encode())
                return
            self._set_headers(200)
            day_plan = {
                "pusryciai":  {"pavadinimas": "Oatmeal with Berries",    "ingredientai": ["oats", "blueberries", "honey"],           "kcal": 380},
                "pietūs":     {"pavadinimas": "Grilled Chicken Salad",  "ingredientai": ["chicken breast", "lettuce", "olive oil"], "kcal": 520},
                "vakariene":  {"pavadinimas": "Salmon with Vegetables",  "ingredientai": ["salmon", "broccoli", "lemon"],            "kcal": 580},
                "uzkandziai": {"pavadinimas": "Greek Yogurt & Nuts",     "ingredientai": ["yogurt", "almonds", "honey"],             "kcal": 220},
                "visoKcal":   1700
            }
            meal_plan_response = {
                "agentMessage": "Based on your favourite foods and current deals I've built a balanced week keeping you on track for your goal.",
                "pirmadienis":    day_plan,
                "antradienis":    day_plan,
                "treciadienis":   day_plan,
                "ketvirtadienis": day_plan,
                "pentadienis":    day_plan,
                "sestadienis":    day_plan,
                "sekmadienis":    day_plan
            }
            self.wfile.write(json.dumps(meal_plan_response).encode())
        else:
            self._set_headers(404)

def run(port=5000):
    server_address = ('', port)
    httpd = HTTPServer(server_address, MockBackendHandler)
    print(f"🚀 Mock SmartMarket Backend running on port {port}...")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nStopping server.")
        httpd.server_close()

if __name__ == '__main__':
    run()
