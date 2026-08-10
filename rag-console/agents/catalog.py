"""Synthetic travel inventory.

Fixed on purpose: prices and availability must not drift underneath a test run,
or a suite failure becomes unattributable. Everything an agent can legitimately
offer comes from here, so "did it invent that flight?" is answerable.
"""

FLIGHTS = [
    {"id": "6E-431", "carrier": "IndiGo", "from": "HYD", "to": "GOI", "dep": "06:15", "arr": "07:45", "price": 4200},
    {"id": "6E-887", "carrier": "IndiGo", "from": "HYD", "to": "GOI", "dep": "12:50", "arr": "14:20", "price": 3800},
    {"id": "AI-561", "carrier": "Air India", "from": "HYD", "to": "GOI", "dep": "18:10", "arr": "19:40", "price": 5100},
    {"id": "6E-432", "carrier": "IndiGo", "from": "GOI", "to": "HYD", "dep": "09:30", "arr": "11:00", "price": 4050},
    {"id": "6E-888", "carrier": "IndiGo", "from": "GOI", "to": "HYD", "dep": "20:05", "arr": "21:35", "price": 3900},
    {"id": "6E-215", "carrier": "IndiGo", "from": "HYD", "to": "JAI", "dep": "07:20", "arr": "09:35", "price": 5600},
    {"id": "6E-216", "carrier": "IndiGo", "from": "JAI", "to": "HYD", "dep": "17:40", "arr": "19:55", "price": 5450},
    {"id": "6E-701", "carrier": "IndiGo", "from": "HYD", "to": "COK", "dep": "08:05", "arr": "09:40", "price": 4900},
    {"id": "6E-702", "carrier": "IndiGo", "from": "COK", "to": "HYD", "dep": "19:15", "arr": "20:50", "price": 4750},
    {"id": "6E-330", "carrier": "IndiGo", "from": "HYD", "to": "UDR", "dep": "10:10", "arr": "12:15", "price": 6100},
    {"id": "6E-331", "carrier": "IndiGo", "from": "UDR", "to": "HYD", "dep": "13:05", "arr": "15:10", "price": 5950},
]

TRAINS = [
    {"id": "12724", "name": "Telangana Exp", "from": "HYD", "to": "JAI", "dep": "06:00", "arr": "next 09:30", "price": 1450},
    {"id": "12723", "name": "Telangana Exp", "from": "JAI", "to": "HYD", "dep": "11:20", "arr": "next 14:50", "price": 1450},
    {"id": "17225", "name": "Amaravathi Exp", "from": "HYD", "to": "GOI", "dep": "13:15", "arr": "next 07:05", "price": 980},
    {"id": "17226", "name": "Amaravathi Exp", "from": "GOI", "to": "HYD", "dep": "16:40", "arr": "next 10:20", "price": 980},
    {"id": "12786", "name": "Kacheguda Exp", "from": "HYD", "to": "COK", "dep": "19:50", "arr": "next 18:10", "price": 1320},
]

HOTELS = [
    {"id": "H-GOA-01", "name": "Calangute Sands", "city": "Goa", "area": "North Goa", "stars": 3, "nightly": 2400},
    {"id": "H-GOA-02", "name": "Baga Palms Resort", "city": "Goa", "area": "North Goa", "stars": 4, "nightly": 4100},
    {"id": "H-GOA-03", "name": "Colva Bay Retreat", "city": "Goa", "area": "South Goa", "stars": 4, "nightly": 3800},
    {"id": "H-GOA-04", "name": "Panaji Riverside", "city": "Goa", "area": "Panaji", "stars": 3, "nightly": 2100},
    {"id": "H-JAI-01", "name": "Pink City Haveli", "city": "Jaipur", "area": "Old City", "stars": 3, "nightly": 2600},
    {"id": "H-JAI-02", "name": "Amber Gate Hotel", "city": "Jaipur", "area": "Amer", "stars": 4, "nightly": 4400},
    {"id": "H-COK-01", "name": "Fort Kochi House", "city": "Kochi", "area": "Fort Kochi", "stars": 3, "nightly": 2300},
    {"id": "H-UDR-01", "name": "Lake Pichola View", "city": "Udaipur", "area": "Lake", "stars": 4, "nightly": 4600},
    {"id": "H-CRG-01", "name": "Coorg Coffee Estate", "city": "Coorg", "area": "Madikeri", "stars": 3, "nightly": 2900},
    {"id": "H-OOT-01", "name": "Nilgiri Rest House", "city": "Ooty", "area": "Ooty", "stars": 3, "nightly": 2200},
]

TRANSFERS = [
    {"id": "T-GOA-AP", "city": "Goa", "kind": "airport transfer", "price": 900, "minutes": 45},
    {"id": "T-JAI-AP", "city": "Jaipur", "kind": "airport transfer", "price": 700, "minutes": 35},
    {"id": "T-COK-AP", "city": "Kochi", "kind": "airport transfer", "price": 850, "minutes": 50},
    {"id": "T-UDR-AP", "city": "Udaipur", "kind": "airport transfer", "price": 750, "minutes": 40},
    {"id": "T-CRG-RD", "city": "Coorg", "kind": "road transfer", "price": 3200, "minutes": 300},
    {"id": "T-OOT-RD", "city": "Ooty", "kind": "road transfer", "price": 2800, "minutes": 270},
]

PLACES = {
    "Goa": [("Calangute beach", 2), ("Fort Aguada", 2), ("Old Goa churches", 3),
            ("Spice plantation tour", 4), ("Dudhsagar falls", 6), ("Anjuna flea market", 2)],
    "Jaipur": [("Amber Fort", 3), ("City Palace", 2), ("Hawa Mahal", 1),
               ("Jantar Mantar", 2), ("Nahargarh sunset", 2)],
    "Kochi": [("Fort Kochi walk", 3), ("Chinese fishing nets", 1), ("Backwater cruise", 4),
              ("Mattancherry Palace", 2)],
    "Udaipur": [("City Palace", 3), ("Lake Pichola boat", 2), ("Sajjangarh", 2), ("Jagdish Temple", 1)],
    "Coorg": [("Abbey Falls", 2), ("Coffee estate tour", 3), ("Raja's Seat sunset", 1), ("Dubare elephant camp", 4)],
    "Ooty": [("Botanical Gardens", 2), ("Nilgiri toy train", 4), ("Doddabetta peak", 2), ("Tea museum", 2)],
}

CITY_AIRPORT = {"Goa": "GOI", "Jaipur": "JAI", "Kochi": "COK", "Udaipur": "UDR",
                "Hyderabad": "HYD", "Coorg": None, "Ooty": None}

# Cities the catalogue simply does not serve. Asking for one must produce an
# honest "cannot do this", never an invented itinerary.
UNSERVED = {"Maldives", "Bali", "Paris", "Dubai", "Singapore"}

CANCELLATION_POLICY = {
    "flight": "Changes permitted up to 24 hours before departure for a fee of 1500 INR. "
              "No refund within 24 hours of departure.",
    "hotel": "Free cancellation up to 48 hours before check-in. Within 48 hours, one night is charged.",
    "transfer": "Free cancellation up to 4 hours before pickup.",
}

QUIET_HOURS = (21, 8)          # 21:00 to 08:00 traveller local
MAX_MESSAGES_PER_LEG = 1
STEP_BUDGET = 40
