import os
import logging
import asyncio
from datetime import datetime
from typing import Dict, List, Optional
import docker
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import uvicorn

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler()  # Only log to stdout for Kubernetes
    ]
)
logger = logging.getLogger(__name__)

# Initialize FastAPI app
app = FastAPI(
    title="Container Resource Monitor",
    description="HTTP service to monitor Docker container resource usage",
    version="1.0.0"
)

# Initialize Docker client
try:
    docker_client = docker.from_env()
    logger.info("Docker client initialized successfully")
except Exception as e:
    logger.error(f"Failed to initialize Docker client: {e}")
    docker_client = None

# Cache Docker status instead of checking on every request
docker_status = {"connected": False}


# Pydantic models for response schemas
class HealthResponse(BaseModel):
    status: str
    timestamp: str
    docker_connected: bool


class ContainerStats(BaseModel):
    container_id: str
    container_name: str
    cpu_percent: float
    memory_usage_mb: float
    memory_limit_mb: float
    memory_percent: float
    network_rx_mb: float
    network_tx_mb: float
    block_read_mb: float
    block_write_mb: float
    status: str


class ContainerInfo(BaseModel):
    container_id: str
    name: str
    image: str
    status: str
    created: str


async def check_docker_status():
    """Background task to check Docker status every 5 seconds"""
    while True:
        try:
            if docker_client:
                await asyncio.to_thread(docker_client.ping)
                docker_status["connected"] = True
            else:
                docker_status["connected"] = False
        except Exception as e:
            logger.warning(f"Docker ping failed: {e}")
            docker_status["connected"] = False
        await asyncio.sleep(5)


@app.on_event("startup")
async def startup():
    """Start background Docker status checker"""
    asyncio.create_task(check_docker_status())
    logger.info("Background Docker status checker started")


@app.get("/", response_model=dict)
async def root():
    """Root endpoint with service information"""
    return {
        "service": "Container Resource Monitor",
        "version": "1.0.0",
        "endpoints": {
            "/health": "Health check endpoint",
            "/containers": "List all containers",
            "/metrics": "Get resource usage for all running containers",
            "/metrics/{container_id}": "Get resource usage for a specific container"
        }
    }


@app.get("/health", response_model=HealthResponse)
async def health_check():
    """Health check endpoint - uses cached Docker status"""
    docker_connected = docker_status["connected"]

    health_status = {
        "status": "ok" if docker_connected else "degraded",
        "timestamp": datetime.utcnow().isoformat(),
        "docker_connected": docker_connected
    }

    logger.info(f"Health check: {health_status}")
    return health_status


@app.get("/containers", response_model=List[ContainerInfo])
async def list_containers(all_containers: bool = False):
    """List all Docker containers"""
    if not docker_client:
        raise HTTPException(status_code=503, detail="Docker client not available")

    try:
        containers = docker_client.containers.list(all=all_containers)
        container_list = []

        for container in containers:
            container_list.append(ContainerInfo(
                container_id=container.id[:12],
                name=container.name,
                image=container.image.tags[0] if container.image.tags else container.image.id[:12],
                status=container.status,
                created=container.attrs['Created']
            ))

        logger.info(f"Listed {len(container_list)} containers")
        return container_list

    except Exception as e:
        logger.error(f"Error listing containers: {e}")
        raise HTTPException(status_code=500, detail=str(e))


def calculate_cpu_percent(stats: dict) -> float:
    """Calculate CPU usage percentage from Docker stats"""
    try:
        cpu_delta = stats['cpu_stats']['cpu_usage']['total_usage'] - \
                   stats['precpu_stats']['cpu_usage']['total_usage']
        system_delta = stats['cpu_stats']['system_cpu_usage'] - \
                      stats['precpu_stats']['system_cpu_usage']

        if system_delta > 0 and cpu_delta > 0:
            cpu_percent = (cpu_delta / system_delta) * \
                         len(stats['cpu_stats']['cpu_usage'].get('percpu_usage', [1])) * 100.0
            return round(cpu_percent, 2)
    except (KeyError, ZeroDivisionError):
        pass
    return 0.0


def get_container_stats(container) -> Optional[ContainerStats]:
    """Get resource usage statistics for a container"""
    try:
        stats = container.stats(stream=False)

        # Calculate CPU percentage
        cpu_percent = calculate_cpu_percent(stats)

        # Calculate memory usage
        memory_usage = stats['memory_stats'].get('usage', 0)
        memory_limit = stats['memory_stats'].get('limit', 1)
        memory_percent = (memory_usage / memory_limit) * 100 if memory_limit > 0 else 0

        # Calculate network I/O
        network_rx = 0
        network_tx = 0
        if 'networks' in stats:
            for interface, data in stats['networks'].items():
                network_rx += data.get('rx_bytes', 0)
                network_tx += data.get('tx_bytes', 0)

        # Calculate block I/O
        block_read = 0
        block_write = 0
        if 'blkio_stats' in stats and 'io_service_bytes_recursive' in stats['blkio_stats']:
            for entry in stats['blkio_stats']['io_service_bytes_recursive'] or []:
                if entry['op'] == 'Read':
                    block_read += entry['value']
                elif entry['op'] == 'Write':
                    block_write += entry['value']

        container_stats = ContainerStats(
            container_id=container.id[:12],
            container_name=container.name,
            cpu_percent=cpu_percent,
            memory_usage_mb=round(memory_usage / 1024 / 1024, 2),
            memory_limit_mb=round(memory_limit / 1024 / 1024, 2),
            memory_percent=round(memory_percent, 2),
            network_rx_mb=round(network_rx / 1024 / 1024, 2),
            network_tx_mb=round(network_tx / 1024 / 1024, 2),
            block_read_mb=round(block_read / 1024 / 1024, 2),
            block_write_mb=round(block_write / 1024 / 1024, 2),
            status=container.status
        )

        # Log the metrics
        logger.info(f"Container {container.name}: CPU={cpu_percent}%, "
                   f"Memory={container_stats.memory_usage_mb}MB "
                   f"({container_stats.memory_percent}%)")

        return container_stats

    except Exception as e:
        logger.error(f"Error getting stats for container {container.name}: {e}")
        return None


@app.get("/metrics", response_model=List[ContainerStats])
async def get_all_metrics():
    """Get resource usage metrics for all running containers"""
    if not docker_client:
        raise HTTPException(status_code=503, detail="Docker client not available")

    try:
        containers = docker_client.containers.list()
        metrics = []

        for container in containers:
            container_metrics = get_container_stats(container)
            if container_metrics:
                metrics.append(container_metrics)

        logger.info(f"Collected metrics for {len(metrics)} containers")
        return metrics

    except Exception as e:
        logger.error(f"Error collecting metrics: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/metrics/{container_id}", response_model=ContainerStats)
async def get_container_metrics(container_id: str):
    """Get resource usage metrics for a specific container"""
    if not docker_client:
        raise HTTPException(status_code=503, detail="Docker client not available")

    try:
        container = docker_client.containers.get(container_id)
        container_metrics = get_container_stats(container)

        if not container_metrics:
            raise HTTPException(status_code=500, detail="Failed to collect container metrics")

        return container_metrics

    except docker.errors.NotFound:
        raise HTTPException(status_code=404, detail=f"Container {container_id} not found")
    except Exception as e:
        logger.error(f"Error getting metrics for container {container_id}: {e}")
        raise HTTPException(status_code=500, detail=str(e))


if __name__ == "__main__":
    port = int(os.getenv("PORT", 8080))
    host = os.getenv("HOST", "0.0.0.0")
    workers = int(os.getenv("WORKERS", 3))  # Default to 4 workers

    logger.info(f"Starting Container Resource Monitor on {host}:{port} with {workers} workers")
    uvicorn.run(
        "main:app",
        host=host,
        port=port,
        workers=workers,
        log_level="info"
    )
