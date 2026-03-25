import pulumi
import pulumi_kubernetes as k8s
from pulumi_kubernetes.apps.v1 import Deployment, DeploymentSpecArgs
from pulumi_kubernetes.core.v1 import (
    ContainerArgs, ContainerPortArgs, EnvVarArgs, EnvVarSourceArgs,
    ObjectFieldSelectorArgs, PersistentVolumeClaimArgs, PersistentVolumeClaimSpecArgs,
    PodSpecArgs, PodTemplateSpecArgs, ResourceRequirementsArgs, ServiceArgs,
    ServicePortArgs, ServiceSpecArgs, ConfigMapArgs, SecretArgs, NamespaceArgs,
    ObjectMetaArgs
)
from pulumi_kubernetes.meta.v1 import ObjectMetaArgs as MetaArgs, LabelSelectorArgs
import pulumi_aws as aws

# Configuration
config = pulumi.Config()
environment = config.get("environment") or "production"
domain = config.require("domain")
namespace = "nextcloud"

# Create namespace
nextcloud_namespace = k8s.core.v1.Namespace(
    "nextcloud",
    metadata=MetaArgs(name=namespace)
)

# Create secrets
nextcloud_secrets = k8s.core.v1.Secret(
    "nextcloud-secrets",
    metadata=MetaArgs(name="nextcloud-secrets", namespace=namespace),
    stringData={
        "NEXTCLOUD_ADMIN_PASSWORD": config.require_secret("nextcloud_admin_password"),
        "POSTGRES_USER": "nextcloud",
        "POSTGRES_PASSWORD": config.require_secret("postgres_password"),
        "REDIS_PASSWORD": config.require_secret("redis_password"),
    }
)

# Create ConfigMap
nextcloud_config = k8s.core.v1.ConfigMap(
    "nextcloud-config",
    metadata=MetaArgs(name="nextcloud-config", namespace=namespace),
    data={
        "NEXTCLOUD_ADMIN_USER": "admin",
        "NEXTCLOUD_TRUSTED_DOMAINS": domain,
        "NEXTCLOUD_OVERWRITE_PROTOCOL": "https",
        "POSTGRES_HOST": "postgres",
        "POSTGRES_DB": "nextcloud",
        "REDIS_HOST": "redis",
    }
)

# PostgreSQL Deployment
postgres_deployment = k8s.apps.v1.Deployment(
    "postgres",
    metadata=MetaArgs(name="postgres", namespace=namespace),
    spec={
        "replicas": 1,
        "selector": {"matchLabels": {"app": "postgres"}},
        "template": {
            "metadata": {"labels": {"app": "postgres"}},
            "spec": {
                "containers": [{
                    "name": "postgres",
                    "image": "postgres:14-alpine",
                    "ports": [{"containerPort": 5432}],
                    "env": [
                        {
                            "name": "POSTGRES_USER",
                            "valueFrom": {
                                "secretKeyRef": {"name": "nextcloud-secrets", "key": "POSTGRES_USER"}
                            }
                        },
                        {
                            "name": "POSTGRES_PASSWORD",
                            "valueFrom": {
                                "secretKeyRef": {"name": "nextcloud-secrets", "key": "POSTGRES_PASSWORD"}
                            }
                        },
                        {
                            "name": "POSTGRES_DB",
                            "value": "nextcloud"
                        }
                    ],
                    "volumeMounts": [
                        {
                            "name": "postgres-data",
                            "mountPath": "/var/lib/postgresql/data"
                        }
                    ],
                    "resources": {
                        "requests": {"memory": "256Mi", "cpu": "100m"},
                        "limits": {"memory": "512Mi", "cpu": "500m"}
                    }
                }],
                "volumes": [{
                    "name": "postgres-data",
                    "persistentVolumeClaim": {"claimName": "postgres-data"}
                }]
            }
        }
    }
)

# PostgreSQL Service
postgres_service = k8s.core.v1.Service(
    "postgres",
    metadata=MetaArgs(name="postgres", namespace=namespace),
    spec={
        "selector": {"app": "postgres"},
        "ports": [{"port": 5432, "targetPort": 5432}]
    }
)

# Redis Deployment
redis_deployment = k8s.apps.v1.Deployment(
    "redis",
    metadata=MetaArgs(name="redis", namespace=namespace),
    spec={
        "replicas": 1,
        "selector": {"matchLabels": {"app": "redis"}},
        "template": {
            "metadata": {"labels": {"app": "redis"}},
            "spec": {
                "containers": [{
                    "name": "redis",
                    "image": "redis:7-alpine",
                    "command": ["redis-server", "--requirepass"],
                    "args": ["$(REDIS_PASSWORD)"],
                    "ports": [{"containerPort": 6379}],
                    "env": [
                        {
                            "name": "REDIS_PASSWORD",
                            "valueFrom": {
                                "secretKeyRef": {"name": "nextcloud-secrets", "key": "REDIS_PASSWORD"}
                            }
                        }
                    ],
                    "volumeMounts": [
                        {"name": "redis-data", "mountPath": "/data"}
                    ],
                    "resources": {
                        "requests": {"memory": "128Mi", "cpu": "50m"},
                        "limits": {"memory": "256Mi", "cpu": "200m"}
                    }
                }],
                "volumes": [{
                    "name": "redis-data",
                    "persistentVolumeClaim": {"claimName": "redis-data"}
                }]
            }
        }
    }
)

# Redis Service
redis_service = k8s.core.v1.Service(
    "redis",
    metadata=MetaArgs(name="redis", namespace=namespace),
    spec={
        "selector": {"app": "redis"},
        "ports": [{"port": 6379, "targetPort": 6379}]
    }
)

# Nextcloud Deployment
nextcloud_deployment = k8s.apps.v1.Deployment(
    "nextcloud",
    metadata=MetaArgs(name="nextcloud", namespace=namespace),
    spec={
        "replicas": 2,
        "selector": {"matchLabels": {"app": "nextcloud"}},
        "strategy": {
            "type": "RollingUpdate",
            "rollingUpdate": {"maxSurge": 1, "maxUnavailable": 0}
        },
        "template": {
            "metadata": {"labels": {"app": "nextcloud"}},
            "spec": {
                "containers": [{
                    "name": "nextcloud",
                    "image": "nextcloud:latest",
                    "imagePullPolicy": "Always",
                    "ports": [{"containerPort": 80}],
                    "envFrom": [
                        {"configMapRef": {"name": "nextcloud-config"}},
                        {"secretRef": {"name": "nextcloud-secrets"}}
                    ],
                    "volumeMounts": [
                        {"name": "nextcloud-data", "mountPath": "/var/www/html"}
                    ],
                    "resources": {
                        "requests": {"memory": "512Mi", "cpu": "250m"},
                        "limits": {"memory": "1Gi", "cpu": "500m"}
                    },
                    "livenessProbe": {
                        "httpGet": {"path": "/status.php", "port": 80},
                        "initialDelaySeconds": 60,
                        "periodSeconds": 10
                    },
                    "readinessProbe": {
                        "httpGet": {"path": "/status.php", "port": 80},
                        "initialDelaySeconds": 30,
                        "periodSeconds": 5
                    }
                }],
                "volumes": [{
                    "name": "nextcloud-data",
                    "persistentVolumeClaim": {"claimName": "nextcloud-data"}
                }]
            }
        }
    }
)

# Nextcloud Service
nextcloud_service = k8s.core.v1.Service(
    "nextcloud",
    metadata=MetaArgs(name="nextcloud", namespace=namespace),
    spec={
        "type": "LoadBalancer",
        "selector": {"app": "nextcloud"},
        "ports": [{"port": 80, "targetPort": 80}]
    }
)

# Horizontal Pod Autoscaler
nextcloud_hpa = k8s.autoscaling.v2.HorizontalPodAutoscaler(
    "nextcloud",
    metadata=MetaArgs(name="nextcloud", namespace=namespace),
    spec={
        "scaleTargetRef": {
            "apiVersion": "apps/v1",
            "kind": "Deployment",
            "name": "nextcloud"
        },
        "minReplicas": 2,
        "maxReplicas": 5,
        "metrics": [
            {
                "type": "Resource",
                "resource": {
                    "name": "cpu",
                    "target": {"type": "Utilization", "averageUtilization": 70}
                }
            },
            {
                "type": "Resource",
                "resource": {
                    "name": "memory",
                    "target": {"type": "Utilization", "averageUtilization": 80}
                }
            }
        ]
    }
)

# Export outputs
pulumi.export("namespace", namespace)
pulumi.export("postgres_service", postgres_service.metadata["name"])
pulumi.export("redis_service", redis_service.metadata["name"])
pulumi.export("nextcloud_service", nextcloud_service.status.apply(
    lambda s: s.load_balancer.ingress[0].hostname if s and s.load_balancer and s.load_balancer.ingress else "Pending"
))
