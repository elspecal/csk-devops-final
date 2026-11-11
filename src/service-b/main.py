from flask import Flask

app = Flask(__name__)

@app.route('/api/sb')
def hello():
    return "Hello from Service B!"

@app.route('/health')
def health():
    return "ok"

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
