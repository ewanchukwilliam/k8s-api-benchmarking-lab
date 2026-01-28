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
            :root {
                --bg-main: #020617;
                --bg-card: #020617;
                --bg-elevated: #020617;
                --border-subtle: #1f2933;
                --text-main: #e5e7eb;
                --text-muted: #9ca3af;
                --accent: #38bdf8;
                --accent-soft: #0f172a;
                --danger: #f97373;
            }

            * {
                margin: 0;
                padding: 0;
                box-sizing: border-box;
            }

            body {
                font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI",
                             sans-serif;
                background: radial-gradient(circle at top, #020617 0, #020617 45%, #000 100%);
                color: var(--text-main);
                min-height: 100vh;
                display: flex;
                align-items: center;
                justify-content: center;
                padding: 24px;
            }

            .container {
                max-width: 960px;
                width: 100%;
            }

            .card {
                background: var(--bg-card);
                border-radius: 16px;
                padding: 28px 28px 22px 28px;
                box-shadow:
                    0 18px 45px rgba(0, 0, 0, 0.9),
                    0 0 0 1px rgba(148, 163, 184, 0.08);
                border: 1px solid rgba(15, 23, 42, 0.9);
                animation: fadeIn 0.35s ease-out;
            }

            @keyframes fadeIn {
                from {
                    opacity: 0;
                    transform: translateY(4px);
                }
                to {
                    opacity: 1;
                    transform: translateY(0);
                }
            }

            h1 {
                font-size: 1.35rem;
                margin-bottom: 6px;
                letter-spacing: 0.02em;
                display: flex;
                align-items: center;
                gap: 6px;
            }

            h1 span {
                font-size: 1rem;
                font-weight: 500;
                color: var(--accent);
            }

            .subtitle {
                font-size: 0.85rem;
                color: var(--text-muted);
                margin-bottom: 20px;
            }

            .top-row {
                display: flex;
                justify-content: space-between;
                align-items: center;
                gap: 12px;
                margin-bottom: 16px;
            }

            .tag {
                font-size: 0.7rem;
                text-transform: uppercase;
                letter-spacing: 0.08em;
                color: var(--text-muted);
                padding: 4px 9px;
                border-radius: 999px;
                border: 1px solid rgba(148, 163, 184, 0.4);
                background: rgba(15, 23, 42, 0.7);
            }

            .stats {
                display: flex;
                justify-content: flex-start;
                gap: 18px;
                margin-bottom: 20px;
            }

            .stat {
                background: var(--bg-elevated);
                border-radius: 8px;
                padding: 10px 12px;
                border: 1px solid rgba(31, 41, 55, 0.9);
                min-width: 96px;
            }

            .stat-label {
                font-size: 0.7rem;
                color: var(--text-muted);
                margin-bottom: 4px;
                text-transform: uppercase;
                letter-spacing: 0.06em;
            }

            .stat-value {
                font-size: 0.95rem;
                font-weight: 600;
                color: var(--accent);
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
                grid-template-columns: repeat(auto-fit, minmax(210px, 1fr));
                gap: 12px;
                margin-top: 14px;
            }

            .endpoint-card {
                background: #020617;
                border-radius: 10px;
                padding: 14px 14px 12px 14px;
                text-decoration: none;
                color: var(--text-main);
                border: 1px solid rgba(30, 64, 175, 0.55);
                display: flex;
                flex-direction: column;
                gap: 4px;
                transition:
                    transform 0.12s ease,
                    border-color 0.12s ease,
                    box-shadow 0.12s ease,
                    background-color 0.12s ease;
            }

            .endpoint-card:hover {
                transform: translateY(-1px);
                border-color: rgba(56, 189, 248, 0.85);
                box-shadow: 0 10px 20px rgba(15, 23, 42, 0.9);
                background-color: #020617;
            }

            .endpoint-title {
                font-size: 0.9rem;
                font-weight: 500;
                display: flex;
                align-items: center;
                gap: 6px;
            }

            .endpoint-icon {
                font-size: 0.9rem;
                opacity: 0.9;
            }

            .endpoint-desc {
                font-size: 0.8rem;
                color: var(--text-muted);
            }

            .endpoint-card.button-like {
                cursor: pointer;
                border: 1px solid rgba(34, 197, 235, 0.9);
                background: radial-gradient(circle at top left,
                                            rgba(34, 211, 238, 0.12),
                                            rgba(15, 23, 42, 1));
            }

            .endpoint-card.button-like:disabled {
                opacity: 0.7;
                cursor: wait;
                transform: none;
                box-shadow: none;
            }

            .footer {
                text-align: right;
                margin-top: 16px;
                color: var(--text-muted);
                font-size: 0.7rem;
                border-top: 1px solid rgba(15, 23, 42, 1);
                padding-top: 8px;
            }

            .footer span {
                color: var(--accent);
            }

            .hidden {
                display: none;
            }

            .section-header {
                display: flex;
                justify-content: space-between;
                align-items: center;
                margin-top: 10px;
                margin-bottom: 8px;
                gap: 10px;
            }

            .section-header h2 {
                font-size: 0.95rem;
                font-weight: 500;
            }

            .section-status {
                font-size: 0.75rem;
                color: var(--text-muted);
            }

            .section-header-right {
                display: flex;
                align-items: center;
                gap: 8px;
            }

            .grid-panel {
                display: grid;
                grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
                gap: 10px;
                margin-top: 8px;
            }

            .data-card {
                background: #020617;
                border-radius: 10px;
                padding: 12px 12px 10px 12px;
                border: 1px solid rgba(31, 41, 55, 0.9);
                box-shadow: 0 8px 18px rgba(15, 23, 42, 0.9);
                font-size: 0.8rem;
            }

            .data-title {
                font-size: 0.8rem;
                color: var(--text-muted);
                margin-bottom: 3px;
                text-transform: uppercase;
                letter-spacing: 0.06em;
            }

            .data-value {
                font-size: 0.95rem;
                font-weight: 600;
            }

            .data-value.accent {
                color: var(--accent);
            }

            .data-value.bad {
                color: var(--danger);
            }

            .small-text {
                font-size: 0.72rem;
                color: var(--text-muted);
            }

            .btn-refresh {
                padding: 6px 11px;
                border-radius: 999px;
                border: 1px solid rgba(148, 163, 184, 0.5);
                background: rgba(15, 23, 42, 0.9);
                color: var(--text-main);
                font-size: 0.75rem;
                cursor: pointer;
                transition:
                    background-color 0.12s ease,
                    border-color 0.12s ease,
                    transform 0.12s ease;
            }

            .btn-refresh:hover {
                background: rgba(30, 64, 175, 0.95);
                border-color: rgba(56, 189, 248, 0.9);
                transform: translateY(-1px);
            }

            .btn-refresh:disabled {
                opacity: 0.6;
                cursor: wait;
                transform: none;
            }
        </style>
    </head>
    <body>
        <div class="container">
            <div class="card">
                <div class="top-row">
                    <div>
                        <h1>Health Service Monitor <span>· k8s pod view</span></h1>
                        <p class="subtitle">Realtime process & per-pod CPU from Redis, exposed via FastAPI.</p>
                    </div>
                    <div class="tag">Internal · Diagnostics</div>
                </div>

                <!-- Load Testing Instructions -->
                <div style="background: rgba(30, 64, 175, 0.15); border: 1px solid rgba(56, 189, 248, 0.3); border-radius: 10px; padding: 14px 16px; margin-bottom: 18px;">
                    <div style="font-size: 0.85rem; font-weight: 500; margin-bottom: 8px; color: var(--accent);">Load Testing with K6</div>
                    <div style="font-size: 0.8rem; color: var(--text-muted); line-height: 1.5;">
                        Test autoscaling by running K6 against these endpoints:<br>
                        <code style="background: rgba(15, 23, 42, 0.8); padding: 2px 6px; border-radius: 4px; font-size: 0.75rem;">https://api.codeseeker.dev/health</code> or
                        <code style="background: rgba(15, 23, 42, 0.8); padding: 2px 6px; border-radius: 4px; font-size: 0.75rem;">https://api.codeseeker.dev/metrics</code><br><br>
                        <strong style="color: var(--text-main);">Suggested config:</strong> ~100 VUs for 5 minutes<br><br>
                        Then open the <strong style="color: var(--accent);">Redis CPU View</strong> below to watch containers scale in real-time as load increases.
                    </div>
                </div>

                <!-- Overview / static -->
                <div id="default-section">
                    <div class="stats">
                        <div class="stat">
                            <div class="stat-label">Status</div>
                            <div class="stat-value pulse">Online</div>
                        </div>
                        <div class="stat">
                            <div class="stat-label">API Version</div>
                            <div class="stat-value">v2.0</div>
                        </div>
                        <div class="stat">
                            <div class="stat-label">Platform</div>
                            <div class="stat-value">Kubernetes</div>
                        </div>
                    </div>

                    <div class="endpoints">
                        <button id="show-health-btn" type="button" class="endpoint-card button-like">
                            <div class="endpoint-title">
                                <span class="endpoint-icon">●</span>
                                Health View
                            </div>
                            <div class="endpoint-desc">
                                Live status, CPU and memory from /health.
                            </div>
                        </button>

                        <button id="show-metrics-btn" type="button" class="endpoint-card button-like">
                            <div class="endpoint-title">
                                <span class="endpoint-icon">◆</span>
                                Metrics View
                            </div>
                            <div class="endpoint-desc">
                                Detailed process metrics from /metrics.
                            </div>
                        </button>

                        <button id="show-redis-btn" type="button" class="endpoint-card button-like">
                            <div class="endpoint-title">
                                <span class="endpoint-icon">▮▮</span>
                                Redis CPU View
                            </div>
                            <div class="endpoint-desc">
                                Aggregate CPU usage per pod from Redis.
                            </div>
                        </button>
                    </div>
                </div>

                <!-- Health section -->
                <div id="health-section" class="hidden">
                    <div class="section-header">
                        <h2>Process Health</h2>
                        <div class="section-header-right">
                            <span id="health-status" class="section-status"></span>
                            <button id="health-refresh-btn" type="button" class="btn-refresh">Refresh</button>
                        </div>
                    </div>
                    <div id="health-panel" class="grid-panel"></div>
                </div>

                <!-- Metrics section -->
                <div id="metrics-section" class="hidden">
                    <div class="section-header">
                        <h2>Process Metrics</h2>
                        <div class="section-header-right">
                            <span id="metrics-status" class="section-status"></span>
                            <button id="metrics-refresh-btn" type="button" class="btn-refresh">Refresh</button>
                        </div>
                    </div>
                    <div id="metrics-panel" class="grid-panel"></div>
                </div>

                <!-- Redis section -->
                <div id="redis-section" class="hidden">
                    <div class="section-header">
                        <h2>Pod CPU Usage (Redis-backed)</h2>
                        <div class="section-header-right">
                            <span id="redis-status" class="section-status"></span>
                            <button id="refresh-redis-btn" type="button" class="btn-refresh">Refresh</button>
                        </div>
                    </div>
                    <div id="redis-panel" class="grid-panel"></div>
                </div>

                <div class="footer">
                    <span>health-service</span> · FastAPI · Redis · Kubernetes
                </div>
            </div>
        </div>

        <script>
            document.addEventListener("DOMContentLoaded", () => {
                const defaultSection = document.getElementById("default-section");
                const healthSection = document.getElementById("health-section");
                const metricsSection = document.getElementById("metrics-section");
                const redisSection = document.getElementById("redis-section");

                const showHealthBtn = document.getElementById("show-health-btn");
                const showMetricsBtn = document.getElementById("show-metrics-btn");
                const showRedisBtn = document.getElementById("show-redis-btn");

                const healthRefreshBtn = document.getElementById("health-refresh-btn");
                const metricsRefreshBtn = document.getElementById("metrics-refresh-btn");
                const redisRefreshBtn = document.getElementById("refresh-redis-btn");

                const healthStatus = document.getElementById("health-status");
                const metricsStatus = document.getElementById("metrics-status");
                const redisStatus = document.getElementById("redis-status");

                const healthPanel = document.getElementById("health-panel");
                const metricsPanel = document.getElementById("metrics-panel");
                const redisPanel = document.getElementById("redis-panel");

                let autoRedisRefreshId = null;
                let loadingHealth = false;
                let loadingMetrics = false;
                let loadingRedis = false;

                function setActiveSection(section) {
                    defaultSection.classList.add("hidden");
                    healthSection.classList.add("hidden");
                    metricsSection.classList.add("hidden");
                    redisSection.classList.add("hidden");

                    if (section === "default") defaultSection.classList.remove("hidden");
                    if (section === "health") healthSection.classList.remove("hidden");
                    if (section === "metrics") metricsSection.classList.remove("hidden");
                    if (section === "redis") redisSection.classList.remove("hidden");
                }

                async function loadHealth() {
                    if (loadingHealth) return;
                    loadingHealth = true;

                    healthStatus.textContent = "Loading /health...";
                    healthRefreshBtn.disabled = true;
                    showHealthBtn.disabled = true;

                    try {
                        const res = await fetch("/health");
                        const text = await res.text();
                        const data = JSON.parse(text || "{}");

                        setActiveSection("health");
                        healthStatus.textContent = "Last updated: " + new Date().toLocaleTimeString();

                        const frag = document.createDocumentFragment();

                        const statusCard = document.createElement("div");
                        statusCard.className = "data-card";
                        statusCard.innerHTML = `
                            <div class="data-title">Status</div>
                            <div class="data-value ${data.status === "ok" ? "accent" : "bad"}">
                                ${data.status || "unknown"}
                            </div>
                            <div class="small-text">${data.timestamp || ""}</div>
                        `;
                        frag.appendChild(statusCard);

                        const cpuCard = document.createElement("div");
                        cpuCard.className = "data-card";
                        cpuCard.innerHTML = `
                            <div class="data-title">CPU</div>
                            <div class="data-value accent">${(data.cpu_percent ?? 0).toFixed(1)}%</div>
                        `;
                        frag.appendChild(cpuCard);

                        const memCard = document.createElement("div");
                        memCard.className = "data-card";
                        memCard.innerHTML = `
                            <div class="data-title">Memory</div>
                            <div class="data-value accent">${(data.memory_mb ?? 0).toFixed(2)} MB</div>
                            <div class="small-text">${(data.memory_percent ?? 0).toFixed(2)}% of process RSS</div>
                        `;
                        frag.appendChild(memCard);

                        healthPanel.replaceChildren(frag);
                    } catch (err) {
                        console.error(err);
                        healthStatus.textContent = "Error loading /health: " + err;
                    } finally {
                        loadingHealth = false;
                        healthRefreshBtn.disabled = false;
                        showHealthBtn.disabled = false;
                    }
                }

                async function loadMetrics() {
                    if (loadingMetrics) return;
                    loadingMetrics = true;

                    metricsStatus.textContent = "Loading /metrics...";
                    metricsRefreshBtn.disabled = true;
                    showMetricsBtn.disabled = true;

                    try {
                        const res = await fetch("/metrics");
                        const text = await res.text();
                        const data = JSON.parse(text || "{}");

                        setActiveSection("metrics");
                        metricsStatus.textContent = "Last updated: " + new Date().toLocaleTimeString();

                        const frag = document.createDocumentFragment();

                        const cpuCard = document.createElement("div");
                        cpuCard.className = "data-card";
                        cpuCard.innerHTML = `
                            <div class="data-title">CPU</div>
                            <div class="data-value accent">${(data.cpu_percent ?? 0).toFixed(1)}%</div>
                        `;
                        frag.appendChild(cpuCard);

                        const memCard = document.createElement("div");
                        memCard.className = "data-card";
                        memCard.innerHTML = `
                            <div class="data-title">Memory</div>
                            <div class="data-value accent">${(data.memory_mb ?? 0).toFixed(2)} MB</div>
                            <div class="small-text">${(data.memory_percent ?? 0).toFixed(2)}% of process RSS</div>
                        `;
                        frag.appendChild(memCard);

                        const threadsCard = document.createElement("div");
                        threadsCard.className = "data-card";
                        threadsCard.innerHTML = `
                            <div class="data-title">Threads</div>
                            <div class="data-value">${data.num_threads ?? 0}</div>
                        `;
                        frag.appendChild(threadsCard);

                        const filesCard = document.createElement("div");
                        filesCard.className = "data-card";
                        filesCard.innerHTML = `
                            <div class="data-title">Open Files</div>
                            <div class="data-value">${data.open_files ?? 0}</div>
                        `;
                        frag.appendChild(filesCard);

                        const connCard = document.createElement("div");
                        connCard.className = "data-card";
                        connCard.innerHTML = `
                            <div class="data-title">Connections</div>
                            <div class="data-value">${data.connections ?? 0}</div>
                        `;
                        frag.appendChild(connCard);

                        const tsCard = document.createElement("div");
                        tsCard.className = "data-card";
                        tsCard.innerHTML = `
                            <div class="data-title">Timestamp</div>
                            <div class="data-value">${data.timestamp || ""}</div>
                        `;
                        frag.appendChild(tsCard);

                        metricsPanel.replaceChildren(frag);
                    } catch (err) {
                        console.error(err);
                        metricsStatus.textContent = "Error loading /metrics: " + err;
                    } finally {
                        loadingMetrics = false;
                        metricsRefreshBtn.disabled = false;
                        showMetricsBtn.disabled = false;
                    }
                }

                async function loadRedisData() {
                    if (loadingRedis) return;
                    loadingRedis = true;

                    redisStatus.textContent = "Loading Redis CPU data...";
                    redisRefreshBtn.disabled = true;
                    showRedisBtn.disabled = true;

                    try {
                        const res = await fetch("/get-all-redis-keys");
                        const text = await res.text();
                        const data = JSON.parse(text || "{}");

                        const entries = Object.values(data);

                        if (!entries.length) {
                            redisStatus.textContent = "No CPU records found in Redis yet.";
                            return;
                        }

                        setActiveSection("redis");
                        redisStatus.textContent = "Last updated: " + new Date().toLocaleTimeString();

                        const frag = document.createDocumentFragment();

                        entries.forEach(item => {
                            const card = document.createElement("div");
                            card.className = "data-card";

                            const ts = new Date(item.ts * 1000);
                            const tsLabel = ts.toLocaleTimeString();

                            card.innerHTML = `
                                <div class="data-title">Pod</div>
                                <div class="data-value accent">${item.pod}</div>
                                <div class="small-text">${item.namespace}</div>
                                <div style="margin-top:6px" class="data-title">CPU</div>
                                <div class="data-value accent">${item.cpu_percent.toFixed(1)}% CPU</div>
                                <div class="small-text">Updated at ${tsLabel}</div>
                            `;

                            frag.appendChild(card);
                        });

                        redisPanel.replaceChildren(frag);
                    } catch (err) {
                        console.error(err);
                        redisStatus.textContent = "Error loading Redis data: " + err;
                    } finally {
                        loadingRedis = false;
                        redisRefreshBtn.disabled = false;
                        showRedisBtn.disabled = false;
                    }
                }

                showHealthBtn.addEventListener("click", () => {
                    loadHealth();
                });

                healthRefreshBtn.addEventListener("click", () => {
                    loadHealth();
                });

                showMetricsBtn.addEventListener("click", () => {
                    loadMetrics();
                });

                metricsRefreshBtn.addEventListener("click", () => {
                    loadMetrics();
                });

                showRedisBtn.addEventListener("click", () => {
                    loadRedisData();

                    if (autoRedisRefreshId === null) {
                        autoRedisRefreshId = setInterval(loadRedisData, 1000);
                    }
                });

                redisRefreshBtn.addEventListener("click", () => {
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
