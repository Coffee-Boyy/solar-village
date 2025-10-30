# Solar Village

**Local Multipass / Ansible Test Environment**

This README walks you through setting up a **four-node local cluster** that mirrors the production-grade decentralized infrastructure:

* **3× MySQL 8.4 Group Replication** (multi-primary)
* **1× Async replica node**
* **4× MinIO distributed object storage nodes**
* **4× Ushahidi containers + Traefik reverse proxies**
* **WireGuard mesh** connecting all VMs over a private overlay network

The entire environment runs on your laptop via **Multipass** and is orchestrated with **Ansible**.
It provides a realistic multi-cloud testbed — minus the cloud billing.

---

## 🧰 Requirements

| Tool          | Version | Notes                                       | Install Link |
| ------------- | ------- | ------------------------------------------- | ---- |
| **Multipass** | ≥ 1.13  | Launch lightweight Ubuntu 24.04 VMs         | https://canonical.com/multipass/install |
| **Ansible**   | ≥ 2.16  | Manages install, WireGuard, Docker, Traefik | `pip install ansible` |
| **Docker**    | –       | Installed inside each VM by Ansible         | - |
| **SSH key**   | –       | `~/.ssh/id_ed25519.pub` used for access     | - |

> 🐧 Works on Linux, macOS, and Windows 11 (via WSL + Multipass).

---

## 🏗️ Step 1 — Launch VMs

Create four Ubuntu 24.04 VMs (2 CPU / 4 GB RAM / 30 GB disk):

```bash
multipass launch 24.04 --name do-a --cpus 2 --memory 4G --disk 30G
multipass launch 24.04 --name do-b --cpus 2 --memory 4G --disk 30G
multipass launch 24.04 --name hz-a --cpus 2 --memory 4G --disk 30G
multipass launch 24.04 --name hz-b --cpus 2 --memory 4G --disk 30G

multipass list
```

Note each VM’s IP address.

---

## 🔑 Step 2 — Authorize SSH Access

Inject your local SSH public key into each VM:

```bash
for h in do-a do-b hz-a hz-b; do
  multipass transfer ~/.ssh/id_ed25519.pub $h:/home/ubuntu/id.pub
  multipass exec $h -- bash -lc 'mkdir -p ~/.ssh && cat ~/id.pub >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys'
done
```

---

## 🗺️ Step 3 — Create Ansible Inventory

`ansible/inventories/local/hosts.ini`

```ini
[all]
do-a ansible_host=<IP_DO_A> ansible_user=ubuntu wg_ip=10.20.0.11 wg_port=51821 node_role=gr_primary
do-b ansible_host=<IP_DO_B> ansible_user=ubuntu wg_ip=10.20.0.12 wg_port=51822 node_role=gr_primary
hz-a ansible_host=<IP_HZ_A> ansible_user=ubuntu wg_ip=10.20.0.13 wg_port=51823 node_role=gr_primary
hz-b ansible_host=<IP_HZ_B> ansible_user=ubuntu wg_ip=10.20.0.14 wg_port=51824 node_role=async_replica

[wg_all]
do-a
do-b
hz-a
hz-b

[mysql_gr]
do-a
do-b
hz-a

[mysql_async]
hz-b

[minio_all]
do-a
do-b
hz-a
hz-b

[ushahidi_all]
do-a
do-b
hz-a
hz-b
```

Replace each `<IP_…>` with the actual Multipass IPs.

---

## ⚙️ Step 4 — Global Variables

`ansible/group_vars/all.yml`

```yaml
domain_root: "local.test"
ushahidi_image: "ushahidi/platform:latest"

# WireGuard
wg_network_cidr: "10.20.0.0/24"
wg_iface: "wg0"
wg_keepalive: 25

# MySQL
mysql_root_password: "rootpass"
mysql_gr_user: "gruser"
mysql_gr_password: "grpass"
mysql_app_user: "ushahidi"
mysql_app_password: "apppass"
mysql_db: "ushahidi"
gr_group_name: "c6b2f7a1-43e9-4b77-9d6d-ccaaab09c6f0"
gr_seeds: |
  {{ hostvars['do-a'].wg_ip }}:33061,{{ hostvars['do-b'].wg_ip }}:33061,{{ hostvars['hz-a'].wg_ip }}:33061

# MinIO
minio_access_key: "minioadmin"
minio_secret_key: "minioadminchange"
minio_cluster_nodes:
  - "http://{{ hostvars['do-a'].wg_ip }}:9000"
  - "http://{{ hostvars['do-b'].wg_ip }}:9000"
  - "http://{{ hostvars['hz-a'].wg_ip }}:9000"
  - "http://{{ hostvars['hz-b'].wg_ip }}:9000"

# Traefik routing
traefik_routes:
  - host: "ushahidi.local.test"
    service: "ushahidi"
    port: 8080
    middlewares: [ "secureHeaders" ]
```

---

## 🧩 Step 5 — Run the Playbook

Install dependencies and deploy:

```bash
ansible-galaxy collection install community.docker
ansible-playbook -i ansible/inventories/local/hosts.ini ansible/site.yml
```

Ansible will:

1. Install WireGuard on each VM.
2. Generate keys locally (per host) and mesh them.
3. Enable Docker and UFW rules.
4. Deploy Traefik (reverse proxy + TLS).
5. Bring up MySQL Group Replication + Router.
6. Deploy MinIO (distributed).
7. Launch Ushahidi containers on each node.

---

## ✅ Step 6 — Verify Deployment

### WireGuard mesh

```bash
ansible -i ansible/inventories/local/hosts.ini all -m command -a "sudo wg show"
```

Each node should list 3 peers with `latest handshake` < 30 s.

### MySQL Group Replication

```bash
ssh ubuntu@<IP_DO_A> "docker exec mysql mysql -uroot -p'rootpass' -e \"SELECT MEMBER_HOST,MEMBER_STATE FROM performance_schema.replication_group_members;\""
```

Expect 3 members ONLINE.

### MinIO console

Open `http://<IP_DO_A>:9001`
Login: `minioadmin / minioadminchange`
Create bucket `ushahidi-uploads`.

### Ushahidi UI

Visit `http://<IP_DO_A>:8080` (or any node’s :8080).
Sign up, create a test post, upload a file, confirm it appears in MinIO.

---

## 🧪 Step 7 — Functional Tests

| Test               | Command                    | Expected                 |
| ------------------ | -------------------------- | ------------------------ |
| Ping peers over WG | `ping -c2 10.20.0.12`      | Replies                  |
| Add post on Node A | via Ushahidi UI            | Appears on Node B        |
| Check GR quorum    | SQL query above            | All ONLINE               |
| Restart Node B     | `multipass restart do-b`   | GR rejoins automatically |
| Upload file        | Ushahidi UI → MinIO bucket | File visible             |

---

## 🧹 Cleanup

Stop containers and delete VMs:

```bash
ansible -i ansible/inventories/local/hosts.ini all -m command -a "docker ps -q | xargs -r docker stop"
multipass delete --purge do-a do-b hz-a hz-b
```

---

## 🧠 How This Maps to Production

| Component       | Local (Multipass)   | Cloud Equivalent                        |
| --------------- | ------------------- | --------------------------------------- |
| VM nodes        | Multipass VMs       | DigitalOcean Droplets / Hetzner Servers |
| Private network | WireGuard mesh      | Inter-cloud overlay                     |
| DB cluster      | MySQL GR containers | Same (multi-region GR)                  |
| Object store    | MinIO containers    | MinIO pods or S3-compatible buckets     |
| Reverse proxy   | Traefik containers  | Per-node Traefik + ACME DNS-01          |
| Deployment      | Ansible playbook    | GitHub Actions / Terraform + Ansible    |

---

## ⚠️ Common Issues & Fixes

| Symptom                      | Likely Cause                  | Fix                                                      |
| ---------------------------- | ----------------------------- | -------------------------------------------------------- |
| `wg show` shows no handshake | UDP port blocked              | `sudo ufw allow 5182x/udp` on each VM                    |
| `GROUP_REPLICATION` OFFLINE  | Seed IP typo or network delay | Re-run playbook or start GR manually                     |
| MinIO “offline disks”        | Container restart timing      | `docker compose restart minio`                           |
| Ushahidi 500 error           | DB not ready yet              | Wait 30 s and refresh                                    |
| DNS name not resolving       | Local host mapping needed     | `sudo nano /etc/hosts` → `<IP_DO_A> ushahidi.local.test` |

---

## 🧭 Next Steps

* Add **CI/CD**: run Terraform → Ansible on cloud nodes.
* Integrate **GitHub Actions** for idempotent deploys.
* Extend **WireGuard** to additional community nodes.
* Add **Prometheus + Grafana** dashboards for GR / MinIO health.
* Run **chaos tests**: kill nodes, verify auto-recovery.

---

**Congratulations! 🎉**
You now have a fully working, decentralized Ushahidi + MySQL Group Replication + MinIO stack running on your laptop — complete with private WireGuard networking and per-node Ushahidi instances.
