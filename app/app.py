from flask import Flask
import os
app = Flask(__name__)
@app.route('/')
def home():
    provider = os.getenv('CLOUD_PROVIDER', 'Unknown')
    return f"<h1>Multi-Cloud Live</h1><p>Provider: <b>{provider}</b></p>"
if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
