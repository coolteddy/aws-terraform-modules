# EKS Add-ons Reference

A complete guide to EKS add-ons — what they are, why they exist, which ones this module
installs automatically, and which ones your consuming repo (aws-workload-infra) should install.

---

## Two types of add-ons

| Type | How installed | Managed by | Version tied to EKS? |
|---|---|---|---|
| **Official EKS managed** | `aws_eks_addon` Terraform resource | AWS | Yes — AWS tests compatibility |
| **Open-source (Helm)** | `helm_release` in consuming repo | You | No — you manage versions |

---

## Official AWS EKS Managed Add-ons

Installed and updated via the EKS API. AWS tests each version against each EKS version
and blocks incompatible combinations. Update them through Terraform or the AWS console.

### Included in this module (always installed)

| Add-on | Why it is always needed |
|---|---|
| `coredns` | DNS resolution for every pod in the cluster. Without it, pods cannot find each other by name. |
| `kube-proxy` | Runs on every node. Maintains `iptables` rules so Kubernetes `Service` traffic routes correctly. |
| `vpc-cni` | AWS-specific. Gives every pod a real VPC IP address (not a virtual overlay network). Enables pods to talk directly to RDS, ElastiCache, and other VPC resources. |
| `aws-ebs-csi-driver` | Enables `PersistentVolumeClaim` backed by EBS disks. Required for any stateful workload — databases, message queues, anything that needs disk. |

### Optional official add-ons (install in consuming repo when needed)

| Add-on | What it does | When to add |
|---|---|---|
| `aws-efs-csi-driver` | Shared persistent volumes using EFS. Multiple pods across multiple nodes can read/write the same volume simultaneously. | When you need shared storage (e.g. media processing, shared config) |
| `aws-mountpoint-s3-csi-driver` | Mount an S3 bucket as a filesystem inside a pod. Read-heavy workloads only. | When pods need direct file-system-style access to S3 |
| `snapshot-controller` | Kubernetes VolumeSnapshot support — create EBS snapshots from inside Kubernetes. | When you want application-consistent backups managed by Kubernetes |
| `eks-pod-identity-agent` | Newer, simpler alternative to IRSA for assigning IAM roles to pods. Does not require OIDC setup. | New clusters preferring Pod Identity over IRSA |
| `amazon-cloudwatch-observability` | Deploys the CloudWatch agent and Container Insights. Sends pod metrics, node metrics, and logs to CloudWatch. | When using CloudWatch as your observability platform |
| `adot` | AWS Distro for OpenTelemetry. Collects distributed traces and metrics. | When using X-Ray or an OTLP-compatible backend |
| `aws-guardduty-agent` | GuardDuty Runtime Monitoring — detects threats inside running containers (e.g. crypto mining, suspicious processes). | Production workloads requiring runtime security |

---

## Open-Source Add-ons (install via Helm in consuming repo)

These are not managed by AWS. Install them with `helm_release` Terraform resources or via
ArgoCD/Flux after the cluster is ready. This module outputs the values they need
(OIDC ARN, cluster name, etc.).

---

### Networking & Ingress

#### `aws-load-balancer-controller` ⭐ Must have
Creates AWS ALB or NLB automatically when you deploy a Kubernetes `Ingress` or
`Service type=LoadBalancer`. Without this, Kubernetes falls back to the old
in-tree controller which creates Classic ELBs (deprecated).

Requires IRSA role — see [IRSA section](#irsa-roles-for-open-source-add-ons).

```yaml
# With this controller, deploying this Ingress creates an ALB automatically:
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
```

#### `external-dns` — Common
Watches Kubernetes Services and Ingresses. When you deploy an app with a hostname,
ExternalDNS automatically creates the Route 53 record pointing to the ALB.
No manual DNS management.

Requires IRSA role with Route 53 write permissions.

#### `cert-manager` — Common
Automates TLS certificates. Watches Ingress resources and automatically requests
certificates from Let's Encrypt or issues them from ACM. Renews them before expiry.

#### `nginx-ingress-controller` — Alternative to ALB controller
Runs Nginx inside the cluster as a reverse proxy. Useful for advanced routing rules
or when not on AWS. Most AWS-native teams prefer the ALB controller.

---

### Scaling

#### `metrics-server` ⭐ Must have
Provides CPU and memory metrics for nodes and pods. Required for:
- HPA (Horizontal Pod Autoscaler) — scale pods based on CPU/memory
- VPA (Vertical Pod Autoscaler) — right-size pod resource requests
- `kubectl top pods` command

#### `karpenter` ⭐ AWS recommended (replaces Cluster Autoscaler)
AWS's node provisioner. Watches for unschedulable pods and launches exactly the right
EC2 instance type within seconds.

**Why Karpenter over Cluster Autoscaler:**

| | Cluster Autoscaler | Karpenter |
|---|---|---|
| Node add time | 2-3 minutes | 30-60 seconds |
| Instance selection | Fixed node groups | Any instance type dynamically |
| Spot handling | Basic | Intelligent — picks cheapest available Spot |
| Bin packing | Basic | Tight — consolidates pods, terminates underused nodes |
| AWS support | Community | AWS-native, AWS team maintains it |

Requires IRSA role. Configure `NodePool` and `EC2NodeClass` in consuming repo.

#### `cluster-autoscaler` — Being replaced by Karpenter
The original node autoscaler. Still works but Karpenter is faster and smarter.
Use Karpenter for new clusters.

#### `KEDA` — Advanced scaling
Kubernetes Event-Driven Autoscaler. Scales pods based on external signals:
- SQS queue depth
- HTTP request rate
- Kafka consumer lag
- Cron schedule

---

### Secrets Management

#### `external-secrets-operator` ⭐ Strongly recommended
Syncs secrets from AWS Secrets Manager or SSM Parameter Store into Kubernetes
`Secret` objects automatically. Pods read secrets as normal Kubernetes secrets
without knowing where they came from.

```yaml
# Deploy this → Kubernetes Secret appears automatically
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: db-password
spec:
  secretStoreRef:
    name: aws-secrets-manager
  target:
    name: db-password-k8s-secret
  data:
    - secretKey: password
      remoteRef:
        key: /prod/tenant-acme/db-password
```

Requires IRSA role with Secrets Manager read permissions.

#### `sealed-secrets` — For GitOps
Encrypts Kubernetes Secrets so they can be safely committed to Git.
Used when secrets must live in the GitOps repo (ArgoCD/Flux).

---

### Observability

#### `kube-prometheus-stack` ⭐ Most popular monitoring
A single Helm chart that installs:
- **Prometheus** — metrics collection and storage
- **Grafana** — dashboards and visualisation
- **Alertmanager** — alert routing (PagerDuty, Slack)
- Pre-built dashboards for nodes, pods, Kubernetes components

Used by Netflix, Airbnb, Shopify, and most cloud-native companies.

#### `loki` — Log aggregation
Grafana's logging system. Stores pod logs efficiently, queryable from Grafana.
Pairs with `kube-prometheus-stack` for a complete observability stack.

#### `tempo` — Distributed tracing
Grafana's tracing backend. Receives traces from OpenTelemetry and displays them in Grafana.
Completes the Grafana observability trio: Prometheus (metrics) + Loki (logs) + Tempo (traces).

#### `fluent-bit` — Log forwarder (lightweight)
Collects pod logs from nodes and forwards them to CloudWatch, S3, Elasticsearch, or Loki.
Very low memory footprint — runs as a DaemonSet on every node.

#### `datadog-agent` — Commercial
Full observability platform. Expensive but very polished. APM, logs, metrics, security.
Common in enterprises that already have a Datadog subscription.

---

### Security

#### `falco` — Runtime security
Detects suspicious behaviour inside running containers:
- Unexpected shell access (`kubectl exec` abuse)
- Crypto mining processes
- Privilege escalation
- Unexpected network connections

Alerts in real-time. Used in security-conscious teams.

#### `OPA Gatekeeper` or `Kyverno` — Policy enforcement
Prevents insecure or non-compliant deployments:
- Block containers running as root
- Require resource limits on all pods
- Prevent `latest` image tags
- Enforce label standards

`Kyverno` is simpler to learn. `OPA Gatekeeper` is more powerful.

---

### GitOps

#### `argocd` ⭐ Industry standard
Watches a Git repository. When you push changes to your app manifests or Helm values,
ArgoCD automatically deploys them to the cluster. Visual UI shows what is deployed
and whether it matches Git.

Used by the majority of companies doing Kubernetes at scale.

#### `flux` — Alternative
Lighter than ArgoCD, more CLI-focused. Used by teams that prefer a GitOps toolkit
over a full UI-driven tool.

---

## IRSA Roles for Open-Source Add-ons

These add-ons need AWS permissions. Create IRSA roles in the consuming repo
using this module's outputs:

```hcl
# In aws-workload-infra (consuming repo)
module "eks" {
  source = "...?ref=v1.0.0"
  # ...
}

# IRSA role for AWS Load Balancer Controller
module "irsa_alb_controller" {
  # ...
  oidc_provider_arn    = module.eks.oidc_provider_arn       # from this module
  oidc_issuer_url      = module.eks.cluster_oidc_issuer_url # from this module
  namespace            = "kube-system"
  service_account_name = "aws-load-balancer-controller"
  policy_arns          = [aws_iam_policy.alb_controller.arn]
}
```

---

## Recommended stack for multi-tenant SaaS startup

```
Phase 1 — Core (install with cluster):
  aws-load-balancer-controller   networking
  metrics-server                  scaling
  external-secrets-operator       secrets

Phase 2 — Operations:
  karpenter                       cost-efficient scaling
  external-dns                    automatic DNS
  kube-prometheus-stack           monitoring + alerting
  fluent-bit                      log forwarding

Phase 3 — Advanced:
  argocd                          GitOps deployments
  cert-manager                    automated TLS
  falco                           runtime security
  kyverno                         policy enforcement
```
