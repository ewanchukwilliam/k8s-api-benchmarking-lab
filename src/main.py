import os
import logging
from datetime import datetime
from typing import Dict
from fastapi.responses import HTMLResponse
import psutil
from fastapi import FastAPI
from pydantic import BaseModel
import uvicorn
import redis
import time
import json
import threading


POD_NAME = os.getenv("POD_NAME")
POD_NAMESPACE = os.getenv("POD_NAMESPACE", "default")
NODE_NAME = os.getenv("NODE_NAME")

print("Node from env:", NODE_NAME)

REDIS_HOST = os.getenv("REDIS_HOST", "localhost")
REDIS_PORT = os.getenv("REDIS_PORT", "6379")
r = redis.Redis(host=REDIS_HOST, port=REDIS_PORT, db=0, decode_responses=True)

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler()  
    ]
)

logger = logging.getLogger(__name__)

app = FastAPI(
    title="Health Service Resource Monitor",
    description="HTTP service to monitor process resource usage",
    version="2.0.0"
)

process = psutil.Process()

class HealthResponse(BaseModel):
    status: str
    timestamp: str
    cpu_percent: float
    memory_mb: float
    memory_percent: float


class ProcessMetrics(BaseModel):
    cpu_percent: float
    memory_mb: float
    memory_percent: float
    num_threads: int
    open_files: int
    connections: int
    timestamp: str


@app.get("/", response_model=dict)
async def root():
    """Root endpoint with service information"""
    return {
        "service": "Health Service Resource Monitor",
        "version": "2.0.0",
        "endpoints": {
            "/health": "Health check with current resource usage",
            "/metrics": "Detailed process resource metrics"
        }
    }

def get_process_metrics() -> Dict:
    """Get current process resource usage"""
    try:
        # Non-blocking CPU check (interval=0 returns instantly)
        cpu_percent = process.cpu_percent(interval=0)
        memory_info = process.memory_info()
        memory_mb = round(memory_info.rss / 1024 / 1024, 2)
        memory_percent = round(process.memory_percent(), 2)
        num_threads = process.num_threads()
        try:
            open_files = len(process.open_files())
        except:
            open_files = 0
        try:
            connections = len(process.connections())
        except:
            connections = 0
        return {
            "cpu_percent": round(cpu_percent, 2),
            "memory_mb": memory_mb,
            "memory_percent": memory_percent,
            "num_threads": num_threads,
            "open_files": open_files,
            "connections": connections
        }
    except Exception as e:
        logger.error(f"Error getting process metrics: {e}")
        return {
            "cpu_percent": 0.0,
            "memory_mb": 0.0,
            "memory_percent": 0.0,
            "num_threads": 0,
            "open_files": 0,
            "connections": 0
        }


@app.get("/health", response_model=HealthResponse)
async def health_check():
    """Health check endpoint with current resource usage"""
    metrics = get_process_metrics()

    health_status = {
        "status": "ok",
        "timestamp": datetime.utcnow().isoformat(),
        "cpu_percent": metrics["cpu_percent"],
        "memory_mb": metrics["memory_mb"],
        "memory_percent": metrics["memory_percent"]
    }

    logger.info(f"Health check: CPU={metrics['cpu_percent']}%, Memory={metrics['memory_mb']}MB")
    return health_status


@app.get("/metrics", response_model=ProcessMetrics)
async def get_metrics():
    """Get detailed process resource metrics"""
    metrics = get_process_metrics()

    response = ProcessMetrics(
        cpu_percent=metrics["cpu_percent"],
        memory_mb=metrics["memory_mb"],
        memory_percent=metrics["memory_percent"],
        num_threads=metrics["num_threads"],
        open_files=metrics["open_files"],
        connections=metrics["connections"],
        timestamp=datetime.utcnow().isoformat()
    )

    logger.info(f"Metrics: CPU={metrics['cpu_percent']}%, "
               f"Memory={metrics['memory_mb']}MB ({metrics['memory_percent']}%), "
               f"Threads={metrics['num_threads']}")

    return response

@app.get("/page", response_class=HTMLResponse)
async def return_page():
    """this just returns a webpage to mess around with"""

    logger.info(f"Someone requested a webpage time: {datetime.utcnow().isoformat()}")
    html_content = """
    <!DOCTYPE html>
    <html>
    <head>
        <title>Health Service Monitor</title>
        <style>
            * {
                margin: 0;
                padding: 0;
                box-sizing: border-box;
            }

            body {
                font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                min-height: 100vh;
                display: flex;
                align-items: center;
                justify-content: center;
                padding: 20px;
            }

            .container {
                max-width: 900px;
                width: 100%;
            }

            .card {
                background: rgba(255, 255, 255, 0.95);
                backdrop-filter: blur(10px);
                border-radius: 20px;
                padding: 40px;
                box-shadow: 0 20px 60px rgba(0, 0, 0, 0.3);
                animation: fadeIn 0.6s ease-out;
            }

            @keyframes fadeIn {
                from {
                    opacity: 0;
                    transform: translateY(20px);
                }
                to {
                    opacity: 1;
                    transform: translateY(0);
                }
            }

            h1 {
                color: #667eea;
                font-size: 2.5em;
                margin-bottom: 10px;
                text-align: center;
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                -webkit-background-clip: text;
                -webkit-text-fill-color: transparent;
                background-clip: text;
            }

            .subtitle {
                text-align: center;
                color: #666;
                margin-bottom: 40px;
                font-size: 1.1em;
            }

            .stats {
                display: flex;
                justify-content: space-around;
                margin: 30px 0;
                padding: 20px;
                background: linear-gradient(135deg, rgba(102, 126, 234, 0.1) 0%, rgba(118, 75, 162, 0.1) 100%);
                border-radius: 15px;
            }

            .stat {
                text-align: center;
            }

            .stat-value {
                font-size: 2em;
                font-weight: bold;
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                -webkit-background-clip: text;
                -webkit-text-fill-color: transparent;
                background-clip: text;
            }

            .stat-label {
                color: #666;
                font-size: 0.9em;
                margin-top: 5px;
            }

            .pulse {
                animation: pulse 2s ease-in-out infinite;
            }

            @keyframes pulse {
                0%, 100% { opacity: 1; }
                50% { opacity: 0.6; }
            }

            .endpoints {
                display: grid;
                grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
                gap: 20px;
                margin-top: 30px;
            }

            .endpoint-card {
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                padding: 25px;
                border-radius: 15px;
                text-decoration: none;
                color: white;
                transition: all 0.3s ease;
                box-shadow: 0 5px 15px rgba(102, 126, 234, 0.3);
            }

            .endpoint-card:hover {
                transform: translateY(-5px);
                box-shadow: 0 10px 25px rgba(102, 126, 234, 0.5);
            }

            .endpoint-title {
                font-size: 1.3em;
                font-weight: bold;
                margin-bottom: 10px;
                display: flex;
                align-items: center;
            }

            .endpoint-icon {
                margin-right: 10px;
                font-size: 1.5em;
            }

            .endpoint-desc {
                font-size: 0.9em;
                opacity: 0.9;
            }

            .footer {
                text-align: center;
                margin-top: 30px;
                color: #666;
                font-size: 0.9em;
            }

            /* extra stuff for Redis view */

            .hidden {
                display: none;
            }

            .redis-header {
                display: flex;
                justify-content: space-between;
                align-items: center;
                margin-top: 30px;
                margin-bottom: 10px;
                gap: 12px;
            }

            .redis-header h2 {
                font-size: 1.4em;
                color: #444;
            }

            .redis-status {
                font-size: 0.85em;
                color: #666;
                margin-right: 8px;
            }

            .redis-header-right {
                display: flex;
                align-items: center;
                gap: 8px;
            }

            .redis-grid {
                display: grid;
                grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
                gap: 16px;
                margin-top: 10px;
            }

            .redis-card {
                background: linear-gradient(135deg, #f5f7ff 0%, #eef2ff 100%);
                border-radius: 12px;
                padding: 16px;
                box-shadow: 0 4px 12px rgba(0, 0, 0, 0.08);
                border: 1px solid rgba(102, 126, 234, 0.2);
            }

            .redis-pod {
                font-weight: 600;
                margin-bottom: 4px;
                color: #333;
            }

            .redis-namespace {
                font-size: 0.85em;
                color: #777;
                margin-bottom: 8px;
            }

            .redis-cpu {
                font-size: 1.2em;
                font-weight: 700;
                color: #667eea;
                margin-bottom: 4px;
            }

            .redis-ts {
                font-size: 0.8em;
                color: #555;
            }

            .endpoint-card.button-like {
                display: flex;
                justify-content: space-between;
                align-items: center;
                cursor: pointer;
                border: none;
                width: 100%;
                text-align: left;
            }

            .endpoint-card.button-like:disabled {
                opacity: 0.6;
                cursor: wait;
            }

            .btn-refresh {
                padding: 8px 14px;
                border-radius: 999px;
                border: none;
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                color: #fff;
                font-size: 0.8em;
                cursor: pointer;
                box-shadow: 0 4px 10px rgba(102,126,234,0.4);
                transition: transform 0.15s ease, box-shadow 0.15s ease, opacity 0.15s ease;
                white-space: nowrap;
            }

            .btn-refresh:hover {
                transform: translateY(-1px);
                box-shadow: 0 6px 14px rgba(102,126,234,0.6);
            }

            .btn-refresh:disabled {
                opacity: 0.6;
                cursor: wait;
                transform: none;
                box-shadow: 0 3px 8px rgba(0,0,0,0.1);
            }
        </style>
    </head>
    <body>
        <div class="container">
            <div class="card">
                <h1>🚀 Health Service Monitor</h1>
                <p class="subtitle">Real-time containerized FastAPI service monitoring</p>

                <div id="default-section">
                    <div class="stats">
                        <div class="stat">
                            <div class="stat-value pulse">✓</div>
                            <div class="stat-label">Status: Online</div>
                        </div>
                        <div class="stat">
                            <div class="stat-value">v2.0</div>
                            <div class="stat-label">API Version</div>
                        </div>
                        <div class="stat">
                            <div class="stat-value">K8s</div>
                            <div class="stat-label">Platform</div>
                        </div>
                    </div>

                    <div class="endpoints">
                        <a href="/health" class="endpoint-card">
                            <div class="endpoint-title">
                                <span class="endpoint-icon">❤️</span>
                                Health Check
                            </div>
                            <div class="endpoint-desc">
                                Current resource usage and health status
                            </div>
                        </a>

                        <a href="/metrics" class="endpoint-card">
                            <div class="endpoint-title">
                                <span class="endpoint-icon">📊</span>
                                Metrics
                            </div>
                            <div class="endpoint-desc">
                                Detailed process and system metrics
                            </div>
                        </a>

                        <button id="show-redis-btn" type="button" class="endpoint-card button-like">
                            <div class="endpoint-title">
                                <span class="endpoint-icon">🧠</span>
                                Redis CPU View
                            </div>
                            <div class="endpoint-desc">
                                Visualize per-pod CPU from Redis
                            </div>
                        </button>
                    </div>
                </div>

                <div id="redis-section" class="hidden">
                    <div class="redis-header">
                        <h2>Pod CPU Usage (from Redis)</h2>
                        <div class="redis-header-right">
                            <span id="redis-status" class="redis-status"></span>
                            <button id="refresh-redis-btn" type="button" class="btn-refresh">Refresh</button>
                        </div>
                    </div>
                    <div id="redis-panel" class="redis-grid"></div>
                </div>

                <div class="footer">
                    Deployed with ❤️ using Docker, Kubernetes, NGINX & cert-manager
                </div>
            </div>
        </div>

        <script>
            document.addEventListener("DOMContentLoaded", () => {
                const btn = document.getElementById("show-redis-btn");
                const refreshBtn = document.getElementById("refresh-redis-btn");
                const defaultSection = document.getElementById("default-section");
                const redisSection = document.getElementById("redis-section");
                const statusEl = document.getElementById("redis-status");
                const panel = document.getElementById("redis-panel");

                async function loadRedisData() {
                    statusEl.textContent = "Loading Redis CPU data...";
                    panel.innerHTML = "";

                    btn.disabled = true;
                    refreshBtn.disabled = true;

                    try {
                        const res = await fetch("/get-all-redis-keys");
                        const text = await res.text();
                        const data = JSON.parse(text);

                        const entries = Object.values(data);

                        if (!entries.length) {
                            statusEl.textContent = "No CPU records found in Redis yet.";
                            return;
                        }

                        // Swap views (idempotent)
                        defaultSection.classList.add("hidden");
                        redisSection.classList.remove("hidden");
                        statusEl.textContent = "Last updated: " + new Date().toLocaleTimeString();

                        entries.forEach(item => {
                            const card = document.createElement("div");
                            card.className = "redis-card";

                            const ts = new Date(item.ts * 1000); // ts is UNIX timestamp
                            const tsLabel = ts.toLocaleTimeString();

                            card.innerHTML = `
                                <div class="redis-pod">${item.pod}</div>
                                <div class="redis-namespace">${item.namespace}</div>
                                <div class="redis-cpu">${item.cpu_percent.toFixed(1)}% CPU</div>
                                <div class="redis-ts">Updated at ${tsLabel}</div>
                            `;

                            panel.appendChild(card);
                        });
                    } catch (err) {
                        console.error(err);
                        statusEl.textContent = "Error loading Redis data: " + err;
                    } finally {
                        btn.disabled = false;
                        refreshBtn.disabled = false;
                    }
                }

                btn.addEventListener("click", () => {
                    loadRedisData();
                });

                refreshBtn.addEventListener("click", () => {
                    loadRedisData();
                });
            });
        </script>
    </body>
    </html>
    """
    return HTMLResponse(content=html_content)



@app.get("/check-redis", response_class=HTMLResponse)
async def return_redis_port_connection_status():
    """this just checks port 6379 to see if redis is running"""
    try:
        r.ping()
        return HTMLResponse(content="container is able to connect to redis")
    except Exception as e:
        return HTMLResponse(content=f"container is unable to connect to redis + {e}")

@app.get("/get-all-redis-keys", response_class=HTMLResponse)
async def get_all_redis_keys():
    """return and join all keys in redis"""
    try:
        state = {}
        for key in r.scan_iter("cpu:*"):
            val = r.get(key)
            if val:
                state[key] = json.loads(val)
        logger.info(f"All keys in redis: {state}")
        return HTMLResponse(content=json.dumps(state))
    except Exception as e:
        logger.error(f"Error getting all keys from redis: {e}")
        return HTMLResponse(content=f"Error getting all keys from redis: {e}")

# this is a background thread/task that runs periodically and reports CPU usage to the shared Redis pod
def start_cpu_reporter():
    redis_url = os.getenv("REDIS_URL", "redis://localhost:6379/0")
    r = redis.Redis.from_url(redis_url, decode_responses=True)
    ns = os.getenv("POD_NAMESPACE", "default")
    pod = os.getenv("POD_NAME", "unknown")
    key = f"cpu:{ns}:{pod}"
    ttl = 5
    interval = 3
    psutil.cpu_percent(interval=None)  # prime
    def loop():
        while True:
            try:
                cpu = psutil.cpu_percent(interval=None)
                payload = {
                    "pod": pod,
                    "namespace": ns,
                    "cpu_percent": cpu,
                    "ts": time.time(),
                }
                r.set(key, json.dumps(payload), ex=ttl)
            except Exception:
                # optionally log the exception here
                pass
            time.sleep(interval)
    t = threading.Thread(target=loop, daemon=True, name="cpu-reporter")
    t.start()
    return t

@app.on_event("startup")
def startup():
    start_cpu_reporter()


if __name__ == "__main__":
    port = int(os.getenv("PORT", 8080))
    host = os.getenv("HOST", "0.0.0.0")
    workers = int(os.getenv("WORKERS", 10))  


    logger.info(f"Starting Container Resource Monitor on {host}:{port} with {workers} workers")
    uvicorn.run(
        "main:app",
        host=host,
        port=port,
        workers=workers,
        log_level="info"
    )
