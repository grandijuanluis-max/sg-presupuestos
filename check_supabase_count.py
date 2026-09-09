import urllib.request
import urllib.error
import json

url = "https://amkkuwgatjcbiyrykuoy.supabase.co/rest/v1/clientes?select=codigo"
headers = {
    "apikey": "sb_publishable_I5bemh3YRuiTNkMzWyCA3A_D_aqFlNJ",
    "Authorization": "Bearer sb_publishable_I5bemh3YRuiTNkMzWyCA3A_D_aqFlNJ"
}

req = urllib.request.Request(url, headers=headers)
try:
    with urllib.request.urlopen(req) as response:
        data = json.loads(response.read().decode('utf-8'))
        print(f"Count: {len(data)}")
        if len(data) > 0:
            print("First row:", data[0])
except urllib.error.HTTPError as e:
    print(f"HTTP Error {e.code}: {e.read().decode('utf-8')}")
except Exception as e:
    print(f"Error: {e}")
