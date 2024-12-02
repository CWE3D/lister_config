import requests

url = "http://localhost:7125/machine/update/client"
data = {
    "name": "lister_printables",
    "action": "reset"
}
response = requests.post(url, json=data)
print(response.json())