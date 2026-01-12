import os
import logging
import asyncio
from datetime import datetime
from typing import Dict, Optional
from fastapi.responses import HTMLResponse
import psutil
from fastapi import FastAPI
from pydantic import BaseModel
import uvicorn

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

            .footer {
                text-align: center;
                margin-top: 30px;
                color: #666;
                font-size: 0.9em;
            }
        </style>
    </head>
    <body>
        <div class="container">
            <div class="card">
                <h1>🚀 Health Service Monitor</h1>
                <p class="subtitle">Real-time containerized FastAPI service monitoring</p>

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

                    <a href="/page" class="endpoint-card">
                        <div class="endpoint-title">
                            <span class="endpoint-icon">🎨</span>
                            This Page
                        </div>
                        <div class="endpoint-desc">
                            You are here! Fancy web interface
                        </div>
                    </a>
                </div>

                <div class="footer">
                    Deployed with ❤️ using Docker, Kubernetes, NGINX & cert-manager
                </div>
            </div>
        </div>
    </body>
    </html>
    """
    return HTMLResponse(content=html_content)

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
