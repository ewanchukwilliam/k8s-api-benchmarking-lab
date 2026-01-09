#!/bin/bash
set -e

kind delete cluster --name devops-lab

echo "Cluster deleted"
