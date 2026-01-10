import os
import logging
import asyncio
from datetime import datetime
from typing import Dict, Optional
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
        
        cpu_percent = process.cpu_percent(interval=0.1)
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


if __name__ == "__main__":
    port = int(os.getenv("PORT", 8080))
    host = os.getenv("HOST", "0.0.0.0")
    workers = int(os.getenv("WORKERS", 3))  

    logger.info(f"Starting Container Resource Monitor on {host}:{port} with {workers} workers")
    uvicorn.run(
        "main:app",
        host=host,
        port=port,
        workers=workers,
        log_level="info"
    )
